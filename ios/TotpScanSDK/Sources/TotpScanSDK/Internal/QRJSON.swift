import CoreFoundation
import Foundation

internal enum QRJSON {
    static let maxPayloadCharacters = 16_384

    static func object(from text: String) throws -> [String: Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TotpScanError.invalidQRCode("二维码内容为空")
        }
        guard trimmed.count <= maxPayloadCharacters else {
            throw TotpScanError.invalidQRCode("二维码内容过长")
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw TotpScanError.invalidQRCode("二维码不是 UTF-8 文本")
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw TotpScanError.invalidQRCode("二维码不是合法 JSON")
        }
        guard let object = value as? [String: Any] else {
            throw TotpScanError.invalidQRCode("二维码载荷必须是 JSON 对象")
        }
        return object
    }

    static func requiredString(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw TotpScanError.invalidQRCode("缺少或类型错误的字段 \(key)")
        }
        return value
    }

    static func optionalString(_ object: [String: Any], _ key: String) throws -> String? {
        guard let raw = object[key] else { return nil }
        guard let value = raw as? String else {
            throw TotpScanError.invalidQRCode("字段 \(key) 类型错误")
        }
        return value
    }

    static func requiredInt(_ object: [String: Any], _ key: String) throws -> Int {
        guard let raw = object[key] else {
            throw TotpScanError.invalidQRCode("缺少字段 \(key)")
        }
        guard CFGetTypeID(raw as CFTypeRef) != CFBooleanGetTypeID(),
              let number = raw as? NSNumber else {
            throw TotpScanError.invalidQRCode("字段 \(key) 必须是整数")
        }
        let doubleValue = number.doubleValue
        guard doubleValue.rounded() == doubleValue,
              doubleValue >= 0,
              doubleValue <= 9_007_199_254_740_991 else {
            throw TotpScanError.invalidQRCode("字段 \(key) 必须是整数")
        }
        return Int(doubleValue)
    }

    static func optionalInt(_ object: [String: Any], _ key: String) throws -> Int? {
        guard object[key] != nil else { return nil }
        return try requiredInt(object, key)
    }

    static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    static func displayField(_ value: String, maxLength: Int, name: String) throws -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty, normalized.count <= maxLength else {
            throw TotpScanError.invalidQRCode("字段 \(name) 长度不合法")
        }
        for scalar in normalized.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                throw TotpScanError.invalidQRCode("字段 \(name) 含控制字符")
            }
        }
        return normalized
    }
}
