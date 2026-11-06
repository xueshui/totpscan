import Foundation

/// 解析后的标准 TOTP 账户（来自 otpauth:// URI）。
public struct OTPAuthAccount: Equatable, Sendable {
    public let issuer: String
    public let account: String
    public let secret: Data
    public let parameters: TotpParameters

    public init(issuer: String, account: String, secret: Data, parameters: TotpParameters) {
        self.issuer = issuer
        self.account = account
        self.secret = secret
        self.parameters = parameters
    }

    /// 规范 U3：低于 16 字节（128 bit）应提示密钥强度不足；仍允许导入历史密钥（≥10 字节）。
    public var isWeakSecret: Bool {
        secret.count < 16
    }
}

public enum OTPAuthURIError: Error, LocalizedError {
    case notAnOTPAuthURI
    case unsupportedType(String)
    case missingSecret
    case invalidLabel
    case invalidField(String)

    public var errorDescription: String? {
        switch self {
        case .notAnOTPAuthURI:
            return "不是有效的 otpauth 链接"
        case .unsupportedType(let type):
            return "暂不支持 \(type.uppercased()) 类型的验证码"
        case .missingSecret:
            return "链接中缺少 secret 参数"
        case .invalidLabel:
            return "账户标签格式不正确"
        case .invalidField(let field):
            return "参数 \(field) 不合法"
        }
    }
}

/// Google Authenticator Key URI 格式（otpauth://totp/...）的解析与生成。
public enum OTPAuthURI {
    public static func parse(_ raw: String) throws -> OTPAuthAccount {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "otpauth" else {
            throw OTPAuthURIError.notAnOTPAuthURI
        }

        let type = (components.host ?? "").lowercased()
        guard type == "totp" else {
            throw OTPAuthURIError.unsupportedType(type.isEmpty ? "未知" : type)
        }

        let label = components.path.hasPrefix("/") ? String(components.path.dropFirst()) : components.path
        let decodedLabel = label.removingPercentEncoding ?? label
        guard !decodedLabel.isEmpty else { throw OTPAuthURIError.invalidLabel }

        var labelIssuer: String?
        var labelAccount = decodedLabel
        if let separator = decodedLabel.firstIndex(of: ":") {
            let prefix = String(decodedLabel[..<separator])
            let suffix = String(decodedLabel[decodedLabel.index(after: separator)...])
            if !prefix.isEmpty {
                labelIssuer = prefix
            }
            labelAccount = suffix
        }
        guard !labelAccount.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw OTPAuthURIError.invalidLabel
        }

        let items = components.queryItems ?? []
        for item in items where item.name.caseInsensitiveCompare("counter") == .orderedSame {
            throw OTPAuthURIError.invalidField("counter")
        }
        let grouped = Dictionary(grouping: items, by: { $0.name.lowercased() })
        for (name, values) in grouped where values.count > 1 {
            throw OTPAuthURIError.invalidField(name)
        }
        func value(_ name: String) -> String? {
            items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
        }

        // U2：label 中的 issuer 与 query 中的 issuer 必须完全一致。
        let queryIssuer = value("issuer")
        if let labelIssuer, let queryIssuer, labelIssuer != queryIssuer {
            throw OTPAuthURIError.invalidField("issuer")
        }
        let issuer = (queryIssuer ?? labelIssuer ?? "").trimmingCharacters(in: .whitespaces)
        let accountName = labelAccount.trimmingCharacters(in: .whitespaces)

        guard let secretValue = value("secret"), !secretValue.isEmpty else {
            throw OTPAuthURIError.missingSecret
        }
        let secret: Data
        do {
            secret = try Base32.decode(secretValue)
        } catch {
            throw OTPAuthURIError.invalidField("secret")
        }
        guard secret.count >= 10 else {
            throw OTPAuthURIError.invalidField("secret")
        }

        let algorithm: OtpAlgorithm
        if let rawAlgorithm = value("algorithm")?.uppercased(), !rawAlgorithm.isEmpty {
            guard let parsed = OtpAlgorithm(rawValue: rawAlgorithm) else {
                throw OTPAuthURIError.invalidField("algorithm")
            }
            algorithm = parsed
        } else {
            algorithm = .sha1
        }

        let digits: Int
        if let rawDigits = value("digits") {
            guard let parsed = Int(rawDigits), parsed == 6 || parsed == 8 else {
                throw OTPAuthURIError.invalidField("digits")
            }
            digits = parsed
        } else {
            digits = 6
        }

        let period: Int
        if let rawPeriod = value("period") {
            guard let parsed = Int(rawPeriod), (1...3600).contains(parsed) else {
                throw OTPAuthURIError.invalidField("period")
            }
            period = parsed
        } else {
            period = 30
        }

        guard issuer.count <= 64, accountName.count <= 255 else {
            throw OTPAuthURIError.invalidField("label")
        }

        let parameters = try TotpParameters(algorithm: algorithm, digits: digits, period: period)
        return OTPAuthAccount(issuer: issuer, account: accountName, secret: secret, parameters: parameters)
    }

    public static func build(
        issuer: String,
        account: String,
        secret: Data,
        parameters: TotpParameters
    ) -> String {
        let labelIssuer = issuer.isEmpty ? "" : "\(issuer):"
        let label = "\(labelIssuer)\(account)"
        let encodedLabel = label.addingPercentEncoding(withAllowedCharacters: .otpauthLabelAllowed) ?? label
        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = "totp"
        components.percentEncodedPath = "/\(encodedLabel)"

        var items: [URLQueryItem] = [
            URLQueryItem(name: "secret", value: Base32.encode(secret)),
            URLQueryItem(name: "algorithm", value: parameters.algorithm.rawValue),
            URLQueryItem(name: "digits", value: String(parameters.digits)),
            URLQueryItem(name: "period", value: String(parameters.period)),
        ]
        if !issuer.isEmpty {
            items.insert(URLQueryItem(name: "issuer", value: issuer), at: 1)
        }
        components.queryItems = items
        return components.string ?? "otpauth://totp/\(encodedLabel)?secret=\(Base32.encode(secret))"
    }
}

private extension CharacterSet {
    static let otpauthLabelAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~:@!$&'()*+,;=")
        return set
    }()
}
