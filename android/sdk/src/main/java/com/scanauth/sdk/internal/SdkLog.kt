package com.scanauth.sdk.internal

import android.util.Log

/**
 * 内部日志。
 *
 * 约束（S9）：只允许输出固定流程节点文本，禁止把密钥、动态码、scan_token、
 * 二维码原文、请求体等敏感内容拼进日志；因此本类不提供格式化参数入口。
 */
internal object SdkLog {

    private const val TAG = "ScanTotp"

    @Volatile
    var enabled: Boolean = false

    fun d(event: String) {
        if (enabled) {
            runCatching { Log.d(TAG, event) }
        }
    }

    fun w(event: String) {
        if (enabled) {
            runCatching { Log.w(TAG, event) }
        }
    }
}
