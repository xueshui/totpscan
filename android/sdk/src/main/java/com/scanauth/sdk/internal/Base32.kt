package com.scanauth.sdk.internal

/**
 * RFC 4648 Base32 解码（RFC 6238 密钥的标准编码方式）。
 *
 * 兼容：小写字母、空格、连字符、尾部补齐符 `=`。不兼容 Crockford 变体（不含 0/1）。
 */
internal object Base32 {

    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    private val REVERSE: IntArray = IntArray(128) { -1 }.also { table ->
        ALPHABET.forEachIndexed { index, c ->
            table[c.code] = index
            table[c.lowercaseChar().code] = index
        }
    }

    fun decode(encoded: String): ByteArray {
        if (encoded.isEmpty()) throw IllegalArgumentException("Base32 内容为空")

        var buffer = 0L
        var bits = 0
        val out = java.io.ByteArrayOutputStream(encoded.length * 5 / 8 + 1)

        for (raw in encoded) {
            when (raw) {
                ' ', '-', '\t', '\n', '\r', '=' -> continue
                else -> {
                    val code = raw.code
                    if (code >= REVERSE.size || REVERSE[code] < 0) {
                        throw IllegalArgumentException("Base32 包含非法字符")
                    }
                    buffer = (buffer shl 5) or REVERSE[code].toLong()
                    bits += 5
                    if (bits >= 8) {
                        bits -= 8
                        out.write(((buffer shr bits) and 0xFF).toInt())
                    }
                }
            }
        }
        // 尾部不足 8 位的填充位按规范应为 0，这里不额外校验。
        return out.toByteArray()
    }

    fun encode(data: ByteArray): String {
        val sb = StringBuilder((data.size * 8 + 4) / 5)
        var buffer = 0L
        var bits = 0
        for (b in data) {
            buffer = (buffer shl 8) or (b.toLong() and 0xFF)
            bits += 8
            while (bits >= 5) {
                bits -= 5
                sb.append(ALPHABET[((buffer shr bits) and 0x1F).toInt()])
            }
        }
        if (bits > 0) {
            sb.append(ALPHABET[((buffer shl (5 - bits)) and 0x1F).toInt()])
        }
        return sb.toString()
    }
}
