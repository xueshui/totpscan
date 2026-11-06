package com.scanauth.app.camera

import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Random
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * 登录二维码分辨率验收：用与现场样本同尺寸的脱敏合成二维码走相机分析链路。
 *
 * 基线：
 * - PNG 233×224，二维码符号 196×196px；
 * - 载荷 100 字节，ECC M，version 6（41×41 模块），4.78px/模块；
 * - 白色卡片四周仅约 5px（≈1 模块）静区，卡片外为深色页面背景。
 *
 * 测试数据为按脱敏载荷重新生成的亮度原始数据（real-login-qr.luma，233×224×1 字节），
 * 避免 Android 单测环境缺少 AWT；仓库内不保留任何真实登录二维码。
 *
 * “扫不出来”的复现方式：按“被扫手机屏幕宽 1080px”折算，640×480 分析帧里
 * 符号只有约 116px（2.83px/模块）；叠加相机常见的轻度模糊与噪声后，旧解码配置失败。
 * 同一视场换到 1280×720 / 1920×1080 分析帧，符号变为 232 / 348px，稳定识别。
 */
class RealSampleQrAcceptanceTest {

    private val expectedPayload =
        "{\"t\":\"totp-login\",\"v\":1,\"url\":\"dkn.example.com\"," +
            "\"token\":\"Zx4Qm2Tk9Lp7Rv1Yb3Nc5SdA\",\"exp\":1793938593}"

    private val sample: Frame = loadSample()

    // ------------------------------------------------------------------ 基线

    @Test
    fun baselineMatchesTheFieldSample() {
        assertEquals(233, sample.width)
        assertEquals(224, sample.height)
        assertEquals(expectedPayload, decodeModern(sample))
        assertEquals(41, encodedModuleCount(expectedPayload))
        assertEquals(196, symbolWidthPx(sample))
        assertEquals(4.78, symbolWidthPx(sample) / 41.0, 0.1)
    }

    // ------------------------------------------------------------------ 复现现场失败

    @Test
    fun legacyPipelineCannotDecodeAt640x480() {
        val frame = simulate(symbolPx = 116, frameWidth = 640, frameHeight = 480)
        assertNull(decodeLegacy(frame))
    }

    @Test
    fun decodeParamsAloneCannotRescueTheLowResolutionFrame() {
        // 说明 640×480 的瓶颈是降采样，而不是 TRY_HARDER / 二值化轮换
        val frame = simulate(symbolPx = 116, frameWidth = 640, frameHeight = 480)
        assertNull(decodeModern(frame))
    }

    // ------------------------------------------------------------------ 改进后

    @Test
    fun decodesAt720pAnalysisFrame() {
        val frame = simulate(symbolPx = symbolPxForAnalysisWidth(1280), frameWidth = 1280, frameHeight = 720)
        assertEquals(expectedPayload, decodeModern(frame))
    }

    @Test
    fun decodesAt1080pAnalysisFrame() {
        val frame = simulate(symbolPx = symbolPxForAnalysisWidth(1920), frameWidth = 1920, frameHeight = 1080)
        assertEquals(expectedPayload, decodeModern(frame))
    }

    @Test
    fun minimumStableModuleSizeIsAboutThreePixels() {
        var firstPassing = -1
        for (symbol in 60..200 step 4) {
            if (decodeModern(simulate(symbol, 640, 480)) != null) {
                firstPassing = symbol
                break
            }
        }
        assertTrue("样本应当能在某个符号尺寸下解出", firstPassing > 0)
        val pxPerModule = firstPassing / 41.0
        assertEquals(3.05, pxPerModule, 0.45)

        // 反推：屏幕上 196px 的码，分析帧至少需要 ~700px 宽；1280×720 已满足，1920×1080 有充足余量
        val requiredAnalysisWidth = 1080 * firstPassing / 196.0
        assertTrue("所需分析宽度应不超过 720p", requiredAnalysisWidth <= 1280)
    }

    // ------------------------------------------------------------------ 工具

    /** 同一视场下，分析帧宽度对应的二维码符号像素宽（被扫屏幕按 1080px 宽计）。 */
    private fun symbolPxForAnalysisWidth(analysisWidth: Int): Int =
        (196.0 * analysisWidth / 1080.0).roundToInt()

    private fun encodedModuleCount(payload: String): Int {
        val matrix = QRCodeWriter().encode(
            payload,
            BarcodeFormat.QR_CODE,
            0,
            0,
            mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M)
        )
        return matrix.width - 8
    }

    private fun loadSample(): Frame {
        val bytes = checkNotNull(
            javaClass.getResourceAsStream("/qr-samples/real-login-qr.luma")
        ) { "缺少真实样本 /qr-samples/real-login-qr.luma" }.use { it.readBytes() }
        assertEquals(233 * 224, bytes.size)
        return Frame(233, 224, bytes)
    }

    /** 白色卡片向内 5px 后的暗像素包围盒宽度，即二维码符号宽度。 */
    private fun symbolWidthPx(frame: Frame): Int {
        var l = Int.MAX_VALUE
        var t = Int.MAX_VALUE
        var r = -1
        var b = -1
        for (y in 0 until frame.height) {
            for (x in 0 until frame.width) {
                if (frame.luma(x, y) > 200) {
                    l = minOf(l, x)
                    t = minOf(t, y)
                    r = maxOf(r, x)
                    b = maxOf(b, y)
                }
            }
        }
        val inset = 5
        var sx0 = Int.MAX_VALUE
        var sy0 = Int.MAX_VALUE
        var sx1 = -1
        var sy1 = -1
        for (y in t + inset..b - inset) {
            for (x in l + inset..r - inset) {
                if (frame.luma(x, y) < 80) {
                    sx0 = minOf(sx0, x)
                    sy0 = minOf(sy0, y)
                    sx1 = maxOf(sx1, x)
                    sy1 = maxOf(sy1, y)
                }
            }
        }
        assertEquals("符号应为正方形", sx1 - sx0, sy1 - sy0)
        return sx1 - sx0 + 1
    }

    private class Frame(val width: Int, val height: Int, val luminance: ByteArray) {
        fun luma(x: Int, y: Int): Int = luminance[y * width + x].toInt() and 0xFF
    }

    /**
     * 按“屏幕宽 1080px”把样本缩放，居中贴到 [frameWidth]×[frameHeight] 画布，
     * 再叠加 1.1px 高斯模糊与 σ=6 噪声，模拟相机分析帧。
     */
    private fun simulate(symbolPx: Int, frameWidth: Int, frameHeight: Int): Frame {
        val scale = symbolPx / 196.0
        val scaledWidth = maxOf(1, (sample.width * scale).roundToInt())
        val scaledHeight = maxOf(1, (sample.height * scale).roundToInt())
        val scaled = bilinearScale(sample, scaledWidth, scaledHeight)

        val canvas = DoubleArray(frameWidth * frameHeight) { 235.0 }
        val offsetX = (frameWidth - scaledWidth) / 2
        val offsetY = (frameHeight - scaledHeight) / 2
        for (y in 0 until scaledHeight) {
            for (x in 0 until scaledWidth) {
                canvas[(offsetY + y) * frameWidth + offsetX + x] = scaled[y * scaledWidth + x]
            }
        }

        val blurred = gaussianBlur(canvas, frameWidth, frameHeight, 1.1)
        val random = Random(42)
        val data = ByteArray(blurred.size)
        for (i in blurred.indices) {
            data[i] = (blurred[i] + random.nextGaussian() * 6.0).coerceIn(0.0, 255.0).roundToInt().toByte()
        }
        return Frame(frameWidth, frameHeight, data)
    }

    private fun bilinearScale(source: Frame, width: Int, height: Int): DoubleArray {
        val out = DoubleArray(width * height)
        for (y in 0 until height) {
            val sy = ((y + 0.5) * source.height / height - 0.5).coerceIn(0.0, source.height - 1.0)
            val y0 = floor(sy).toInt()
            val y1 = minOf(y0 + 1, source.height - 1)
            val fy = sy - y0
            for (x in 0 until width) {
                val sx = ((x + 0.5) * source.width / width - 0.5).coerceIn(0.0, source.width - 1.0)
                val x0 = floor(sx).toInt()
                val x1 = minOf(x0 + 1, source.width - 1)
                val fx = sx - x0

                val v00 = source.luma(x0, y0).toDouble()
                val v10 = source.luma(x1, y0).toDouble()
                val v01 = source.luma(x0, y1).toDouble()
                val v11 = source.luma(x1, y1).toDouble()
                val top = v00 + (v10 - v00) * fx
                val bottom = v01 + (v11 - v01) * fx
                out[y * width + x] = top + (bottom - top) * fy
            }
        }
        return out
    }

    private fun gaussianBlur(source: DoubleArray, width: Int, height: Int, sigma: Double): DoubleArray {
        val radius = maxOf(1, ceil(sigma * 3).toInt())
        val kernel = DoubleArray(radius * 2 + 1)
        var sum = 0.0
        for (i in -radius..radius) {
            val v = exp(-(i * i) / (2 * sigma * sigma))
            kernel[i + radius] = v
            sum += v
        }
        for (i in kernel.indices) kernel[i] /= sum

        val temp = DoubleArray(source.size)
        for (y in 0 until height) {
            for (x in 0 until width) {
                var acc = 0.0
                for (k in -radius..radius) {
                    val xx = (x + k).coerceIn(0, width - 1)
                    acc += source[y * width + xx] * kernel[k + radius]
                }
                temp[y * width + x] = acc
            }
        }
        val result = DoubleArray(source.size)
        for (y in 0 until height) {
            for (x in 0 until width) {
                var acc = 0.0
                for (k in -radius..radius) {
                    val yy = (y + k).coerceIn(0, height - 1)
                    acc += temp[yy * width + x] * kernel[k + radius]
                }
                result[y * width + x] = acc
            }
        }
        return result
    }

    /** 旧实现：HybridBinarizer + TRY_HARDER，不做反色与二值化轮换。 */
    private fun decodeLegacy(frame: Frame): String? {
        val source = PlanarYUVLuminanceSource(
            frame.luminance, frame.width, frame.height, 0, 0, frame.width, frame.height, false
        )
        val reader = MultiFormatReader()
        reader.setHints(
            mapOf(
                DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
                DecodeHintType.TRY_HARDER to true
            )
        )
        return try {
            reader.decode(BinaryBitmap(HybridBinarizer(source))).text
        } catch (_: Throwable) {
            null
        }
    }

    private fun decodeModern(frame: Frame): String? =
        QrImageDecoder.decodeLuminance(frame.luminance, frame.width, frame.height, frame.width)
}
