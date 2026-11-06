package com.scanauth.sdk

/**
 * SDK 统一错误码。
 *
 * 调用方应优先依据枚举分支处理，而不是解析 [defaultMessage] 文本。
 * 错误码分段：
 * - 1xxx 本地状态 / 参数；
 * - 2xxx 二维码与地址校验；
 * - 3xxx 安全存储；
 * - 4xxx 网络与服务端；
 * - 9xxx 其它内部错误。
 */
enum class SdkError(val code: Int, val defaultMessage: String) {

    /** 尚未调用 [ScanTotpClient.create]。 */
    NOT_INITIALIZED(1001, "SDK 未初始化"),

    /** 本机没有对应的账户。 */
    NOT_BOUND(1003, "本机尚未绑定该账户"),

    /** 入参不合法（如备注为空或过长）。 */
    INVALID_ARGUMENT(1004, "参数不合法"),

    /** 当前操作与账户类型不匹配（标准型账户不参与扫码提交）。 */
    ACCOUNT_TYPE_MISMATCH(1005, "当前账户类型不支持该操作"),

    /** 同一固化地址下存在多个候选账户，需要用户显式选择。 */
    ACCOUNT_SELECTION_REQUIRED(1006, "存在多个候选账户，请选择要使用的账户"),

    /** 二维码内容格式非法（非 JSON、字段缺失或取值不合法）。 */
    INVALID_PAYLOAD(2001, "二维码内容格式非法"),

    /** 二维码协议版本不受支持（v != 1）。 */
    UNSUPPORTED_VERSION(2002, "二维码协议版本不受支持"),

    /** 二维码已过期。 */
    PAYLOAD_EXPIRED(2003, "二维码已过期，请刷新后重试"),

    /** 地址不满足 C1–C7 规范（非 HTTPS、含 userinfo/fragment、host 非法等）。 */
    INSECURE_ADDRESS(2005, "提交地址不满足安全要求"),

    /** 二维码地址与本机全部固化地址都不匹配（此时不会发起任何网络请求）。 */
    ADDRESS_MISMATCH(2006, "该二维码不属于任何已绑定的服务器，已终止且未发起任何网络请求"),

    /** 二维码类型与当前操作不符（例如把登录码当成绑定码）。 */
    QR_TYPE_MISMATCH(2008, "二维码类型不匹配"),

    /** 安全存储不可用、数据损坏或被清除。 */
    SECURE_STORAGE_ERROR(3001, "安全存储不可用或数据已损坏"),

    /** 网络异常（连接失败、超时、TLS 握手失败等）。 */
    NETWORK_ERROR(4001, "网络请求失败，请检查网络后重试"),

    /** 服务端明确拒绝本次请求（401 统一失败响应）。 */
    SERVER_REJECTED(4002, "认证失败，请重新发起登录"),

    /** 服务端返回了非预期的状态码。 */
    HTTP_ERROR(4003, "服务端返回异常状态码"),

    /** 服务端限流（429）。 */
    RATE_LIMITED(4004, "请求过于频繁，请稍后再试"),

    /** 服务端认为请求格式无效（400）。 */
    SERVER_INVALID_REQUEST(4005, "请求格式无效"),

    /** 其它内部错误。 */
    INTERNAL_ERROR(9001, "内部错误")
}
