package com.scanauth.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.scanauth.app.AppViewModel
import com.scanauth.sdk.AccountSummary
import com.scanauth.sdk.AccountType
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 首页：顶部扫码登录入口 + 账户列表。
 *
 * - 标准型账户：展示实时动态码与倒计时环，点击复制；
 * - 扫码型账户：默认**不展示动态码**，只提供扫码提交入口，避免用户手动输入而绕过地址绑定；
 *   仅当用户在设置中显式开启「显示扫码型账户的动态码」后，才展示六位码与倒计时（可复制）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    viewModel: AppViewModel,
    onOpenSettings: () -> Unit,
    onAddAccount: () -> Unit,
    onScanLogin: () -> Unit,
    onOpenAccount: (String) -> Unit
) {
    val accounts by viewModel.accounts.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current

    var nowSeconds by remember { mutableLongStateOf(System.currentTimeMillis() / 1000L) }

    LaunchedEffect(Unit) {
        viewModel.refresh()
        while (true) {
            delay(250L)
            nowSeconds = System.currentTimeMillis() / 1000L
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("扫码验证器") },
                actions = {
                    IconButton(onClick = onAddAccount) {
                        Icon(Icons.Filled.Add, contentDescription = "添加账户")
                    }
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Filled.Settings, contentDescription = "设置")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                ScanLoginCard(onClick = onScanLogin)
            }

            if (accounts.isEmpty()) {
                item {
                    EmptyAccounts(onScanLogin = onScanLogin, onAddAccount = onAddAccount)
                }
            } else {
                item { SectionTitle("我的账户（${accounts.size}）") }
                items(accounts, key = { it.localId }) { account ->
                    AccountCard(
                        account = account,
                        nowSeconds = nowSeconds,
                        viewModel = viewModel,
                        revealProtocolCodes = settings.showProtocolCodes,
                        onClick = { onOpenAccount(account.localId) },
                        onCopy = { code ->
                            clipboard.setText(AnnotatedString(code))
                            scope.launch { snackbarHostState.showSnackbar("动态码已复制") }
                        }
                    )
                }
            }

            item {
                Spacer(Modifier.height(8.dp))
                Text(
                    if (settings.showProtocolCodes) {
                        "已开启「显示扫码型账户的动态码」：列表中的六位码可被旁人看到，建议仅在私密环境使用，用完请及时关闭。"
                    } else {
                        "扫码型账户的动态码默认不显示，只能通过扫描登录二维码提交；可在「设置 → 安全」中开启显示。"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun ScanLoginCard(onClick: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer
        )
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Icon(
                Icons.Filled.QrCodeScanner,
                contentDescription = null,
                modifier = Modifier.size(40.dp)
            )
            Column(Modifier.weight(1f)) {
                Text("扫码登录", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Text(
                    "扫描网页上的登录二维码，自动匹配已绑定的服务器",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

@Composable
private fun AccountCard(
    account: AccountSummary,
    nowSeconds: Long,
    viewModel: AppViewModel,
    revealProtocolCodes: Boolean,
    onClick: () -> Unit,
    onCopy: (String) -> Unit
) {
    val period = account.parameters.periodSeconds.coerceAtLeast(1L)
    val counterStart = (nowSeconds / period) * period
    val secondsLeft = (period - (nowSeconds % period)).coerceAtLeast(1L)
    val progress = secondsLeft.toFloat() / period.toFloat()

    Card(modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        text = account.displayName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    val secondary = buildString {
                        if (account.issuer.isNotBlank()) append(account.issuer)
                        if (account.accountId.isNotBlank() && account.accountId != account.displayName) {
                            if (isNotEmpty()) append(" · ")
                            append(account.accountId)
                        }
                    }
                    if (secondary.isNotBlank()) {
                        Text(
                            text = secondary,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                AccountTypeChip(account.type)
            }

            Spacer(Modifier.height(12.dp))

            when (account.type) {
                AccountType.STANDARD -> StandardCodeRow(
                    account = account,
                    counterStart = counterStart,
                    secondsLeft = secondsLeft,
                    progress = progress,
                    viewModel = viewModel,
                    onCopy = onCopy
                )

                AccountType.PROTOCOL -> if (revealProtocolCodes) {
                    ProtocolCodeRow(
                        account = account,
                        counterStart = counterStart,
                        secondsLeft = secondsLeft,
                        progress = progress,
                        viewModel = viewModel,
                        onCopy = onCopy
                    )
                } else {
                    ProtocolInfoRow(account)
                }
            }
        }
    }
}

@Composable
private fun StandardCodeRow(
    account: AccountSummary,
    counterStart: Long,
    secondsLeft: Long,
    progress: Float,
    viewModel: AppViewModel,
    onCopy: (String) -> Unit
) {
    // 每个时间步只计算一次，避免重组时重复计算
    val code = remember(account.localId, counterStart) {
        viewModel.standardCode(account.localId, counterStart)
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = if (code.isNullOrEmpty()) "------" else formatTotpCode(code),
            modifier = Modifier
                .weight(1f)
                .clickable(enabled = !code.isNullOrEmpty()) { code?.let(onCopy) },
            fontSize = 30.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium,
            letterSpacing = 2.sp
        )
        CountdownRing(progress = progress, secondsLeft = secondsLeft)
    }
    Text(
        text = "点击动态码可复制",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Start
    )
}

@Composable
private fun ProtocolCodeRow(
    account: AccountSummary,
    counterStart: Long,
    secondsLeft: Long,
    progress: Float,
    viewModel: AppViewModel,
    onCopy: (String) -> Unit
) {
    // 仅当设置开关打开时 SDK 才返回该账户的动态码；关闭后本组件整段移出组合树
    val code = remember(account.localId, counterStart) {
        viewModel.protocolCode(account.localId, counterStart)
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = if (code.isNullOrEmpty()) "------" else formatTotpCode(code),
            modifier = Modifier
                .weight(1f)
                .clickable(enabled = !code.isNullOrEmpty()) { code?.let(onCopy) },
            fontSize = 30.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium,
            letterSpacing = 2.sp
        )
        CountdownRing(progress = progress, secondsLeft = secondsLeft)
    }
    Text(
        text = "已开启显示扫码型动态码 · 点击可复制 · 旁人可见，请注意环境",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.error
    )
    Text(
        text = "提交地址：${hostOf(account.submitUrl)}（扫码提交路径不变）",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun ProtocolInfoRow(account: AccountSummary) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = "提交地址：${hostOf(account.submitUrl)}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = if (account.isConfirmed) {
                "已确认，可在登录页扫码提交（不显示动态码）"
            } else {
                "尚未完成服务端确认，暂时无法登录，请进入详情页完成确认"
            },
            style = MaterialTheme.typography.bodySmall,
            color = if (account.isConfirmed) {
                MaterialTheme.colorScheme.onSurfaceVariant
            } else {
                MaterialTheme.colorScheme.error
            }
        )
    }
}
