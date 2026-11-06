import Foundation
import XCTest
@testable import TotpScanSDK

enum TestSupport {
    static let bindingID = "b_0123456789abcdefghijkl"

    static func bindingObject(
        issuer: String = "Example Corp",
        account: String = "alice@example.com",
        secret: Data,
        algorithm: String = "SHA1",
        digits: Int = 6,
        period: Int = 30,
        dom: String = "auth.example.com",
        path: String = "/totp/v1/verify",
        issuedAt: Int = 1_700_000_000,
        expiresAt: Int? = 1_800_000_000
    ) -> [String: Any] {
        var object: [String: Any] = [
            "t": "totp-bind",
            "v": 1,
            "bid": bindingID,
            "iss": issuer,
            "acc": account,
            "sec": Base32.encode(secret),
            "alg": algorithm,
            "dig": digits,
            "per": period,
            "dom": dom,
            "path": path,
            "iat": issuedAt,
        ]
        if let expiresAt {
            object["exp"] = expiresAt
        }
        return object
    }

    static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    static func boundRecord(
        id: String,
        issuer: String = "Example Corp",
        account: String = "alice@example.com",
        secretBase32: String = "JBSWY3DPEHPK3PXPJBSWY3DP",
        pinned: String = "https://auth.example.com/totp/v1/verify",
        bindingID: String = TestSupport.bindingID,
        domain: String? = nil,
        path: String? = nil,
        confirmed: Bool = true,
        lastConfirmed: TimeInterval? = 1_700_000_000
    ) -> StoredAccount {
        let canonical = try! CanonicalURL.parse(pinned)
        let resolvedPath = path ?? canonical.pathWithQuery
        return StoredAccount(
            id: id,
            kind: .bound,
            issuer: issuer,
            account: account,
            displayName: "",
            algorithm: .sha1,
            digits: 6,
            period: 30,
            secret: try! Base32.decode(secretBase32),
            bindingID: bindingID,
            pinnedSubmitURL: pinned,
            boundAtEpochSeconds: 1_699_000_000,
            isConfirmed: confirmed,
            looseOriginPinning: resolvedPath == "/",
            lastConfirmedAtEpochSeconds: lastConfirmed,
            registrableDomain: domain ?? canonical.registrableDomain,
            pinnedSubmitPath: resolvedPath
        )
    }
}

final class MemoryAccountStore: AccountStoring {
    var records: [String: StoredAccount] = [:]

    func loadAll() throws -> [StoredAccount] {
        Array(records.values)
    }

    func save(_ record: StoredAccount) throws {
        records[record.id] = record
    }

    func delete(accountID: String) throws {
        records[accountID] = nil
    }

    func deleteAll() throws {
        records.removeAll()
    }
}
