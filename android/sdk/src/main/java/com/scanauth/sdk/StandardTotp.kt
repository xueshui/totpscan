package com.scanauth.sdk

import com.scanauth.sdk.internal.Base32
import com.scanauth.sdk.internal.OtpauthUri
import com.scanauth.sdk.internal.Totp
import java.util.concurrent.TimeUnit

/**
 * 标准 TOTP 能力（可独立于协议绑定使用）。
 *
 * 适用于任何兼容 RFC 6238 的第三方系统：
 * ```
 * val account = StandardTotp.parseOtpauthUri(uri)
 * val code = StandardTotp.generateCode(account.secretBase32, account.parameters)
 * ```
 */
object StandardTotp {

    private fun nowSeconds(): Long = System.currentTimeMillis() / 1000L

    /** 解析 `otpauth://totp/...`，失败抛 [SdkException]（错误码 [SdkError.INVALID_PAYLOAD]）。 */
    @JvmStatic
    fun parseOtpauthUri(uri: String): OtpauthAccount = OtpauthUri.parse(uri)

    /** 生成规范的 `otpauth://totp/...` URI。 */
    @JvmStatic
    fun buildOtpauthUri(account: OtpauthAccount): String = OtpauthUri.build(account)

    /** 按参数计算动态码。 */
    @JvmStatic
    @JvmOverloads
    fun generateCode(
        secretBase32: String,
        parameters: TotpParameters = TotpParameters(),
        epochSeconds: Long = nowSeconds()
    ): String = Totp.generate(decodeSecret(secretBase32), epochSeconds, parameters)

    /** 当前时间窗剩余秒数（用于倒计时）。 */
    @JvmStatic
    fun secondsRemaining(
        parameters: TotpParameters,
        epochSeconds: Long = TimeUnit.MILLISECONDS.toSeconds(System.currentTimeMillis())
    ): Long = Totp.secondsRemaining(epochSeconds, parameters.periodSeconds)

    /**
     * 在 ±[windowSteps] 个时间窗内校验动态码。
     *
     * 命中且 [offsetSteps] != 0 时，说明两端时间存在一个或多个步长的偏差。
     */
    @JvmStatic
    @JvmOverloads
    fun verifyCode(
        secretBase32: String,
        parameters: TotpParameters,
        code: String,
        epochSeconds: Long = nowSeconds(),
        windowSteps: Int = 1
    ): TotpVerifyResult = Totp.verify(decodeSecret(secretBase32), code, epochSeconds, parameters, windowSteps)

    private fun decodeSecret(secretBase32: String): ByteArray = try {
        Base32.decode(secretBase32)
    } catch (e: IllegalArgumentException) {
        throw SdkException(SdkError.INVALID_ARGUMENT, "secret 不是合法 Base32", e)
    }
}
