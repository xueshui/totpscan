package com.scanauth.app.ui

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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.scanauth.app.AddAccountState
import com.scanauth.app.AppViewModel
import com.scanauth.sdk.TotpAlgorithm

/**
 * 添加标准 TOTP 账户。
 *
 * - [mode] = `manual`：手动输入签发方 / 账户 / 密钥与参数；
 * - [mode] = `uri`：粘贴 `otpauth://totp/...` 链接。
 *
 * 标准型账户只在本地计算动态码，不涉及固化地址与扫码提交。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddStandardScreen(
    mode: String,
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onDone: () -> Unit
) {
    val addState by viewModel.addState.collectAsStateWithLifecycle()
    val isUriMode = mode == "uri"

    var issuer by rememberSaveable { mutableStateOf("") }
    var accountId by rememberSaveable { mutableStateOf("") }
    var secret by rememberSaveable { mutableStateOf("") }
    var remark by rememberSaveable { mutableStateOf("") }
    var otpauthUri by rememberSaveable { mutableStateOf("") }
    var algorithm by rememberSaveable { mutableStateOf(TotpAlgorithm.SHA1) }
    var digits by rememberSaveable { mutableStateOf(6) }
    var periodText by rememberSaveable { mutableStateOf("30") }
    var showAdvanced by rememberSaveable { mutableStateOf(false) }
    var showSuccess by remember { mutableStateOf(false) }

    DisposableEffect(Unit) {
        viewModel.resetAddState()
        onDispose { viewModel.resetAddState() }
    }

    LaunchedEffect(addState) {
        if (addState is AddAccountState.Added) {
            showSuccess = true
        }
    }

    val failedMessage = (addState as? AddAccountState.Failed)?.message
    val working = addState is AddAccountState.Working

    if (showSuccess) {
        AlertDialog(
            onDismissRequest = { },
            title = { Text("账户已添加") },
            text = { Text("标准 TOTP 账户已保存到本机，可在首页查看动态码。") },
            confirmButton = {
                TextButton(onClick = {
                    showSuccess = false
                    onDone()
                }) { Text("完成") }
            }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (isUriMode) "从链接导入" else "添加标准账户") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
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
            Text(
                "标准型账户只在本机展示动态码，不参与扫码提交，也不会上送任何服务器地址。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (isUriMode) {
                OutlinedTextField(
                    value = otpauthUri,
                    onValueChange = { otpauthUri = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("otpauth 链接") },
                    placeholder = { Text("otpauth://totp/Example:me@example.com?secret=...") },
                    minLines = 3,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Uri,
                        imeAction = ImeAction.Done
                    )
                )
            } else {
                OutlinedTextField(
                    value = issuer,
                    onValueChange = { if (it.length <= 64) issuer = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("签发方（可选）") },
                    placeholder = { Text("例如 GitHub") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next)
                )
                OutlinedTextField(
                    value = accountId,
                    onValueChange = { if (it.length <= 255) accountId = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("账户 / 用户名") },
                    placeholder = { Text("例如 me@example.com") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next)
                )
                OutlinedTextField(
                    value = secret,
                    onValueChange = { secret = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("密钥（Base32）") },
                    supportingText = { Text("例如 JBSWY3DPEHPK3PXP；至少 16 个字符") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Ascii,
                        imeAction = ImeAction.Next
                    )
                )

                TextButton(onClick = { showAdvanced = !showAdvanced }) {
                    Text(if (showAdvanced) "收起高级选项" else "高级选项（算法 / 位数 / 周期）")
                }

                if (showAdvanced) {
                    Text("摘要算法", style = MaterialTheme.typography.labelMedium)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TotpAlgorithm.entries.forEach { item ->
                            FilterChip(
                                selected = algorithm == item,
                                onClick = { algorithm = item },
                                label = { Text(item.uriName) }
                            )
                        }
                    }

                    Text("动态码位数", style = MaterialTheme.typography.labelMedium)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(6, 8).forEach { item ->
                            FilterChip(
                                selected = digits == item,
                                onClick = { digits = item },
                                label = { Text("$item 位") }
                            )
                        }
                    }

                    OutlinedTextField(
                        value = periodText,
                        onValueChange = { text -> periodText = text.filter { it.isDigit() }.take(4) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("周期（秒）") },
                        supportingText = { Text("默认 30 秒，允许 1–3600") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Done
                        )
                    )
                }
            }

            OutlinedTextField(
                value = remark,
                onValueChange = { remark = it.take(64) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("备注（可选，仅存本机）") },
                supportingText = { Text("${remark.length}/64，仅用于本机展示") },
                singleLine = true
            )

            if (failedMessage != null) {
                MessageCard(title = "添加失败", message = failedMessage, isError = true)
            }

            Spacer(Modifier.height(4.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = onBack, enabled = !working) { Text("取消") }
                Button(
                    onClick = {
                        if (isUriMode) {
                            if (otpauthUri.isNotBlank()) {
                                viewModel.addStandardByUri(otpauthUri.trim(), remark)
                            }
                        } else if (accountId.isNotBlank() && secret.isNotBlank()) {
                            val period = periodText.toLongOrNull()?.coerceIn(1L, 3600L) ?: 30L
                            viewModel.addStandardManually(
                                issuer = issuer,
                                accountId = accountId,
                                secret = secret,
                                remark = remark,
                                algorithm = algorithm,
                                digits = digits,
                                periodSeconds = period
                            )
                        }
                    },
                    enabled = !working && if (isUriMode) {
                        otpauthUri.isNotBlank()
                    } else {
                        accountId.isNotBlank() && secret.isNotBlank()
                    }
                ) {
                    if (working) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                    } else {
                        Text("保存账户")
                    }
                }
            }
        }
    }

    if (addState is AddAccountState.Added) {
        showSuccess = true
    }
}
