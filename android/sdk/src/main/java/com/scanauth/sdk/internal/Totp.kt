package com.scanauth.sdk.internal

import com.scanauth.sdk.TotpAlgorithm
import com.scanauth.sdk.TotpParameters
import com.scanauth.sdk.TotpVerifyResult
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * RFC 6238 TOTP 实现（支持 HMAC-SHA1 / SHA256 / SHA512，6~8 位，可配置步长）。
 *
 * 时间一律使用 Unix 秒，避免依赖设备时区。
 */
internal object Totp {

    const val DIGITS = 6
    const val PERIOD_SECONDS = 30L

    private val POW10 = longArrayOf(1, 10, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000)

    fun generate(
        secret: ByteArray,
        epochSeconds: Long,
        parameters: TotpParameters
    ): String = generate(secret, epochSeconds, parameters.algorithm, parameters.digits, parameters.periodSeconds)

    fun generate(
        secret: ByteArray,
        epochSeconds: Long,
        algorithm: TotpAlgorithm = TotpAlgorithm.SHA1,
        digits: Int = DIGITS,
        periodSeconds: Long = PERIOD_SECONDS
    ): String {
        require(secret.isNotEmpty()) { "共享密钥不能为空" }
        require(digits in 6..8) { "动态码位数仅支持 6~8" }
        require(periodSeconds > 0) { "步长必须为正数" }

        val message = counterToBytes(epochSeconds / periodSeconds)
        val mac = Mac.getInstance(algorithm.macName)
        mac.init(SecretKeySpec(secret, algorithm.macName))
        val hash = mac.doFinal(message)

        // RFC 4226 §5.3 动态截断
        val offset = hash[hash.size - 1].toInt() and 0x0F
        val binary = ((hash[offset].toInt() and 0x7F) shl 24) or
            ((hash[offset + 1].toInt() and 0xFF) shl 16) or
            ((hash[offset + 2].toInt() and 0xFF) shl 8) or
            (hash[offset + 3].toInt() and 0xFF)

        val code = binary.toLong() % POW10[digits]
        return code.toString().padStart(digits, '0')
    }

    /**
     * 在 ±[windowSteps] 个时间窗内校验动态码。
     *
     * 返回命中偏移（0 为当前窗口），便于 UI 提示“设备时间可能不准”。
     */
    fun verify(
        secret: ByteArray,
        code: String,
        epochSeconds: Long,
        parameters: TotpParameters,
        windowSteps: Int = 1
    ): TotpVerifyResult {
        val candidate = code.filter { it.isDigit() }
        if (candidate.length != parameters.digits) {
            return TotpVerifyResult(false, null, null)
        }
        val period = parameters.periodSeconds
        for (offset in -windowSteps..windowSteps) {
            val generated = generate(secret, epochSeconds + offset * period, parameters)
            if (constantTimeEquals(generated, candidate)) {
                return TotpVerifyResult(true, offset, generated)
            }
        }
        return TotpVerifyResult(false, null, null)
    }

    /** 当前窗口剩余秒数（用于倒计时环）。 */
    fun secondsRemaining(epochSeconds: Long, periodSeconds: Long = PERIOD_SECONDS): Long =
        periodSeconds - (epochSeconds % periodSeconds)

    fun currentCounterStart(epochSeconds: Long, periodSeconds: Long = PERIOD_SECONDS): Long =
        epochSeconds / periodSeconds * periodSeconds

    private fun counterToBytes(counter: Long): ByteArray {
        val message = ByteArray(8)
        var value = counter
        for (i in 7 downTo 0) {
            message[i] = (value and 0xFF).toByte()
            value = value ushr 8
        }
        return message
    }

    private fun constantTimeEquals(a: String, b: String): Boolean {
        if (a.length != b.length) return false
        var diff = 0
        for (i in a.indices) {
            diff = diff or (a[i].code xor b[i].code)
        }
        return diff == 0
    }
}
