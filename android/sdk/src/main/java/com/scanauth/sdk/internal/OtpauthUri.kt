package com.scanauth.sdk.internal

import com.scanauth.sdk.OtpauthAccount
import com.scanauth.sdk.SdkError
import com.scanauth.sdk.SdkException
import com.scanauth.sdk.TotpAlgorithm
import com.scanauth.sdk.TotpParameters
import java.net.URLDecoder
import java.net.URLEncoder

/**
 * 标准 `otpauth://totp/...` URI 解析与生成（规范 §13.2 U1–U9）。
 *
 * - 只支持 `otpauth://totp`，`hotp` 或带 `counter` 的 URI 一律拒绝；
 * - `secret` 必填，Base32 解码后 ≥10 字节；
 * - `algorithm` 缺省 SHA1，大小写不敏感；
 * - `digits` 仅允许 6 或 8；`period` 允许 1–3600 秒的正整数；
 * - 未知参数忽略；同名参数重复视为非法；
 * - label 中的 issuer 与 query 中的 issuer 冲突时拒绝。
 */
internal object OtpauthUri {

    private const val MAX_URI_LENGTH = 2048
    private const val MIN_SECRET_BYTES = 10
    private const val MAX_SECRET_BYTES = 128

    private val URI_PATTERN =
        Regex("^otpauth://([^/?#]+)(/[^?#]*)?(?:\\?([^#]*))?$", RegexOption.IGNORE_CASE)

    fun parse(rawUri: String): OtpauthAccount {
        val uri = rawUri.trim()
        if (uri.isEmpty() || uri.length > MAX_URI_LENGTH) {
            throw invalid("otpauth URI 为空或过长")
        }
        val match = URI_PATTERN.matchEntire(uri) ?: throw invalid("otpauth URI 格式非法")
        val type = match.groupValues[1]
        if (!type.equals("totp", ignoreCase = true)) {
            throw invalid("仅支持 otpauth://totp，当前为 $type")
        }

        val label = percentDecode(match.groupValues[2].removePrefix("/")).trim()
        if (label.isEmpty()) throw invalid("缺少账户标签")

        val params = parseQuery(match.groupValues[3])

        val secretRaw = params["secret"].orEmpty()
        if (secretRaw.isBlank()) throw invalid("缺少 secret")
        val secretBytes = try {
            Base32.decode(secretRaw)
        } catch (e: IllegalArgumentException) {
            throw invalid("secret 不是合法 Base32")
        }
        if (secretBytes.size < MIN_SECRET_BYTES) throw invalid("secret 长度不足（至少 80 位）")
        if (secretBytes.size > MAX_SECRET_BYTES) throw invalid("secret 长度超出限制")

        val algorithm = TotpAlgorithm.fromUriName(params["algorithm"])

        val digits = params["digits"]?.let {
            it.toIntOrNull() ?: throw invalid("digits 必须为整数")
        } ?: 6
        if (digits != 6 && digits != 8) throw invalid("digits 仅支持 6 或 8")

        val period = params["period"]?.let {
            it.toLongOrNull() ?: throw invalid("period 必须为整数")
        } ?: 30L
        if (period !in 1..3600) throw invalid("period 仅支持 1–3600 秒")

        val queryIssuer = params["issuer"].orEmpty().trim()
        var labelIssuer = ""
        var accountId = label
        val colon = label.indexOf(':')
        if (colon > 0) {
            labelIssuer = label.substring(0, colon).trim()
            accountId = label.substring(colon + 1).trim()
        }
        if (accountId.isEmpty()) throw invalid("缺少账户标签")

        val issuer = when {
            labelIssuer.isNotEmpty() && queryIssuer.isNotEmpty() -> {
                if (labelIssuer != queryIssuer) {
                    throw invalid("label 与 issuer 参数中的签发方不一致")
                }
                queryIssuer
            }
            queryIssuer.isNotEmpty() -> queryIssuer
            else -> labelIssuer
        }

        return OtpauthAccount(
            issuer = issuer,
            accountId = accountId,
            secretBase32 = secretBytes.let { Base32.encode(it) },
            parameters = TotpParameters(algorithm, digits, period)
        )
    }

    fun build(account: OtpauthAccount, omitDefaults: Boolean = false): String {
        val secret = Base32.encode(Base32.decode(account.secretBase32))
        val label = if (account.issuer.isBlank()) {
            percentEncode(account.accountId)
        } else {
            percentEncode(account.issuer) + ":" + percentEncode(account.accountId)
        }
        val query = StringBuilder()
        query.append("secret=").append(secret)
        if (account.issuer.isNotBlank()) {
            query.append("&issuer=").append(percentEncode(account.issuer))
        }
        if (!omitDefaults || account.parameters.algorithm != TotpAlgorithm.SHA1) {
            query.append("&algorithm=").append(account.parameters.algorithm.uriName)
        }
        if (!omitDefaults || account.parameters.digits != 6) {
            query.append("&digits=").append(account.parameters.digits)
        }
        if (!omitDefaults || account.parameters.periodSeconds != 30L) {
            query.append("&period=").append(account.parameters.periodSeconds)
        }
        return "otpauth://totp/$label?$query"
    }

    private fun parseQuery(raw: String): Map<String, String> {
        if (raw.isEmpty()) return emptyMap()
        val map = HashMap<String, String>()
        raw.split('&').forEach { pair ->
            if (pair.isEmpty()) return@forEach
            val index = pair.indexOf('=')
            if (index <= 0) throw invalid("查询参数格式非法")
            val key = percentDecode(pair.substring(0, index)).lowercase()
            val value = percentDecode(pair.substring(index + 1))
            if (key == "counter") throw invalid("不支持 HOTP（counter 参数）")
            if (map.containsKey(key)) throw invalid("参数 $key 重复出现")
            map[key] = value
        }
        return map
    }

    private fun percentDecode(value: String): String = try {
        // '+' 在 URI 中是字面量，不作为空格
        URLDecoder.decode(value.replace("+", "%2B"), "UTF-8")
    } catch (e: Exception) {
        throw invalid("URI 百分号编码非法")
    }

    private fun percentEncode(value: String): String =
        URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    private fun invalid(message: String): SdkException =
        SdkException(SdkError.INVALID_PAYLOAD, message)
}
