import XCTest
@testable import TotpScanSDK

final class OTPAuthURITests: XCTestCase {
    func testParsesFullURI() throws {
        let uri = "otpauth://totp/Example%20Corp:alice%40example.com?secret=JBSWY3DPEHPK3PXPJBSWY3DP&issuer=Example%20Corp&algorithm=SHA256&digits=8&period=60"
        let parsed = try OTPAuthURI.parse(uri)
        XCTAssertEqual(parsed.issuer, "Example Corp")
        XCTAssertEqual(parsed.account, "alice@example.com")
        XCTAssertEqual(parsed.parameters.algorithm, .sha256)
        XCTAssertEqual(parsed.parameters.digits, 8)
        XCTAssertEqual(parsed.parameters.period, 60)
        XCTAssertEqual(parsed.secret.count, 16)
        XCTAssertFalse(parsed.isWeakSecret)
    }

    func testDefaults() throws {
        let parsed = try OTPAuthURI.parse("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP")
        XCTAssertEqual(parsed.issuer, "")
        XCTAssertEqual(parsed.account, "alice")
        XCTAssertEqual(parsed.parameters, TotpParameters.standard)
        XCTAssertTrue(parsed.isWeakSecret)
    }

    func testCaseInsensitiveSchemeTypeAndAlgorithm() throws {
        let parsed = try OTPAuthURI.parse(
            "OTPAUTH://TOTP/alice?SECRET=JBSWY3DPEHPK3PXPJBSWY3DP&ALGORITHM=sha512"
        )
        XCTAssertEqual(parsed.parameters.algorithm, .sha512)
    }

    func testRejectsHOTP() {
        XCTAssertThrowsError(try OTPAuthURI.parse("otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP&counter=1"))
    }

    func testRejectsDuplicateParameters() {
        let uri = "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&secret=JBSWY3DPEHPK3PXP"
        XCTAssertThrowsError(try OTPAuthURI.parse(uri))
    }

    func testRejectsCounterParameter() {
        let uri = "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&counter=1"
        XCTAssertThrowsError(try OTPAuthURI.parse(uri))
    }

    func testRejectsIssuerConflict() {
        let uri = "otpauth://totp/Example%20Corp:alice?secret=JBSWY3DPEHPK3PXP&issuer=Other%20Corp"
        XCTAssertThrowsError(try OTPAuthURI.parse(uri))
    }

    func testAcceptsMatchingIssuer() throws {
        let uri = "otpauth://totp/Example%20Corp:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example%20Corp"
        let parsed = try OTPAuthURI.parse(uri)
        XCTAssertEqual(parsed.issuer, "Example Corp")
    }

    func testRejectsInvalidSecret() {
        XCTAssertThrowsError(try OTPAuthURI.parse("otpauth://totp/alice?secret=JBSWY3DP1"))
        XCTAssertThrowsError(try OTPAuthURI.parse("otpauth://totp/alice?secret=JBSWY3DP"))
        XCTAssertThrowsError(try OTPAuthURI.parse("otpauth://totp/alice"))
    }

    func testRejectsUnsupportedDigitsAndPeriod() {
        XCTAssertThrowsError(try OTPAuthURI.parse(
            "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&digits=7"
        ))
        XCTAssertThrowsError(try OTPAuthURI.parse(
            "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&period=0"
        ))
        XCTAssertThrowsError(try OTPAuthURI.parse(
            "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&period=3601"
        ))
    }

    func testExplicitDefaultPort() throws {
        let parsed = try OTPAuthURI.parse(
            "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&digits=6&period=45&algorithm=SHA1"
        )
        XCTAssertEqual(parsed.parameters.digits, 6)
        XCTAssertEqual(parsed.parameters.period, 45)
    }

    func testBuildRoundTrip() throws {
        let secret = try Base32.decode("JBSWY3DPEHPK3PXPJBSWY3DP")
        let parameters = try TotpParameters(algorithm: .sha256, digits: 8, period: 90)
        let uri = OTPAuthURI.build(
            issuer: "Example Corp",
            account: "alice@example.com",
            secret: secret,
            parameters: parameters
        )
        let parsed = try OTPAuthURI.parse(uri)
        XCTAssertEqual(parsed.issuer, "Example Corp")
        XCTAssertEqual(parsed.account, "alice@example.com")
        XCTAssertEqual(parsed.secret, secret)
        XCTAssertEqual(parsed.parameters, parameters)
    }
}
