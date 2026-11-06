package com.scanauth.app.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.LuminanceSource
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.GlobalHistogramBinarizer
import com.google.zxing.common.HybridBinarizer

/**
 * 二维码解码核心（相机帧与静态图共用）。
 *
 * 针对高密度码（如 version 13、69×69 模块）的可靠性设计：
 * - 开启 `TRY_HARDER` 与 `ALSO_INVERTED`；
 * - 依次尝试 `HybridBinarizer` 与 `GlobalHistogramBinarizer`，任一成功即返回；
 * - 静态图先按最长边缩放，避免超大位图拖慢解码。
 */
internal object QrImageDecoder {

    private val HINTS: Map<DecodeHintType, Any> = mapOf(
        DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
        DecodeHintType.TRY_HARDER to true,
        DecodeHintType.ALSO_INVERTED to true,
        DecodeHintType.CHARACTER_SET to "UTF-8"
    )

    /** 解码 Y 平面亮度数据（[rowStride] 可大于 [width]，为行尾填充）。 */
    fun decodeLuminance(data: ByteArray, width: Int, height: Int, rowStride: Int): String? {
        if (width <= 0 || height <= 0 || rowStride < width) return null
        if (data.size < rowStride * (height - 1) + width) return null
        val source = PlanarYUVLuminanceSource(data, rowStride, height, 0, 0, width, height, false)
        return decodeSource(source)
    }

    /** 解码 JPEG 静态图（ImageCapture 兜底路径）。 */
    fun decodeJpeg(bytes: ByteArray, maxDimension: Int = 2048): String? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sampleSize = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sampleSize * 2) >= maxDimension) {
            sampleSize *= 2
        }
        val bitmap = BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sampleSize }
        ) ?: return null
        return try {
            decodeBitmap(bitmap)
        } finally {
            bitmap.recycle()
        }
    }

    /** 解码位图（超大时先等比缩小到 [maxDimension]）。 */
    fun decodeBitmap(bitmap: Bitmap, maxDimension: Int = 2048): String? {
        val scaled = scaleDown(bitmap, maxDimension)
        return try {
            val width = scaled.width
            val height = scaled.height
            val pixels = IntArray(width * height)
            scaled.getPixels(pixels, 0, width, 0, 0, width, height)
            decodeSource(RGBLuminanceSource(width, height, pixels))
        } finally {
            if (scaled !== bitmap) scaled.recycle()
        }
    }

    private fun decodeSource(source: LuminanceSource): String? {
        decodeAll(source)?.let { return it }
        // 显式反转再试一次，兼容/兜底 ALSO_INVERTED 在不同 ZXing 分支上的差异
        return decodeAll(source.invert())
    }

    private fun decodeAll(source: LuminanceSource): String? {
        for (binarizer in listOf(HybridBinarizer(source), GlobalHistogramBinarizer(source))) {
            val reader = MultiFormatReader()
            try {
                reader.setHints(HINTS)
                return reader.decode(BinaryBitmap(binarizer)).text
            } catch (_: Throwable) {
                // 换另一种二值化再试
            } finally {
                reader.reset()
            }
        }
        return null
    }

    private fun scaleDown(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest <= maxDimension) return bitmap
        val ratio = maxDimension.toFloat() / longest
        val width = (bitmap.width * ratio).toInt().coerceAtLeast(1)
        val height = (bitmap.height * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }
}
