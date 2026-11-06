package com.scanauth.sdk.internal

import com.scanauth.sdk.SdkError
import com.scanauth.sdk.SdkException

/**
 * “已固化的提交地址”句柄。
 *
 * 刻意设计为：
 * - 构造函数私有；
 * - 只能通过 [fromStored] 从本地安全存储读取的规范化字符串构造；
 * - [Submitter] 只接受本类型，**不接受 String / URL 入参**。
 *
 * 这样就从 API 层杜绝“把二维码里的地址拿去提交”的误用（S1）。
 */
internal class PinnedEndpoint private constructor(
    val url: CanonicalUrl,
    val canonicalUrl: String
) {

    /** 仅回环地址允许 http（规范 §7.2 C2 的本地开发例外）。 */
    val isLoopbackHttp: Boolean get() = url.scheme == "http" && url.isLoopback

    companion object {
        fun fromStored(canonicalUrl: String): PinnedEndpoint {
            val parsed = CanonicalAddress.parse(canonicalUrl)
            if (parsed.canonical != canonicalUrl) {
                throw SdkException(SdkError.SECURE_STORAGE_ERROR, "本地固化地址不是规范形式")
            }
            if (parsed.scheme != "https" && !parsed.isLoopback) {
                throw SdkException(SdkError.SECURE_STORAGE_ERROR, "本地固化地址不是 HTTPS")
            }
            return PinnedEndpoint(parsed, parsed.canonical)
        }
    }

    override fun toString(): String = canonicalUrl
}
