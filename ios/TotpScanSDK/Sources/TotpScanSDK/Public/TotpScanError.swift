import Foundation

/// SDK 对外的统一错误类型。对外文案不包含密钥、token、动态码或服务端内部细节。
public enum TotpScanError: Error, LocalizedError {
    case invalidQRCode(String)
    case unsupportedVersion
    case expiredQRCode
    case insecureAddress(String)
    case noMatchingAccount
    case multipleMatchingAccounts([AccountSummary])
    case accountNotFound
    case accountNotBound
    case accountNotConfirmed
    case boundAccountCodeNotAvailable
    case bindingConfirmationFailed
    case duplicateBinding
    case keychainFailure(String)
    case networkFailure(String)
    case serverRejected
    case rateLimited
    case adminAuthorizationFailed
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidQRCode:
            return "二维码无效或已过期"
        case .unsupportedVersion:
            return "二维码版本不受支持"
        case .expiredQRCode:
            return "二维码已过期，请刷新后重试"
        case .insecureAddress:
            return "二维码中的提交地址不安全"
        case .noMatchingAccount:
            return "该二维码不属于已绑定的服务器"
        case .multipleMatchingAccounts(let accounts):
            return "有多个已绑定账户与二维码地址匹配（\(accounts.count) 个），请选择要使用的账户"
        case .accountNotFound:
            return "账户不存在或已被删除"
        case .accountNotBound:
            return "该账户不是扫码绑定账户"
        case .accountNotConfirmed:
            return "该账户尚未完成绑定确认，暂时不能用于扫码登录"
        case .boundAccountCodeNotAvailable:
            return "扫码绑定账户不提供动态码，请在登录页扫码提交"
        case .bindingConfirmationFailed:
            return "绑定确认失败。请重新发起绑定，或稍后在账户详情中重试"
        case .duplicateBinding:
            return "该绑定已存在，请勿重复添加"
        case .keychainFailure:
            return "无法访问本机安全存储"
        case .networkFailure:
            return "无法连接服务器，请检查网络后重新扫码"
        case .serverRejected:
            return "认证失败，请重新发起登录"
        case .rateLimited:
            return "操作过于频繁，请稍后再试"
        case .adminAuthorizationFailed:
            return "管理员令牌无效，无法完成服务器端解绑"
        case .invalidInput:
            return "输入内容不合法"
        }
    }

    public var failureReason: String? {
        switch self {
        case .invalidQRCode(let reason): return reason
        case .insecureAddress(let reason): return reason
        case .keychainFailure(let reason): return reason
        case .networkFailure(let reason): return reason
        case .invalidInput(let reason): return reason
        default: return nil
        }
    }
}
