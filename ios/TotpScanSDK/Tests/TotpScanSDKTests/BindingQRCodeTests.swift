import XCTest
@testable import TotpScanSDK

final class BindingQRCodeTests: XCTestCase {
    private let secret = Data((0..<20).map { UInt8($0) })
    private let now = TestSupport.date(1_700_000_100)

    private func parse(_ object: [String: Any]) throws -> BindingQRCode {
        try BindingQRCode.parse(try TestSupport.jsonString(object), now: now)
    }

    func testValidPayload() throws {
        let decoded = try parse(TestSupport.bindingObject(secret: secret))

        XCTAssertEqual(decoded.bindingID, TestSupport.bindingID)
        XCTAssertEqual(decoded.issuer, "Example Corp")
        XCTAssertEqual(decoded.account, "alice@example.com")
        XCTAssertEqual(decoded.secret, secret)
        XCTAssertEqual(decoded.algorithm, .sha1)
        XCTAssertEqual(decoded.digits, 6)
        XCTAssertEqual(decoded.period, 30)
        XCTAssertEqual(decoded.submitURL, "https://auth.example.com/totp/v1/verify")
        XCTAssertEqual(decoded.registrableDomain, "example.com")
        XCTAssertEqual(decoded.submitPath, "/totp/v1/verify")
        XCTAssertFalse(decoded.isLooseOrigin)
    }

    func testBuildsSubmitURLFromDomAndPath() throws {
        let decoded = try parse(TestSupport.bindingObject(
            secret: secret,
            dom: "dkn.example.com",
            path: "/dtm/ulr?ma=xxx"
        ))
        XCTAssertEqual(decoded.submitURL, "https://dkn.example.com/dtm/ulr?ma=xxx")
        XCTAssertEqual(decoded.registrableDomain, "example.com")
        XCTAssertEqual(decoded.submitPath, "/dtm/ulr?ma=xxx")
    }

    func testDomMustBePlainDomain() throws {
        let withScheme = TestSupport.bindingObject(
            secret: secret,
            dom: "https://auth.example.com"
        )
        XCTAssertThrowsError(try parse(withScheme))

        let withPath = TestSupport.bindingObject(
            secret: secret,
            dom: "auth.example.com/totp"
        )
        XCTAssertThrowsError(try parse(withPath))
    }

    func testPathMustStartWithSlash() throws {
        let object = TestSupport.bindingObject(secret: secret, path: "totp/v1")
        XCTAssertThrowsError(try parse(object))
    }

    func testMissingDomOrPathRejected() throws {
        var noDom = TestSupport.bindingObject(secret: secret)
        noDom.removeValue(forKey: "dom")
        XCTAssertThrowsError(try parse(noDom))

        var noPath = TestSupport.bindingObject(secret: secret)
        noPath.removeValue(forKey: "path")
        XCTAssertThrowsError(try parse(noPath))
    }

    func testNormalizesSecretCase() throws {
        var object = TestSupport.bindingObject(secret: secret)
        object["sec"] = (object["sec"] as! String).lowercased()
        let decoded = try parse(object)
        XCTAssertEqual(decoded.secret, secret)
    }

    func testExpiredRejected() throws {
        let object = TestSupport.bindingObject(secret: secret, expiresAt: 1_700_000_000)
        XCTAssertThrowsError(try parse(object)) { error in
            guard case TotpScanError.expiredQRCode = error else {
                return XCTFail("期望 expiredQRCode，实际 \(error)")
            }
        }
    }

    func testWrongTypeAndVersionRejected() throws {
        var object = TestSupport.bindingObject(secret: secret)
        object["t"] = "totp-login"
        XCTAssertThrowsError(try parse(object))

        var versioned = TestSupport.bindingObject(secret: secret)
        versioned["v"] = 2
        XCTAssertThrowsError(try parse(versioned)) { error in
            guard case TotpScanError.unsupportedVersion = error else {
                return XCTFail("期望 unsupportedVersion，实际 \(error)")
            }
        }
    }

    func testInvalidParametersRejected() throws {
        let cases: [[String: Any]] = [
            TestSupport.bindingObject(secret: Data(repeating: 1, count: 15)),
            TestSupport.bindingObject(secret: Data(repeating: 1, count: 65)),
            TestSupport.bindingObject(secret: secret, digits: 7),
            TestSupport.bindingObject(secret: secret, period: 45),
            TestSupport.bindingObject(secret: secret, algorithm: "MD5"),
        ]
        for object in cases {
            XCTAssertThrowsError(try parse(object))
        }
    }

    func testUnknownFieldsIgnored() throws {
        var object = TestSupport.bindingObject(secret: secret)
        object["future_field"] = ["a": 1]
        let decoded = try parse(object)
        XCTAssertEqual(decoded.bindingID, TestSupport.bindingID)
    }

    func testLooseOriginFlag() throws {
        let decoded = try parse(TestSupport.bindingObject(
            secret: secret,
            dom: "auth.example.com",
            path: "/"
        ))
        XCTAssertEqual(decoded.submitURL, "https://auth.example.com/")
        XCTAssertEqual(decoded.submitPath, "/")
        XCTAssertTrue(decoded.isLooseOrigin)
    }
}
