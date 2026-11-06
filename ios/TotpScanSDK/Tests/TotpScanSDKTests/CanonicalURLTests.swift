import XCTest
@testable import TotpScanSDK

final class CanonicalURLTests: XCTestCase {
    private func canonical(_ raw: String) throws -> String {
        try CanonicalURL.parse(raw).string
    }

    func testNormalization() throws {
        XCTAssertEqual(
            try canonical("HTTPS://Auth.Example.COM:443//totp//v1/./verify/../verify/"),
            "https://auth.example.com/totp/v1/verify"
        )
        XCTAssertEqual(
            try canonical("https://auth.example.com"),
            "https://auth.example.com/"
        )
    }

    func testQueryPreserved() throws {
        XCTAssertEqual(
            try canonical("https://dkn.example.com/dtm/ulr?ma=xxx"),
            "https://dkn.example.com/dtm/ulr?ma=xxx"
        )
        XCTAssertEqual(
            try CanonicalURL.parse("https://dkn.example.com/dtm/ulr?ma=xxx").pathWithQuery,
            "/dtm/ulr?ma=xxx"
        )
    }

    func testRegistrableDomainFromURL() throws {
        XCTAssertEqual(
            try CanonicalURL.parse("https://dkn.example.com/dtm/ulr?ma=xxx").registrableDomain,
            "example.com"
        )
    }

    func testIDNHostBecomesPunycode() throws {
        XCTAssertEqual(
            try canonical("https://例子.测试/path"),
            "https://xn--fsqu00a.xn--0zwm56d/path"
        )
    }

    func testInvalidAddressesRejected() {
        let invalid = [
            "",
            " https://example.com/a",
            "https://example.com/a ",
            "https://example.com/\u{0007}",
            "https://example.com/a\\b",
            "https://example.com/a#frag",
            "example.com/a",
            "ftp://example.com/a",
            "https://user@example.com/a",
            "http://example.com/a",
            "https://example.com:99999/a",
            "https:///a",
        ]
        for raw in invalid {
            XCTAssertThrowsError(try CanonicalURL.parse(raw), "应拒绝 \(raw)")
        }
    }
}
