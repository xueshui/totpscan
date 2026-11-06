package com.scanauth.app.camera

import android.os.SystemClock
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import java.util.concurrent.atomic.AtomicLong

/**
 * CameraX 帧分析器：只解析二维码，不做任何业务判断。
 *
 * - 分析帧保持相机输出的原始分辨率，解码前不做任何缩放；
 * - 连续失败 [escalateAfterMs] 后先请求升一档分析分辨率（由调用方换绑分析用例），
 *   只要还能升就一直升；升到设备最大档后，再连续失败 [stuckThresholdMs]
 *   触发一次全分辨率静态图兜底；
 * - 对短时间内的重复内容去重，避免一帧多次回调。
 *
 * 为什么不在默认档直接顶到最高分辨率：解码开销随像素数近似线性增长，
 * 实际扫码速度取决于「帧率 × 单帧成功率」。清晰码在默认档就能解出，
 * 高分辨率只会让帧率变低、发热变高；只有连续解不出时才值得用帧率换成功率。
 */
class QrCodeAnalyzer(
    private val onDecoded: (String) -> Unit,
    private val onEscalate: () -> Unit = {},
    private val onStillCaptureNeeded: () -> Unit = {},
    private val canEscalate: () -> Boolean = { false },
    private val escalateAfterMs: Long = 1_000L,
    private val stuckThresholdMs: Long = 1_500L,
    private val stillCaptureIntervalMs: Long = 3_000L
) : ImageAnalysis.Analyzer {

    private val lastAttemptAt = AtomicLong(0L)

    /** 本轮连续失败的起点；成功解码或升档后重新计时。 */
    private var firstFailureAt = 0L

    private var lastEscalateAt = 0L

    private var lastStillCaptureAt = 0L

    @Volatile
    private var lastText: String? = null

    @Volatile
    private var lastTextAt: Long = 0L

    override fun analyze(image: ImageProxy) {
        try {
            val now = SystemClock.elapsedRealtime()
            if (now - lastAttemptAt.get() < FRAME_INTERVAL_MS) return
            lastAttemptAt.set(now)

            val plane = readLuminance(image)
            val text = plane?.let {
                QrImageDecoder.decodeLuminance(it.data, it.width, it.height, it.rowStride)
            }

            if (!text.isNullOrBlank()) {
                firstFailureAt = 0L
                lastEscalateAt = 0L
                if (text == lastText && now - lastTextAt < 2_000L) return
                lastText = text
                lastTextAt = now
                onDecoded(text)
                return
            }

            if (firstFailureAt == 0L) firstFailureAt = now

            // 还没到最高档：先逐档升分辨率，换更大的视场去换单帧成功率
            if (canEscalate()) {
                if (now - firstFailureAt >= escalateAfterMs &&
                    now - lastEscalateAt >= escalateAfterMs
                ) {
                    lastEscalateAt = now
                    firstFailureAt = now
                    onEscalate()
                }
                return
            }

            // 已在最高档仍解不出：抓一张全分辨率静态图兜底
            if (now - firstFailureAt >= stuckThresholdMs &&
                now - lastStillCaptureAt >= stillCaptureIntervalMs
            ) {
                lastStillCaptureAt = now
                onStillCaptureNeeded()
            }
        } catch (_: Throwable) {
            // 单帧解析失败不影响后续帧
        } finally {
            image.close()
        }
    }

    private data class YPlane(
        val data: ByteArray,
        val width: Int,
        val height: Int,
        val rowStride: Int
    )

    /**
     * 读取 Y 平面亮度。兼容 `pixelStride != 1` 的设备：此时重新打包为紧密排列。
     * 不做缩放或裁剪，保证解码拿到的是完整分析帧。
     */
    private fun readLuminance(image: ImageProxy): YPlane? {
        val plane = image.planes.firstOrNull() ?: return null
        val width = image.width
        val height = image.height
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val buffer = plane.buffer
        val needed = rowStride * (height - 1) + width * pixelStride
        if (rowStride < width || pixelStride < 1 || buffer.remaining() < needed) return null

        if (pixelStride == 1) {
            val data = ByteArray(rowStride * height)
            val copy = buffer.duplicate()
            copy.get(data, 0, minOf(copy.remaining(), data.size))
            return YPlane(data, width, height, rowStride)
        }

        val data = ByteArray(width * height)
        val copy = buffer.duplicate()
        val row = ByteArray(rowStride)
        for (y in 0 until height) {
            copy.position(y * rowStride)
            val length = minOf(rowStride, copy.remaining())
            copy.get(row, 0, length)
            for (x in 0 until width) {
                data[y * width + x] = row[x * pixelStride]
            }
        }
        return YPlane(data, width, height, width)
    }

    private companion object {
        /** 连续分析节流，避免高分辨率下占满 CPU。 */
        const val FRAME_INTERVAL_MS = 120L
    }
}
