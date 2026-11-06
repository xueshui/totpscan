package com.scanauth.app.ui

import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.view.WindowManager
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.scanauth.app.AppViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** 二维码在屏幕上的存活时间。到时自动关闭并回收 Bitmap。 */
private const val QR_LIFETIME_SECONDS = 60

/**
 * 单账户 otpauth 二维码展示页。
 *
 * - 进入即对窗口开启 `FLAG_SECURE`，离开时清除（禁止截屏 / 录屏 / 最近任务预览）；
 * - 默认显示模糊遮罩，点击后才渲染清晰二维码；
 * - 60 秒后自动关闭并回收 Bitmap；
 * - 不提供复制，不写剪贴板、不写日志、不落盘。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportQrScreen(
    localId: String,
    viewModel: AppViewModel,
    activity: FragmentActivity?,
    onClose: () -> Unit
) {
    val accounts by viewModel.accounts.collectAsStateWithLifecycle()
    val account = accounts.firstOrNull { it.localId == localId }

    // 防截屏：仅在本页存活期间生效
    DisposableEffect(activity) {
        val window = activity?.window
        window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        onDispose { window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }
    }

    var uri by remember { mutableStateOf<String?>(null) }
    var clearBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var blurredBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var revealed by remember { mutableStateOf(false) }
    var secondsLeft by remember { mutableIntStateOf(QR_LIFETIME_SECONDS) }
    var failed by remember { mutableStateOf(false) }

    LaunchedEffect(localId) {
        val built = withContext(Dispatchers.IO) { viewModel.otpauthUriFor(localId) }
        uri = built
        if (built == null) {
            failed = true
            return@LaunchedEffect
        }
        val bitmap = withContext(Dispatchers.Default) { encodeQr(built) }
        if (bitmap == null) {
            failed = true
            return@LaunchedEffect
        }
        clearBitmap = bitmap
        blurredBitmap = downscaleForMask(bitmap)
    }

    // 60 秒后自动关闭；Bitmap 在 onDispose 中回收
    LaunchedEffect(Unit) {
        repeat(QR_LIFETIME_SECONDS) {
            delay(1_000)
            secondsLeft--
        }
        onClose()
    }

    DisposableEffect(Unit) {
        onDispose {
            clearBitmap?.recycle()
            blurredBitmap?.recycle()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("导出二维码") },
                navigationIcon = {
                    IconButton(onClick = onClose) {
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
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = account?.displayName ?: localId,
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center
            )
            Text(
                text = "otpauth://totp/…",
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Card(shape = RoundedCornerShape(16.dp)) {
                Box(
                    modifier = Modifier
                        .size(288.dp)
                        .background(Color.White)
                        .clickable(enabled = !revealed && blurredBitmap != null) { revealed = true },
                    contentAlignment = Alignment.Center
                ) {
                    val visible = if (revealed) clearBitmap else blurredBitmap
                    if (visible != null) {
                        Image(
                            bitmap = visible.asImageBitmap(),
                            contentDescription = if (revealed) "账户 otpauth 二维码" else "二维码已模糊遮挡",
                            modifier = Modifier
                                .fillMaxSize()
                                .clip(RoundedCornerShape(16.dp)),
                            contentScale = androidx.compose.ui.layout.ContentScale.Fit,
                            filterQuality = if (revealed) FilterQuality.High else FilterQuality.Medium
                        )
                    }
                    if (!revealed) {
                        Column(
                            modifier = Modifier
                                .clip(RoundedCornerShape(24.dp))
                                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.92f))
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Icon(Icons.Filled.Lock, contentDescription = null)
                            Spacer(Modifier.height(4.dp))
                            Text("点击显示二维码", style = MaterialTheme.typography.labelLarge)
                        }
                    }
                    if (failed) {
                        Text(
                            "无法生成二维码",
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }

            Text(
                text = "该二维码包含账户密钥。本页已开启防截屏，请勿拍照或转发；" +
                    "点击后 $QR_LIFETIME_SECONDS 秒自动关闭并清除图像（剩余 $secondsLeft 秒）。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            if (account != null && account.type == com.scanauth.sdk.AccountType.PROTOCOL) {
                Text(
                    text = "扫码型账户：导出后该账户的防钓鱼优势失效，任何扫码者都能独立生成动态码。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}

/** 用 ZXing 在本地生成二维码位图（无网络依赖）。 */
private fun encodeQr(content: String, size: Int = 720): Bitmap? = try {
    val hints = mapOf(
        EncodeHintType.MARGIN to 1,
        EncodeHintType.CHARACTER_SET to "UTF-8",
        EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M
    )
    val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size, hints)
    val pixels = IntArray(size * size)
    for (y in 0 until size) {
        val offset = y * size
        for (x in 0 until size) {
            pixels[offset + x] = if (matrix.get(x, y)) AndroidColor.BLACK else AndroidColor.WHITE
        }
    }
    Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
} catch (e: Exception) {
    null
}

/** 缩小后再放大即可得到模糊效果，兼容所有 API 级别（Modifier.blur 仅 31+ 生效）。 */
private fun downscaleForMask(source: Bitmap): Bitmap =
    Bitmap.createScaledBitmap(source, 28, 28, true)
