import Foundation
import UIKit

/// 应用状态。所有账户数据都通过 `TotpScanClient` 读写，界面不直接接触密钥。
@MainActor
final class AppModel: ObservableObject {
    static let noteLimit = TotpScanClient.displayNameMaxLength

    /// 「显示扫码型账户动态码」开关的本地存储键。默认关闭，不参与任何迁移或导出。
    private static let showBoundCodesKey = "com.scanauth.totpscan.showBoundCodes"

    let client: TotpScanClient

    @Published private(set) var accounts: [AccountSummary] = []
    @Published private(set) var codes: [String: TotpCode] = [:]
    /// 高风险选项：开启后扫码型账户也会显示动态码。状态只存在本机。
    @Published private(set) var showBoundCodes: Bool
    @Published private(set) var loaded = false
    @Published private(set) var serverDrift: TimeInterval?
    @Published private(set) var driftAccountTitle: String?
    @Published private(set) var isRefreshingDrift = false

    @Published var alertMessage: String?
    @Published var toastMessage: String?

    private var timer: Timer?
    private var toastWorkItem: DispatchWorkItem?

    init(client: TotpScanClient = TotpScanClient()) {
        self.client = client
        self.showBoundCodes = UserDefaults.standard.bool(forKey: Self.showBoundCodesKey)
        reload()
        startTicker()
    }

    deinit {
        timer?.invalidate()
        toastWorkItem?.cancel()
    }

    // MARK: - 账户列表

    var boundAccounts: [AccountSummary] {
        accounts.filter { $0.kind == .bound }
    }

    var standardAccounts: [AccountSummary] {
        accounts.filter { $0.kind == .standard }
    }

    var hasDriftWarning: Bool {
        guard let serverDrift else { return false }
        return abs(serverDrift) >= 5
    }

    func reload() {
        do {
            accounts = try client.loadAccounts()
            loaded = true
            refreshCodes()
        } catch {
            loaded = true
            present(error)
        }
    }

    func refreshCodes(now: Date = Date()) {
        var next: [String: TotpCode] = [:]
        for account in accounts {
            let code: TotpCode?
            if account.kind == .standard {
                code = try? client.code(for: account.id, at: now)
            } else if showBoundCodes {
                code = try? client.revealedCode(for: account.id, at: now)
            } else {
                code = nil
            }
            if let code {
                next[account.id] = code
            }
        }
        codes = next
    }

    func account(id: String) -> AccountSummary? {
        accounts.first(where: { $0.id == id })
    }

    // MARK: - 标准 TOTP 账户

    @discardableResult
    func addStandardAccount(
        issuer: String,
        account: String,
        secret: String,
        algorithm: OtpAlgorithm,
        digits: Int,
        period: Int,
        note: String
    ) throws -> AccountSummary {
        let summary = try client.addStandardAccount(
            issuer: issuer,
            account: account,
            secretBase32: secret,
            algorithm: algorithm,
            digits: digits,
            period: period,
            displayName: note
        )
        reload()
        showToast("已添加标准 TOTP 账户")
        return summary
    }

    @discardableResult
    func addStandardAccount(fromOTPAuthURI uri: String, note: String) throws -> AccountSummary {
        let summary = try client.addStandardAccount(fromOTPAuthURI: uri)
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try client.renameAccount(id: summary.id, displayName: note)
        }
        reload()
        showToast("已导入标准 TOTP 账户")
        return summary
    }

    // MARK: - 绑定流程

    func previewBinding(qrText: String) throws -> BindingPreview {
        try client.previewBinding(qrText: qrText)
    }

    @discardableResult
    func commitBinding(_ preview: BindingPreview, note: String) throws -> AccountSummary {
        let summary = try client.commitBinding(preview, displayName: note)
        reload()
        showToast("绑定已保存")
        return summary
    }

    @discardableResult
    func confirmBinding(accountID: String) async throws -> AccountSummary {
        let summary = try await client.confirmBinding(accountID: accountID)
        reload()
        showToast("绑定已确认，可用于扫码登录")
        return summary
    }

    // MARK: - 扫码登录

    func prepareLogin(qrText: String, preferredAccountID: String? = nil) throws -> LoginApproval {
        try client.prepareLogin(qrText: qrText, preferredAccountID: preferredAccountID)
    }

    func submit(_ approval: LoginApproval) async throws -> SubmitOutcome {
        let outcome = try await client.submit(approval)
        reload()
        return outcome
    }

    /// 提交前的身份门禁。生物识别不可用时才允许回退到设备密码，避免用户被锁死在门外。
    func authenticateForSubmit() async throws {
        let reason = "验证身份以提交一次性动态码"
        if DeviceAuthenticator.canAuthenticate() {
            try await DeviceAuthenticator.authenticate(reason: reason, allowPasscodeFallback: false)
        } else {
            try await DeviceAuthenticator.authenticate(reason: reason, allowPasscodeFallback: true)
        }
    }

    var biometryLabel: String {
        DeviceAuthenticator.biometryName
    }

    // MARK: - 导出二维码与扫码型账户动态码

    /// 仅用于屏幕展示的 otpauth URI。调用前必须先通过 `authenticateForExport()`。
    func otpauthURI(for accountID: String) throws -> String {
        try client.otpauthURI(for: accountID)
    }

    /// 导出前的身份门禁：生物识别不可用时允许设备密码。
    func authenticateForExport() async throws {
        try await DeviceAuthenticator.authenticate(
            reason: "验证身份以导出账户二维码",
            allowPasscodeFallback: true
        )
    }

    /// 开启「显示扫码型账户动态码」。先做本地认证，认证通过才写入状态。
    func enableBoundCodes() async throws {
        guard !showBoundCodes else { return }
        try await DeviceAuthenticator.authenticate(
            reason: "验证身份以开启扫码型账户动态码显示",
            allowPasscodeFallback: true
        )
        showBoundCodes = true
        UserDefaults.standard.set(true, forKey: Self.showBoundCodesKey)
        refreshCodes()
        showToast("已开启，扫码型账户将显示动态码")
    }

    /// 关闭后立即隐藏并清空所有扫码型账户的动态码。
    func disableBoundCodes() {
        guard showBoundCodes else { return }
        showBoundCodes = false
        UserDefaults.standard.set(false, forKey: Self.showBoundCodesKey)
        refreshCodes()
        showToast("已关闭并清除扫码型账户动态码")
    }

    // MARK: - 编辑与删除

    func rename(accountID: String, note: String) throws {
        try client.renameAccount(id: accountID, displayName: note)
        reload()
        showToast("备注已保存")
    }

    func delete(accountID: String) throws {
        try client.deleteAccount(id: accountID)
        reload()
        showToast("账户已从本机移除")
    }

    func clearAllAccounts() throws {
        try client.clearAllAccounts()
        reload()
        showToast("已清空本机账户")
    }

    // MARK: - 时间偏差

    func refreshDrift() async {
        guard !isRefreshingDrift else { return }
        isRefreshingDrift = true
        defer { isRefreshingDrift = false }

        guard let target = accounts.first(where: { $0.kind == .bound && $0.isConfirmed }) else {
            serverDrift = nil
            driftAccountTitle = nil
            return
        }
        driftAccountTitle = target.title
        if let serverNow = await client.serverDate(for: target.id) {
            serverDrift = serverNow.timeIntervalSinceNow
        } else {
            serverDrift = nil
        }
    }

    var driftDescription: String? {
        guard let serverDrift else { return nil }
        let seconds = Int(serverDrift.rounded())
        if abs(seconds) < 2 {
            return "设备时间与服务器一致"
        }
        if seconds > 0 {
            return "设备时间比服务器慢约 \(abs(seconds)) 秒"
        }
        return "设备时间比服务器快约 \(abs(seconds)) 秒"
    }

    // MARK: - 复制与提示

    func copyCode(_ value: String) {
        ClipboardService.copy(value)
        showToast("动态码已复制，60 秒后自动清除剪贴板")
    }

    @discardableResult
    func copyText(_ value: String, message: String = "已复制") -> Bool {
        ClipboardService.copy(value)
        showToast(message)
        return true
    }

    func present(_ error: Error) {
        alertMessage = message(for: error)
    }

    func message(for error: Error) -> String {
        if let sdkError = error as? TotpScanError {
            let title = sdkError.errorDescription ?? "操作失败"
            if let reason = sdkError.failureReason, !reason.isEmpty {
                return "\(title)\n\(reason)"
            }
            return title
        }
        if let authError = error as? DeviceAuthError {
            return authError.errorDescription ?? "身份验证失败"
        }
        if let otpError = error as? OTPAuthURIError {
            return otpError.errorDescription ?? "链接格式不正确"
        }
        if let totpError = error as? TotpError {
            return totpError.errorDescription ?? "动态码参数不正确"
        }
        return error.localizedDescription
    }

    func showToast(_ message: String) {
        toastMessage = message
        toastWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.toastMessage = nil
        }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: workItem)
    }

    // MARK: - 内部

    private func startTicker() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCodes()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
