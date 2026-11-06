import Foundation

/// Keychain 中保存的完整账户记录。`secret` 只存在于安全存储与内存缓存中。
internal struct StoredAccount: Codable {
    var id: String
    var kind: AccountKind
    var issuer: String
    var account: String
    var displayName: String
    var algorithm: OtpAlgorithm
    var digits: Int
    var period: Int
    var secret: Data
    var source: AccountSource? = nil

    var bindingID: String?
    /// 绑定时的完整 submit URL（含 path 与 query），作为唯一提交目标原样保存。
    var pinnedSubmitURL: String?
    var boundAtEpochSeconds: Double?
    var isConfirmed: Bool
    var looseOriginPinning: Bool
    var lastConfirmedAtEpochSeconds: Double?

    // MARK: - 注册域名 / 提交路径

    /// 绑定载荷 `dom` 推导出的注册域名（eTLD+1），登录比对的第一道条件。
    var registrableDomain: String? = nil
    /// 绑定载荷 `path` 原样保存；提交时拼接到 `https://<dom>` 之后，登录匹配不使用它。
    var pinnedSubmitPath: String? = nil

    var parameters: TotpParameters {
        TotpParameters(uncheckedAlgorithm: algorithm, digits: digits, period: period)
    }

    var pinnedCanonicalURL: CanonicalURL? {
        guard let pinnedSubmitURL else { return nil }
        return try? CanonicalURL.parse(pinnedSubmitURL)
    }

    var summary: AccountSummary {
        AccountSummary(
            id: id,
            kind: kind,
            issuer: issuer,
            account: account,
            displayName: displayName,
            algorithm: algorithm,
            digits: digits,
            period: period,
            source: source ?? (kind == .bound ? .binding : .manual),
            pinnedSubmitURL: pinnedSubmitURL,
            bindingID: bindingID,
            boundAt: boundAtEpochSeconds.map { Date(timeIntervalSince1970: $0) },
            isConfirmed: isConfirmed,
            looseOriginPinning: looseOriginPinning,
            registrableDomain: registrableDomain,
            pinnedSubmitPath: pinnedSubmitPath
        )
    }

    func validated() throws -> StoredAccount {
        guard !id.isEmpty, !issuer.isEmpty, !account.isEmpty else {
            throw TotpScanError.keychainFailure("账户记录字段不完整")
        }
        guard !secret.isEmpty else {
            throw TotpScanError.keychainFailure("账户密钥缺失")
        }
        guard parameters.isValid else {
            throw TotpScanError.keychainFailure("账户 TOTP 参数损坏")
        }
        switch kind {
        case .standard:
            guard bindingID == nil, pinnedSubmitURL == nil,
                  registrableDomain == nil, pinnedSubmitPath == nil else {
                throw TotpScanError.keychainFailure("标准账户记录包含非法绑定字段")
            }
        case .bound:
            guard let bindingID, !bindingID.isEmpty,
                  let pinnedSubmitURL,
                  let canonical = try? CanonicalURL.parse(pinnedSubmitURL),
                  let registrableDomain, !registrableDomain.isEmpty,
                  registrableDomain == canonical.registrableDomain,
                  let pinnedSubmitPath,
                  pinnedSubmitPath.hasPrefix("/"),
                  !pinnedSubmitPath.contains("#") else {
                throw TotpScanError.keychainFailure("绑定账户记录损坏")
            }
            guard (digits == 6 || digits == 8), (period == 30 || period == 60) else {
                throw TotpScanError.keychainFailure("绑定账户参数不符合协议")
            }
        }
        return self
    }
}
