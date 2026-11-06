import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

internal enum CanonicalizationFailure: Error {
    case reason(String)
}

/// 提交地址规范化与注册域名推导。
///
/// 任何解析失败都必须视为“不匹配”，绝不降级为字符串包含或后缀判断。
internal struct CanonicalURL: Equatable, Sendable {
    let scheme: String
    let host: String
    let port: String?
    let path: String
    /// 原样保留的查询串（不含 `?`）。绑定与登录比对都会用到它。
    let query: String?

    var string: String {
        var value = "\(scheme)://\(host)"
        if let port, !port.isEmpty {
            value += ":\(port)"
        }
        return value + pathWithQuery
    }

    /// `path?query`，用于展示与“绑定路径”的固化。
    var pathWithQuery: String {
        guard let query, !query.isEmpty else { return path }
        return path + "?" + query
    }

    /// PSL 级注册域名（eTLD+1）。登录比对的第一道条件。
    var registrableDomain: String {
        RegistrableDomain.of(host: host)
    }

    /// `scheme://host[:port]`，用于访问协议固定端点（如绑定确认）。
    var origin: String {
        var value = "\(scheme)://\(host)"
        if let port, !port.isEmpty {
            value += ":\(port)"
        }
        return value
    }

    var isLoopback: Bool {
        host == "localhost" || host == "127.0.0.1" || host == "[::1]"
    }

    static func parse(_ raw: String) throws -> CanonicalURL {
        guard !raw.isEmpty, raw.count <= 2048 else {
            throw CanonicalizationFailure.reason("LENGTH_OUT_OF_RANGE")
        }
        guard raw == raw.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw CanonicalizationFailure.reason("SURROUNDING_WHITESPACE")
        }
        for scalar in raw.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                throw CanonicalizationFailure.reason("CONTROL_CHARACTER")
            }
        }
        guard !raw.contains("\\") else {
            throw CanonicalizationFailure.reason("BACKSLASH_NOT_ALLOWED")
        }
        // fragment 一律不允许；query 允许保留（绑定路径包含查询串，如 `/dtm/ulr?ma=xxx`）。
        guard !raw.contains("#") else {
            throw CanonicalizationFailure.reason("FRAGMENT_PRESENT")
        }
        guard let separator = raw.range(of: "://") else {
            throw CanonicalizationFailure.reason("NOT_ABSOLUTE_URL")
        }

        let scheme = String(raw[..<separator.lowerBound]).lowercased()
        guard scheme == "https" || scheme == "http" else {
            throw CanonicalizationFailure.reason("UNSUPPORTED_SCHEME")
        }

        let remainder = String(raw[separator.upperBound...])
        guard !remainder.isEmpty else {
            throw CanonicalizationFailure.reason("EMPTY_AUTHORITY")
        }
        let tailStart = remainder.firstIndex(where: { $0 == "/" || $0 == "?" })
        let authority = tailStart.map { String(remainder[..<$0]) } ?? remainder
        let tail = tailStart.map { String(remainder[$0...]) } ?? ""

        var rawPath = tail
        var rawQuery: String?
        if let queryStart = tail.firstIndex(of: "?") {
            rawPath = String(tail[..<queryStart])
            let value = String(tail[tail.index(after: queryStart)...])
            rawQuery = value.isEmpty ? nil : value
        }

        guard !authority.isEmpty else {
            throw CanonicalizationFailure.reason("EMPTY_HOST")
        }
        guard !authority.contains("@") else {
            throw CanonicalizationFailure.reason("USERINFO_PRESENT")
        }

        let (rawHost, rawPort) = try splitAuthority(authority)
        let host = try normalizeHost(rawHost)
        guard !host.isEmpty else {
            throw CanonicalizationFailure.reason("EMPTY_HOST")
        }

        let port = try normalizePort(rawPort, scheme: scheme)

        if scheme == "http" {
            let loopback = host == "localhost" || host == "127.0.0.1" || host == "[::1]"
            guard loopback else {
                throw CanonicalizationFailure.reason("INSECURE_HTTP")
            }
        }

        var path = rawPath
        if path.isEmpty { path = "/" }
        if !path.hasPrefix("/") { path = "/" + path }
        path = normalizePercentEncoding(path)
        path = collapseSlashes(path)
        path = resolveDotSegments(path)
        path = stripTrailingSlash(path)

        let query = rawQuery.map(normalizePercentEncoding)
        return CanonicalURL(scheme: scheme, host: host, port: port, path: path, query: query)
    }

    private static func splitAuthority(_ authority: String) throws -> (host: String, port: String?) {
        if authority.hasPrefix("[") {
            guard let closing = authority.firstIndex(of: "]") else {
                throw CanonicalizationFailure.reason("INVALID_IPV6_HOST")
            }
            let host = String(authority[authority.index(after: authority.startIndex)..<closing])
            let suffix = String(authority[authority.index(after: closing)...])
            guard !host.isEmpty else {
                throw CanonicalizationFailure.reason("EMPTY_HOST")
            }
            if suffix.isEmpty {
                return (host, nil)
            }
            guard suffix.hasPrefix(":") else {
                throw CanonicalizationFailure.reason("INVALID_AUTHORITY")
            }
            return (host, String(suffix.dropFirst()))
        }

        let pieces = authority.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count <= 2 else {
            throw CanonicalizationFailure.reason("INVALID_AUTHORITY")
        }
        let host = String(pieces[0])
        let port = pieces.count == 2 ? String(pieces[1]) : nil
        return (host, port)
    }

    private static func normalizePort(_ raw: String?, scheme: String) throws -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard raw.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(raw),
              (1...65535).contains(value) else {
            throw CanonicalizationFailure.reason("INVALID_PORT")
        }
        let defaultPort = scheme == "https" ? 443 : 80
        if value == defaultPort { return nil }
        return String(value)
    }

    private static func normalizeHost(_ raw: String) throws -> String {
        var host = raw.lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else {
            throw CanonicalizationFailure.reason("EMPTY_HOST")
        }

        if host.contains(":") {
            guard !host.hasPrefix("["), !host.hasSuffix("]"),
                  let normalized = normalizeIPv6(host) else {
                throw CanonicalizationFailure.reason("INVALID_IPV6_HOST")
            }
            return "[\(normalized)]"
        }
        if host.contains("[") || host.contains("]") {
            throw CanonicalizationFailure.reason("INVALID_HOST")
        }
        if looksLikeIPv4(host) {
            guard let normalized = normalizeIPv4(host) else {
                throw CanonicalizationFailure.reason("INVALID_IPV4_HOST")
            }
            return normalized
        }

        var labels: [String] = []
        for piece in host.split(separator: ".", omittingEmptySubsequences: false) {
            guard !piece.isEmpty else {
                throw CanonicalizationFailure.reason("INVALID_HOST")
            }
            let label = String(piece)
            if label.unicodeScalars.allSatisfy({ $0.value < 128 }) {
                guard isValidAsciiLabel(label) else {
                    throw CanonicalizationFailure.reason("INVALID_HOST")
                }
                labels.append(label)
            } else {
                guard let encoded = Punycode.encode(label: label) else {
                    throw CanonicalizationFailure.reason("INVALID_IDN_HOST")
                }
                labels.append(encoded)
            }
        }
        let normalized = labels.joined(separator: ".")
        guard normalized.count <= 253 else {
            throw CanonicalizationFailure.reason("HOST_TOO_LONG")
        }
        return normalized
    }

    private static func isValidAsciiLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 63 else { return false }
        for scalar in label.unicodeScalars {
            let value = scalar.value
            let isLetter = (value >= 97 && value <= 122) || (value >= 65 && value <= 90)
            let isDigit = value >= 48 && value <= 57
            let isHyphen = value == 45
            let isUnderscore = value == 95
            if !(isLetter || isDigit || isHyphen || isUnderscore) {
                return false
            }
        }
        return true
    }

    private static func looksLikeIPv4(_ host: String) -> Bool {
        !host.isEmpty && host.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
    }

    private static func normalizeIPv4(_ host: String) -> String? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var values: [Int] = []
        for part in parts {
            guard (1...3).contains(part.count),
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part),
                  (0...255).contains(value) else {
                return nil
            }
            values.append(value)
        }
        return values.map(String.init).joined(separator: ".")
    }

    private static func normalizeIPv6(_ host: String) -> String? {
        var address = in6_addr()
        guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
            return nil
        }
        let result: String? = withUnsafePointer(to: &address) { pointer in
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, pointer, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        }
        return result?.lowercased()
    }

    private static func normalizePercentEncoding(_ path: String) -> String {
        let bytes = Array(path.utf8)
        var output = ""
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x25, index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]),
               let low = hexValue(bytes[index + 2]) {
                let value = high * 16 + low
                if isUnreserved(value) {
                    output.append(Character(UnicodeScalar(value)))
                } else {
                    output += String(format: "%%%02X", value)
                }
                index += 3
                continue
            }
            if byte >= 0x80 || byte <= 0x20 || byte == 0x7F {
                output += String(format: "%%%02X", byte)
            } else {
                output.append(Character(UnicodeScalar(byte)))
            }
            index += 1
        }
        return output
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) {
            return true
        }
        switch byte {
        case 45, 46, 95, 126: // - . _ ~
            return true
        default:
            return false
        }
    }

    private static func collapseSlashes(_ path: String) -> String {
        var output = ""
        var previousWasSlash = false
        for character in path {
            if character == "/" {
                if !previousWasSlash {
                    output.append(character)
                }
                previousWasSlash = true
            } else {
                output.append(character)
                previousWasSlash = false
            }
        }
        return output
    }

    private static func resolveDotSegments(_ path: String) -> String {
        var segments: [String] = []
        for piece in path.split(separator: "/", omittingEmptySubsequences: false) {
            let segment = String(piece)
            if segment.isEmpty || segment == "." {
                continue
            }
            if segment == ".." {
                if !segments.isEmpty {
                    segments.removeLast()
                }
                continue
            }
            segments.append(segment)
        }
        return "/" + segments.joined(separator: "/")
    }

    private static func stripTrailingSlash(_ path: String) -> String {
        var value = path
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value.isEmpty ? "/" : value
    }
}
