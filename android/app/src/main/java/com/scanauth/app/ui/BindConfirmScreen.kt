package com.scanauth.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.scanauth.app.AppViewModel
import com.scanauth.app.BindConfirmState
import com.scanauth.app.BindFlowState
import com.scanauth.sdk.BindPreview

/**
 * 绑定确认页：展示待固化的提交地址（唯一允许后续提交的目标）并允许填写本地备注。
 *
 * 地址来自已验签的绑定二维码，但**必须由用户肉眼确认**后才写入安全存储。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BindConfirmScreen(
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onDone: () -> Unit
) {
    val bindState by viewModel.bindState.collectAsStateWithLifecycle()
    val confirmState by viewModel.confirmState.collectAsStateWithLifecycle()
    var remark by rememberSaveable { mutableStateOf("") }

    val busy = confirmState is BindConfirmState.Saving || confirmState is BindConfirmState.Confirming

    DisposableEffect(Unit) {
        onDispose { viewModel.resetBind() }
    }

    BackHandler(enabled = !busy) {
        viewModel.resetBind()
        onBack()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("确认绑定") },
                navigationIcon = {
                    IconButton(
                        onClick = {
                            if (!busy) {
                                viewModel.resetBind()
                                onBack()
                            }
                        }
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            when (val state = bindState) {
                BindFlowState.Idle, BindFlowState.Parsing -> {
                    LoadingBlock("正在校验二维码签名…")
                }

                is BindFlowState.Failed -> {
                    MessageCard(
                        title = "无法绑定该二维码",
                        message = state.message,
                        isError = true
                    )
                    OutlinedButton(
                        onClick = {
                            viewModel.resetBind()
                            onBack()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("返回重新扫描") }
                }

                is BindFlowState.NeedsConfirm -> {
                    when (val confirm = confirmState) {
                        is BindConfirmState.Confirmed -> {
                            BindSuccessContent(
                                displayName = confirm.account.displayName,
                                submitUrl = confirm.account.submitUrl.orEmpty(),
                                onDone = {
                                    viewModel.resetBind()
                                    onDone()
                                }
                            )
                        }

                        is BindConfirmState.StoredOnly -> {
                            StoredOnlyContent(
                                message = confirm.message,
                                onRetry = {
                                    viewModel.retryConfirmBinding(confirm.localId, bindFlow = true)
                                },
                                onLater = {
                                    viewModel.resetBind()
                                    onDone()
                                }
                            )
                        }

                        is BindConfirmState.Saving, is BindConfirmState.Confirming -> {
                            LoadingBlock("正在保存并完成服务端确认…")
                        }

                        else -> {
                            ConfirmForm(
                                preview = state.preview,
                                remark = remark,
                                onRemarkChange = { remark = it.take(64) },
                                errorMessage = (confirm as? BindConfirmState.Failed)?.message,
                                onCancel = {
                                    viewModel.resetBind()
                                    onBack()
                                },
                                onConfirm = { viewModel.confirmBind(state.preview, remark) }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ConfirmForm(
    preview: BindPreview,
    remark: String,
    onRemarkChange: (String) -> Unit,
    errorMessage: String?,
    onCancel: () -> Unit,
    onConfirm: () -> Unit
) {
    MessageCard(
        title = "请核对提交地址",
        message = "绑定后，本机只会向下面这个地址提交动态码，且不会接受其它地址。" +
            "请确认域名与路径（含查询串）和服务器管理员提供的一致。"
    )

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Column(Modifier.padding(14.dp)) {
            Text(
                "提交地址",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(4.dp))
            SelectionContainer {
                Text(
                    preview.submitUrl,
                    style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace)
                )
            }
        }
    }

    LabeledRow("签发方", preview.issuer)
    LabeledRow("账户", preview.accountId)
    LabeledRow(
        "动态码参数",
        "${preview.parameters.algorithm.uriName} · ${preview.parameters.digits} 位 · " +
            "${preview.parameters.periodSeconds} 秒"
    )
    LabeledRow("钉住注册域名", preview.registeredDomain)
    LabeledRow("钉住提交路径", preview.submitPath)

    OutlinedTextField(
        value = remark,
        onValueChange = onRemarkChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text("备注（可选，仅存本机）") },
        supportingText = { Text("${remark.length}/64，用于在列表中区分多个账户，不会上送服务器") },
        singleLine = true
    )

    if (errorMessage != null) {
        MessageCard(title = "绑定失败", message = errorMessage, isError = true)
    }

    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedButton(onClick = onCancel, modifier = Modifier.weight(1f)) {
            Text("取消")
        }
        Button(onClick = onConfirm, modifier = Modifier.weight(1f)) {
            Text("确认并绑定")
        }
    }
}

@Composable
private fun BindSuccessContent(displayName: String, submitUrl: String, onDone: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        MessageCard(
            title = "绑定成功",
            message = "「$displayName」已保存到本机并完成服务端确认，现在可以扫描该服务器的登录二维码。"
        )
        LabeledRow("提交地址", submitUrl)
        Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text("完成") }
    }
}

@Composable
private fun StoredOnlyContent(message: String, onRetry: () -> Unit, onLater: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        MessageCard(
            title = "已保存到本机，但服务端确认未完成",
            message = "$message\n\n在确认成功之前，该账户不能用于扫码登录。你可以稍后在账户详情页重试确认。",
            isError = true
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onLater, modifier = Modifier.weight(1f)) {
                Text("稍后处理")
            }
            Button(onClick = onRetry, modifier = Modifier.weight(1f)) {
                Text("重试确认")
            }
        }
    }
}
