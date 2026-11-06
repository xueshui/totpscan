package com.scanauth.sdk.internal

import com.scanauth.sdk.SdkError
import com.scanauth.sdk.SdkException
import com.scanauth.sdk.TotpAlgorithm
import com.scanauth.sdk.TotpParameters

/**
 * 绑定二维码解析结果（规范 §4.3）。
 *
 * 只有通过全部字段校验才会构造出本对象；任何一个字段失败都不会产生实例。
 */
internal data class BindingQrData(
    val bindingId: String,
    val issuer: String,
    val account: String,
    val secretBase32: String,
    val algorithm: TotpAlgorithm,
    val digits: Int,
    val periodSeconds: Long,
    /** 由 `dom + path` 构造出的完整提交地址（含查询串）。 */
    val submitUrl: CanonicalUrl,
    val issuedAt: Long,
    val expiresAt: Long?,
    /** 提交地址所属的注册域名（钉住对象之一）。 */
    val registeredDomain: String,
    /** 绑定时固化的 `path[?query]`。 */
    val submitPath: String,
    val rawPayload: String
) {
    val parameters: TotpParameters
        get() = TotpParameters(algorithm, digits, periodSeconds)
}

/**
 * `totp-bind` 载荷解析。
 *
 * 绑定载荷字段：`t / v / bid / iss / acc / sec / alg / dig / per / dom / path / iat / exp`。
 * 不再包含签名（`sig` / `kid`），解析阶段不做任何验签：
 * 扫码 → 字段与 `exp` 校验 → 用户确认 `dom` / `path` → 写入存储。
 */
internal class BindingQrParser {

    companion object {
        const val TYPE = "totp-bind"
        const val SUPPORTED_VERSION = 1

        private val BINDING_ID = Regex("^b_[A-Za-z0-9_-]{16,64}$")
        private val SECRET = Regex("^[A-Z2-7]{26,103}$")
        private val DOMAIN = Regex("^[A-Za-z0-9._\\-\\[\\]:]+$")
        private val PATH = Regex("^/[^\\s#]*$")
    }

    fun parse(payload: String, nowSeconds: Long, clockSkewSeconds: Long = 0): BindingQrData {
        val json = QrJson.parseObject(payload)

        val type = QrJson.requireString(json, "t")
        if (type != TYPE) {
            throw SdkException(SdkError.QR_TYPE_MISMATCH, "这不是绑定二维码")
        }

        val version = QrJson.requireInt(json, "v")
        if (version != SUPPORTED_VERSION) {
            throw SdkException(SdkError.UNSUPPORTED_VERSION, "不支持的协议版本: $version")
        }

        val bindingId = QrJson.requireString(json, "bid")
        if (!BINDING_ID.matches(bindingId)) QrJson.invalid("bid 格式非法")

        val issuerRaw = QrJson.requireString(json, "iss")
        val issuer = QrJson.nfc(issuerRaw)
        QrJson.requireNoControlChars("iss", issuer)
        if (issuer.isEmpty() || issuer.length > 64) QrJson.invalid("iss 长度必须为 1–64 个字符")

        val accountRaw = QrJson.requireString(json, "acc")
        val account = QrJson.nfc(accountRaw)
        QrJson.requireNoControlChars("acc", account)
        if (account.isEmpty() || account.length > 255) QrJson.invalid("acc 长度必须为 1–255 个字符")

        val secret = QrJson.requireString(json, "sec")
        if (!SECRET.matches(secret)) QrJson.invalid("sec 必须是大写无填充的 Base32")
        val secretBytes = try {
            Base32.decode(secret)
        } catch (e: IllegalArgumentException) {
            QrJson.invalid("sec 不是合法 Base32", e)
        }
        if (secretBytes.size !in 16..64) QrJson.invalid("sec 解码后必须为 16–64 字节")

        val algorithmName = QrJson.requireString(json, "alg")
        val algorithm = when (algorithmName) {
            "SHA1" -> TotpAlgorithm.SHA1
            "SHA256" -> TotpAlgorithm.SHA256
            "SHA512" -> TotpAlgorithm.SHA512
            else -> QrJson.invalid("不支持的 alg: $algorithmName")
        }

        val digits = QrJson.requireInt(json, "dig")
        if (digits != 6 && digits != 8) QrJson.invalid("dig 仅允许 6 或 8")

        val period = QrJson.requireLong(json, "per")
        if (period != 30L && period != 60L) QrJson.invalid("per 仅允许 30 或 60")

        val dom = QrJson.requireString(json, "dom")
        if (dom.isEmpty() || dom.length > 253 || !DOMAIN.matches(dom)) {
            QrJson.invalid("dom 必须是合法主机名")
        }

        val path = QrJson.requireString(json, "path")
        if (path.length !in 1..2048 || !PATH.matches(path)) {
            QrJson.invalid("path 必须以 / 开头且不得包含空白或片段")
        }

        val submitUrl = CanonicalAddress.parse("https://$dom$path")
        if (submitUrl.host != RegisteredDomain.normalize(dom)) {
            QrJson.invalid("dom 与 path 组合后的地址非法")
        }

        val issuedAt = QrJson.requireLong(json, "iat")
        if (issuedAt < 0) QrJson.invalid("iat 不能为负数")

        val expiresAt = QrJson.optionalLong(json, "exp")
        if (expiresAt != null && expiresAt < 0) QrJson.invalid("exp 不能为负数")
        if (expiresAt != null && nowSeconds > expiresAt + clockSkewSeconds) {
            throw SdkException(SdkError.PAYLOAD_EXPIRED, "绑定二维码已过期")
        }

        return BindingQrData(
            bindingId = bindingId,
            issuer = issuer,
            account = account,
            secretBase32 = secret,
            algorithm = algorithm,
            digits = digits,
            periodSeconds = period,
            submitUrl = submitUrl,
            issuedAt = issuedAt,
            expiresAt = expiresAt,
            registeredDomain = submitUrl.registeredDomain,
            submitPath = submitUrl.submitPath,
            rawPayload = payload
        )
    }
}
