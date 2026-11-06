package com.scanauth.sdk.internal

import com.scanauth.sdk.ScanTotpConfig
import com.scanauth.sdk.SdkError
import com.scanauth.sdk.SdkException
import com.scanauth.sdk.SubmitResult
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL

/**
 * 提交层（规范 §6.1(5)、§8、§11 S1/S10/S11）。
 *
 * 安全约束：
 * - 只接受 [PinnedEndpoint]（只能由本地固化记录构造），**不提供任何 URL / String 入参**；
 * - 目标地址必须与固化地址同源（scheme + host + port），杜绝被拼接逻辑带偏；
 * - 使用系统默认 TLS 栈与主机名校验，不设置自定义 SSLSocketFactory / TrustManager / HostnameVerifier；
 * - 关闭自动重定向，3xx 一律失败；
 * - 不携带 Cookie / Authorization / 设备标识；
 * - 日志只记录状态码，绝不记录会话 `token`、动态码或响应体。
 */
internal class Submitter(private val config: ScanTotpConfig) {

    /**
     * 登录提交：`POST https://<dom><path>`，请求体 `{"code":"123456","token":"..."}`。
     *
     * 提交目标只来自绑定阶段的完整地址；请求体不再包含 scan_token / account / device_id。
     */
    fun submitCode(pinned: PinnedEndpoint, token: String, code: String): SubmitResult {
        val body = JSONObject()
            .put("code", code)
            .put("token", token)
            .toString()
        return post(pinned, pinned.canonicalUrl, body)
    }

    /**
     * 绑定确认：`POST /totp/v1/bindings/{bid}/confirm`，请求体 `{"code":"..."}`。
     *
     * 服务端接口路径固定；这里从固化地址推导 API 前缀：
     * - `.../totp/v1/verify` → `.../totp/v1`
     * - `.../totp/v1` → 原样
     * - 其它 → 回退到站点的 `/totp/v1`
     */
    fun confirmBinding(pinned: PinnedEndpoint, bindingId: String, code: String): SubmitResult {
        val body = JSONObject().put("code", code).toString()
        return post(pinned, confirmUrl(pinned, bindingId), body)
    }

    private fun confirmUrl(pinned: PinnedEndpoint, bindingId: String): String {
        val path = pinned.url.path
        val base = when {
            path.endsWith("/verify") -> path.dropLast("/verify".length)
            path.endsWith("/totp/v1") -> path
            else -> "/totp/v1"
        }
        val prefix = if (base.isEmpty() || base == "/") "" else base
        val port = if (pinned.url.port >= 0) ":${pinned.url.port}" else ""
        return "${pinned.url.scheme}://${pinned.url.host}$port$prefix/bindings/$bindingId/confirm"
    }

    private fun post(pinned: PinnedEndpoint, targetUrl: String, body: String): SubmitResult {
        if (pinned.url.scheme == "http" && !pinned.url.isLoopback) {
            throw SdkException(SdkError.INSECURE_ADDRESS, "明文 http 仅允许本机调试")
        }

        // 第二次同源校验：确认拼接后的目标没有被引到其它主机
        val target = CanonicalAddress.parse(targetUrl)
        if (target.scheme != pinned.url.scheme ||
            target.host != pinned.url.host ||
            target.port != pinned.url.port
        ) {
            throw SdkException(SdkError.INSECURE_ADDRESS, "提交目标与固化地址不同源")
        }

        val url = try {
            URL(target.canonical)
        } catch (e: Exception) {
            throw SdkException(SdkError.INSECURE_ADDRESS, "提交地址无法解析", e)
        }

        var connection: HttpURLConnection? = null
        try {
            connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.useCaches = false
            connection.instanceFollowRedirects = false
            connection.connectTimeout = config.connectTimeoutMs
            connection.readTimeout = config.readTimeoutMs
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("User-Agent", "ScanTotpSdk/1.0")

            val payload = body.toByteArray(Charsets.UTF_8)
            connection.setFixedLengthStreamingMode(payload.size)
            connection.outputStream.use { it.write(payload) }

            val status = connection.responseCode
            val text = readResponse(connection, status)
            val offset = readServerTimeOffset(connection)

            SdkLog.d("submit finished with status $status")

            if (status in 200..299) {
                val json = parseJson(text)
                if (json != null && json.has("authenticated") && !json.optBoolean("authenticated", true)) {
                    throw SdkException(SdkError.SERVER_REJECTED)
                }
                return SubmitResult(
                    httpStatus = status,
                    serverErrorCode = json?.optStringOrNull("error"),
                    serverMessage = json?.optStringOrNull("message"),
                    requestId = json?.optStringOrNull("request_id"),
                    serverTimeOffsetSeconds = offset
                )
            }

            throw when (status) {
                400 -> SdkException(SdkError.SERVER_INVALID_REQUEST, "请求格式无效")
                401, 403 -> SdkException(SdkError.SERVER_REJECTED)
                429 -> SdkException(SdkError.RATE_LIMITED)
                in 300..399 -> SdkException(SdkError.HTTP_ERROR, "服务端返回重定向，已按安全策略拒绝")
                else -> SdkException(SdkError.HTTP_ERROR, "服务端返回异常状态码 HTTP $status")
            }
        } catch (e: SdkException) {
            throw e
        } catch (e: SocketTimeoutException) {
            throw SdkException(SdkError.NETWORK_ERROR, "请求超时", e)
        } catch (e: IOException) {
            throw SdkException(SdkError.NETWORK_ERROR, "网络不可用或 TLS 校验失败", e)
        } catch (e: Exception) {
            throw SdkException(SdkError.INTERNAL_ERROR, "提交过程异常", e)
        } finally {
            connection?.disconnect()
        }
    }

    private fun readResponse(connection: HttpURLConnection, status: Int): String {
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        return stream?.bufferedReader(Charsets.UTF_8)?.use { reader ->
            val buffer = CharArray(2048)
            val builder = StringBuilder()
            while (builder.length < 8192) {
                val count = reader.read(buffer)
                if (count <= 0) break
                builder.append(buffer, 0, count)
            }
            builder.toString()
        } ?: ""
    }

    /** 由响应头 `Date` 估算设备与服务器的时间偏差（秒），仅用于 UI 提示。 */
    private fun readServerTimeOffset(connection: HttpURLConnection): Long? {
        val serverMillis = connection.getHeaderFieldDate("Date", 0L)
        if (serverMillis <= 0L) return null
        return (serverMillis - System.currentTimeMillis()) / 1000L
    }

    private fun parseJson(text: String): JSONObject? = runCatching {
        if (text.isBlank()) null else JSONObject(text)
    }.getOrNull()

    private fun JSONObject.optStringOrNull(name: String): String? {
        if (!has(name) || isNull(name)) return null
        return optString(name, "").ifBlank { null }
    }
}
