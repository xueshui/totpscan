package com.scanauth.sdk.internal

import com.scanauth.sdk.SdkError
import com.scanauth.sdk.SdkException
import java.net.IDN
import java.util.Locale

/**
 * 规范形式的提交地址（规范 §7.2 的 C1–C7 输出）。
 *
 * - [scheme] 只有 `https` / `http`（http 仅限回环地址）；
 * - [host] 已转 punycode 小写；IPv6 保留方括号；
 * - [port] 为 -1 表示使用默认端口（https:443 / http:80）；
 * - [path] 以 `/` 开头，除根路径外不带结尾 `/`；
 * - [query] 原样保留（不重排、不解码），仅在存在时参与拼接。
 */
internal data class CanonicalUrl(
    val scheme: String,
    val host: String,
    val port: Int,
    val path: String,
    val query: String? = null
) {
    /** 绑定与比对使用的“路径 + 查询串”，例如 `/dtm/ulr?ma=xxx`。 */
    val submitPath: String
        get() = if (query.isNullOrEmpty()) path else "$path?$query"

    /** C7：`scheme://host[:port]path[?query]`。 */
    val canonical: String
        get() = buildString {
            append(scheme).append("://").append(host)
            if (port >= 0) append(':').append(port)
            append(submitPath)
        }

    val isRootPath: Boolean get() = path == "/"

    val isLoopback: Boolean get() = CanonicalAddress.isLoopback(host)

    /** 该地址所属的注册域名（PSL 子集推导）。 */
    val registeredDomain: String get() = RegisteredDomain.of(host)
}

/** 比对结果。裸源（P == `/`）命中属于宽松模式，UI 必须提示风险（M3）。 */
internal data class AddressMatch(
    val matched: Boolean,
    val lenientRoot: Boolean,
    /** 实际命中的注册域名（未命中时为 null）。 */
    val registeredDomain: String? = null
)

/**
 * 地址规范化（C1–C7）与登录域名比对的**唯一**实现。
 *
 * 设计约束：
 * 1. 登录比对只要求“注册域名相同”；路径只使用绑定记录里的 `path` 作为提交目标；
 * 2. 规范化与比对是纯函数，便于单元测试逐条覆盖；
 * 3. 失败一律抛 [SdkError.INSECURE_ADDRESS]，调用方据此终止流程且不发起任何网络请求。
 */
internal object CanonicalAddress {

    private const val MAX_LENGTH = 2048
    private const val DEFAULT_HTTPS_PORT = 443
    private const val DEFAULT_HTTP_PORT = 80
    private const val HEX = "0123456789ABCDEF"

    /** C1–C7：解析并输出规范形式。 */
    fun parse(raw: String): CanonicalUrl {
        // C1：长度、首尾空白、控制字符
        if (raw.isEmpty() || raw.length > MAX_LENGTH) fail("地址长度非法")
        if (raw != raw.trim()) fail("地址前后不得包含空白")
        for (ch in raw) {
            if (ch.code < 0x20 || ch.code == 0x7F) fail("地址不得包含控制字符")
        }

        // C2：绝对 URL，协议仅 https / http
        val schemeEnd = raw.indexOf("://")
        if (schemeEnd <= 0) fail("地址必须是绝对 URL")
        val scheme = raw.substring(0, schemeEnd).lowercase(Locale.ROOT)
        if (scheme != "https" && scheme != "http") fail("仅支持 https，http 仅限本机调试")

        val rest = raw.substring(schemeEnd + 3)
        if (rest.isEmpty()) fail("缺少主机名")

        // C3：禁止 userinfo、fragment；查询串保留（绑定路径需要原样保留，例如 ?ma=xxx）
        if (rest.contains('#')) fail("地址不得包含片段")

        val queryMark = rest.indexOf('?')
        val restNoQuery = if (queryMark >= 0) rest.substring(0, queryMark) else rest
        val rawQuery = if (queryMark >= 0) rest.substring(queryMark + 1) else null

        val slash = restNoQuery.indexOf('/')
        val authority = if (slash >= 0) restNoQuery.substring(0, slash) else restNoQuery
        val rawPath = if (slash >= 0) restNoQuery.substring(slash) else ""
        if (authority.isEmpty()) fail("缺少主机名")
        if (authority.contains('@')) fail("地址不得包含用户信息")

        val (rawHost, rawPort) = splitAuthority(authority)

        // C4：host 规范化
        val host = normalizeHost(rawHost)

        // C5：端口规范化
        val port = normalizePort(scheme, rawPort)

        // http 仅允许回环地址（规范 §7.2 C2）
        if (scheme == "http" && !isLoopback(host)) {
            fail("明文 http 仅允许 localhost / 127.0.0.1 / [::1]")
        }

        // C6：路径规范化
        val path = normalizePath(rawPath)

        val query = rawQuery?.takeIf { it.isNotEmpty() }
        if (query != null && query.any { it.isWhitespace() || it.code < 0x20 || it.code == 0x7F }) {
            fail("查询串不得包含空白或控制字符")
        }

        return CanonicalUrl(scheme, host, port, path, query)
    }

    /**
     * 登录比对：只比较**注册域名**（`dkn.example.com` 与 `example.com` 视为同站）。
     *
     * 登录码不携带路径；路径只使用绑定记录里的 `path` 作为提交目标。
     * 该方法保留为纯函数工具，便于单测覆盖域名判定。
     */
    fun matches(pinned: CanonicalUrl, candidate: CanonicalUrl): AddressMatch {
        val pinnedDomain = pinned.registeredDomain
        if (pinnedDomain != candidate.registeredDomain) return AddressMatch(false, false)
        return AddressMatch(true, false, pinnedDomain)
    }

    /** 便捷重载（仅用于测试与文档示例）。 */
    fun matches(pinnedUrl: String, candidateUrl: String): AddressMatch =
        matches(parse(pinnedUrl), parse(candidateUrl))

    /** 回环地址判定：localhost / 127.0.0.1 / [::1]。 */
    fun isLoopback(host: String): Boolean =
        host == "localhost" || host == "127.0.0.1" || host == "[::1]"

    // ------------------------------------------------------------------ 内部

    private fun splitAuthority(authority: String): Pair<String, String?> {
        if (authority.startsWith("[")) {
            val close = authority.indexOf(']')
            if (close < 0) fail("IPv6 地址缺少右方括号")
            val host = authority.substring(0, close + 1)
            val tail = authority.substring(close + 1)
            return when {
                tail.isEmpty() -> host to null
                tail.startsWith(":") -> host to tail.substring(1)
                else -> fail("主机名与端口之间格式非法")
            }
        }
        val firstColon = authority.indexOf(':')
        if (firstColon < 0) return authority to null
        if (firstColon != authority.lastIndexOf(':')) fail("IPv6 地址必须使用方括号")
        return authority.substring(0, firstColon) to authority.substring(firstColon + 1)
    }

    private fun normalizeHost(raw: String): String {
        if (raw.isEmpty()) fail("缺少主机名")
        if (raw.startsWith("[")) {
            if (!raw.endsWith("]")) fail("IPv6 地址格式非法")
            val inner = raw.substring(1, raw.length - 1)
            return "[" + compressIpv6(inner) + "]"
        }
        if (raw.any { it.isWhitespace() }) fail("主机名不得包含空白")

        val ascii = try {
            IDN.toASCII(raw, IDN.ALLOW_UNASSIGNED)
        } catch (e: Exception) {
            fail("主机名不是合法域名")
        }
        var host = ascii.lowercase(Locale.ROOT)
        // C4：去掉结尾的点
        while (host.endsWith(".")) host = host.dropLast(1)
        if (host.isEmpty()) fail("主机名非法")
        if (host.length > 253) fail("主机名过长")
        if (host.split('.').any { it.isEmpty() }) fail("主机名包含空标签")
        for (ch in host) {
            val ok = ch in 'a'..'z' || ch in '0'..'9' || ch == '-' || ch == '.' || ch == '_'
            if (!ok) fail("主机名包含非法字符")
        }
        return host
    }

    private fun normalizePort(scheme: String, raw: String?): Int {
        if (raw == null || raw.isEmpty()) return -1
        if (raw.length > 5 || raw.any { !it.isDigit() }) fail("端口格式非法")
        val port = raw.toIntOrNull() ?: fail("端口格式非法")
        if (port !in 1..65535) fail("端口超出范围")
        if (scheme == "https" && port == DEFAULT_HTTPS_PORT) return -1
        if (scheme == "http" && port == DEFAULT_HTTP_PORT) return -1
        return port
    }

    private fun normalizePath(rawPath: String): String {
        if (rawPath.isEmpty()) return "/"
        if (rawPath.any { it.isWhitespace() }) fail("路径不得包含空白")
        if (!rawPath.startsWith("/")) fail("路径必须以 / 开头")

        // C6：解码 unreserved 的百分号编码，其余 %XX 统一大写
        val decoded = normalizePercentEncoding(rawPath)

        // C6：合并连续 `/`，解析 `.` 与 `..`（不越过根）
        val stack = ArrayDeque<String>()
        for (segment in decoded.split('/')) {
            when (segment) {
                "", "." -> Unit
                ".." -> if (stack.isNotEmpty()) stack.removeLast()
                else -> stack.addLast(segment)
            }
        }
        val result = "/" + stack.joinToString("/")
        // C6：除根路径外去掉末尾 `/`
        return if (result.isEmpty()) "/" else result
    }

    private fun normalizePercentEncoding(path: String): String {
        val builder = StringBuilder(path.length)
        var i = 0
        while (i < path.length) {
            val ch = path[i]
            if (ch != '%') {
                builder.append(ch)
                i++
                continue
            }
            if (i + 2 >= path.length) fail("路径百分号编码非法")
            val high = hexValue(path[i + 1])
            val low = hexValue(path[i + 2])
            if (high < 0 || low < 0) fail("路径百分号编码非法")
            val value = (high shl 4) or low
            if (isUnreserved(value)) {
                builder.append(value.toChar())
            } else {
                builder.append('%').append(HEX[high]).append(HEX[low])
            }
            i += 3
        }
        return builder.toString()
    }

    private fun isUnreserved(value: Int): Boolean {
        val ch = value.toChar()
        return ch in 'A'..'Z' || ch in 'a'..'z' || ch in '0'..'9' ||
            ch == '-' || ch == '.' || ch == '_' || ch == '~'
    }

    private fun hexValue(ch: Char): Int = when (ch) {
        in '0'..'9' -> ch - '0'
        in 'a'..'f' -> ch - 'a' + 10
        in 'A'..'F' -> ch - 'A' + 10
        else -> -1
    }

    /** IPv6 压缩：取最长连续 0 段，输出小写十六进制。 */
    private fun compressIpv6(inner: String): String {
        if (inner.isEmpty()) fail("IPv6 地址格式非法")
        if (inner.contains('.')) fail("不支持内嵌 IPv4 的 IPv6 地址")
        for (ch in inner) {
            val ok = ch.isDigit() || ch in 'a'..'f' || ch in 'A'..'F' || ch == ':'
            if (!ok) fail("IPv6 地址格式非法")
        }

        val parts = inner.split("::")
        if (parts.size > 2) fail("IPv6 地址格式非法")

        fun groups(text: String): List<Int> {
            if (text.isEmpty()) return emptyList()
            return text.split(':').map { group ->
                if (group.isEmpty() || group.length > 4) fail("IPv6 地址格式非法")
                group.toInt(16)
            }
        }

        val head = groups(parts[0])
        val tail = if (parts.size == 2) groups(parts[1]) else emptyList()
        val values = IntArray(8)
        if (parts.size == 1) {
            if (head.size != 8) fail("IPv6 地址格式非法")
            head.forEachIndexed { index, value -> values[index] = value }
        } else {
            if (head.size + tail.size > 7) fail("IPv6 地址格式非法")
            head.forEachIndexed { index, value -> values[index] = value }
            tail.forEachIndexed { index, value -> values[8 - tail.size + index] = value }
        }

        var bestStart = -1
        var bestLength = 1
        var index = 0
        while (index < 8) {
            if (values[index] == 0) {
                var end = index
                while (end < 8 && values[end] == 0) end++
                if (end - index > bestLength) {
                    bestLength = end - index
                    bestStart = index
                }
                index = end
            } else {
                index++
            }
        }

        val segments = ArrayList<String>(8)
        index = 0
        while (index < 8) {
            if (index == bestStart) {
                segments.add("")
                index += bestLength
            } else {
                segments.add(Integer.toHexString(values[index]))
                index++
            }
        }
        if (bestStart == 0 && bestLength == 8) return "::"

        var text = segments.joinToString(":")
        if (segments.firstOrNull() == "") text = ":$text"
        if (segments.lastOrNull() == "") text = "$text:"
        return text
    }

    private fun fail(message: String): Nothing =
        throw SdkException(SdkError.INSECURE_ADDRESS, message)
}
