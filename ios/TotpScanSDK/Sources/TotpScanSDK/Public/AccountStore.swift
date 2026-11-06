import Foundation
import Security

internal protocol AccountStoring {
    func loadAll() throws -> [StoredAccount]
    func save(_ record: StoredAccount) throws
    func delete(accountID: String) throws
    func deleteAll() throws
}

/// 基于 iOS Keychain 的账户安全存储。
///
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`：设备解锁后可读，不随 iCloud 钥匙串同步，不能迁移到新设备；
/// - 不写入 UserDefaults、文件、日志或剪贴板；
/// - 每个账户一个 generic password，`account` 为本地随机 ID，`service` 固定。
public final class AccountStore {
    public static let defaultService = "com.scanauth.totpscan.accounts"

    private let service: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(service: String = AccountStore.defaultService) {
        self.service = service
    }

    internal func loadAll() throws -> [StoredAccount] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw TotpScanError.keychainFailure(Self.message(for: status))
        }
        guard let rawItems = result as? [Any] else {
            throw TotpScanError.keychainFailure("安全存储返回了意外的数据类型")
        }

        var accounts: [StoredAccount] = []
        for item in rawItems {
            guard let data = item as? Data else {
                throw TotpScanError.keychainFailure("安全存储条目损坏")
            }
            do {
                let record = try decoder.decode(StoredAccount.self, from: data)
                accounts.append(try record.validated())
            } catch let error as TotpScanError {
                throw error
            } catch {
                throw TotpScanError.keychainFailure("账户数据无法解析")
            }
        }
        return accounts.sorted {
            if $0.kind != $1.kind {
                return $0.kind == .bound
            }
            return $0.issuer.localizedCompare($1.issuer) == .orderedAscending
        }
    }

    internal func save(_ record: StoredAccount) throws {
        let validated = try record.validated()
        let data: Data
        do {
            data = try encoder.encode(validated)
        } catch {
            throw TotpScanError.keychainFailure("账户数据无法序列化")
        }

        var query = baseQuery(accountID: validated.id)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            query[kSecAttrSynchronizable as String] = false
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TotpScanError.keychainFailure(Self.message(for: addStatus))
            }
        } else if updateStatus != errSecSuccess {
            throw TotpScanError.keychainFailure(Self.message(for: updateStatus))
        }
    }

    internal func delete(accountID: String) throws {
        let status = SecItemDelete(baseQuery(accountID: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TotpScanError.keychainFailure(Self.message(for: status))
        }
    }

    internal func deleteAll() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TotpScanError.keychainFailure(Self.message(for: status))
        }
    }

    private func baseQuery(accountID: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accountID {
            query[kSecAttrAccount as String] = accountID
        }
        return query
    }

    private static func message(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (\(status))"
        }
        return "OSStatus \(status)"
    }
}

extension AccountStore: AccountStoring {}
