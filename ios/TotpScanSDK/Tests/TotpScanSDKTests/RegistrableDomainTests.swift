import XCTest
@testable import TotpScanSDK

final class RegistrableDomainTests: XCTestCase {
    func testCommonSuffixes() {
        XCTAssertEqual(RegistrableDomain.of(host: "dkn.example.com"), "example.com")
        XCTAssertEqual(RegistrableDomain.of(host: "login.example.com"), "example.com")
        XCTAssertEqual(RegistrableDomain.of(host: "a.b.co.uk"), "b.co.uk")
        XCTAssertEqual(RegistrableDomain.of(host: "www.example.com.cn"), "example.com.cn")
    }

    func testSingleLabelSuffix() {
        XCTAssertEqual(RegistrableDomain.of(host: "example.com"), "example.com")
        XCTAssertEqual(RegistrableDomain.of(host: "localhost"), "localhost")
        XCTAssertEqual(RegistrableDomain.of(host: "127.0.0.1"), "127.0.0.1")
    }

    func testSuffixOnlyHostIsItself() {
        XCTAssertEqual(RegistrableDomain.of(host: "com.cn"), "com.cn")
        XCTAssertEqual(RegistrableDomain.of(host: "com"), "com")
    }
}
