import XCTest
@testable import TotpScanSDK

final class LoginQRCodeTests: XCTestCase {
    private let now = TestSupport.date(1_700_000_000)
    private let sessionToken = String(repeating: "a", count: 16)

    private func object(
        expiresIn: Int = 30,
        url: String = "auth.example.com",
        token: String? = nil
    ) -> [String: Any] {
        [
            "t": "totp-login",
            "v": 1,
            "url": url,
            "token": token ?? sessionToken,
            "exp": Int(now.timeIntervalSince1970) + expiresIn,
        ]
    }

    private func parse(_ object: [String: Any]) throws -> LoginQRCode {
        try LoginQRCode.parse(try TestSupport.jsonString(object), now: now)
    }

    func testValidPayload() throws {
        let decoded = try parse(object())
        XCTAssertEqual(decoded.loginDomain, "auth.example.com")
        XCTAssertEqual(decoded.registrableDomain, "example.com")
        XCTAssertEqual(decoded.token, sessionToken)
        XCTAssertEqual(decoded.expiresAt, now.addingTimeInterval(30))
    }

    func testTokenAcceptsSixteenOrTwentyFourCharacters() throws {
        XCTAssertNoThrow(try parse(object(token: String(repeating: "a", count: 16))))
        XCTAssertNoThrow(try parse(object(token: String(repeating: "A1_-", count: 6))))
    }

    func testInvalidTokenRejected() {
        for token in [
            String(repeating: "a", count: 15),
            String(repeating: "a", count: 17),
            String(repeating: "a", count: 43),
            String(repeating: "!", count: 16),
            "",
        ] {
            XCTAssertThrowsError(try parse(object(token: token)), "token=\(token)")
        }
    }

    func testExpiredRejected() {
        XCTAssertThrowsError(try parse(object(expiresIn: -1))) { error in
            guard case TotpScanError.expiredQRCode = error else {
                return XCTFail("期望 expiredQRCode，实际 \(error)")
            }
        }
    }

    func testLifetimeOverSixtySecondsRejected() {
        XCTAssertThrowsError(try parse(object(expiresIn: 61)))
    }

    func testBareDomainRequired() {
        for url in [
            "https://auth.example.com",
            "auth.example.com/totp/v1/verify",
            "auth.example.com?x=1",
            "auth.example.com#frag",
            "user@auth.example.com",
            "auth.example.com:8443",
            "",
        ] {
            XCTAssertThrowsError(try parse(object(url: url)), "url=\(url)")
        }
    }

    func testRegistrableDomainIsDerivedFromSubdomain() throws {
        let decoded = try parse(object(url: "dkn.example.com"))
        XCTAssertEqual(decoded.loginDomain, "dkn.example.com")
        XCTAssertEqual(decoded.registrableDomain, "example.com")
    }

    func testMissingRequiredFieldsRejected() throws {
        var missingURL = object()
        missingURL.removeValue(forKey: "url")
        XCTAssertThrowsError(try parse(missingURL))

        var missingToken = object()
        missingToken.removeValue(forKey: "token")
        XCTAssertThrowsError(try parse(missingToken))

        var missingExpiry = object()
        missingExpiry.removeValue(forKey: "exp")
        XCTAssertThrowsError(try parse(missingExpiry))
    }
}
