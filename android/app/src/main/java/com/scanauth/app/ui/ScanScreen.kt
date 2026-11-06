package com.scanauth.app.ui

import android.Manifest
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.net.Uri
import android.provider.Settings
import android.util.Log
import android.util.Size
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.core.Camera
import androidx.camera.core.CameraInfo
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.scanauth.app.camera.AnalysisSize
import com.scanauth.app.camera.AnalysisTiers
import com.scanauth.app.camera.QrCodeAnalyzer
import com.scanauth.app.camera.QrImageDecoder
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

private const val TAG = "ScanResolution"

/**
 * 通用扫码页。
 *
 * 覆盖的异常路径：未授权、永久拒绝（需去系统设置开启）、设备无相机、相机启动失败；
 * 所有失败路径都提供“手动粘贴二维码内容”的兜底入口。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScanScreen(
    title: String,
    subtitle: String,
    onBack: () -> Unit,
    onPayload: (String) -> Unit
) {
    val context = LocalContext.current
    val activity = remember(context) { context.findFragmentActivity() }

    val cameraAvailable = remember(context) {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    }
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    var permanentlyDenied by remember { mutableStateOf(false) }
    var cameraError by remember { mutableStateOf<String?>(null) }
    var showManualInput by remember { mutableStateOf(false) }
    // 防止相机连续回调触发多次导航
    var consumed by remember { mutableStateOf(false) }
    val deliver: (String) -> Unit = { text ->
        if (!consumed && text.isNotBlank()) {
            consumed = true
            onPayload(text)
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasPermission = granted
        if (!granted) {
            permanentlyDenied = activity != null &&
                !ActivityCompat.shouldShowRequestPermissionRationale(
                    activity,
                    Manifest.permission.CAMERA
                )
        }
    }

    LaunchedEffect(cameraAvailable) {
        if (cameraAvailable && !hasPermission) {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    // 从系统设置返回时重新检查权限，避免用户授权后仍停留在提示页
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                hasPermission = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.CAMERA
                ) == PackageManager.PERMISSION_GRANTED
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    if (showManualInput) {
        ManualPayloadDialog(
            onDismiss = { showManualInput = false },
            onConfirm = { text ->
                showManualInput = false
                deliver(text)
            }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    TextButton(onClick = { showManualInput = true }) { Text("手动输入") }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                !cameraAvailable -> {
                    ScanFallback(
                        title = "本机没有可用相机",
                        description = "你仍然可以手动粘贴二维码中的文本内容来完成本次操作。",
                        onBack = onBack,
                        onManualInput = { showManualInput = true }
                    )
                }

                !hasPermission -> {
                    ScanFallback(
                        title = "需要相机权限",
                        description = if (permanentlyDenied) {
                            "相机权限已被拒绝。请前往系统设置 › 应用 › 扫码验证器 › 权限，开启相机权限。"
                        } else {
                            "扫码需要使用相机。授权后即可扫描二维码，相机画面不会离开本机。"
                        },
                        primaryLabel = if (permanentlyDenied) "前往设置" else "重新授权",
                        onPrimary = {
                            if (permanentlyDenied) {
                                openAppSettings(context)
                            } else {
                                permissionLauncher.launch(Manifest.permission.CAMERA)
                            }
                        },
                        onBack = onBack,
                        onManualInput = { showManualInput = true }
                    )
                }

                cameraError != null -> {
                    ScanFallback(
                        title = "相机启动失败",
                        description = cameraError ?: "无法启动相机，请稍后重试或手动粘贴内容。",
                        primaryLabel = "重试",
                        onPrimary = { cameraError = null },
                        onBack = onBack,
                        onManualInput = { showManualInput = true }
                    )
                }

                else -> {
                    CameraPreview(
                        modifier = Modifier.fillMaxSize(),
                        onDecoded = deliver,
                        onError = { cameraError = it }
                    )
                    ScanOverlay(subtitle = subtitle)
                }
            }
        }
    }
}

@Composable
private fun ScanOverlay(subtitle: String) {
    Box(modifier = Modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .align(Alignment.Center)
                .size(240.dp)
                .border(
                    width = 2.dp,
                    color = Color.White.copy(alpha = 0.9f),
                    shape = RoundedCornerShape(16.dp)
                )
        )
        Text(
            text = subtitle,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(Color.Black.copy(alpha = 0.55f))
                .padding(24.dp),
            color = Color.White,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center
        )
        Text(
            text = "双指缩放 · 点击对焦",
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 92.dp)
                .background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(50))
                .padding(horizontal = 12.dp, vertical = 6.dp),
            color = Color.White.copy(alpha = 0.9f),
            style = MaterialTheme.typography.labelMedium
        )
    }
}

@Composable
private fun ScanFallback(
    title: String,
    description: String,
    onBack: () -> Unit,
    onManualInput: () -> Unit,
    primaryLabel: String? = null,
    onPrimary: (() -> Unit)? = null
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Spacer(Modifier.height(12.dp))
        Text(
            description,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(24.dp))
        if (primaryLabel != null && onPrimary != null) {
            Button(onClick = onPrimary, modifier = Modifier.fillMaxWidth()) {
                Text(primaryLabel)
            }
            Spacer(Modifier.height(8.dp))
        }
        OutlinedButton(onClick = onManualInput, modifier = Modifier.fillMaxWidth()) {
            Text("手动粘贴二维码内容")
        }
        Spacer(Modifier.height(8.dp))
        TextButton(onClick = onBack) { Text("返回") }
    }
}

@Composable
private fun CameraPreview(
    modifier: Modifier,
    onDecoded: (String) -> Unit,
    onError: (String) -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }
    val stillExecutor = remember { Executors.newSingleThreadExecutor() }
    // 手势回调需要始终拿到当前绑定的 Camera，避免闭包持有旧值
    val cameraRef = remember { AtomicReference<Camera?>(null) }

    DisposableEffect(lifecycleOwner) {
        val future = ProcessCameraProvider.getInstance(context)
        val mainExecutor = ContextCompat.getMainExecutor(context)
        val captureBusy = AtomicBoolean(false)
        var provider: ProcessCameraProvider? = null
        var unbound = false

        // ---- 自适应分析分辨率 ----
        // 取舍：解码开销随像素数近似线性增长，实际扫码速度取决于「帧率 × 单帧成功率」，
        // 因此默认档取「不超过 1920×1080 的最大档」而不是设备最大档；只有连续解不出时
        // 才逐档升到设备最大值，识别成功后立刻回到默认档，避免长时间高分辨率导致发热掉帧。
        var tiers = AnalysisTiers.fromSupported(emptyList())
        val currentTier = AtomicInteger(0)
        var analysis: ImageAnalysis? = null
        var analyzer: QrCodeAnalyzer? = null
        var switchingTier = false

        fun buildAnalysis(size: AnalysisSize): ImageAnalysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
            .setResolutionSelector(
                ResolutionSelector.Builder()
                    .setResolutionStrategy(
                        ResolutionStrategy(
                            Size(size.width, size.height),
                            ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                        )
                    )
                    .build()
            )
            .build()

        /** 换档：只重建并重绑分析用例，预览与抓拍用例保持不动。 */
        fun switchTo(index: Int) {
            val p = provider ?: return
            val a = analyzer ?: return
            if (switchingTier || index < 0 || index >= tiers.descending.size) return
            if (index == currentTier.get()) return
            switchingTier = true
            val previousIndex = currentTier.get()
            val previous = analysis
            try {
                val next = buildAnalysis(tiers.descending[index])
                next.setAnalyzer(analysisExecutor, a)
                previous?.let { p.unbind(it) }
                cameraRef.set(p.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, next))
                analysis = next
                currentTier.set(index)
                Log.d(TAG, "分析分辨率切到 ${tiers.descending[index]}（第 $index 档）")
            } catch (t: Throwable) {
                // 个别设备不接受该尺寸与预览/抓拍的组合，退回原档位继续扫码
                runCatching {
                    val restore = buildAnalysis(tiers.descending[previousIndex])
                    restore.setAnalyzer(analysisExecutor, a)
                    cameraRef.set(
                        p.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, restore)
                    )
                    analysis = restore
                    currentTier.set(previousIndex)
                }.onFailure {
                    if (!unbound) onError(it.message ?: "无法切换分析分辨率")
                }
            } finally {
                switchingTier = false
            }
        }

        future.addListener({
            try {
                val providerRef = future.get()
                provider = providerRef
                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }
                // 兜底抓拍显式要求最高档静态图（4:3 最大尺寸），不依赖默认取值
                val imageCapture = ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .setResolutionSelector(
                        ResolutionSelector.Builder()
                            .setResolutionStrategy(
                                ResolutionStrategy(
                                    Size(4032, 3024),
                                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                                )
                            )
                            .build()
                    )
                    .build()

                // 从设备支持的分析尺寸里分档，默认档 = 不超过 1080p 的最大一档
                val selector = CameraSelector.DEFAULT_BACK_CAMERA
                tiers = AnalysisTiers.fromSupported(
                    selector.filter(providerRef.availableCameraInfos)
                        .firstOrNull()
                        ?.let { supportedAnalysisSizes(it) }
                        .orEmpty()
                )
                currentTier.set(tiers.defaultIndex)
                val initialAnalysis = buildAnalysis(tiers.default)

                val codeAnalyzer = QrCodeAnalyzer(
                    onDecoded = { text ->
                        mainExecutor.execute {
                            // 认出来后回到默认档，避免长时间高分辨率发热掉帧
                            if (currentTier.get() != tiers.defaultIndex) switchTo(tiers.defaultIndex)
                            onDecoded(text)
                        }
                    },
                    onEscalate = {
                        // 失败累计够时间：升到候选里更大的下一档
                        mainExecutor.execute { switchTo(currentTier.get() - 1) }
                    },
                    onStillCaptureNeeded = {
                        captureStill(
                            context = context,
                            imageCapture = imageCapture,
                            busy = captureBusy,
                            executor = stillExecutor,
                            mainExecutor = mainExecutor,
                            onDecoded = onDecoded
                        )
                    },
                    canEscalate = { tiers.canEscalate(currentTier.get()) }
                )
                analyzer = codeAnalyzer
                initialAnalysis.setAnalyzer(analysisExecutor, codeAnalyzer)
                analysis = initialAnalysis

                providerRef.unbindAll()
                cameraRef.set(
                    providerRef.bindToLifecycle(
                        lifecycleOwner,
                        selector,
                        preview,
                        initialAnalysis,
                        imageCapture
                    )
                )
                Log.d(TAG, "分析分辨率默认档 ${tiers.default}，候选 ${tiers.descending}")
            } catch (t: Throwable) {
                if (!unbound) {
                    onError(t.message ?: "无法打开相机")
                }
            }
        }, mainExecutor)

        onDispose {
            unbound = true
            cameraRef.set(null)
            runCatching { provider?.unbindAll() }
            analysisExecutor.shutdown()
            stillExecutor.shutdown()
            future.cancel(false)
        }
    }

    AndroidView(
        factory = { previewView },
        modifier = modifier
            .pointerInput(previewView) {
                detectTransformGestures { _, _, zoom, _ ->
                    val camera = cameraRef.get() ?: return@detectTransformGestures
                    val state = camera.cameraInfo.zoomState.value ?: return@detectTransformGestures
                    val ratio = (state.zoomRatio * zoom)
                        .coerceIn(state.minZoomRatio, state.maxZoomRatio)
                    camera.cameraControl.setZoomRatio(ratio)
                }
            }
            .pointerInput(previewView) {
                detectTapGestures { offset ->
                    val camera = cameraRef.get() ?: return@detectTapGestures
                    val point = previewView.meteringPointFactory.createPoint(offset.x, offset.y)
                    val action = FocusMeteringAction.Builder(
                        point,
                        FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE
                    )
                        .setAutoCancelDuration(3, TimeUnit.SECONDS)
                        .build()
                    camera.cameraControl.startFocusAndMetering(action)
                }
            }
    )
}

/**
 * 枚举该相机的 YUV_420_888 输出尺寸，作为分析分辨率的候选档。
 * 拿不到能力时返回空列表，由 [AnalysisTiers] 退回默认档。
 */
private fun supportedAnalysisSizes(cameraInfo: CameraInfo): List<AnalysisSize> {
    val configMap = Camera2CameraInfo.from(cameraInfo)
        .getCameraCharacteristic(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        ?: return emptyList()
    return configMap.getOutputSizes(ImageFormat.YUV_420_888)
        ?.map { AnalysisSize(it.width, it.height) }
        .orEmpty()
}

/**
 * 连续解码失败后的静态图兜底：用 ImageCapture 抓一张全分辨率 JPEG，再解码一次。
 *
 * 成功后视为普通识别结果；无论成功与否都自动回到连续扫码（分析器从未停止）。
 */
private fun captureStill(
    context: Context,
    imageCapture: ImageCapture,
    busy: AtomicBoolean,
    executor: java.util.concurrent.Executor,
    mainExecutor: java.util.concurrent.Executor,
    onDecoded: (String) -> Unit
) {
    if (!busy.compareAndSet(false, true)) return
    val file = File(context.cacheDir, "qr-fallback-${System.currentTimeMillis()}.jpg")
    val options = ImageCapture.OutputFileOptions.Builder(file).build()
    try {
        imageCapture.takePicture(
            options,
            executor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    try {
                        val text = QrImageDecoder.decodeJpeg(file.readBytes())
                        if (!text.isNullOrBlank()) {
                            mainExecutor.execute { onDecoded(text) }
                        }
                    } catch (_: Throwable) {
                        // 忽略本次兜底失败，继续连续扫码
                    } finally {
                        file.delete()
                        busy.set(false)
                    }
                }

                override fun onError(exception: ImageCaptureException) {
                    file.delete()
                    busy.set(false)
                }
            }
        )
    } catch (_: Throwable) {
        file.delete()
        busy.set(false)
    }
}

@Composable
private fun ManualPayloadDialog(
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var text by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("手动输入二维码内容") },
        text = {
            Column {
                Text(
                    "把二维码中的完整文本粘贴到下方（通常以 { 开头）。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 4,
                    maxLines = 8,
                    label = { Text("二维码内容") }
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(text.trim()) },
                enabled = text.isNotBlank()
            ) { Text("确定") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        }
    )
}

/** 从任意 Context 中取出宿主 Activity（用于权限与生物识别）。 */
fun Context.findFragmentActivity(): FragmentActivity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is FragmentActivity) return current
        current = current.baseContext
    }
    return null
}

private fun openAppSettings(context: Context) {
    val intent = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", context.packageName, null)
    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }
}
