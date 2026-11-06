package com.scanauth.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.scanauth.app.AppViewModel
import com.scanauth.app.LoginFlowState
import com.scanauth.app.biometric.BiometricGate
import com.scanauth.sdk.LoginCandidate
import com.scanauth.sdk.LoginScanResult
import com.scanauth.sdk.SubmitResult
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

/**
 * 扫码登录确认页。
 *
 * 候选账户来自 SDK：用二维码 `sub` 与本地全部固化地址精确比对得出。
 * 0 个候选时 SDK 已在本机终止且没有发起任何网络请求；
 * 多个候选仅限同一固化地址下的多个账户，选择后随请求上行。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginScreen(
    viewModel: AppViewModel,
    activity: FragmentActivity?,
    onBack: () -> Unit,
    onDone: () -> Unit
) {
    val loginState by viewModel.loginState.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1000L)
            nowMs = System.currentTimeMillis()
        }
    }

    DisposableEffect(Unit) {
        onDispose { viewModel.resetLogin() }
    }

    BackHandler {
        viewModel.resetLogin()
        onBack()
    }

    fun finish() {
        viewModel.resetLogin()
        onDone()
    }

    fun submitWithGate() {
        if (!settings.biometricEnabled || activity == null) {
            viewModel.submitLogin()
            return
        }
        if (!BiometricGate.canAuthenticate(activity)) {
            scope.launch {
                snackbarHostState.showSnackbar("本机没有可用的生物识别，已直接提交")
            }
            viewModel.submitLogin()
            return
        }
        BiometricGate.authenticate(
            activity = activity,
            title = "验证身份后提交",
            subtitle = "即将向已绑定的服务器提交本次动态码",
            onSuccess = { viewModel.submitLogin() },
            onFailure = { message ->
                scope.launch { snackbarHostState.showSnackbar(message) }
            },
            onUnavailable = { message ->
                scope.launch { snackbarHostState.showSnackbar("$message，已直接提交") }
                viewModel.submitLogin()
            }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("扫码登录") },
                navigationIcon = {
                    IconButton(onClick = {
                        viewModel.resetLogin()
                        onBack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            when (val state = loginState) {
                LoginFlowState.Idle, LoginFlowState.Parsing -> {
                    LoadingBlock("正在校验登录二维码…")
                }

                is LoginFlowState.Select -> {
                    CandidateSelection(
                        result = state.result,
                        onSelect = { viewModel.selectCandidate(state.result, it) },
                        onCancel = {
                            viewModel.resetLogin()
                            onBack()
                        }
                    )
                }

                is LoginFlowState.Ready -> {
                    val remainSeconds = ((state.result.expiresAtEpochMs - nowMs) / 1000L).coerceAtLeast(0L)
                    ReadyContent(
                        result = state.result,
                        candidate = state.candidate,
                        remainSeconds = remainSeconds,
                        onSubmit = { submitWithGate() },
                        onCancel = {
                            viewModel.resetLogin()
                            onBack()
                        }
                    )
                }

                is LoginFlowState.Submitting -> {
                    LoadingBlock("正在向已绑定的服务器提交动态码…")
                }

                is LoginFlowState.Success -> {
                    SuccessContent(result = state.result, candidate = state.candidate, onDone = { finish() })
                }

                is LoginFlowState.SubmitFailed -> {
                    MessageCard(title = "提交失败", message = state.message, isError = true)
                    Text(
                        "本次二维码在有效期内仍可重试。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        OutlinedButton(
                            onClick = {
                                viewModel.resetLogin()
                                onBack()
                            },
                            modifier = Modifier.weight(1f)
                        ) { Text("重新扫码") }
                        Button(
                            onClick = { viewModel.retrySubmitLogin() },
                            modifier = Modifier.weight(1f)
                        ) { Text("重试") }
                    }
                }

                is LoginFlowState.Failed -> {
                    MessageCard(title = "无法完成登录", message = state.message, isError = true)
                    Text(
                        "常见原因：二维码已过期、扫描的不是登录二维码，或本机没有绑定该服务器的账户。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedButton(
                        onClick = {
                            viewModel.resetLogin()
                            onBack()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("重新扫码") }
                    OutlinedButton(onClick = { finish() }, modifier = Modifier.fillMaxWidth()) {
                        Text("返回首页")
                    }
                }
            }
        }
    }
}

@Composable
private fun CandidateSelection(
    result: LoginScanResult,
    onSelect: (LoginCandidate) -> Unit,
    onCancel: () -> Unit
) {
    Text(
        "本次二维码匹配到 ${result.candidates.size} 个账户，它们绑定在同一个地址上。请选择要提交的账户：",
        style = MaterialTheme.typography.bodyMedium
    )
    if (result.lenientAddressMatch) {
        MessageCard(
            title = "地址匹配较为宽松",
            message = "本机绑定的地址只包含协议与域名，任何该域名下的路径都会被视为同一服务器。" +
                "如非管理员明确要求，建议重新按完整地址绑定。",
            isError = true
        )
    }
    result.candidates.forEach { candidate ->
        Card(
            modifier = Modifier.fillMaxWidth().clickable { onSelect(candidate) }
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    candidate.displayName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    if (candidate.issuer.isBlank()) candidate.accountId else "${candidate.issuer} · ${candidate.accountId}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
    Spacer(Modifier.height(4.dp))
    OutlinedButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) { Text("取消") }
}

@Composable
private fun ReadyContent(
    result: LoginScanResult,
    candidate: LoginCandidate,
    remainSeconds: Long,
    onSubmit: () -> Unit,
    onCancel: () -> Unit
) {
    val expired = remainSeconds <= 0L
    MessageCard(
        title = "即将提交动态码",
        message = "将使用「${candidate.displayName}」的密钥计算动态码，并提交到下面这个已固化的地址。"
    )
    LabeledRow("账户", candidate.accountId)
    LabeledRow("提交地址", result.submitUrl)
    LabeledRow(
        "二维码剩余有效期",
        if (expired) "已过期，请重新扫描" else "$remainSeconds 秒"
    )
    if (result.lenientAddressMatch) {
        MessageCard(
            title = "地址匹配较为宽松",
            message = "本机绑定的地址只包含协议与域名，本次会向该域名下的路径提交。如非管理员明确要求，请重新按完整地址绑定。",
            isError = true
        )
    }
    if (expired) {
        Text(
            "二维码已过期，继续提交会被服务器拒绝。请返回重新扫描。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error
        )
    }
    Spacer(Modifier.height(4.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedButton(onClick = onCancel, modifier = Modifier.weight(1f)) { Text("取消") }
        Button(onClick = onSubmit, enabled = !expired, modifier = Modifier.weight(1f)) {
            Text("验证并提交")
        }
    }
}

@Composable
private fun SuccessContent(result: SubmitResult, candidate: LoginCandidate, onDone: () -> Unit) {
    MessageCard(
        title = "提交成功",
        message = "服务器已接受本次动态码，请回到网页完成登录。"
    )
    LabeledRow("账户", candidate.displayName)
    LabeledRow("提交地址", candidate.submitUrl)
    val serverMessage = result.serverMessage
    if (!serverMessage.isNullOrBlank()) {
        LabeledRow("服务器提示", serverMessage)
    }
    result.requestId?.let { LabeledRow("请求编号", it) }
    LabeledRow("响应时间", formatTimestamp(System.currentTimeMillis()))

    val offset = result.serverTimeOffsetSeconds
    if (offset != null && abs(offset) >= 30L) {
        MessageCard(
            title = "设备时间与服务器相差约 $offset 秒",
            message = "时间偏差过大可能导致动态码校验失败。建议在系统设置中开启自动校准时间后重试。",
            isError = true
        )
    }

    Spacer(Modifier.height(4.dp))
    Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text("完成") }
}
