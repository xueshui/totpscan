package com.scanauth.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import com.scanauth.sdk.AccountOperationListenerAdapter
import com.scanauth.sdk.AccountSummary
import com.scanauth.sdk.BindListenerAdapter
import com.scanauth.sdk.BindPreview
import com.scanauth.sdk.BindingConfirmListenerAdapter
import com.scanauth.sdk.LoginCandidate
import com.scanauth.sdk.LoginListenerAdapter
import com.scanauth.sdk.LoginScanListenerAdapter
import com.scanauth.sdk.LoginScanResult
import com.scanauth.sdk.ScanTotpClient
import com.scanauth.sdk.ScanTotpConfig
import com.scanauth.sdk.SdkError
import com.scanauth.sdk.SubmitResult
import com.scanauth.sdk.TotpAlgorithm
import com.scanauth.sdk.TotpParameters
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

sealed interface BindFlowState {
    data object Idle : BindFlowState
    data object Parsing : BindFlowState
    data class NeedsConfirm(val preview: BindPreview) : BindFlowState
    data class Failed(val error: SdkError, val message: String) : BindFlowState
}

sealed interface BindConfirmState {
    data object Idle : BindConfirmState
    data object Saving : BindConfirmState
    data class Confirming(val account: AccountSummary) : BindConfirmState
    data class Confirmed(val account: AccountSummary) : BindConfirmState
    data class StoredOnly(val localId: String, val error: SdkError, val message: String) : BindConfirmState
    data class Failed(val error: SdkError, val message: String) : BindConfirmState
}

sealed interface AddAccountState {
    data object Idle : AddAccountState
    data object Working : AddAccountState
    data class Added(val account: AccountSummary) : AddAccountState
    data class Failed(val message: String) : AddAccountState
}

sealed interface LoginFlowState {
    data object Idle : LoginFlowState
    data object Parsing : LoginFlowState
    data class Select(val result: LoginScanResult) : LoginFlowState
    data class Ready(val result: LoginScanResult, val candidate: LoginCandidate) : LoginFlowState
    data class Submitting(val result: LoginScanResult, val candidate: LoginCandidate) : LoginFlowState
    data class Success(val result: SubmitResult, val candidate: LoginCandidate) : LoginFlowState

    /** 可重试的提交失败（网络 / 限流 / 服务端 5xx 等），保留本次二维码以便重试。 */
    data class SubmitFailed(
        val result: LoginScanResult,
        val candidate: LoginCandidate,
        val message: String
    ) : LoginFlowState

    data class Failed(val message: String) : LoginFlowState
}

sealed interface AccountOpState {
    data object Idle : AccountOpState
    data object Working : AccountOpState
    data class Done(val message: String) : AccountOpState
    data class Failed(val message: String) : AccountOpState
}

/**
 * 应用级状态容器。
 *
 * 所有安全校验都在 SDK 内完成，本类只负责把结果映射成 UI 状态，
 * 不接触密钥、`scan_token` 或动态码（标准型账户的动态码除外）。
 */
class AppViewModel(application: Application) : AndroidViewModel(application) {

    private val client = ScanTotpClient.create(application, ScanTotpConfig())
    private val settingsStore = SettingsStore(application)

    private val _accounts = MutableStateFlow(client.accounts())
    val accounts: StateFlow<List<AccountSummary>> = _accounts.asStateFlow()

    private val _settings = MutableStateFlow(settingsStore.load())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    private val _bindState = MutableStateFlow<BindFlowState>(BindFlowState.Idle)
    val bindState: StateFlow<BindFlowState> = _bindState.asStateFlow()

    private val _confirmState = MutableStateFlow<BindConfirmState>(BindConfirmState.Idle)
    val confirmState: StateFlow<BindConfirmState> = _confirmState.asStateFlow()

    private val _addState = MutableStateFlow<AddAccountState>(AddAccountState.Idle)
    val addState: StateFlow<AddAccountState> = _addState.asStateFlow()

    private val _loginState = MutableStateFlow<LoginFlowState>(LoginFlowState.Idle)
    val loginState: StateFlow<LoginFlowState> = _loginState.asStateFlow()

    private val _accountOp = MutableStateFlow<AccountOpState>(AccountOpState.Idle)
    val accountOp: StateFlow<AccountOpState> = _accountOp.asStateFlow()

    override fun onCleared() {
        client.close()
        super.onCleared()
    }

    fun refresh() {
        _accounts.value = client.accounts()
    }

    fun account(localId: String): AccountSummary? =
        _accounts.value.firstOrNull { it.localId == localId }

    /** 仅标准型账户返回动态码；增强型账户恒为 null（SDK 不暴露）。 */
    fun standardCode(localId: String, epochSeconds: Long): String? =
        client.standardCodeFor(localId, epochSeconds)

    /**
     * 扫码型账户动态码：只有用户在设置中显式开启后才返回，
     * 关闭开关的瞬间即返回 null，从而清空界面上的码。
     */
    fun protocolCode(localId: String, epochSeconds: Long): String? =
        if (_settings.value.showProtocolCodes) {
            client.protocolCodeFor(localId, epochSeconds)
        } else {
            null
        }

    /** 单账户 `otpauth://` URI：仅用于屏幕二维码展示，不复制、不落盘。 */
    fun otpauthUriFor(localId: String): String? = client.otpauthUriFor(localId)

    // ---------------------------------------------------------------- 设置

    fun setTheme(mode: ThemeMode) {
        val updated = _settings.value.copy(theme = mode)
        _settings.value = updated
        settingsStore.save(updated)
    }

    fun setBiometricEnabled(enabled: Boolean) {
        val updated = _settings.value.copy(biometricEnabled = enabled)
        _settings.value = updated
        settingsStore.save(updated)
    }

    /** 显示扫码型账户动态码开关。关闭时立即生效（UI 下一次重组即拿到 null）。 */
    fun setShowProtocolCodes(enabled: Boolean) {
        val updated = _settings.value.copy(showProtocolCodes = enabled)
        _settings.value = updated
        settingsStore.save(updated)
    }

    // ---------------------------------------------------------------- 绑定流程

    fun resetBind() {
        _bindState.value = BindFlowState.Idle
        _confirmState.value = BindConfirmState.Idle
    }

    fun beginBind(payload: String) {
        _bindState.value = BindFlowState.Parsing
        client.beginBind(payload, object : BindListenerAdapter() {
            override fun onConfirmRequired(preview: BindPreview) {
                _bindState.value = BindFlowState.NeedsConfirm(preview)
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                _bindState.value = BindFlowState.Failed(error, message ?: error.defaultMessage)
            }
        })
    }

    fun confirmBind(preview: BindPreview, remark: String) {
        _confirmState.value = BindConfirmState.Saving
        client.confirmBind(preview, remark, object : BindListenerAdapter() {
            override fun onBound(account: AccountSummary) {
                refresh()
                confirmOnServer(account)
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                _confirmState.value = BindConfirmState.Failed(error, message ?: error.defaultMessage)
            }
        })
    }

    private fun confirmOnServer(account: AccountSummary) {
        _confirmState.value = BindConfirmState.Confirming(account)
        client.confirmBinding(account.localId, object : BindingConfirmListenerAdapter() {
            override fun onConfirmed(account: AccountSummary) {
                refresh()
                _confirmState.value = BindConfirmState.Confirmed(account)
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                refresh()
                _confirmState.value = BindConfirmState.StoredOnly(
                    localId = account.localId,
                    error = error,
                    message = message ?: error.defaultMessage
                )
            }
        })
    }

    /**
     * 重试服务端绑定确认。
     *
     * [bindFlow] 为 true 表示由绑定确认页发起（状态写入 [confirmState]），
     * 否则由账户详情页发起（状态写入 [accountOp]）。
     */
    fun retryConfirmBinding(localId: String, bindFlow: Boolean = false) {
        val account = account(localId)
        if (account == null) {
            if (bindFlow) {
                _confirmState.value = BindConfirmState.Failed(SdkError.NOT_BOUND, "账户不存在")
            } else {
                _accountOp.value = AccountOpState.Failed("账户不存在")
            }
            return
        }
        if (bindFlow) {
            _confirmState.value = BindConfirmState.Confirming(account)
        } else {
            _accountOp.value = AccountOpState.Working
        }
        client.confirmBinding(localId, object : BindingConfirmListenerAdapter() {
            override fun onConfirmed(account: AccountSummary) {
                refresh()
                if (bindFlow) {
                    _confirmState.value = BindConfirmState.Confirmed(account)
                } else {
                    _accountOp.value = AccountOpState.Done("绑定已确认，可以扫码登录了")
                }
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                refresh()
                val text = message ?: error.defaultMessage
                if (bindFlow) {
                    _confirmState.value = BindConfirmState.StoredOnly(localId, error, text)
                } else {
                    _accountOp.value = AccountOpState.Failed(text)
                }
            }
        })
    }

    // ---------------------------------------------------------------- 标准账户

    fun resetAddState() {
        _addState.value = AddAccountState.Idle
    }

    fun addStandardByUri(uri: String, remark: String) {
        _addState.value = AddAccountState.Working
        client.addStandardAccount(uri, remark, object : BindListenerAdapter() {
            override fun onBound(account: AccountSummary) {
                refresh()
                _addState.value = AddAccountState.Added(account)
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                _addState.value = AddAccountState.Failed(message ?: error.defaultMessage)
            }
        })
    }

    fun addStandardManually(
        issuer: String,
        accountId: String,
        secret: String,
        remark: String,
        algorithm: TotpAlgorithm,
        digits: Int,
        periodSeconds: Long
    ) {
        _addState.value = AddAccountState.Working
        val parameters = TotpParameters(algorithm, digits, periodSeconds)
        client.addStandardAccount(issuer, accountId, secret, parameters, remark, object : BindListenerAdapter() {
            override fun onBound(account: AccountSummary) {
                refresh()
                _addState.value = AddAccountState.Added(account)
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                _addState.value = AddAccountState.Failed(message ?: error.defaultMessage)
            }
        })
    }

    // ---------------------------------------------------------------- 登录流程

    fun resetLogin() {
        _loginState.value = LoginFlowState.Idle
    }

    fun beginLogin(payload: String) {
        _loginState.value = LoginFlowState.Parsing
        client.verifyLoginQr(payload, object : LoginScanListenerAdapter() {
            override fun onReady(result: LoginScanResult) {
                if (result.candidates.size == 1) {
                    selectCandidate(result, result.candidates.first())
                } else {
                    _loginState.value = LoginFlowState.Select(result)
                }
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                _loginState.value = LoginFlowState.Failed(message ?: error.defaultMessage)
            }
        })
    }

    fun selectCandidate(result: LoginScanResult, candidate: LoginCandidate) {
        _loginState.value = LoginFlowState.Ready(result, candidate)
    }

    fun submitLogin() {
        val state = _loginState.value as? LoginFlowState.Ready ?: return
        doSubmit(state.result, state.candidate)
    }

    /** 提交失败但二维码仍有效时，允许直接重试。 */
    fun retrySubmitLogin() {
        val state = _loginState.value
        val retry = when (state) {
            is LoginFlowState.SubmitFailed -> state
            is LoginFlowState.Ready -> null
            else -> null
        } ?: return
        doSubmit(retry.result, retry.candidate)
    }

    private fun doSubmit(result: LoginScanResult, candidate: LoginCandidate) {
        _loginState.value = LoginFlowState.Submitting(result, candidate)
        client.submitLogin(result, candidate.localId, object : LoginListenerAdapter() {
            override fun onResult(result: SubmitResult) {
                _loginState.value = LoginFlowState.Success(result, candidate)
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                val text = message ?: error.defaultMessage
                val retryable = error == SdkError.NETWORK_ERROR ||
                    error == SdkError.RATE_LIMITED ||
                    error == SdkError.HTTP_ERROR ||
                    error == SdkError.SERVER_INVALID_REQUEST ||
                    error == SdkError.INTERNAL_ERROR
                _loginState.value = if (retryable) {
                    LoginFlowState.SubmitFailed(result, candidate, text)
                } else {
                    LoginFlowState.Failed(text)
                }
            }
        })
    }

    // ---------------------------------------------------------------- 账户操作

    fun resetAccountOp() {
        _accountOp.value = AccountOpState.Idle
    }

    fun renameAccount(localId: String, remark: String) {
        _accountOp.value = AccountOpState.Working
        client.renameAccount(localId, remark, object : AccountOperationListenerAdapter() {
            override fun onSuccess(accounts: List<AccountSummary>) {
                _accounts.value = accounts
                _accountOp.value = AccountOpState.Done("备注已更新")
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                _accountOp.value = AccountOpState.Failed(message ?: error.defaultMessage)
            }
        })
    }

    fun removeAccount(localId: String) {
        _accountOp.value = AccountOpState.Working
        client.removeAccount(localId, object : AccountOperationListenerAdapter() {
            override fun onSuccess(accounts: List<AccountSummary>) {
                _accounts.value = accounts
                _accountOp.value = AccountOpState.Done("账户已删除")
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                _accountOp.value = AccountOpState.Failed(message ?: error.defaultMessage)
            }
        })
    }

    /** 清空本机全部账户（并删除 Keystore 主密钥）。服务端绑定需管理员另行解绑。 */
    fun unbindAll() {
        _accountOp.value = AccountOpState.Working
        client.unbindAll(object : AccountOperationListenerAdapter() {
            override fun onSuccess(accounts: List<AccountSummary>) {
                _accounts.value = accounts
                _accountOp.value = AccountOpState.Done("本机账户已全部清除")
            }

            override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
                _accountOp.value = AccountOpState.Failed(message ?: error.defaultMessage)
            }
        })
    }
}
