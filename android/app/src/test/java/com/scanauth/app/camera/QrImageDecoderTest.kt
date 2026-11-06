package com.scanauth.app.camera

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 高密度绑定二维码的解码回归测试。
 *
 * 用包含完整字段的绑定载荷按 ECC M / version 13 生成 69×69 模块的二维码，分别以每模块 3px、4px
 * 渲染成亮度帧，验证相机分析路径使用的解码参数（TRY_HARDER + ALSO_INVERTED +
 * 两种二值化）确实能解出来。
 */
class QrImageDecoderTest {

    private val payload = "{\"t\":\"totp-bind\",\"v\":1,\"bid\":\"b_7Qm2Xk9pLd4Rt8Vw1Yz3Nc\"," +
        "\"iss\":\"Example Corp\",\"acc\":\"alice\",\"sec\":\"K7R2M9XQ4TZP6WJN3VBY5CSD8FGH2LKA\"," +
        "\"alg\":\"SHA1\",\"dig\":6,\"per\":30,\"dom\":\"dkn.example.com\"," +
        "\"path\":\"/totp/v1/verify\",\"iat\":1793937505,\"exp\":1793938105}"

    private fun denseMatrix(): BitMatrix = QRCodeWriter().encode(
        payload,
        BarcodeFormat.QR_CODE,
        0,
        0,
        mapOf(
            EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
            EncodeHintType.QR_VERSION to 13,
            EncodeHintType.CHARACTER_SET to "UTF-8"
        )
    )

    @Test
    fun payloadIsVersion13WithSixtyNineModules() {
        val matrix = denseMatrix()
        assertEquals(69, matrix.width - 8)
        assertEquals(69, matrix.height - 8)
    }

    @Test
    fun decodesAtFourPixelsPerModule() {
        val frame = render(denseMatrix(), 4)
        assertEquals(payload, decode(frame, 4))
    }

    @Test
    fun decodesAtThreePixelsPerModule() {
        val frame = render(denseMatrix(), 3)
        assertEquals(payload, decode(frame, 3))
    }

    @Test
    fun decodesInvertedFrame() {
        val frame = render(denseMatrix(), 4, invert = true)
        assertEquals(payload, decode(frame, 4))
    }

    @Test
    fun decodesSlightlyBlurredFrame() {
        // 放大瞄准后每模块像素更多，轻度模糊不应影响识别
        val scale = 8
        val dimension = denseMatrix().width * scale
        val frame = boxBlur(render(denseMatrix(), scale), dimension, dimension)
        assertEquals(payload, QrImageDecoder.decodeLuminance(frame, dimension, dimension, dimension))
    }

    private fun decode(frame: ByteArray, scale: Int): String? {
        val size = frame.size
        val dimension = kotlin.math.sqrt(size.toDouble()).toInt()
        assertEquals(denseMatrix().width * scale, dimension)
        return QrImageDecoder.decodeLuminance(frame, dimension, dimension, dimension)
    }

    private fun render(matrix: BitMatrix, scale: Int, invert: Boolean = false): ByteArray {
        val width = matrix.width * scale
        val height = matrix.height * scale
        val data = ByteArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val dark = matrix.get(x / scale, y / scale)
                val on = if (invert) !dark else dark
                data[y * width + x] = if (on) 0x00 else 0xFF.toByte()
            }
        }
        return data
    }

    private fun boxBlur(source: ByteArray, width: Int, height: Int): ByteArray {
        val result = ByteArray(source.size)
        for (y in 0 until height) {
            for (x in 0 until width) {
                var sum = 0
                var count = 0
                for (dy in -1..1) {
                    for (dx in -1..1) {
                        val ny = y + dy
                        val nx = x + dx
                        if (ny in 0 until height && nx in 0 until width) {
                            // 中心权重更高，模拟轻度光学模糊而非强抹平
                            val weight = if (dx == 0 && dy == 0) 8 else 1
                            sum += (source[ny * width + nx].toInt() and 0xFF) * weight
                            count += weight
                        }
                    }
                }
                result[y * width + x] = (sum / count).toByte()
            }
        }
        return result
    }
}
