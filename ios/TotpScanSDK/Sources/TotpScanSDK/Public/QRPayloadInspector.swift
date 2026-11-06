import Foundation

/// 扫描内容的大致类型，用于 App 在“添加账户 / 扫码登录”之间分流。
public enum QRPayloadKind: String, Sendable {
    case otpAuth
    case binding
    case login
    case unknown
}

public enum QRPayloadInspector {
    public static func kind(of text: String) -> QRPayloadKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth://") {
            return .otpAuth
        }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["t"] as? String else {
            return .unknown
        }
        switch type {
        case "totp-bind": return .binding
        case "totp-login": return .login
        default: return .unknown
        }
    }
}
