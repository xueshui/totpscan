package com.scanauth.sdk.internal

import com.scanauth.sdk.SdkError
import com.scanauth.sdk.SdkException

/**
 * 登录二维码解析结果。
 *
 * 登录码只声明“提交域名 + 会话标识 + 过期时间”，不携带提交路径：
 * 提交目标固定使用绑定阶段保存的 `https://<dom><path>`。
 */
internal data class LoginQrData(
    /** 16 或 24 位会话标识，提交时原样放进 `{"code","token"}` 请求体。 */
    val token: String,
    val expiresAt: Long,
    /** 登录码声明的域名（小写 / punycode，不含 scheme 与路径）。 */
    val host: String,
    /** 由 [host] 推导的注册域名，用于与绑定记录比对。 */
    val registeredDomain: String,
    val rawPayload: String
)

/**
 * `totp-login` 载荷解析。
 *
 * 登录载荷：`t / v / url / token / exp`。
 * - `url` 是域名（不带 scheme 与路径）；
 * - `token` 为 16 或 24 位会话标识；
 * - 不参与签名校验，安全性由“注册域名与绑定记录一致”保证。
 */
internal object LoginQrParser {

    const val TYPE = "totp-login"
    const val SUPPORTED_VERSION = 1

    /** `exp - now` 必须 ≤ 60 秒。 */
    const val MAX_TTL_SECONDS = 60L

    private val TOKEN = Regex("^(?:[A-Za-z0-9_-]{16}|[A-Za-z0-9_-]{24})$")

    private val HOST_LABEL = Regex(
        "^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?" +
            "(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"
    )

    fun parse(payload: String, nowSeconds: Long, clockSkewSeconds: Long = 0): LoginQrData {
        val json = QrJson.parseObject(payload)

        val type = QrJson.requireString(json, "t")
        if (type != TYPE) {
            throw SdkException(SdkError.QR_TYPE_MISMATCH, "这不是登录二维码")
        }

        val version = QrJson.requireInt(json, "v")
        if (version != SUPPORTED_VERSION) {
            throw SdkException(SdkError.UNSUPPORTED_VERSION, "不支持的协议版本: $version")
        }

        val rawHost = QrJson.requireString(json, "url")
        if (rawHost.length !in 1..253 || !HOST_LABEL.matches(rawHost)) {
            QrJson.invalid("url 必须是不带 scheme 与路径的域名")
        }
        val host = RegisteredDomain.normalize(rawHost)
        if (host.isEmpty()) QrJson.invalid("url 域名非法")

        val token = QrJson.requireString(json, "token")
        if (!TOKEN.matches(token)) QrJson.invalid("token 必须是 16 或 24 位会话标识")

        val expiresAt = QrJson.requireLong(json, "exp")
        if (expiresAt < 0) QrJson.invalid("exp 不能为负数")
        if (nowSeconds > expiresAt + clockSkewSeconds) {
            throw SdkException(SdkError.PAYLOAD_EXPIRED, "登录二维码已过期，请刷新页面后重试")
        }
        if (expiresAt - nowSeconds > MAX_TTL_SECONDS + clockSkewSeconds) {
            QrJson.invalid("登录二维码有效期不得超过 60 秒")
        }

        return LoginQrData(
            token = token,
            expiresAt = expiresAt,
            host = host,
            registeredDomain = RegisteredDomain.of(host),
            rawPayload = payload
        )
    }
}
