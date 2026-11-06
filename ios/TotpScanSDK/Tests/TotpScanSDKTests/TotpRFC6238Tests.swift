import XCTest
@testable import TotpScanSDK

final class TotpRFC6238Tests: XCTestCase {
    private let times: [TimeInterval] = [
        59,
        1_111_111_109,
        1_111_111_111,
        1_234_567_890,
        2_000_000_000,
        20_000_000_000,
    ]

    private let sha1Secret = Data("12345678901234567890".utf8)
    private let sha256Secret = Data("12345678901234567890123456789012".utf8)
    private let sha512Secret = Data(
        "1234567890123456789012345678901234567890123456789012345678901234".utf8
    )

    func testRFC6238SHA1Vectors() throws {
        let parameters = try TotpParameters(algorithm: .sha1, digits: 8, period: 30)
        let expected = ["94287082", "07081804", "14050471", "89005924", "69279037", "65353130"]
        for (index, time) in times.enumerated() {
            XCTAssertEqual(
                TOTP.generate(secret: sha1Secret, at: TestSupport.date(time), parameters: parameters),
                expected[index]
            )
        }
    }

    func testRFC6238SHA256Vectors() throws {
        let parameters = try TotpParameters(algorithm: .sha256, digits: 8, period: 30)
        let expected = ["46119246", "68084774", "67062674", "91819424", "90698825", "77737706"]
        for (index, time) in times.enumerated() {
            XCTAssertEqual(
                TOTP.generate(secret: sha256Secret, at: TestSupport.date(time), parameters: parameters),
                expected[index]
            )
        }
    }

    func testRFC6238SHA512Vectors() throws {
        let parameters = try TotpParameters(algorithm: .sha512, digits: 8, period: 30)
        let expected = ["90693936", "25091201", "99943326", "93441116", "38618901", "47863826"]
        for (index, time) in times.enumerated() {
            XCTAssertEqual(
                TOTP.generate(secret: sha512Secret, at: TestSupport.date(time), parameters: parameters),
                expected[index]
            )
        }
    }

    func testSixDigitCodeUsesSameTruncation() throws {
        let eight = try TotpParameters(algorithm: .sha1, digits: 8, period: 30)
        let six = try TotpParameters(algorithm: .sha1, digits: 6, period: 30)
        for time in times {
            let full = TOTP.generate(secret: sha1Secret, at: TestSupport.date(time), parameters: eight)
            let short = TOTP.generate(secret: sha1Secret, at: TestSupport.date(time), parameters: six)
            XCTAssertEqual(short, String(full.suffix(6)))
        }
    }

    func testTimeStepAndRemaining() throws {
        XCTAssertEqual(TOTP.timeStep(at: TestSupport.date(59), period: 30), 1)
        XCTAssertEqual(TOTP.timeStep(at: TestSupport.date(60), period: 30), 2)
        XCTAssertEqual(TOTP.secondsRemaining(at: TestSupport.date(59), period: 30), 1)
        XCTAssertEqual(TOTP.secondsRemaining(at: TestSupport.date(60), period: 30), 30)
        XCTAssertEqual(TOTP.secondsRemaining(at: TestSupport.date(61), period: 60), 59)
    }

    func testVerifyWindowAcceptsOnlyOneStepAround() throws {
        let parameters = try TotpParameters(algorithm: .sha1, digits: 6, period: 30)
        let now = TestSupport.date(1_700_000_000)
        let currentStep = TOTP.timeStep(at: now, period: 30)

        let previous = TOTP.generate(
            secret: sha1Secret,
            counter: currentStep - 1,
            parameters: parameters
        )
        let current = TOTP.generate(secret: sha1Secret, counter: currentStep, parameters: parameters)
        let next = TOTP.generate(
            secret: sha1Secret,
            counter: currentStep + 1,
            parameters: parameters
        )
        let tooOld = TOTP.generate(
            secret: sha1Secret,
            counter: currentStep - 2,
            parameters: parameters
        )
        let tooNew = TOTP.generate(
            secret: sha1Secret,
            counter: currentStep + 2,
            parameters: parameters
        )

        XCTAssertTrue(TOTP.verify(secret: sha1Secret, code: previous, at: now, parameters: parameters))
        XCTAssertTrue(TOTP.verify(secret: sha1Secret, code: current, at: now, parameters: parameters))
        XCTAssertTrue(TOTP.verify(secret: sha1Secret, code: next, at: now, parameters: parameters))
        XCTAssertFalse(TOTP.verify(secret: sha1Secret, code: tooOld, at: now, parameters: parameters))
        XCTAssertFalse(TOTP.verify(secret: sha1Secret, code: tooNew, at: now, parameters: parameters))
    }

    func testPeriodSixtyAndNonSHA1Parameters() throws {
        let parameters = try TotpParameters(algorithm: .sha256, digits: 8, period: 60)
        let now = TestSupport.date(1_700_000_000)
        let step = TOTP.timeStep(at: now, period: 60)
        let code = TOTP.generate(secret: sha256Secret, counter: step, parameters: parameters)
        XCTAssertEqual(code.count, 8)
        XCTAssertEqual(TOTP.generate(secret: sha256Secret, at: now, parameters: parameters), code)
        XCTAssertTrue(TOTP.verify(secret: sha256Secret, code: code, at: now, parameters: parameters))
    }

    func testInvalidParametersRejected() {
        XCTAssertThrowsError(try TotpParameters(algorithm: .sha1, digits: 5, period: 30))
        XCTAssertThrowsError(try TotpParameters(algorithm: .sha1, digits: 6, period: 0))
        XCTAssertThrowsError(try TotpParameters(algorithm: .sha1, digits: 6, period: 3601))
    }
}
