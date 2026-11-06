import Foundation
import os

/// 结构化日志。API 不接受自由文本，确保共享密钥、token、动态码与提交路径查询参数
/// 不可能被误写进日志（规范 S3 / S11）。
public enum SDKLog {
    public struct Event: Sendable {
        let name: String
        let detail: String?

        init(_ name: String, detail: String? = nil) {
            self.name = name
            self.detail = detail
        }
    }

    public static var isEnabled = false

    private static let logger = Logger(subsystem: "com.scanauth.totpscan", category: "sdk")

    public static func record(_ event: Event) {
        guard isEnabled else { return }
        if let detail = event.detail {
            logger.debug("\(event.name, privacy: .public) \(detail, privacy: .public)")
        } else {
            logger.debug("\(event.name, privacy: .public)")
        }
    }

    public static let bindingVerified = Event("binding.verified")
    public static let bindingStored = Event("binding.stored")
    public static let bindingConfirmed = Event("binding.confirmed")
    public static let bindingConfirmFailed = Event("binding.confirm_failed")
    public static let loginMatched = Event("login.matched")
    public static let loginMismatch = Event("login.mismatch")
    public static func submitFinished(status: Int) -> Event {
        Event("submit.finished", detail: "status=\(status)")
    }
    public static let accountDeleted = Event("account.deleted")
    public static let keychainUnavailable = Event("keychain.unavailable")
}
