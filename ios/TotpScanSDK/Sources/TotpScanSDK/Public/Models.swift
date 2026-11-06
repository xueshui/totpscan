import Foundation

/// 账户类型：标准 TOTP 账户，或通过绑定二维码固化地址的协议账户。
public enum AccountKind: String, Codable, Sendable {
    case standard
    case bound

    public var displayName: String {
        switch self {
        case .standard: return "标准 TOTP"
        case .bound: return "扫码绑定"
        }
    }
}

/// 账户的创建来源。仅用于界面展示，不参与安全判定。
public enum AccountSource: String, Codable, Sendable {
    case manual
    case uri
    case binding

    public var displayName: String {
        switch self {
        case .manual: return "手动输入"
        case .uri: return "otpauth 链接导入"
        case .binding: return "扫码绑定"
        }
    }
}

/// 账户的只读摘要，不包含共享密钥。
public struct AccountSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: AccountKind
    public let issuer: String
    public let account: String
    public let displayName: String
    public let algorithm: OtpAlgorithm
    public let digits: Int
    public let period: Int
    public let source: AccountSource
    public let pinnedSubmitURL: String?
    public let bindingID: String?
    public let boundAt: Date?
    public let isConfirmed: Bool
    public let looseOriginPinning: Bool
    /// 绑定站点的注册域名（eTLD+1），仅扫码型账户有值。
    public let registrableDomain: String?
    /// 绑定时保留的 path + query，仅扫码型账户有值。
    public let pinnedSubmitPath: String?

    public var isBound: Bool { kind == .bound }

    public var title: String {
        displayName.isEmpty ? account : displayName
    }

    public var subtitle: String {
        issuer.isEmpty ? account : "\(issuer) · \(account)"
    }

    public var canSubmitByScan: Bool {
        kind == .bound && isConfirmed
    }
}

/// 绑定二维码通过格式校验后、写入安全存储前的确认上下文。
/// 只能由 SDK 构造，调用方无法伪造地址或密钥。
public struct BindingPreview: Identifiable, Sendable {
    public let id = UUID()
    public let issuer: String
    public let account: String
    public let bindingID: String
    /// 绑定时的完整提交地址（含查询串），必须展示给用户确认。
    public let submitURL: String
    public let algorithm: OtpAlgorithm
    public let digits: Int
    public let period: Int
    public let expiresAt: Date?
    /// 固化地址为裸源（路径为 `/`）时，同源任意路径都会命中，风险更高。
    public let isLooseOrigin: Bool
    /// 注册域名（eTLD+1），登录时要求二维码的注册域名与它相等。
    public let registrableDomain: String
    /// 绑定的 path + query，提交时原样拼接到 `https://<dom>` 之后。
    public let submitPath: String

    let secret: Data
    let issuedAt: Date

    init(
        issuer: String,
        account: String,
        bindingID: String,
        submitURL: String,
        algorithm: OtpAlgorithm,
        digits: Int,
        period: Int,
        expiresAt: Date?,
        isLooseOrigin: Bool,
        registrableDomain: String,
        submitPath: String,
        secret: Data,
        issuedAt: Date
    ) {
        self.issuer = issuer
        self.account = account
        self.bindingID = bindingID
        self.submitURL = submitURL
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.expiresAt = expiresAt
        self.isLooseOrigin = isLooseOrigin
        self.registrableDomain = registrableDomain
        self.submitPath = submitPath
        self.secret = secret
        self.issuedAt = issuedAt
    }
}

/// 登录二维码通过注册域名比对后的上下文。不包含动态码，也不允许指定提交地址。
public struct LoginApproval: Identifiable, Sendable {
    public let id = UUID()
    public let accountID: String
    public let issuer: String
    public let account: String
    /// 本机固化的完整提交地址（含查询串），仅用于展示；实际提交目标由 SDK 从 Keychain 重新读取。
    public let submitURL: String
    public let expiresAt: Date
    public let isLooseOrigin: Bool
    /// 匹配到的注册域名（eTLD+1）。
    public let registrableDomain: String

    /// 登录二维码中的会话标识（16 或 24 位），用于提交 body。
    let token: String

    init(
        accountID: String,
        issuer: String,
        account: String,
        submitURL: String,
        expiresAt: Date,
        isLooseOrigin: Bool,
        registrableDomain: String,
        token: String
    ) {
        self.accountID = accountID
        self.issuer = issuer
        self.account = account
        self.submitURL = submitURL
        self.expiresAt = expiresAt
        self.isLooseOrigin = isLooseOrigin
        self.registrableDomain = registrableDomain
        self.token = token
    }
}

/// 服务端提交结果。
public struct SubmitOutcome: Equatable, Sendable {
    public let httpStatus: Int
    public let accepted: Bool
    public let serverMessage: String?

    public init(httpStatus: Int, accepted: Bool, serverMessage: String?) {
        self.httpStatus = httpStatus
        self.accepted = accepted
        self.serverMessage = serverMessage
    }
}

/// 协议绑定状态（用于 UI 展示）。
public enum BindingStatus: String, Sendable {
    case confirmed
    case unconfirmed

    public var displayName: String {
        switch self {
        case .confirmed: return "已确认，可扫码登录"
        case .unconfirmed: return "待确认，暂不可扫码登录"
        }
    }
}
