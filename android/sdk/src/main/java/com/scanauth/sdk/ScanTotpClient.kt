package com.scanauth.sdk

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.scanauth.sdk.internal.AccountRecord
import com.scanauth.sdk.internal.Base32
import com.scanauth.sdk.internal.BindingQrData
import com.scanauth.sdk.internal.BindingQrParser
import com.scanauth.sdk.internal.CanonicalAddress
import com.scanauth.sdk.internal.LoginQrData
import com.scanauth.sdk.internal.LoginQrParser
import com.scanauth.sdk.internal.OtpauthUri
import com.scanauth.sdk.internal.PinnedEndpoint
import com.scanauth.sdk.internal.SdkLog
import com.scanauth.sdk.internal.SecureStore
import com.scanauth.sdk.internal.Submitter
import com.scanauth.sdk.internal.Totp
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * 扫码增强型 TOTP 认证 SDK 入口。
 *
 * 两类账户（规范 §13.1）：
 * - [AccountType.PROTOCOL]：扫码型账户，绑定阶段固化“提交地址 + 共享密钥”，
 *   只能通过扫码提交；SDK **不向调用方暴露**这类账户的即时动态码；
 * - [AccountType.STANDARD]：标准 TOTP 账户，来自 `otpauth://` 或手动录入，
 *   由调用方自行展示动态码，不参与扫码提交。
 *
 * 扫码登录没有“当前选中账户”的概念：每次扫描都用登录码 `url` 的注册域名与**全部**本地固化
 * 记录比对，得到候选集。0 个候选 → 立即终止且零出站请求；1 个 → 直接提交；
 * 多个（同一注册域名下）→ 由用户在选择框内挑选。
 *
 * 所有耗时操作在内部单线程串行执行，回调统一切回主线程。
 */
class ScanTotpClient private constructor(
    private val config: ScanTotpConfig,
    private val store: SecureStore,
    private val submitter: Submitter,
    private val bindingParser: BindingQrParser
) {

    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "scan-totp-sdk").apply { isDaemon = true }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var closed: Boolean = false

    companion object {
        /** 本地备注长度上限（仅本机字段，不进二维码；规范 §13.3 为 ≤64 字符）。 */
        const val MAX_REMARK_LENGTH = 64

        @JvmStatic
        @JvmOverloads
        fun create(context: Context, config: ScanTotpConfig = ScanTotpConfig()): ScanTotpClient {
            SdkLog.enabled = config.debugLogging
            val appContext = context.applicationContext
            return ScanTotpClient(
                config = config,
                store = SecureStore(appContext),
                submitter = Submitter(config),
                bindingParser = BindingQrParser()
            )
        }
    }

    // ---------------------------------------------------------------- 账户查询

    /** 本机全部账户（按绑定/添加时间排序，最近添加的在前）。 */
    fun accounts(): List<AccountSummary> = try {
        store.loadAll()
            .sortedByDescending { it.boundAtEpochMs }
            .map { it.toSummary() }
    } catch (e: SdkException) {
        SdkLog.w("list accounts failed")
        emptyList()
    }

    /** 按本地 ID 查询账户摘要。 */
    fun account(localId: String): AccountSummary? =
        accounts().firstOrNull { it.localId == localId }

    /** 是否至少存在一个账户。 */
    fun isBound(): Boolean = accounts().isNotEmpty()

    /**
     * 计算**标准型账户**的动态码。
     *
     * 增强型账户返回 null：这类账户的动态码只能由 SDK 在扫码提交流程内部计算，
     * 不得暴露给调用方（避免用户手动输入而破坏防钓鱼语义，规范 §13.3 / §13.4）。
     */
    @JvmOverloads
    fun standardCodeFor(localId: String, epochSeconds: Long = nowSeconds()): String? {
        return try {
            val record = store.loadAll().firstOrNull { it.localId == localId } ?: return null
            if (record.type != AccountType.STANDARD) return null
            Totp.generate(Base32.decode(record.secretBase32), epochSeconds, record.parameters)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * 计算**协议（扫码型）账户**的动态码。
     *
     * 这类账户默认不向调用方暴露动态码。只有在用户**显式开启**「显示扫码型账户的动态码」
     * 并完成本地认证后才可调用；宿主必须在关闭开关时立即丢弃已展示的码。
     * 该能力不影响扫码提交流程：提交仍只走 [submitLogin]。
     */
    @JvmOverloads
    fun protocolCodeFor(localId: String, epochSeconds: Long = nowSeconds()): String? {
        return try {
            val record = store.loadAll().firstOrNull { it.localId == localId } ?: return null
            if (record.type != AccountType.PROTOCOL) return null
            Totp.generate(Base32.decode(record.secretBase32), epochSeconds, record.parameters)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * 构造单个账户的 `otpauth://totp/...` URI，**仅供屏幕展示二维码**。
     *
     * - label 为 `issuer:account`（无签发方时仅 `account`），按 URI 规范百分号编码；
     * - 参数取账户真实值，等于默认值（SHA1 / 6 位 / 30 秒）时省略；
     * - 返回的字符串只应交给二维码渲染器：SDK 不写剪贴板、不写日志、不落盘；
     * - 调用方必须在渲染前完成本地认证（生物识别 / 设备凭据）。
     *
     * 账户不存在时返回 null。
     */
    fun otpauthUriFor(localId: String): String? {
        return try {
            val record = store.loadAll().firstOrNull { it.localId == localId } ?: return null
            OtpauthUri.build(
                OtpauthAccount(
                    issuer = record.issuer,
                    accountId = record.accountId,
                    secretBase32 = record.secretBase32,
                    parameters = record.parameters
                ),
                omitDefaults = true
            )
        } catch (e: Exception) {
            SdkLog.w("build otpauth uri failed")
            null
        }
    }

    // ---------------------------------------------------------------- 协议绑定

    /**
     * 第一步：解析绑定二维码并校验字段与 `exp`（不写入任何数据）。
     *
     * 成功后回调 [BindListener.onConfirmRequired]，宿主 App 必须把
     * [BindPreview.submitUrl] 原样展示给用户确认。
     */
    fun beginBind(qrPayload: String, listener: BindListener) {
        runAsync(
            block = { bindingParser.parse(qrPayload, nowSeconds(), config.clockSkewSeconds) },
            onSuccess = { listener.onConfirmRequired(it.toPreview()) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    /**
     * 第二步：用户确认地址后写入本地安全存储。
     *
     * [remark] 为用户填写的本地备注（可空），只保存在本机。
     * 协议账户写入后仍处于“未确认”状态，需调用 [confirmBinding] 完成服务端确认。
     */
    fun confirmBind(preview: BindPreview, remark: String, listener: BindListener) {
        runAsync(
            block = {
                val cleanRemark = normalizeRemark(remark)
                // 重新解析：确认期间二维码可能已过期，或被替换
                val data = bindingParser.parse(
                    preview.rawPayload, nowSeconds(), config.clockSkewSeconds
                )
                if (data.submitUrl.canonical != preview.submitUrl || data.bindingId != preview.bindingId) {
                    throw SdkException(SdkError.ADDRESS_MISMATCH, "待确认地址与二维码内容不一致")
                }
                if (data.registeredDomain != preview.registeredDomain ||
                    data.submitPath != preview.submitPath
                ) {
                    throw SdkException(SdkError.ADDRESS_MISMATCH, "待确认的注册域名或提交路径已变化")
                }

                val localId = AccountRecord.newLocalId(
                    AccountType.PROTOCOL, data.account, data.issuer, data.submitUrl.canonical
                )
                val existing = store.loadAll()
                val previous = existing.firstOrNull { it.localId == localId }
                val record = AccountRecord(
                    localId = localId,
                    type = AccountType.PROTOCOL,
                    accountId = data.account,
                    remark = cleanRemark.ifBlank { previous?.remark.orEmpty() },
                    issuer = data.issuer,
                    submitUrlCanonical = data.submitUrl.canonical,
                    secretBase32 = data.secretBase32,
                    boundAtEpochMs = System.currentTimeMillis(),
                    bindingId = data.bindingId,
                    confirmedAtEpochMs = 0L,
                    algorithm = data.algorithm,
                    digits = data.digits,
                    periodSeconds = data.periodSeconds,
                    registeredDomain = data.registeredDomain,
                    submitPath = data.submitPath
                )
                store.writeAll(existing.filterNot { it.localId == localId } + record)
                record.toSummary()
            },
            onSuccess = { listener.onBound(it) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    /**
     * 第三步（可选但推荐）：调用服务端确认绑定：
     * `POST <API 前缀>/totp/v1/bindings/{bid}/confirm`，请求体 `{"code":"..."}`。
     *
     * 未确认的绑定不能用于登录（规范 §8.3(5)）。失败时本地记录保留，可稍后重试。
     */
    fun confirmBinding(localId: String, listener: BindingConfirmListener) {
        runAsync(
            block = {
                val record = requireProtocolRecord(localId)
                val bindingId = record.bindingId
                if (bindingId.isBlank()) {
                    throw SdkException(SdkError.INVALID_PAYLOAD, "缺少绑定标识，无法确认")
                }
                val pinned = PinnedEndpoint.fromStored(
                    record.submitUrlCanonical
                        ?: throw SdkException(SdkError.SECURE_STORAGE_ERROR, "缺少固化地址")
                )
                val code = Totp.generate(
                    decodeSecret(record), nowSeconds(), record.parameters
                )
                submitter.confirmBinding(pinned, bindingId, code)
                markConfirmed(record.localId)
            },
            onSuccess = { listener.onConfirmed(it) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    // ---------------------------------------------------------------- 标准 TOTP 账户

    /** 通过 `otpauth://totp` URI 添加标准 TOTP 账户。 */
    @JvmOverloads
    fun addStandardAccount(otpauthUri: String, remark: String = "", listener: BindListener) {
        runAsync(
            block = { addStandardAccountInternal(OtpauthUri.parse(otpauthUri), remark) },
            onSuccess = { listener.onBound(it) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    /** 通过手动录入（签发方 / 账户 / 密钥 / 参数）添加标准 TOTP 账户。 */
    @JvmOverloads
    fun addStandardAccount(
        issuer: String,
        accountId: String,
        secretBase32: String,
        parameters: TotpParameters = TotpParameters(),
        remark: String = "",
        listener: BindListener
    ) {
        runAsync(
            block = {
                val normalized = OtpauthAccount(
                    issuer = issuer.trim(),
                    accountId = accountId.trim(),
                    secretBase32 = secretBase32.trim(),
                    parameters = parameters
                )
                addStandardAccountInternal(normalized, remark)
            },
            onSuccess = { listener.onBound(it) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    private fun addStandardAccountInternal(account: OtpauthAccount, remark: String): AccountSummary {
        if (account.issuer.isBlank() && account.accountId.isBlank()) {
            throw SdkException(SdkError.INVALID_ARGUMENT, "签发方与账户名不能同时为空")
        }
        if (account.issuer.length > 64) {
            throw SdkException(SdkError.INVALID_ARGUMENT, "签发方名称不能超过 64 个字符")
        }
        if (account.accountId.length > 255) {
            throw SdkException(SdkError.INVALID_ARGUMENT, "账户名不能超过 255 个字符")
        }
        val secretBytes = try {
            Base32.decode(account.secretBase32)
        } catch (e: IllegalArgumentException) {
            throw SdkException(SdkError.INVALID_ARGUMENT, "密钥不是合法 Base32", e)
        }
        if (secretBytes.size < 10) {
            throw SdkException(SdkError.INVALID_ARGUMENT, "密钥长度不足（至少 80 位）")
        }
        if (secretBytes.size > 128) {
            throw SdkException(SdkError.INVALID_ARGUMENT, "密钥长度超出限制")
        }

        val cleanRemark = normalizeRemark(remark)
        val secret = Base32.encode(secretBytes)
        val localId = AccountRecord.newLocalId(
            AccountType.STANDARD, account.accountId, account.issuer, null
        )
        val existing = store.loadAll()
        val previous = existing.firstOrNull { it.localId == localId }
        val record = AccountRecord(
            localId = localId,
            type = AccountType.STANDARD,
            accountId = account.accountId,
            remark = cleanRemark.ifBlank { previous?.remark.orEmpty() },
            issuer = account.issuer,
            submitUrlCanonical = null,
            secretBase32 = secret,
            boundAtEpochMs = System.currentTimeMillis(),
            bindingId = "",
            confirmedAtEpochMs = System.currentTimeMillis(),
            algorithm = account.parameters.algorithm,
            digits = account.parameters.digits,
            periodSeconds = account.parameters.periodSeconds
        )
        store.writeAll(existing.filterNot { it.localId == localId } + record)
        SdkLog.d("standard account added")
        return record.toSummary()
    }

    // ---------------------------------------------------------------- 扫码登录

    /**
     * 解析登录二维码，并用 `url` 的注册域名与**全部**本地固化记录比对。
     *
     * - 无候选：回调 [SdkError.ADDRESS_MISMATCH]，不计算动态码、不发起任何请求；
     * - 有候选：回调 [LoginScanResult]，由宿主决定是否弹选择框、是否做生物识别门禁。
     */
    fun verifyLoginQr(qrPayload: String, listener: LoginScanListener) {
        runAsync(
            block = { matchLoginQr(qrPayload) },
            onSuccess = { listener.onReady(it) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    /**
     * 对选中的候选账户计算动态码并提交到**该账户的固化地址**。
     *
     * [localId] 必须属于 [result] 的候选集合，否则拒绝（防止跨固化地址混用）。
     */
    fun submitLogin(result: LoginScanResult, localId: String, listener: LoginListener) {
        runAsync(
            block = { submitLoginInternal(result, localId) },
            onSuccess = { listener.onResult(it) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    /**
     * 便捷方法：候选唯一时直接提交；多个候选返回 [SdkError.ACCOUNT_SELECTION_REQUIRED]。
     *
     * 需要生物识别门禁的宿主应改用 [verifyLoginQr] + [submitLogin] 两段式。
     */
    fun scanLogin(qrPayload: String, listener: LoginListener) {
        runAsync(
            block = {
                val result = matchLoginQr(qrPayload)
                if (result.candidates.size != 1) {
                    throw SdkException(SdkError.ACCOUNT_SELECTION_REQUIRED)
                }
                submitLoginInternal(result, result.candidates.first().localId)
            },
            onSuccess = { listener.onResult(it) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    private data class CandidateMatch(
        val record: AccountRecord,
        val pinnedCanonical: String
    )

    private fun matchLoginQr(qrPayload: String): LoginScanResult {
        val qr = LoginQrParser.parse(qrPayload, nowSeconds(), config.clockSkewSeconds)

        // 先按注册域名筛；同一注册域名下的多个账户都作为候选，由用户选择。
        val matches = store.loadAll().mapNotNull { record ->
            if (record.type != AccountType.PROTOCOL) return@mapNotNull null
            if (!record.isConfirmed) return@mapNotNull null
            val storedUrl = record.submitUrlCanonical ?: return@mapNotNull null
            val domain = record.registeredDomain.ifBlank {
                runCatching { CanonicalAddress.parse(storedUrl).registeredDomain }.getOrNull().orEmpty()
            }
            if (domain != qr.registeredDomain) return@mapNotNull null
            CandidateMatch(record, storedUrl)
        }

        if (matches.isEmpty()) {
            throw SdkException(SdkError.ADDRESS_MISMATCH)
        }

        val candidates = matches
            .sortedByDescending { it.record.boundAtEpochMs }
            .map {
                LoginCandidate(
                    localId = it.record.localId,
                    accountId = it.record.accountId,
                    displayName = it.record.displayName,
                    issuer = it.record.issuer,
                    submitUrl = it.pinnedCanonical
                )
            }

        return LoginScanResult(
            candidates = candidates,
            expiresAtEpochMs = qr.expiresAt * 1000L,
            lenientAddressMatch = false,
            submitUrl = candidates.first().submitUrl,
            token = qr.token,
            rawPayload = qr.rawPayload
        )
    }

    private fun submitLoginInternal(result: LoginScanResult, localId: String): SubmitResult {
        if (result.candidates.none { it.localId == localId }) {
            throw SdkException(SdkError.ACCOUNT_TYPE_MISMATCH, "所选账户不是该二维码的候选账户")
        }
        // 重新解析：确保 token 未过期、二维码内容未被替换
        val qr: LoginQrData = LoginQrParser.parse(
            result.rawPayload, nowSeconds(), config.clockSkewSeconds
        )
        val record = requireProtocolRecord(localId)
        if (!record.isConfirmed) {
            throw SdkException(SdkError.NOT_BOUND, "该账户尚未完成绑定确认")
        }
        val pinned = PinnedEndpoint.fromStored(
            record.submitUrlCanonical
                ?: throw SdkException(SdkError.SECURE_STORAGE_ERROR, "缺少固化地址")
        )
        // 二次确认：登录码的注册域名必须与绑定时的 dom 注册域名一致
        val domain = record.registeredDomain.ifBlank { pinned.url.registeredDomain }
        if (domain != qr.registeredDomain) {
            throw SdkException(SdkError.ADDRESS_MISMATCH)
        }

        val code = Totp.generate(decodeSecret(record), nowSeconds(), record.parameters)
        // 提交目标固定为绑定时保存的完整地址 https://<dom><path>，请求体只含 code + token。
        return submitter.submitCode(pinned, qr.token, code)
    }

    // ---------------------------------------------------------------- 账户管理

    /** 修改账户备注（1–32 个字符；传空串表示恢复默认展示名）。 */
    fun renameAccount(localId: String, remark: String, listener: AccountOperationListener) {
        runAsync(
            block = {
                val clean = normalizeRemark(remark)
                if (remark.isNotBlank() && clean.isEmpty()) {
                    throw SdkException(SdkError.INVALID_ARGUMENT, "备注不能只包含空白字符")
                }
                val all = store.loadAll()
                val index = all.indexOfFirst { it.localId == localId }
                if (index < 0) throw SdkException(SdkError.NOT_BOUND, "账户不存在")
                val updated = all.toMutableList()
                updated[index] = updated[index].copy(remark = clean)
                store.writeAll(updated)
                updated.sortedByDescending { it.boundAtEpochMs }.map { it.toSummary() }
            },
            onSuccess = { listener.onSuccess(it) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    /** 删除账户。 */
    fun removeAccount(localId: String, listener: AccountOperationListener) {
        runAsync(
            block = {
                val all = store.loadAll()
                val remaining = all.filterNot { it.localId == localId }
                if (remaining.size == all.size) {
                    throw SdkException(SdkError.NOT_BOUND, "账户不存在")
                }
                if (remaining.isEmpty()) {
                    store.clearAll()
                    emptyList<AccountSummary>()
                } else {
                    store.writeAll(remaining)
                    remaining.sortedByDescending { it.boundAtEpochMs }.map { it.toSummary() }
                }
            },
            onSuccess = { listener.onSuccess(it) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    /**
     * 清空本机全部账户并删除 Keystore 主密钥。
     *
     * 说明：服务端解绑接口 `/totp/v1/bindings/{bid}/revoke` 需要管理员令牌，
     * App 不持有该令牌，因此本方法只清理本机数据；服务端解绑需由管理端完成（规范 S12）。
     */
    fun unbindAll(listener: AccountOperationListener) {
        runAsync(
            block = {
                store.clearAll()
                emptyList<AccountSummary>()
            },
            onSuccess = { listener.onSuccess(it) },
            onFailure = { listener.onFailure(it.error, it.message, it.cause) }
        )
    }

    /** 释放内部线程。释放后不可再调用其它方法。 */
    fun close() {
        closed = true
        executor.shutdownNow()
    }

    // ---------------------------------------------------------------- 内部

    private fun markConfirmed(localId: String): AccountSummary {
        val all = store.loadAll()
        val index = all.indexOfFirst { it.localId == localId }
        if (index < 0) throw SdkException(SdkError.NOT_BOUND, "账户不存在")
        val updated = all.toMutableList()
        updated[index] = updated[index].copy(confirmedAtEpochMs = System.currentTimeMillis())
        store.writeAll(updated)
        return updated[index].toSummary()
    }

    private fun requireProtocolRecord(localId: String): AccountRecord {
        val record = store.loadAll().firstOrNull { it.localId == localId }
            ?: throw SdkException(SdkError.NOT_BOUND, "账户不存在")
        if (record.type != AccountType.PROTOCOL) {
            throw SdkException(SdkError.ACCOUNT_TYPE_MISMATCH, "标准型账户不支持扫码提交")
        }
        return record
    }

    private fun decodeSecret(record: AccountRecord): ByteArray = try {
        Base32.decode(record.secretBase32)
    } catch (e: IllegalArgumentException) {
        throw SdkException(SdkError.SECURE_STORAGE_ERROR, "本地密钥损坏", e)
    }

    private fun normalizeRemark(raw: String): String {
        val clean = raw.trim()
        if (clean.length > MAX_REMARK_LENGTH) {
            throw SdkException(SdkError.INVALID_ARGUMENT, "备注不能超过 $MAX_REMARK_LENGTH 个字符")
        }
        return clean
    }

    private fun BindingQrData.toPreview(): BindPreview = BindPreview(
        accountId = account,
        issuer = issuer,
        submitUrl = submitUrl.canonical,
        bindingId = bindingId,
        parameters = parameters,
        expiresAtEpochMs = expiresAt?.times(1000L),
        host = submitUrl.host,
        registeredDomain = registeredDomain,
        submitPath = submitPath,
        rawPayload = rawPayload
    )

    private fun AccountRecord.toSummary(): AccountSummary = AccountSummary(
        localId = localId,
        type = type,
        accountId = accountId,
        remark = remark,
        displayName = displayName,
        issuer = issuer,
        submitUrl = submitUrlCanonical,
        bindingId = bindingId.ifBlank { null },
        isConfirmed = isConfirmed,
        boundAtEpochMs = boundAtEpochMs,
        parameters = parameters,
        registeredDomain = registeredDomain.ifBlank {
            submitUrlCanonical?.let { runCatching { CanonicalAddress.parse(it).registeredDomain }.getOrNull() }
        },
        submitPath = submitPath.ifBlank {
            submitUrlCanonical?.let { runCatching { CanonicalAddress.parse(it).submitPath }.getOrNull() }
        }
    )

    private fun nowSeconds(): Long = System.currentTimeMillis() / 1000L

    private fun <T> runAsync(
        block: () -> T,
        onSuccess: (T) -> Unit,
        onFailure: (SdkException) -> Unit
    ) {
        if (closed) {
            onFailure(SdkException(SdkError.INTERNAL_ERROR, "SDK 已关闭"))
            return
        }
        try {
            executor.execute {
                var value: T? = null
                var error: SdkException? = null
                try {
                    value = block()
                } catch (e: SdkException) {
                    error = e
                } catch (t: Throwable) {
                    error = SdkException(SdkError.INTERNAL_ERROR, t.message, t)
                }
                val result = value
                val failure = error
                mainHandler.post {
                    if (failure != null) {
                        onFailure(failure)
                    } else if (result != null) {
                        onSuccess(result)
                    } else {
                        onFailure(SdkException(SdkError.INTERNAL_ERROR, "未返回结果"))
                    }
                }
            }
        } catch (e: RejectedExecutionException) {
            onFailure(SdkException(SdkError.INTERNAL_ERROR, "SDK 已关闭", e))
        }
    }
}
