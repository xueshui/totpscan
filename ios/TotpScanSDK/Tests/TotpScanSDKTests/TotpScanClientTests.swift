import XCTest
@testable import TotpScanSDK

final class TotpScanClientTests: XCTestCase {
    private let now = TestSupport.date(1_700_000_000)
    private let sessionToken = String(repeating: "a", count: 16)

    private func makeClient(store: MemoryAccountStore = MemoryAccountStore()) -> TotpScanClient {
        TotpScanClient(storeBacking: store)
    }

    private func loginQR(
        domain: String = "auth.example.com",
        expiresIn: Int = 30
    ) throws -> String {
        let value: [String: Any] = [
            "t": "totp-login",
            "v": 1,
            "url": domain,
            "token": sessionToken,
            "exp": Int(now.timeIntervalSince1970) + expiresIn,
        ]
        return try TestSupport.jsonString(value)
    }

    // MARK: - 账户类型边界

    func testStandardAccountExposesCode() throws {
        let client = makeClient()
        let summary = try client.addStandardAccount(
            issuer: "Example",
            account: "alice@example.com",
            secretBase32: "JBSWY3DPEHPK3PXPJBSWY3DP"
        )
        XCTAssertEqual(summary.kind, .standard)
        XCTAssertEqual(summary.source, .manual)

        let code = try client.code(for: summary.id, at: now)
        XCTAssertEqual(code.value.count, 6)
        XCTAssertTrue(code.value.allSatisfy { $0.isNumber })
        XCTAssertEqual(code.period, 30)
    }

    func testBoundAccountCodeIsNeverExposed() throws {
        let store = MemoryAccountStore()
        store.records["bound-1"] = TestSupport.boundRecord(id: "bound-1")
        let client = makeClient(store: store)

        XCTAssertThrowsError(try client.code(for: "bound-1", at: now)) { error in
            guard case TotpScanError.boundAccountCodeNotAvailable = error else {
                return XCTFail("期望 boundAccountCodeNotAvailable，实际 \(error)")
            }
        }
    }

    func testOtpauthExportRoundTripsForStandardAccount() throws {
        let client = makeClient()
        let summary = try client.addStandardAccount(
            issuer: "Example",
            account: "alice@example.com",
            secretBase32: "JBSWY3DPEHPK3PXPJBSWY3DP",
            algorithm: .sha256,
            digits: 8,
            period: 60
        )

        let uri = try client.otpauthURI(for: summary.id)
        XCTAssertTrue(uri.hasPrefix("otpauth://totp/"))

        let parsed = try OTPAuthURI.parse(uri)
        let expectedParameters = try TotpParameters(algorithm: .sha256, digits: 8, period: 60)
        XCTAssertEqual(parsed.issuer, "Example")
        XCTAssertEqual(parsed.account, "alice@example.com")
        XCTAssertEqual(parsed.parameters, expectedParameters)
        XCTAssertEqual(try Base32.decode("JBSWY3DPEHPK3PXPJBSWY3DP"), parsed.secret)
    }

    func testOtpauthExportWorksForBoundAccount() throws {
        let store = MemoryAccountStore()
        store.records["bound-1"] = TestSupport.boundRecord(id: "bound-1")
        let client = makeClient(store: store)

        let uri = try client.otpauthURI(for: "bound-1")
        let parsed = try OTPAuthURI.parse(uri)
        XCTAssertEqual(parsed.issuer, "Example Corp")
        XCTAssertEqual(parsed.account, "alice@example.com")
        XCTAssertEqual(parsed.secret, try Base32.decode("JBSWY3DPEHPK3PXPJBSWY3DP"))
    }

    func testRevealedCodeIsOptInButDefaultAPIRemainsClosed() throws {
        let store = MemoryAccountStore()
        store.records["bound-1"] = TestSupport.boundRecord(id: "bound-1")
        let client = makeClient(store: store)

        XCTAssertThrowsError(try client.code(for: "bound-1", at: now))

        let revealed = try client.revealedCode(for: "bound-1", at: now)
        let parameters = try TotpParameters(algorithm: .sha1, digits: 6, period: 30)
        let expected = TOTP.code(
            secret: try Base32.decode("JBSWY3DPEHPK3PXPJBSWY3DP"),
            at: now,
            parameters: parameters
        )
        XCTAssertEqual(revealed, expected)
    }

    func testStandardAccountNeverBecomesScanCandidate() throws {
        let client = makeClient()
        _ = try client.addStandardAccount(
            issuer: "Example",
            account: "alice@example.com",
            secretBase32: "JBSWY3DPEHPK3PXPJBSWY3DP"
        )

        XCTAssertThrowsError(try client.prepareLogin(qrText: try loginQR(), now: now)) { error in
            guard case TotpScanError.noMatchingAccount = error else {
                return XCTFail("期望 noMatchingAccount，实际 \(error)")
            }
        }
    }

    func testUnconfirmedBindingNeverBecomesScanCandidate() throws {
        let store = MemoryAccountStore()
        store.records["pending"] = TestSupport.boundRecord(id: "pending", confirmed: false)
        let client = makeClient(store: store)

        XCTAssertThrowsError(try client.prepareLogin(qrText: try loginQR(), now: now)) { error in
            guard case TotpScanError.noMatchingAccount = error else {
                return XCTFail("期望 noMatchingAccount，实际 \(error)")
            }
        }
    }

    // MARK: - 候选反查（按注册域名）

    func testZeroCandidatesTerminatesLocally() {
        let client = makeClient()
        XCTAssertThrowsError(try client.prepareLogin(qrText: try loginQR(), now: now)) { error in
            guard case TotpScanError.noMatchingAccount = error else {
                return XCTFail("期望 noMatchingAccount，实际 \(error)")
            }
        }
    }

    func testSingleCandidateIsSelectedAutomatically() throws {
        let store = MemoryAccountStore()
        store.records["alice"] = TestSupport.boundRecord(id: "alice")
        let client = makeClient(store: store)

        let approval = try client.prepareLogin(qrText: try loginQR(), now: now)
        XCTAssertEqual(approval.accountID, "alice")
        XCTAssertEqual(approval.registrableDomain, "example.com")
        XCTAssertEqual(approval.submitURL, "https://auth.example.com/totp/v1/verify")
    }

    func testMultipleCandidatesOnlyWithinSameDomain() throws {
        let store = MemoryAccountStore()
        store.records["alice"] = TestSupport.boundRecord(
            id: "alice",
            account: "alice@example.com"
        )
        store.records["bob"] = TestSupport.boundRecord(
            id: "bob",
            account: "bob@example.com"
        )
        let client = makeClient(store: store)

        XCTAssertThrowsError(try client.prepareLogin(qrText: try loginQR(), now: now)) { error in
            guard case TotpScanError.multipleMatchingAccounts(let accounts) = error else {
                return XCTFail("期望 multipleMatchingAccounts，实际 \(error)")
            }
            XCTAssertEqual(Set(accounts.map(\.id)), ["alice", "bob"])
            XCTAssertTrue(accounts.allSatisfy { $0.pinnedSubmitURL == "https://auth.example.com/totp/v1/verify" })
        }
    }

    func testDifferentPinnedAddressesKeepTheirOwnTarget() throws {
        let store = MemoryAccountStore()
        store.records["base"] = TestSupport.boundRecord(
            id: "base",
            account: "base@example.com",
            pinned: "https://auth.example.com/totp/v1",
            path: "/totp/v1"
        )
        store.records["exact"] = TestSupport.boundRecord(
            id: "exact",
            account: "exact@example.com",
            pinned: "https://auth.example.com/totp/v1/verify"
        )
        let client = makeClient(store: store)

        XCTAssertThrowsError(try client.prepareLogin(qrText: try loginQR(), now: now)) { error in
            guard case TotpScanError.multipleMatchingAccounts(let accounts) = error else {
                return XCTFail("期望 multipleMatchingAccounts，实际 \(error)")
            }
            XCTAssertEqual(Set(accounts.map(\.id)), ["base", "exact"])

            let byID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
            XCTAssertEqual(byID["base"]?.pinnedSubmitURL, "https://auth.example.com/totp/v1")
            XCTAssertEqual(byID["exact"]?.pinnedSubmitURL, "https://auth.example.com/totp/v1/verify")
        }
    }

    func testDuplicateBindingsCollapseToLatestConfirmed() throws {
        let store = MemoryAccountStore()
        store.records["old"] = TestSupport.boundRecord(
            id: "old",
            lastConfirmed: 1_600_000_000
        )
        store.records["new"] = TestSupport.boundRecord(
            id: "new",
            lastConfirmed: 1_650_000_000
        )
        let client = makeClient(store: store)

        let approval = try client.prepareLogin(qrText: try loginQR(), now: now)
        XCTAssertEqual(approval.accountID, "new")
    }

    func testPreferredAccountNarrowsAmbiguousCandidates() throws {
        let store = MemoryAccountStore()
        store.records["alice"] = TestSupport.boundRecord(id: "alice", account: "alice@example.com")
        store.records["bob"] = TestSupport.boundRecord(id: "bob", account: "bob@example.com")
        let client = makeClient(store: store)

        let approval = try client.prepareLogin(
            qrText: try loginQR(),
            preferredAccountID: "bob",
            now: now
        )
        XCTAssertEqual(approval.accountID, "bob")
    }

    func testPreferredAccountOutsideCandidatesIsRejected() throws {
        let store = MemoryAccountStore()
        store.records["alice"] = TestSupport.boundRecord(id: "alice")
        store.records["other"] = TestSupport.boundRecord(
            id: "other",
            account: "other@example.com",
            pinned: "https://other.example.org/totp/v1/verify"
        )
        let client = makeClient(store: store)

        XCTAssertThrowsError(
            try client.prepareLogin(qrText: try loginQR(), preferredAccountID: "other", now: now)
        ) { error in
            guard case TotpScanError.noMatchingAccount = error else {
                return XCTFail("期望 noMatchingAccount，实际 \(error)")
            }
        }
    }

    // MARK: - 注册域名比对与绑定路径

    func testLoginMatchesByRegistrableDomain() throws {
        let store = MemoryAccountStore()
        store.records["alice"] = TestSupport.boundRecord(
            id: "alice",
            pinned: "https://dkn.example.com/dtm/ulr?ma=xxx",
            path: "/dtm/ulr?ma=xxx"
        )
        let client = makeClient(store: store)

        let approval = try client.prepareLogin(
            qrText: try loginQR(domain: "login.example.com"),
            now: now
        )
        XCTAssertEqual(approval.accountID, "alice")
        XCTAssertEqual(approval.registrableDomain, "example.com")
        // 提交目标固定为绑定时的完整地址，不使用登录二维码的 host。
        XCTAssertEqual(approval.submitURL, "https://dkn.example.com/dtm/ulr?ma=xxx")
    }

    func testLoginRejectsDifferentRegistrableDomain() throws {
        let store = MemoryAccountStore()
        store.records["alice"] = TestSupport.boundRecord(
            id: "alice",
            pinned: "https://dkn.example.com/dtm/ulr?ma=xxx",
            path: "/dtm/ulr?ma=xxx"
        )
        let client = makeClient(store: store)

        XCTAssertThrowsError(
            try client.prepareLogin(qrText: try loginQR(domain: "dkn.example.org"), now: now)
        ) { error in
            guard case TotpScanError.noMatchingAccount = error else {
                return XCTFail("期望 noMatchingAccount，实际 \(error)")
            }
        }
    }

    func testCandidatesDoNotMixDifferentDomains() throws {
        let store = MemoryAccountStore()
        store.records["alice"] = TestSupport.boundRecord(
            id: "alice",
            pinned: "https://dkn.example.com/dtm/ulr",
            path: "/dtm/ulr"
        )
        store.records["bob"] = TestSupport.boundRecord(
            id: "bob",
            account: "bob@example.com",
            pinned: "https://auth.example.com/dtm/ulr",
            path: "/dtm/ulr"
        )
        let client = makeClient(store: store)

        // 只应命中 example.com，不应把 example.com 的账户混入候选。
        let approval = try client.prepareLogin(
            qrText: try loginQR(domain: "login.example.com"),
            now: now
        )
        XCTAssertEqual(approval.accountID, "alice")
    }

    func testBindingPayloadRequiresDomAndPath() throws {
        let client = makeClient()

        var missingDom = TestSupport.bindingObject(secret: Data(repeating: 7, count: 20))
        missingDom.removeValue(forKey: "dom")
        XCTAssertThrowsError(
            try client.previewBinding(qrText: try TestSupport.jsonString(missingDom), now: now)
        )

        var missingPath = TestSupport.bindingObject(secret: Data(repeating: 7, count: 20))
        missingPath.removeValue(forKey: "path")
        XCTAssertThrowsError(
            try client.previewBinding(qrText: try TestSupport.jsonString(missingPath), now: now)
        )
    }

    // MARK: - 提交前复核

    func testSubmitRejectsExpiredApproval() async throws {
        let store = MemoryAccountStore()
        store.records["alice"] = TestSupport.boundRecord(id: "alice")
        let client = makeClient(store: store)

        let approval = try client.prepareLogin(qrText: try loginQR(), now: now)
        do {
            _ = try await client.submit(approval, now: approval.expiresAt.addingTimeInterval(1))
            XCTFail("过期后不应提交")
        } catch let error as TotpScanError {
            guard case .expiredQRCode = error else {
                return XCTFail("期望 expiredQRCode，实际 \(error)")
            }
        }
    }

    func testSubmitRejectsApprovalWhoseDomainNoLongerMatches() async throws {
        let store = MemoryAccountStore()
        store.records["alice"] = TestSupport.boundRecord(id: "alice")
        let client = makeClient(store: store)

        let approval = LoginApproval(
            accountID: "alice",
            issuer: "Example Corp",
            account: "alice@example.com",
            submitURL: "https://auth.example.com/totp/v1/verify",
            expiresAt: now.addingTimeInterval(30),
            isLooseOrigin: false,
            registrableDomain: "evil.example.org",
            token: sessionToken
        )

        do {
            _ = try await client.submit(approval, now: now)
            XCTFail("注册域名不一致时不应提交")
        } catch let error as TotpScanError {
            guard case .noMatchingAccount = error else {
                return XCTFail("期望 noMatchingAccount，实际 \(error)")
            }
        }
    }

    // MARK: - 绑定与备注

    func testCommitBindingStoresSanitizedNoteAndRejectsDuplicate() throws {
        let store = MemoryAccountStore()
        let client = makeClient(store: store)

        let object = TestSupport.bindingObject(secret: Data(repeating: 7, count: 20))
        let preview = try client.previewBinding(
            qrText: try TestSupport.jsonString(object),
            now: now
        )
        XCTAssertFalse(preview.submitURL.hasSuffix("/"))
        XCTAssertEqual(preview.bindingID, TestSupport.bindingID)
        XCTAssertEqual(preview.registrableDomain, "example.com")
        XCTAssertEqual(preview.submitPath, "/totp/v1/verify")

        let note = "我的登录账户\n" + String(repeating: "备", count: 80)
        let summary = try client.commitBinding(preview, displayName: note, now: now)
        XCTAssertEqual(summary.kind, .bound)
        XCTAssertFalse(summary.isConfirmed)
        XCTAssertEqual(summary.source, .binding)
        XCTAssertEqual(summary.displayName.count, TotpScanClient.displayNameMaxLength)
        XCTAssertFalse(summary.displayName.contains("\n"))
        XCTAssertTrue(summary.displayName.hasPrefix("我的登录账户"))
        XCTAssertEqual(summary.pinnedSubmitURL, preview.submitURL)
        XCTAssertEqual(summary.registrableDomain, "example.com")
        XCTAssertEqual(summary.pinnedSubmitPath, "/totp/v1/verify")

        XCTAssertThrowsError(try client.commitBinding(preview, displayName: "再次", now: now)) { error in
            guard case TotpScanError.duplicateBinding = error else {
                return XCTFail("期望 duplicateBinding，实际 \(error)")
            }
        }
        XCTAssertEqual(try client.loadAccounts().count, 1)
    }

    func testRenameCanClearNoteAndIsTruncated() throws {
        let client = makeClient()
        let summary = try client.addStandardAccount(
            issuer: "Example",
            account: "alice@example.com",
            secretBase32: "JBSWY3DPEHPK3PXPJBSWY3DP",
            displayName: "旧备注"
        )
        XCTAssertEqual(client.account(id: summary.id).title, "旧备注")

        try client.renameAccount(id: summary.id, displayName: "")
        let cleared = try client.account(id: summary.id)
        XCTAssertEqual(cleared.displayName, "")
        XCTAssertEqual(cleared.title, "alice@example.com")

        try client.renameAccount(
            id: summary.id,
            displayName: String(repeating: "长", count: 80)
        )
        XCTAssertEqual(
            try client.account(id: summary.id).displayName.count,
            TotpScanClient.displayNameMaxLength
        )
    }

    func testDeleteAccountRemovesRecord() throws {
        let client = makeClient()
        let summary = try client.addStandardAccount(
            issuer: "Example",
            account: "alice@example.com",
            secretBase32: "JBSWY3DPEHPK3PXPJBSWY3DP"
        )
        try client.deleteAccount(id: summary.id)
        XCTAssertTrue(try client.loadAccounts().isEmpty)
        XCTAssertThrowsError(try client.account(id: summary.id)) { error in
            guard case TotpScanError.accountNotFound = error else {
                return XCTFail("期望 accountNotFound，实际 \(error)")
            }
        }
    }

    func testStandardAccountFromOTPAuthURI() throws {
        let client = makeClient()
        let uri = "otpauth://totp/Example:alice@example.com"
            + "?secret=JBSWY3DPEHPK3PXPJBSWY3DP&issuer=Example&algorithm=SHA256&digits=8&period=60"
        let summary = try client.addStandardAccount(fromOTPAuthURI: uri)
        XCTAssertEqual(summary.issuer, "Example")
        XCTAssertEqual(summary.account, "alice@example.com")
        XCTAssertEqual(summary.source, .uri)
        XCTAssertEqual(summary.algorithm, .sha256)
        XCTAssertEqual(summary.digits, 8)
        XCTAssertEqual(summary.period, 60)

        let code = try client.code(for: summary.id, at: now)
        XCTAssertEqual(code.value.count, 8)
        XCTAssertEqual(code.period, 60)
    }
}
