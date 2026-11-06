import XCTest
@testable import TotpScanSDK

final class Base32Tests: XCTestCase {
    func testKnownVector() throws {
        let data = try Base32.decode("JBSWY3DPEHPK3PXP")
        XCTAssertEqual(data, Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x21, 0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertEqual(Base32.encode(data), "JBSWY3DPEHPK3PXP")
    }

    func testLenientDecodingAllowsLowercaseSpacesAndPadding() throws {
        let expected = try Base32.decode("JBSWY3DPEHPK3PXP")
        XCTAssertEqual(try Base32.decode("jbsw y3dp ehpk 3pxp===="), expected)
    }

    func testCanonicalDecodingRejectsLowercaseWhitespaceAndPadding() {
        XCTAssertThrowsError(try Base32.decodeCanonical("JBSWY3DPEHPK3PXP"))
        XCTAssertThrowsError(try Base32.decodeCanonical("jbswy3dpehpk3pxp"))
        XCTAssertThrowsError(try Base32.decodeCanonical("JBSW Y3DP"))
        XCTAssertThrowsError(try Base32.decodeCanonical("JBSWY3DP===="))
        XCTAssertThrowsError(try Base32.decodeCanonical("JBSWY3DP1"))
    }

    func testRoundTripRandomData() throws {
        var generator = SystemRandomNumberGenerator()
        for length in [1, 2, 5, 16, 20, 32, 64] {
            let data = Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) })
            let encoded = Base32.encode(data)
            XCTAssertEqual(try Base32.decodeCanonical(encoded), data)
        }
    }

    func testEmptyRejected() {
        XCTAssertThrowsError(try Base32.decode(""))
        XCTAssertThrowsError(try Base32.decodeCanonical(""))
    }
}
