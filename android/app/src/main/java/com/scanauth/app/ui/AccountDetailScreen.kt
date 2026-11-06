package com.scanauth.app.ui

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
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.fragment.app.FragmentActivity
import com.scanauth.app.AccountOpState
import com.scanauth.app.AppViewModel
import com.scanauth.app.biometric.BiometricGate
import com.scanauth.sdk.AccountSummary
import com.scanauth.sdk.AccountType
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 账户详情：重命名、删除、单账户二维码导出与未确认绑定的重试。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountDetailScreen(
    localId: String,
    viewModel: AppViewModel,
    activity: FragmentActivity?,
    onExportQr: (String) -> Unit,
    onBack: () -> Unit
) {
    val accounts by viewModel.accounts.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val accountOp by viewModel.accountOp.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current

    val account = accounts.firstOrNull { it.localId == localId }

    var nowSeconds by remember { mutableLongStateOf(System.currentTimeMillis() / 1000L) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(250L)
            nowSeconds = System.currentTimeMillis() / 1000L
        }
    }

    var showRename by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf(false) }
    var exportTarget by remember { mutableStateOf<AccountSummary?>(null) }
    var exportRiskAccepted by remember { mutableStateOf(false) }

    LaunchedEffect(accountOp) {
        when (val op = accountOp) {
            is AccountOpState.Done -> snackbarHostState.showSnackbar(op.message)
            is AccountOpState.Failed -> snackbarHostState.showSnackbar(op.message)
            else -> Unit
        }
    }

    // 删除成功后自动返回列表
    LaunchedEffect(accounts, pendingDelete) {
        if (pendingDelete && accounts.none { it.localId == localId }) {
            viewModel.resetAccountOp()
            onBack()
        }
    }

    if (showRename && account != null) {
        RenameDialog(
            initial = account.remark,
            onDismiss = { showRename = false },
            onConfirm = { text ->
                showRename = false
                viewModel.renameAccount(account.localId, text)
            }
        )
    }

    if (showDelete && account != null) {
        val isProtocol = account.type == AccountType.PROTOCOL
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text("删除账户") },
            text = {
                Text(
                    if (isProtocol) {
                        "将从本机删除「${account.displayName}」及其密钥。服务端的绑定记录不会自动解除，" +
                            "如需彻底解绑请联系管理员。删除后该账户将无法再用于扫码登录。"
                    } else {
                        "将从本机删除「${account.displayName}」。删除后无法恢复，请确认已在其他认证器中备份密钥。"
                    }
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showDelete = false
                    pendingDelete = true
                    viewModel.removeAccount(account.localId)
                }) { Text("删除") }
            },
            dismissButton = {
                TextButton(onClick = { showDelete = false }) { Text("取消") }
            }
        )
    }

    exportTarget?.let { target ->
        val isProtocol = target.type == AccountType.PROTOCOL
        AlertDialog(
            onDismissRequest = { exportTarget = null },
            title = { Text("导出二维码") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "屏幕上会显示「${target.displayName}」的 otpauth 二维码，" +
                            "其中包含该账户的密钥。请勿拍照或转发给他人。"
                    )
                    if (isProtocol) {
                        Text(
                            "导出后该账户的防钓鱼优势失效，任何扫码者都能独立生成动态码。",
                            color = MaterialTheme.colorScheme.error
                        )
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { exportRiskAccepted = !exportRiskAccepted },
                            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                        ) {
                            Checkbox(
                                checked = exportRiskAccepted,
                                onCheckedChange = { exportRiskAccepted = it }
                            )
                            Text("我已知晓风险，仍要导出", style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                    Text(
                        "二维码只在屏幕上展示，不写入剪贴板、不落盘、不进备份；" +
                            "界面已开启防截屏，点击后显示清晰内容，60 秒自动关闭。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            },
            confirmButton = {
                TextButton(
                    enabled = !isProtocol || exportRiskAccepted,
                    onClick = {
                        exportTarget = null
                        onExportQr(target.localId)
                    }
                ) { Text("显示二维码") }
            },
            dismissButton = {
                TextButton(onClick = { exportTarget = null }) { Text("取消") }
            }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("账户详情") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        if (account == null) {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).padding(32.dp),
                verticalArrangement = Arrangement.Center
            ) {
                Text("账户不存在或已被删除", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(12.dp))
                OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                    Text("返回")
                }
            }
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        account.displayName,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        if (account.issuer.isBlank()) "未设置签发方" else account.issuer,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                AccountTypeChip(account.type)
            }

            Spacer(Modifier.height(4.dp))

            when (account.type) {
                AccountType.STANDARD -> StandardAccountBody(
                    account = account,
                    viewModel = viewModel,
                    nowSeconds = nowSeconds,
                    onCopy = { code ->
                        clipboard.setText(AnnotatedString(code))
                        scope.launch { snackbarHostState.showSnackbar("动态码已复制") }
                    }
                )

                AccountType.PROTOCOL -> {
                    val period = account.parameters.periodSeconds.coerceAtLeast(1L)
                    val counterStart = (nowSeconds / period) * period
                    val secondsLeft = (period - (nowSeconds % period)).coerceAtLeast(1L)
                    // 开关关闭时 SDK 立即返回 null，界面随即清空动态码
                    val revealedCode = remember(account.localId, counterStart, settings.showProtocolCodes) {
                        viewModel.protocolCode(account.localId, counterStart)
                    }
                    ProtocolAccountBody(
                        account = account,
                        revealedCode = revealedCode,
                        secondsLeft = secondsLeft,
                        progress = secondsLeft.toFloat() / period,
                        onCopy = { code ->
                            clipboard.setText(AnnotatedString(code))
                            scope.launch { snackbarHostState.showSnackbar("动态码已复制") }
                        },
                        onRetryConfirm = { viewModel.retryConfirmBinding(account.localId) }
                    )
                }
            }

            Spacer(Modifier.height(16.dp))
            OutlinedButton(
                onClick = {
                    val act = activity
                    if (act == null || !BiometricGate.canAuthenticate(act)) {
                        scope.launch {
                            snackbarHostState.showSnackbar("本机没有可用的本地认证方式，无法导出二维码")
                        }
                        return@OutlinedButton
                    }
                    BiometricGate.authenticate(
                        activity = act,
                        title = "导出账户二维码",
                        subtitle = "验证身份后才能显示二维码",
                        onSuccess = {
                            exportRiskAccepted = false
                            exportTarget = account
                        },
                        onFailure = { message ->
                            scope.launch {
                                snackbarHostState.showSnackbar("未通过认证：$message")
                            }
                        },
                        onUnavailable = { message ->
                            scope.launch { snackbarHostState.showSnackbar(message) }
                        }
                    )
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("导出二维码")
            }
            OutlinedButton(onClick = { showRename = true }, modifier = Modifier.fillMaxWidth()) {
                Text("修改备注")
            }
            OutlinedButton(onClick = { showDelete = true }, modifier = Modifier.fillMaxWidth()) {
                Text("删除账户")
            }
        }
    }
}

@Composable
private fun StandardAccountBody(
    account: AccountSummary,
    viewModel: AppViewModel,
    nowSeconds: Long,
    onCopy: (String) -> Unit
) {
    val period = account.parameters.periodSeconds.coerceAtLeast(1L)
    val counterStart = (nowSeconds / period) * period
    val secondsLeft = (period - (nowSeconds % period)).coerceAtLeast(1L)
    val code = remember(account.localId, counterStart) {
        // 标准型账户：由 SDK 在本地计算动态码
        viewModel.standardCode(account.localId, counterStart)
    }

    // 说明：增强型账户不会走到这个分支，SDK 也不会返回其动态码。
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("当前动态码", style = MaterialTheme.typography.labelMedium)
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = if (code.isNullOrEmpty()) "------" else formatTotpCode(code),
                    modifier = Modifier
                        .weight(1f)
                        .clickable(enabled = !code.isNullOrEmpty()) { code?.let(onCopy) },
                    fontSize = 30.sp,
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 2.sp
                )
                CountdownRing(progress = secondsLeft.toFloat() / period, secondsLeft = secondsLeft)
            }
            Text(
                "点击可复制。参数：${account.parameters.algorithm.uriName} · " +
                    "${account.parameters.digits} 位 · ${account.parameters.periodSeconds} 秒",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }

    LabeledRow("账户", account.accountId)
    LabeledRow("添加时间", formatTimestamp(account.boundAtEpochMs))
    if (account.remark.isNotBlank()) {
        LabeledRow("备注", account.remark)
    }
    Text(
        "移动端不提供批量备份导入导出；单个账户可通过上方「导出二维码」在屏幕上查看 otpauth 地址。",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun ProtocolAccountBody(
    account: AccountSummary,
    revealedCode: String?,
    secondsLeft: Long,
    progress: Float,
    onCopy: (String) -> Unit,
    onRetryConfirm: () -> Unit
) {
    MessageCard(
        title = "扫码型账户",
        message = if (revealedCode == null) {
            "该账户默认不显示动态码，只能通过在登录页扫描二维码提交；可在「设置 → 安全」中开启显示。"
        } else {
            "已开启显示扫码型动态码：六位码可被旁人看到，用完请及时在设置中关闭。扫码提交路径不变。"
        }
    )
    if (revealedCode != null) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = formatTotpCode(revealedCode),
                modifier = Modifier
                    .weight(1f)
                    .clickable { onCopy(revealedCode) },
                fontSize = 30.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium,
                letterSpacing = 2.sp
            )
            CountdownRing(progress = progress, secondsLeft = secondsLeft)
        }
        Text(
            "点击动态码可复制 · 剩余 $secondsLeft 秒",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
    LabeledRow("账户", account.accountId)
    if (account.remark.isNotBlank()) {
        LabeledRow("备注", account.remark)
    }
    LabeledRow("绑定时间", formatTimestamp(account.boundAtEpochMs))
    account.bindingId?.let { LabeledRow("绑定标识", it) }

    Text(
        "提交地址（已固化）",
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    Card(modifier = Modifier.fillMaxWidth()) {
        SelectionContainer {
            Text(
                account.submitUrl.orEmpty(),
                modifier = Modifier.padding(12.dp),
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace)
            )
        }
    }

    if (!account.isConfirmed) {
        MessageCard(
            title = "尚未完成服务端确认",
            message = "在确认成功之前，该账户无法用于扫码登录。请确认设备网络可用后重试。",
            isError = true
        )
        Button(onClick = onRetryConfirm, modifier = Modifier.fillMaxWidth()) {
            Text("重新确认绑定")
        }
    }
}

@Composable
private fun RenameDialog(
    initial: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("修改备注") },
        text = {
            Column {
                Text(
                    "备注只保存在本机，不会写入二维码，也不会上送服务器。留空则恢复默认名称。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it.take(64) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("备注") },
                    supportingText = { Text("${text.length}/64") },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(text) }) { Text("保存") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        }
    )
}
