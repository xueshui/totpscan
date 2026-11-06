import CryptoKit
import Foundation

/// RFC 6238 支持的 HMAC 算法。
public enum OtpAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    public var displayName: String {
        switch self {
        case .sha1: return "SHA-1"
        case .sha256: return "SHA-256"
        case .sha512: return "SHA-512"
        }
    }
}

/// TOTP 参数。标准账户允许任意正整数步长，协议绑定账户只允许 30/60 秒。
public struct TotpParameters: Codable, Equatable, Sendable {
    public let algorithm: OtpAlgorithm
    public let digits: Int
    public let period: Int

    public init(algorithm: OtpAlgorithm = .sha1, digits: Int = 6, period: Int = 30) throws {
        guard (6...8).contains(digits) else { throw TotpError.invalidDigits }
        guard (1...3600).contains(period) else { throw TotpError.invalidPeriod }
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }

    /// 仅用于内部反序列化后的可信数据；仍会在计算前校验。
    init(uncheckedAlgorithm: OtpAlgorithm, digits: Int, period: Int) {
        self.algorithm = uncheckedAlgorithm
        self.digits = digits
        self.period = period
    }

    public static let standard = TotpParameters(uncheckedAlgorithm: .sha1, digits: 6, period: 30)

    public var isValid: Bool {
        (6...8).contains(digits) && (1...3600).contains(period)
    }
}

public enum TotpError: Error, LocalizedError {
    case invalidDigits
    case invalidPeriod
    case invalidSecret
    case invalidCode

    public var errorDescription: String? {
        switch self {
        case .invalidDigits: return "动态码位数必须是 6–8 位"
        case .invalidPeriod: return "时间步长必须在 1–3600 秒之间"
        case .invalidSecret: return "共享密钥无效"
        case .invalidCode: return "动态码格式不正确"
        }
    }
}

/// 一次计算出的动态码及其有效期。
public struct TotpCode: Equatable, Sendable {
    public let value: String
    public let period: Int
    public let expiresAt: Date

    public init(value: String, period: Int, expiresAt: Date) {
        self.value = value
        self.period = period
        self.expiresAt = expiresAt
    }

    public func remainingSeconds(at date: Date = Date()) -> Int {
        max(0, Int(ceil(expiresAt.timeIntervalSince(date))))
    }
}

/// RFC 6238 / RFC 4226 的纯函数实现，不依赖任何存储。
public enum TOTP {
    private static let powersOfTen: [UInt32] = [1, 10, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000]

    public static func timeStep(at date: Date, period: Int) -> UInt64 {
        guard period > 0 else { return 0 }
        let seconds = Int64(floor(date.timeIntervalSince1970))
        let nonNegative = max(0, seconds)
        return UInt64(nonNegative) / UInt64(period)
    }

    /// 计算指定时间步的动态码。
    public static func generate(secret: Data, counter: UInt64, parameters: TotpParameters) -> String {
        precondition(parameters.isValid, "TOTP 参数必须有效")
        var message = Data(count: 8)
        for index in 0..<8 {
            message[7 - index] = UInt8(truncatingIfNeeded: counter >> UInt64(index * 8))
        }

        let digest = hmac(algorithm: parameters.algorithm, key: secret, message: message)
        guard digest.count >= 20 else { return String(repeating: "0", count: parameters.digits) }

        let offset = Int(digest[digest.count - 1] & 0x0F)
        let binary = (UInt32(digest[offset] & 0x7F) << 24)
            | (UInt32(digest[offset + 1]) << 16)
            | (UInt32(digest[offset + 2]) << 8)
            | UInt32(digest[offset + 3])
        let otp = binary % powersOfTen[parameters.digits]
        return String(otp).leftPadding(toLength: parameters.digits, withPad: "0")
    }

    /// 计算当前时刻的动态码。
    public static func generate(secret: Data, at date: Date = Date(), parameters: TotpParameters = .standard) -> String {
        generate(secret: secret, counter: timeStep(at: date, period: parameters.period), parameters: parameters)
    }

    /// 计算动态码的完整有效期信息。
    public static func code(secret: Data, at date: Date = Date(), parameters: TotpParameters) -> TotpCode {
        let step = timeStep(at: date, period: parameters.period)
        let expiresAt = Date(timeIntervalSince1970: Double(step + 1) * Double(parameters.period))
        return TotpCode(
            value: generate(secret: secret, counter: step, parameters: parameters),
            period: parameters.period,
            expiresAt: expiresAt
        )
    }

    public static func secondsRemaining(at date: Date = Date(), period: Int) -> Int {
        guard period > 0 else { return 0 }
        let seconds = Int(floor(date.timeIntervalSince1970))
        let remainder = ((seconds % period) + period) % period
        return remainder == 0 ? period : period - remainder
    }

    /// 校验动态码，默认接受 t-1 / t / t+1 三个时间窗（与服务端一致）。
    public static func verify(
        secret: Data,
        code: String,
        at date: Date = Date(),
        parameters: TotpParameters = .standard,
        window: Int = 1
    ) -> Bool {
        guard code.count == parameters.digits,
              code.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            return false
        }
        let current = timeStep(at: date, period: parameters.period)
        var offsets: [Int] = [0]
        if window > 0 {
            for value in 1...window {
                offsets.append(value)
                offsets.append(-value)
            }
        }
        for offset in offsets {
            let step = Int64(current) + Int64(offset)
            guard step >= 0 else { continue }
            let expected = generate(secret: secret, counter: UInt64(step), parameters: parameters)
            if constantTimeEquals(expected, code) {
                return true
            }
        }
        return false
    }

    private static func hmac(algorithm: OtpAlgorithm, key: Data, message: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        switch algorithm {
        case .sha1:
            return Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey))
        case .sha256:
            return Data(HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey))
        case .sha512:
            return Data(HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey))
        }
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<left.count {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
}

private extension String {
    func leftPadding(toLength length: Int, withPad pad: Character) -> String {
        guard count < length else { return self }
        return String(repeating: String(pad), count: length - count) + self
    }
}
