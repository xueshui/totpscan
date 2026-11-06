package com.scanauth.sdk

/**
 * SDK 运行时配置。
 *
 * 注意：这里刻意 **不提供** 提交地址配置项——提交地址只能来自绑定二维码，
 * 且必须经用户确认后固化到本地安全存储。
 */
data class ScanTotpConfig(
    /** 建立连接超时（毫秒）。 */
    val connectTimeoutMs: Int = 8_000,
    /** 读取响应超时（毫秒）。 */
    val readTimeoutMs: Int = 10_000,
    /** 二维码过期判断允许的时钟偏差（秒）。默认 0，严格按 exp 判断。 */
    val clockSkewSeconds: Long = 0,
    /**
     * 是否输出调试日志（仅输出流程节点，永不输出密钥、动态码、会话 token）。
     */
    val debugLogging: Boolean = false
)
