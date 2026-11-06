import Foundation

/// 扫码增强型 TOTP 认证 SDK 的唯一入口。
///
/// 安全边界：
/// - 绑定二维码通过格式与字段一致性校验后才写入 Keychain；
/// - 登录二维码只提供域名与会话标识；提交目标永远来自 Keychain 中的 `https://<dom><path>`；
/// - 公开 API 不接受任意提交 URL；
/// - 不在日志中写入密钥、token 或动态码。
public final class TotpScanClient {
    /// 本地备注最大长度（规范 §4.1）。备注只存本地，不进入二维码、不上送服务器。
    public static let displayNameMaxLength = 64

    private let store: AccountStoring
    private let http = HTTPSubmitter()
    private let lock = NSRecursiveLock()

    private var cachedRecords: [StoredAccount]?
    private var cachedSecrets: [String: Data] = [:]

    public init(store: AccountStore = AccountStore()) {
        self.store = store
    }

    internal init(storeBacking: AccountStoring) {
        self.store = storeBacking
    }

    // MARK: - 账户读取

    /// 从 Keychain 重新加载全部账户摘要。不返回共享密钥。
    public func loadAccounts() throws -> [AccountSummary] {
        lock.lock()
        defer { lock.unlock() }
        let records = try reloadLocked()
        return records.map(\.summary)
    }

    /// 读取单个账户摘要。
    public func account(id: String) throws -> AccountSummary {
        try snapshotRecord(id).summary
    }

    /// 生成该账户的 `otpauth://totp/...` URI（仅内存拼接，不写日志、不落盘）。
    ///
    /// 返回值包含共享密钥，等同于密钥本身：
    /// - 调用方必须先完成本地身份验证，且只能用于屏幕展示；
    /// - 禁止复制到剪贴板、写入文件或发送到网络；
    /// - 扫码型账户同样支持导出，但调用方必须先行警告：导出后该账户的防钓鱼优势失效。
    public func otpauthURI(for accountID: String) throws -> String {
        let record = try snapshotRecord(accountID)
        return OTPAuthURI.build(
            issuer: record.issuer,
            account: record.account,
            secret: record.secret,
            parameters: record.parameters
        )
    }

    /// 计算标准 TOTP 账户当前动态码。
    ///
    /// 扫码型账户默认不通过该 API 暴露（规范 §13.4），只能经 `submit` 在地址比对命中后
    /// 由 SDK 内部计算并直接提交；用户显式开启显示开关后才可改用 `revealedCode(for:)`。
    public func code(for accountID: String, at date: Date = Date()) throws -> TotpCode {
        let record = try snapshotRecord(accountID)
        guard record.kind == .standard else {
            throw TotpScanError.boundAccountCodeNotAvailable
        }
        return TOTP.code(secret: record.secret, at: date, parameters: record.parameters)
    }

    /// 计算任意账户（含扫码型）的动态码。
    ///
    /// 仅供用户在 App 设置中**显式开启**「显示扫码型账户动态码」后调用：
    /// - 调用方必须先完成本地身份验证，并在界面上保持风险提示；
    /// - 默认的 `code(for:)` 仍然拒绝扫码型账户，二者语义不可混淆；
    /// - 扫码提交路径不受影响，提交仍由 `submit` 内部计算。
    public func revealedCode(for accountID: String, at date: Date = Date()) throws -> TotpCode {
        let record = try snapshotRecord(accountID)
        return TOTP.code(secret: record.secret, at: date, parameters: record.parameters)
    }

    // MARK: - 标准 TOTP 账户

    @discardableResult
    public func addStandardAccount(
        issuer: String,
        account: String,
        secretBase32: String,
        algorithm: OtpAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        displayName: String = "",
        source: AccountSource = .manual
    ) throws -> AccountSummary {
        let secret: Data
        do {
            secret = try Base32.decode(secretBase32)
        } catch {
            throw TotpScanError.invalidInput("密钥不是合法的 Base32")
        }
        guard !secret.isEmpty else {
            throw TotpScanError.invalidInput("密钥不能为空")
        }
        let parameters = try TotpParameters(algorithm: algorithm, digits: digits, period: period)
        return try addStandardAccount(
            issuer: issuer,
            account: account,
            secret: secret,
            parameters: parameters,
            displayName: displayName,
            source: source
        )
    }

    @discardableResult
    public func addStandardAccount(fromOTPAuthURI uri: String) throws -> AccountSummary {
        let parsed = try OTPAuthURI.parse(uri)
        return try addStandardAccount(
            issuer: parsed.issuer,
            account: parsed.account,
            secret: parsed.secret,
            parameters: parsed.parameters,
            displayName: "",
            source: .uri
        )
    }

    // MARK: - 绑定流程

    /// 解析绑定二维码。成功只返回待确认信息，不写入任何数据。
    /// 协议不携带签名，`dom` / `path` 由 SDK 做格式与一致性校验。
    public func previewBinding(qrText: String, now: Date = Date()) throws -> BindingPreview {
        let decoded = try BindingQRCode.parse(qrText, now: now)
        SDKLog.record(SDKLog.bindingVerified)
        return BindingPreview(
            issuer: decoded.issuer,
            account: decoded.account,
            bindingID: decoded.bindingID,
            submitURL: decoded.submitURL,
            algorithm: decoded.algorithm,
            digits: decoded.digits,
            period: decoded.period,
            expiresAt: decoded.expiresAt,
            isLooseOrigin: decoded.isLooseOrigin,
            registrableDomain: decoded.registrableDomain,
            submitPath: decoded.submitPath,
            secret: decoded.secret,
            issuedAt: decoded.issuedAt
        )
    }

    /// 用户确认提交地址后，把密钥、完整提交地址、注册域名与提交路径写入 Keychain。
    @discardableResult
    public func commitBinding(
        _ preview: BindingPreview,
        displayName: String = "",
        now: Date = Date()
    ) throws -> AccountSummary {
        guard let canonical = try? CanonicalURL.parse(preview.submitURL),
              canonical.registrableDomain == preview.registrableDomain else {
            throw TotpScanError.invalidQRCode("提交地址已被篡改")
        }
        guard preview.submitPath.hasPrefix("/"),
              !preview.submitPath.contains("#"),
              let pathOnly = try? CanonicalURL.parse("https://binding.invalid\(preview.submitPath)"),
              pathOnly.pathWithQuery == canonical.pathWithQuery else {
            throw TotpScanError.invalidQRCode("绑定路径不合法")
        }
        guard !preview.secret.isEmpty else {
            throw TotpScanError.invalidQRCode("绑定密钥为空")
        }

        let existing = try snapshotRecords()
        guard !existing.contains(where: { $0.bindingID == preview.bindingID }) else {
            throw TotpScanError.duplicateBinding
        }

        let record = StoredAccount(
            id: UUID().uuidString.lowercased(),
            kind: .bound,
            issuer: preview.issuer,
            account: preview.account,
            displayName: Self.sanitizedDisplayName(displayName, fallback: ""),
            algorithm: preview.algorithm,
            digits: preview.digits,
            period: preview.period,
            secret: preview.secret,
            source: .binding,
            bindingID: preview.bindingID,
            pinnedSubmitURL: preview.submitURL,
            boundAtEpochSeconds: now.timeIntervalSince1970,
            isConfirmed: false,
            looseOriginPinning: preview.submitPath == "/",
            lastConfirmedAtEpochSeconds: nil,
            registrableDomain: preview.registrableDomain,
            pinnedSubmitPath: preview.submitPath
        )
        try persist(record)
        SDKLog.record(SDKLog.bindingStored)
        return record.summary
    }

    /// 用本地密钥计算动态码，调用固化地址的绑定确认端点。
    @discardableResult
    public func confirmBinding(accountID: String, now: Date = Date()) async throws -> AccountSummary {
        let record = try snapshotRecord(accountID)
        guard record.kind == .bound else { throw TotpScanError.accountNotBound }
        if record.isConfirmed { return record.summary }
        guard let endpoint = PinnedEndpoint(rawURL: record.pinnedSubmitURL ?? "") else {
            throw TotpScanError.invalidQRCode("固化地址不可用")
        }

        let code = TOTP.generate(secret: record.secret, at: now, parameters: record.parameters)
        let outcome: SubmitOutcome
        do {
            outcome = try await http.confirmBinding(
                bindingID: record.bindingID ?? "",
                code: code,
                endpoint: endpoint
            )
        } catch TotpScanError.serverRejected {
            SDKLog.record(SDKLog.bindingConfirmFailed)
            throw TotpScanError.bindingConfirmationFailed
        } catch {
            SDKLog.record(SDKLog.bindingConfirmFailed)
            throw error
        }
        guard outcome.accepted else {
            SDKLog.record(SDKLog.bindingConfirmFailed)
            throw TotpScanError.bindingConfirmationFailed
        }

        var updated = record
        updated.isConfirmed = true
        updated.lastConfirmedAtEpochSeconds = now.timeIntervalSince1970
        try persist(updated)
        SDKLog.record(SDKLog.bindingConfirmed)
        return updated.summary
    }

    // MARK: - 登录流程

    /// 解析登录二维码，并按注册域名与已绑定账户比对。
    ///
    /// - 二维码只提供域名（`url`）与会话标识（`token`），不提供路径；
    /// - 用登录域名与绑定时的 `dom` 各自推导注册域名（eTLD+1），相等才算命中；
    /// - 只在同一注册域名内列出候选，不跨不同 dom 混列；
    /// - 提交目标固定为绑定时的完整 `https://<dom><path>`，不使用二维码中的 host。
    ///
    /// 该方法**不会**计算动态码，也不会发起任何网络请求。
    public func prepareLogin(
        qrText: String,
        preferredAccountID: String? = nil,
        now: Date = Date()
    ) throws -> LoginApproval {
        let decoded = try LoginQRCode.parse(qrText, now: now)

        // A2：只按注册域名筛；路径只使用绑定时保存的 path，登录二维码不提供路径。
        var candidates: [StoredAccount] = []
        for record in try snapshotRecords() {
            guard record.kind == .bound, record.isConfirmed,
                  record.registrableDomain == decoded.registrableDomain else {
                continue
            }
            candidates.append(record)
        }

        guard !candidates.isEmpty else {
            SDKLog.record(SDKLog.loginMismatch)
            throw TotpScanError.noMatchingAccount
        }

        // A3：同一账户存在多条绑定记录时，只保留最近确认的一条。
        // 候选之间即使固化地址不同也允许共存，但每个候选始终使用自己的固化地址。
        var latestByAccount: [String: StoredAccount] = [:]
        for record in candidates {
            let key = "\(record.issuer)\u{0}\(record.account)"
            if let existing = latestByAccount[key] {
                let existingTime = existing.lastConfirmedAtEpochSeconds ?? existing.boundAtEpochSeconds ?? 0
                let recordTime = record.lastConfirmedAtEpochSeconds ?? record.boundAtEpochSeconds ?? 0
                if recordTime > existingTime {
                    latestByAccount[key] = record
                }
            } else {
                latestByAccount[key] = record
            }
        }
        var matches = Array(latestByAccount.values)
        matches.sort { $0.issuer.localizedCompare($1.issuer) == .orderedAscending }

        if let preferredAccountID {
            matches = matches.filter { $0.id == preferredAccountID }
        }

        guard !matches.isEmpty else {
            SDKLog.record(SDKLog.loginMismatch)
            throw TotpScanError.noMatchingAccount
        }
        if matches.count > 1 {
            throw TotpScanError.multipleMatchingAccounts(matches.map(\.summary))
        }

        let record = matches[0]
        guard let submitURL = record.pinnedSubmitURL,
              let domain = record.registrableDomain else {
            throw TotpScanError.noMatchingAccount
        }
        SDKLog.record(SDKLog.loginMatched)
        return LoginApproval(
            accountID: record.id,
            issuer: record.issuer,
            account: record.account,
            submitURL: submitURL,
            expiresAt: decoded.expiresAt,
            isLooseOrigin: record.pinnedSubmitPath == "/",
            registrableDomain: domain,
            token: decoded.token
        )
    }

    /// 提交动态码。目标地址在提交前从 Keychain 重新读取，`LoginApproval` 中的地址仅用于展示。
    @discardableResult
    public func submit(_ approval: LoginApproval, now: Date = Date()) async throws -> SubmitOutcome {
        guard now <= approval.expiresAt else {
            throw TotpScanError.expiredQRCode
        }
        let record = try snapshotRecord(approval.accountID)
        guard record.kind == .bound else { throw TotpScanError.accountNotBound }
        guard record.isConfirmed else { throw TotpScanError.accountNotConfirmed }
        // 提交前再次核对注册域名，防止账户在扫码后被替换。
        guard record.registrableDomain == approval.registrableDomain else {
            throw TotpScanError.noMatchingAccount
        }
        // 提交目标只使用绑定时的 https://<dom><path>，绝不使用登录二维码里的域名组装路径。
        guard let endpoint = PinnedEndpoint(rawURL: record.pinnedSubmitURL ?? "") else {
            throw TotpScanError.invalidQRCode("固化地址不可用")
        }

        let code = TOTP.generate(secret: record.secret, at: now, parameters: record.parameters)
        let outcome = try await http.submit(
            token: approval.token,
            code: code,
            endpoint: endpoint
        )
        SDKLog.record(SDKLog.submitFinished(status: outcome.httpStatus))
        guard outcome.accepted else {
            throw TotpScanError.serverRejected
        }
        return outcome
    }

    // MARK: - 解绑与服务器端撤销

    /// 仅删除本机账户与密钥，不调用服务端接口。
    public func deleteAccount(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try store.delete(accountID: id)
        cachedRecords?.removeAll(where: { $0.id == id })
        cachedSecrets[id] = nil
        SDKLog.record(SDKLog.accountDeleted)
    }

    /// 管理员工具可使用：撤销服务端绑定（§S12）。App 普通用户流程不保存管理员令牌。
    @discardableResult
    public func revokeBindingOnServer(
        accountID: String,
        adminToken: String
    ) async throws -> SubmitOutcome {
        guard !adminToken.isEmpty else { throw TotpScanError.adminAuthorizationFailed }
        let record = try snapshotRecord(accountID)
        guard record.kind == .bound, let bindingID = record.bindingID,
              let endpoint = PinnedEndpoint(rawURL: record.pinnedSubmitURL ?? "") else {
            throw TotpScanError.accountNotBound
        }
        do {
            return try await http.revokeBinding(
                bindingID: bindingID,
                adminToken: adminToken,
                endpoint: endpoint
            )
        } catch TotpScanError.serverRejected {
            throw TotpScanError.adminAuthorizationFailed
        }
    }

    /// 修改本地备注。传空字符串表示清空；备注不参与任何安全判定。
    public func renameAccount(id: String, displayName: String) throws {
        var record = try snapshotRecord(id)
        record.displayName = Self.sanitizedDisplayName(displayName, fallback: "")
        try persist(record)
    }

    public func clearAllAccounts() throws {
        lock.lock()
        defer { lock.unlock() }
        try store.deleteAll()
        cachedRecords = []
        cachedSecrets.removeAll()
    }

    /// 读取服务端时间（仅 HEAD `/healthz`，不携带凭据），用于判断设备时钟偏差。
    public func serverDate(for accountID: String) async -> Date? {
        guard let record = try? snapshotRecord(accountID),
              let endpoint = PinnedEndpoint(rawURL: record.pinnedSubmitURL ?? "") else {
            return nil
        }
        return await http.serverDate(endpoint: endpoint)
    }

    private func addStandardAccount(
        issuer: String,
        account: String,
        secret: Data,
        parameters: TotpParameters,
        displayName: String,
        source: AccountSource
    ) throws -> AccountSummary {
        let cleanIssuer = Self.sanitizedField(issuer, maxLength: 64, fallback: "未命名签发方")
        let cleanAccount = Self.sanitizedField(account, maxLength: 255, fallback: "未命名账户")
        let record = StoredAccount(
            id: UUID().uuidString.lowercased(),
            kind: .standard,
            issuer: cleanIssuer,
            account: cleanAccount,
            displayName: Self.sanitizedDisplayName(displayName, fallback: ""),
            algorithm: parameters.algorithm,
            digits: parameters.digits,
            period: parameters.period,
            secret: secret,
            source: source,
            bindingID: nil,
            pinnedSubmitURL: nil,
            boundAtEpochSeconds: nil,
            isConfirmed: false,
            looseOriginPinning: false,
            lastConfirmedAtEpochSeconds: nil
        )
        try persist(record)
        return record.summary
    }

    private func snapshotRecords() throws -> [StoredAccount] {
        lock.lock()
        defer { lock.unlock() }
        if let cachedRecords {
            return cachedRecords
        }
        return try reloadLocked()
    }

    private func snapshotRecord(_ id: String) throws -> StoredAccount {
        let records = try snapshotRecords()
        guard let record = records.first(where: { $0.id == id }) else {
            throw TotpScanError.accountNotFound
        }
        return record
    }

    private func reloadLocked() throws -> [StoredAccount] {
        let records = try store.loadAll()
        cachedRecords = records
        cachedSecrets = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.secret) })
        return records
    }

    private func persist(_ record: StoredAccount) throws {
        lock.lock()
        defer { lock.unlock() }
        try persistLocked(record)
    }

    private func persistLocked(_ record: StoredAccount) throws {
        try store.save(record)
        var records = cachedRecords ?? []
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        cachedRecords = records
        cachedSecrets[record.id] = record.secret
    }

    private static func sanitizedField(_ value: String, maxLength: Int, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(maxLength))
    }

    /// 本地备注规范化（规范 §4.1）：NFC、禁止换行与 C0 控制字符、≤64 字符。
    /// 备注非法时不连带拒绝绑定，只丢弃非法字符。
    private static func sanitizedDisplayName(_ value: String, fallback: String) -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
        let cleaned = String(normalized.unicodeScalars.compactMap { scalar in
            scalar.value < 0x20 || scalar.value == 0x7F ? nil : Character(scalar)
        })
        return sanitizedField(cleaned, maxLength: displayNameMaxLength, fallback: fallback)
    }
}
