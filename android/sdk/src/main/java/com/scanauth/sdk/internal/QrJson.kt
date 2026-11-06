package com.scanauth.sdk.internal

import com.scanauth.sdk.SdkError
import com.scanauth.sdk.SdkException
import org.json.JSONException
import org.json.JSONObject
import java.text.Normalizer

/**
 * 二维码 JSON 的严格解析工具。
 *
 * 规范 §4.2 / §12.1 要求：
 * - 紧凑 UTF-8 JSON，不做“宽松修复”；
 * - 未知字段必须忽略，但已知字段的类型必须严格匹配（`"1"` 不能当成整数 1）；
 * - 版本不是 1 一律拒绝。
 */
internal object QrJson {

    const val MAX_PAYLOAD_CHARS = 4096

    fun parseObject(payload: String): JSONObject {
        if (payload.isEmpty()) invalid("二维码内容为空")
        if (payload.length > MAX_PAYLOAD_CHARS) invalid("二维码内容超出长度限制")
        if (payload != payload.trim()) invalid("二维码内容前后不得包含空白")
        return try {
            JSONObject(payload)
        } catch (e: JSONException) {
            invalid("二维码内容不是合法 JSON", e)
        }
    }

    fun requireString(json: JSONObject, name: String): String {
        if (!json.has(name)) invalid("缺少字段 $name")
        val value = json.opt(name) ?: invalid("字段 $name 不能为 null")
        if (value !is String) invalid("字段 $name 类型必须为字符串")
        return value
    }

    fun optionalString(json: JSONObject, name: String): String? {
        if (!json.has(name) || json.isNull(name)) return null
        return requireString(json, name)
    }

    fun requireInt(json: JSONObject, name: String): Int {
        val value = requireNumber(json, name)
        if (value !is Int && value !is Long && value !is Short && value !is Byte) {
            // 兼容 JSON 解析器把 1 解析成 1.0 的情况，但要求数值确实为整数
            val asDouble = value.toDouble()
            if (asDouble % 1.0 != 0.0) invalid("字段 $name 必须为整数")
            if (asDouble < Int.MIN_VALUE || asDouble > Int.MAX_VALUE) invalid("字段 $name 超出范围")
            return asDouble.toInt()
        }
        return value.toInt()
    }

    fun optionalInt(json: JSONObject, name: String): Int? {
        if (!json.has(name) || json.isNull(name)) return null
        return requireInt(json, name)
    }

    fun requireLong(json: JSONObject, name: String): Long {
        val value = requireNumber(json, name)
        if (value is Long || value is Int || value is Short || value is Byte) {
            return value.toLong()
        }
        val asDouble = value.toDouble()
        if (asDouble % 1.0 != 0.0) invalid("字段 $name 必须为整数")
        if (asDouble > 9.0E15) invalid("字段 $name 超出范围")
        return asDouble.toLong()
    }

    fun optionalLong(json: JSONObject, name: String): Long? {
        if (!json.has(name) || json.isNull(name)) return null
        return requireLong(json, name)
    }

    private fun requireNumber(json: JSONObject, name: String): Number {
        if (!json.has(name)) invalid("缺少字段 $name")
        val value = json.opt(name) ?: invalid("字段 $name 不能为 null")
        if (value !is Number) invalid("字段 $name 类型必须为数字")
        return value
    }

    /** Unicode NFC 规范化（§5.2 对 iss / acc 的要求）。 */
    fun nfc(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFC)

    /** 禁止 C0 控制字符与 DEL（换行会破坏签名原文）。 */
    fun requireNoControlChars(field: String, value: String) {
        for (ch in value) {
            if (ch.code < 0x20 || ch.code == 0x7F) {
                invalid("字段 $field 不得包含控制字符")
            }
        }
    }

    fun invalid(message: String, cause: Throwable? = null): Nothing =
        throw SdkException(SdkError.INVALID_PAYLOAD, message, cause)
}
