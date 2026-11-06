import Foundation
import LocalAuthentication

public enum DeviceAuthError: Error, LocalizedError {
    case unavailable
    case notEnrolled
    case lockedOut
    case cancelled
    case failed

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "此设备不支持 Face ID / Touch ID"
        case .notEnrolled: return "尚未设置 Face ID 或 Touch ID"
        case .lockedOut: return "生物识别已被锁定，请先用设备密码解锁"
        case .cancelled: return "已取消身份验证"
        case .failed: return "身份验证失败"
        }
    }
}

/// Face ID / Touch ID 门禁。提交动态码前调用，验证失败即终止，不提供绕过。
public enum DeviceAuthenticator {
    /// 当前设备的生物识别名称，用于界面文案。
    public static var biometryName: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default:
            if #available(iOS 17.0, macOS 14.0, *), context.biometryType == .opticID {
                return "Optic ID"
            }
            return "生物识别"
        }
    }

    public static func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// - Parameter allowPasscodeFallback: 为 `true` 时允许在生物识别不可用时回退到设备密码。
    public static func authenticate(
        reason: String,
        allowPasscodeFallback: Bool = false
    ) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        let policy: LAPolicy = allowPasscodeFallback
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        var policyError: NSError?
        guard context.canEvaluatePolicy(policy, error: &policyError) else {
            throw mapError(policyError)
        }

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            if !success {
                throw DeviceAuthError.failed
            }
        } catch let error as DeviceAuthError {
            throw error
        } catch {
            throw mapError(error as NSError)
        }
    }

    private static func mapError(_ error: NSError?) -> DeviceAuthError {
        guard let error else { return .failed }
        guard let code = LAError.Code(rawValue: error.code) else { return .failed }
        switch code {
        case .biometryNotAvailable:
            return .unavailable
        case .biometryNotEnrolled:
            return .notEnrolled
        case .biometryLockout:
            return .lockedOut
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        default:
            return .failed
        }
    }
}
