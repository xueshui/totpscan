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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.scanauth.app.AccountOpState
import com.scanauth.app.AppViewModel
import com.scanauth.app.ThemeMode
import com.scanauth.app.biometric.BiometricGate
import kotlinx.coroutines.launch

/** 设置：主题、生物识别门禁、安全说明与本机数据清理。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: AppViewModel,
    activity: FragmentActivity?,
    onBack: () -> Unit
) {
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val accountOp by viewModel.accountOp.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    var showClearAll by remember { mutableStateOf(false) }
    var showProtocolRisk by remember { mutableStateOf(false) }
    var riskAccepted by remember { mutableStateOf(false) }

    val biometricSupported = remember(activity) {
        activity != null && BiometricGate.canAuthenticate(activity)
    }

    LaunchedEffect(accountOp) {
        when (val op = accountOp) {
            is AccountOpState.Done -> snackbarHostState.showSnackbar(op.message)
            is AccountOpState.Failed -> snackbarHostState.showSnackbar(op.message)
            else -> Unit
        }
    }

    if (showClearAll) {
        AlertDialog(
            onDismissRequest = { showClearAll = false },
            title = { Text("清除本机全部账户") },
            text = {
                Text(
                    "这会删除本机保存的所有扫码型账户与标准型账户，并销毁本地加密主密钥，操作不可撤销。" +
                        "服务端的绑定记录不会自动解除，如需彻底解绑请联系管理员。"
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showClearAll = false
                    viewModel.unbindAll()
                }) { Text("全部清除") }
            },
            dismissButton = {
                TextButton(onClick = { showClearAll = false }) { Text("取消") }
            }
        )
    }

    if (showProtocolRisk) {
        AlertDialog(
            onDismissRequest = { showProtocolRisk = false },
            title = { Text("开启显示扫码型动态码") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "开启后，扫码型账户的六位动态码会直接显示在账户列表与详情页，旁人可见，" +
                            "防钓鱼优势下降：动态码一旦被看到或拍下，在有效期内可被手动用于登录，" +
                            "不再受「必须扫到登录二维码才能提交」的保护。"
                    )
                    Text("关闭开关后立即恢复为不显示、不可复制。")
                    Row(
                        modifier = Modifier.fillMaxWidth().clickable { riskAccepted = !riskAccepted },
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(checked = riskAccepted, onCheckedChange = { riskAccepted = it })
                        Text("我已了解风险并确认开启", style = MaterialTheme.typography.bodyMedium)
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = riskAccepted,
                    onClick = {
                        showProtocolRisk = false
                        val act = activity
                        if (act == null || !BiometricGate.canAuthenticate(act)) {
                            scope.launch {
                                snackbarHostState.showSnackbar("本机没有可用的本地认证方式，无法开启")
                            }
                            return@TextButton
                        }
                        BiometricGate.authenticate(
                            activity = act,
                            title = "开启显示扫码型动态码",
                            subtitle = "验证身份后开启",
                            onSuccess = { viewModel.setShowProtocolCodes(true) },
                            onFailure = { message ->
                                scope.launch {
                                    snackbarHostState.showSnackbar("未通过认证：$message")
                                }
                            },
                            onUnavailable = { message ->
                                scope.launch { snackbarHostState.showSnackbar(message) }
                            }
                        )
                    }
                ) { Text("验证并开启") }
            },
            dismissButton = {
                TextButton(onClick = { showProtocolRisk = false }) { Text("取消") }
            }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("设置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
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
            Text("外观", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ThemeMode.entries.forEach { mode ->
                    FilterChip(
                        selected = settings.theme == mode,
                        onClick = { viewModel.setTheme(mode) },
                        label = {
                            Text(
                                when (mode) {
                                    ThemeMode.SYSTEM -> "跟随系统"
                                    ThemeMode.LIGHT -> "浅色"
                                    ThemeMode.DARK -> "深色"
                                }
                            )
                        }
                    )
                }
            }

            Spacer(Modifier.height(4.dp))
            Text("安全", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Column(Modifier.weight(1f)) {
                    Text("提交前验证身份", style = MaterialTheme.typography.bodyLarge)
                    Text(
                        if (biometricSupported) {
                            "扫码登录提交动态码前要求指纹 / 面容或设备密码确认。"
                        } else {
                            "本机没有可用的生物识别或设备凭据，开关不可用。"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(
                    checked = settings.biometricEnabled && biometricSupported,
                    onCheckedChange = { enabled ->
                        if (biometricSupported) viewModel.setBiometricEnabled(enabled)
                    },
                    enabled = biometricSupported
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Column(Modifier.weight(1f)) {
                    Text("显示扫码型账户的动态码", style = MaterialTheme.typography.bodyLarge)
                    Text(
                        "默认关闭。开启后扫码型账户会在列表与详情中显示六位码与倒计时，可复制；" +
                            "旁人可见，防钓鱼优势下降。关闭后立即隐藏并清空。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(
                    checked = settings.showProtocolCodes,
                    onCheckedChange = { enabled ->
                        if (enabled) {
                            riskAccepted = false
                            showProtocolRisk = true
                        } else {
                            // 关闭立即生效：UI 下一次重组就不再拿到动态码
                            viewModel.setShowProtocolCodes(false)
                        }
                    }
                )
            }

            Spacer(Modifier.height(4.dp))
            Text("安全说明", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            SecurityNotes()

            Spacer(Modifier.height(8.dp))
            Text("数据", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            OutlinedButton(
                onClick = { showClearAll = true },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("清除本机全部账户")
            }

            Spacer(Modifier.height(8.dp))
            Text(
                "扫码验证器 1.0.0\n支持 RFC 6238 标准 TOTP 与扫码增强型认证。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun SecurityNotes() {
    val notes = listOf(
        "只接受 HTTPS 提交地址；除本机回环地址外不允许明文 HTTP。",
        "扫码登录时，二维码中的地址必须与本机固化的地址精确匹配，否则立即终止且不发起任何网络请求。",
        "扫码型账户默认不显示、不复制动态码，只能通过扫码提交；仅在设置中显式开启并完成本地认证后才会展示。",
        "单账户「导出二维码」是把该账户的 otpauth 地址显示在屏幕上，需本地认证；不写剪贴板、不落盘、不进备份。",
        "密钥保存在系统 Keystore 保护的加密存储中，系统备份已关闭；仅通过受本地认证保护的单账户二维码对外展示。",
        "备注、动态码与一次性登录凭据不会写入日志。"
    )
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        notes.forEach { note ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("•", style = MaterialTheme.typography.bodySmall)
                Text(
                    note,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
