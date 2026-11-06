package com.scanauth.sdk.internal

/**
 * 极简标准 Base64 编解码（RFC 4648，带 `=` 补齐）。
 *
 * 自行实现而非使用 `android.util.Base64`，是为了让核心校验逻辑能在纯 JVM 单元测试中运行，
 * 同时避免引入额外依赖。
 */
internal object Base64Codec {

    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    private val REVERSE = IntArray(128) { -1 }.also { table ->
        ALPHABET.forEachIndexed { i, c -> table[c.code] = i }
        table['-'.code] = 62
        table['_'.code] = 63
    }

    fun decode(input: String): ByteArray {
        val text = input.trim()
        if (text.isEmpty()) return ByteArray(0)
        val out = java.io.ByteArrayOutputStream(text.length * 3 / 4 + 2)
        var buffer = 0
        var bits = 0
        for (c in text) {
            if (c == '=' || c == '\n' || c == '\r' || c == ' ') continue
            val code = c.code
            if (code >= REVERSE.size || REVERSE[code] < 0) {
                throw IllegalArgumentException("Base64 包含非法字符")
            }
            buffer = (buffer shl 6) or REVERSE[code]
            bits += 6
            if (bits >= 8) {
                bits -= 8
                out.write((buffer shr bits) and 0xFF)
            }
        }
        return out.toByteArray()
    }

    fun encode(data: ByteArray): String {
        if (data.isEmpty()) return ""
        val sb = StringBuilder((data.size * 4 + 2) / 3)
        var i = 0
        while (i + 2 < data.size) {
            val n = ((data[i].toInt() and 0xFF) shl 16) or
                ((data[i + 1].toInt() and 0xFF) shl 8) or
                (data[i + 2].toInt() and 0xFF)
            sb.append(ALPHABET[(n shr 18) and 0x3F])
            sb.append(ALPHABET[(n shr 12) and 0x3F])
            sb.append(ALPHABET[(n shr 6) and 0x3F])
            sb.append(ALPHABET[n and 0x3F])
            i += 3
        }
        when (data.size - i) {
            1 -> {
                val n = (data[i].toInt() and 0xFF) shl 16
                sb.append(ALPHABET[(n shr 18) and 0x3F])
                sb.append(ALPHABET[(n shr 12) and 0x3F])
                sb.append("==")
            }
            2 -> {
                val n = ((data[i].toInt() and 0xFF) shl 16) or ((data[i + 1].toInt() and 0xFF) shl 8)
                sb.append(ALPHABET[(n shr 18) and 0x3F])
                sb.append(ALPHABET[(n shr 12) and 0x3F])
                sb.append(ALPHABET[(n shr 6) and 0x3F])
                sb.append('=')
            }
        }
        return sb.toString()
    }
}
