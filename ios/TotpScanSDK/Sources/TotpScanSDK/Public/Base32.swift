import Foundation

/// Base32 编解码错误。
public enum Base32Error: Error, Equatable, LocalizedError {
    case invalidCharacter(Character)
    case invalidLength
    case empty

    public var errorDescription: String? {
        switch self {
        case .invalidCharacter:
            return "密钥包含非法的 Base32 字符"
        case .invalidLength:
            return "密钥长度不合法"
        case .empty:
            return "密钥为空"
        }
    }
}

/// RFC 4648 Base32（字母表 A–Z 2–7）。
public enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// 宽松解码：允许小写、内部空白与 `=` 填充（用于标准 otpauth URI）。
    public static func decode(_ raw: String) throws -> Data {
        var text = raw.uppercased().filter { !$0.isWhitespace && $0 != "=" }
        guard !text.isEmpty else { throw Base32Error.empty }

        var buffer: UInt32 = 0
        var bits = 0
        var output = Data()
        output.reserveCapacity(text.count * 5 / 8)

        for character in text {
            guard let index = alphabet.firstIndex(of: character) else {
                throw Base32Error.invalidCharacter(character)
            }
            buffer = (buffer << 5) | UInt32(index)
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> UInt32(bits)) & 0xFF))
            }
        }
        guard !output.isEmpty else { throw Base32Error.invalidLength }
        return output
    }

    /// 严格解码：只接受大写 A–Z 2–7、无填充、无空白（用于协议二维码）。
    public static func decodeCanonical(_ raw: String) throws -> Data {
        guard !raw.isEmpty else { throw Base32Error.empty }
        guard raw.count <= 1024 else { throw Base32Error.invalidLength }
        for character in raw {
            guard alphabet.contains(character) else {
                throw Base32Error.invalidCharacter(character)
            }
        }
        return try decode(raw)
    }

    /// 编码为无填充的大写 Base32。
    public static func encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var buffer: UInt32 = 0
        var bits = 0
        var output = ""
        output.reserveCapacity((data.count * 8 + 4) / 5)

        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[Int((buffer >> UInt32(bits)) & 0x1F)])
            }
        }
        if bits > 0 {
            output.append(alphabet[Int((buffer << UInt32(5 - bits)) & 0x1F)])
        }
        return output
    }
}
