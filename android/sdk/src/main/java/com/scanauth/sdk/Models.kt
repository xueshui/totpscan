package com.scanauth.sdk

/** TOTP 摘要算法（RFC 6238 允许 HMAC-SHA1 / SHA256 / SHA512）。 */
enum class TotpAlgorithm(val macName: String, val uriName: String) {
    SHA1("HmacSHA1", "SHA1"),
    SHA256("HmacSHA256", "SHA256"),
    SHA512("HmacSHA512", "SHA512");

    companion object {
        /** `otpauth://` 参数解析；缺省为 SHA1，未知值拒绝（U4）。 */
        fun fromUriName(value: String?): TotpAlgorithm {
            if (value.isNullOrBlank()) return SHA1
            return entries.firstOrNull { it.uriName.equals(value, ignoreCase = true) }
                ?: throw SdkException(SdkError.INVALID_PAYLOAD, "不支持的算法: $value")
        }
    }
}

/** 标准 TOTP 参数。协议绑定账户由二维码中的 `alg/dig/per` 决定。 */
data class TotpParameters(
    val algorithm: TotpAlgorithm = TotpAlgorithm.SHA1,
    val digits: Int = 6,
    val periodSeconds: Long = 30
) {
    init {
        require(digits in 6..8) { "digits 仅支持 6~8" }
        require(periodSeconds in 1..3600) { "period 仅支持 1~3600 秒" }
    }

    companion object {
        val PROTOCOL = TotpParameters(TotpAlgorithm.SHA1, 6, 30)
    }
}

/**
 * 账户类型（规范 §13.1）。
 *
 * - [PROTOCOL]：扫码型账户，含固化提交地址，只能通过扫码提交动态码，SDK 不向调用方暴露即时码；
 * - [STANDARD]：标准型账户，来自 `otpauth://` 或手动录入，仅本地计算动态码，不参与扫码提交。
 */
enum class AccountType {
    PROTOCOL,
    STANDARD
}

/** `otpauth://totp` 解析结果。 */
data class OtpauthAccount(
    val issuer: String,
    val accountId: String,
    val secretBase32: String,
    val parameters: TotpParameters = TotpParameters()
)

/** 校验窗口内的匹配结果。 */
data class TotpVerifyResult(
    /** 是否命中。 */
    val matched: Boolean,
    /** 命中的时间步偏移（0 表示当前步长；-1 表示上一窗口），未命中为 null。 */
    val offsetSteps: Int?,
    /** 命中时对应的动态码，未命中为 null。 */
    val matchedCode: String?
)

/**
 * 单个账户的只读摘要（不含任何密钥材料）。
 *
 * 注意：[AccountType.PROTOCOL] 账户默认不暴露动态码；只有用户显式开启
 * 「显示扫码型账户的动态码」后，宿主才可调用 `ScanTotpClient.protocolCodeFor`。
 */
data class AccountSummary(
    /** 本地唯一标识，用于选择/重命名/删除。 */
    val localId: String,
    val type: AccountType,
    /** 账号标识（例如邮箱 / 工号）。 */
    val accountId: String,
    /** 用户填写的本地备注（仅存本机，不进二维码、不上送服务器）。 */
    val remark: String,
    /** 展示名：备注优先，否则 `issuer · accountId`。 */
    val displayName: String,
    /** 签发方名称。 */
    val issuer: String,
    /** 协议账户已固化的提交地址；标准型账户为 null。 */
    val submitUrl: String?,
    /** 协议账户的服务端绑定标识；标准型账户为 null。 */
    val bindingId: String?,
    /** 协议账户是否已完成服务端确认；标准型账户恒为 true。 */
    val isConfirmed: Boolean,
    /** 绑定 / 添加时间（Unix 毫秒）。 */
    val boundAtEpochMs: Long,
    val parameters: TotpParameters,
    /** 协议账户绑定的注册域名（例如 `example.com`）；标准型账户为 null。 */
    val registeredDomain: String? = null,
    /** 协议账户绑定的 `path[?query]`；标准型账户为 null。 */
    val submitPath: String? = null
)

/**
 * 绑定预览（字段解析通过，尚未写入本地）。
 *
 * 宿主 App 必须把 [submitUrl] / [registeredDomain] / [submitPath] 展示给用户确认，
 * 再调用 [ScanTotpClient.confirmBind]。该类由 SDK 构造，调用方无法伪造。
 */
class BindPreview internal constructor(
    val accountId: String,
    val issuer: String,
    /** 待固化的完整提交地址（规范化形式，含查询串）。 */
    val submitUrl: String,
    val bindingId: String,
    val parameters: TotpParameters,
    /** 绑定二维码过期时间（Unix 毫秒）；无 `exp` 时为 null。 */
    val expiresAtEpochMs: Long?,
    /** 提交地址的完整 host（已转 punycode / 小写）。 */
    val host: String,
    /** 本次绑定钉住的注册域名（PSL 子集推导）。 */
    val registeredDomain: String,
    /** 本次绑定钉住的 `path[?query]`。 */
    val submitPath: String,
    internal val rawPayload: String
)

/** 扫码登录的一个候选账户（由二维码 `sub` 与本地固化地址精确比对得出）。 */
data class LoginCandidate(
    val localId: String,
    val accountId: String,
    val displayName: String,
    val issuer: String,
    /** 该候选的固化地址（提交目标）。 */
    val submitUrl: String
)

/**
 * 登录二维码解析 + 地址比对结果。
 *
 * 只有在存在至少一个候选账户时才会返回；[candidates] 一定属于同一固化地址集合，
 * 不允许跨固化地址混合选择。
 */
class LoginScanResult internal constructor(
    /** 匹配到的候选账户，至少 1 个。 */
    val candidates: List<LoginCandidate>,
    /** 登录二维码过期时间（Unix 毫秒）。 */
    val expiresAtEpochMs: Long,
    /** 是否命中了“固化到裸源”的宽松规则，UI 应当提示风险。 */
    val lenientAddressMatch: Boolean,
    /** 匹配到的固化地址（规范形式），仅用于展示；提交时使用账户自身的完整地址。 */
    val submitUrl: String,
    internal val token: String,
    internal val rawPayload: String
)

/** 服务端提交结果。 */
data class SubmitResult(
    /** HTTP 状态码。 */
    val httpStatus: Int,
    /** 服务端返回的错误码（成功时为 null）。 */
    val serverErrorCode: String?,
    /** 服务端返回的文案（成功时可能为 null）。 */
    val serverMessage: String?,
    /** 服务端 request_id，便于用户向运维反馈。 */
    val requestId: String?,
    /** 由响应头 Date 估算的设备与服务器时间偏差（秒）；无法获取时为 null。 */
    val serverTimeOffsetSeconds: Long? = null
) {
    val isAccepted: Boolean get() = httpStatus in 200..299
}

/** 绑定 / 添加账户流程回调。所有回调都在主线程触发。 */
interface BindListener {
    /** 解析 + 验签通过，等待用户确认待固化地址与备注。 */
    fun onConfirmRequired(preview: BindPreview)

    /** 账户已写入本地（协议账户此时可能仍未完成服务端确认）。 */
    fun onBound(account: AccountSummary)

    /** 流程失败。 */
    fun onFailure(error: SdkError, message: String?, cause: Throwable?)
}

/** 绑定服务端确认回调（`POST /totp/v1/bindings/{bid}/confirm`）。 */
interface BindingConfirmListener {
    fun onConfirmed(account: AccountSummary)

    fun onFailure(error: SdkError, message: String?, cause: Throwable?)
}

/** 登录二维码扫描（解析 + 地址比对）回调。 */
interface LoginScanListener {
    fun onReady(result: LoginScanResult)

    fun onFailure(error: SdkError, message: String?, cause: Throwable?)
}

/** 登录提交回调。所有回调都在主线程触发。 */
interface LoginListener {
    /** 服务端已响应并接受本次动态码。 */
    fun onResult(result: SubmitResult)

    /** 提交失败。 */
    fun onFailure(error: SdkError, message: String?, cause: Throwable?)
}

/** 账户操作（重命名 / 删除 / 解绑 / 确认）回调。所有回调都在主线程触发。 */
interface AccountOperationListener {
    /** 操作成功，返回操作后的账户列表。 */
    fun onSuccess(accounts: List<AccountSummary>)

    /** 操作失败。 */
    fun onFailure(error: SdkError, message: String?, cause: Throwable?)
}
