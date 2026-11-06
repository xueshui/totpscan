import Foundation

/// 绑定二维码（`t = totp-bind`）的解析结果。
///
/// 协议不携带签名，也不再有 `sig` / `kid`。绑定载荷显式提供：
/// - `dom`：域名（不带 scheme 与路径）；
/// - `path`：提交路径（可含查询串，例如 `/dtm/ulr?ma=xxx`）。
///
/// 提交目标固定为 `https://<dom><path>`；登录时只要求二维码域名的注册域名与
/// `dom` 的注册域名相同，路径只使用这里绑定的 `path`。
internal struct BindingQRCode {
    let bindingID: String
    let issuer: String
    let account: String
    let secret: Data
    let algorithm: OtpAlgorithm
    let digits: Int
    let period: Int
    /// `https://<dom><path>`，作为唯一的提交目标原样固化。
    let submitURL: String
    /// 由 `dom` 推导出的注册域名（eTLD+1），例如 `dkn.example.com` → `example.com`。
    let registrableDomain: String
    /// 绑定载荷中的 `path`，保持原样（例如 `/dtm/ulr?ma=xxx`）。
    let submitPath: String
    let issuedAt: Date
    let expiresAt: Date?

    var isLooseOrigin: Bool { submitPath == "/" }

    static func parse(_ text: String, now: Date) throws -> BindingQRCode {
        let object = try QRJSON.object(from: text)

        let type = try QRJSON.requiredString(object, "t")
        guard type == "totp-bind" else {
            throw TotpScanError.invalidQRCode("二维码类型不是 totp-bind")
        }
        let version = try QRJSON.requiredInt(object, "v")
        guard version == 1 else {
            throw TotpScanError.unsupportedVersion
        }

        let bindingID = try QRJSON.requiredString(object, "bid")
        guard (24...64).contains(bindingID.count),
              QRJSON.matches(bindingID, pattern: "^b_[A-Za-z0-9_-]{16,64}$") else {
            throw TotpScanError.invalidQRCode("bid 格式不合法")
        }

        let issuer = try QRJSON.displayField(try QRJSON.requiredString(object, "iss"), maxLength: 64, name: "iss")
        let account = try QRJSON.displayField(try QRJSON.requiredString(object, "acc"), maxLength: 255, name: "acc")

        let rawSecret = try QRJSON.requiredString(object, "sec")
        let normalizedSecret = rawSecret
            .uppercased()
            .replacingOccurrences(of: "=", with: "")
            .filter { !$0.isWhitespace }
        guard !normalizedSecret.isEmpty,
              QRJSON.matches(normalizedSecret, pattern: "^[A-Z2-7]+$") else {
            throw TotpScanError.invalidQRCode("sec 不是合法的 Base32")
        }
        let secret: Data
        do {
            secret = try Base32.decodeCanonical(normalizedSecret)
        } catch {
            throw TotpScanError.invalidQRCode("sec 不是合法的 Base32")
        }
        guard (16...64).contains(secret.count) else {
            throw TotpScanError.invalidQRCode("sec 长度必须在 128–512 bit 之间")
        }

        let algorithmRaw = try QRJSON.requiredString(object, "alg")
        guard let algorithm = OtpAlgorithm(rawValue: algorithmRaw) else {
            throw TotpScanError.invalidQRCode("不支持的 alg")
        }
        let digits = try QRJSON.requiredInt(object, "dig")
        guard digits == 6 || digits == 8 else {
            throw TotpScanError.invalidQRCode("dig 只能是 6 或 8")
        }
        let period = try QRJSON.requiredInt(object, "per")
        guard period == 30 || period == 60 else {
            throw TotpScanError.invalidQRCode("per 只能是 30 或 60")
        }

        let rawDomain = try QRJSON.requiredString(object, "dom")
        guard !rawDomain.isEmpty,
              rawDomain.count <= 253,
              !rawDomain.contains("://"),
              !rawDomain.contains("/"),
              !rawDomain.contains("?"),
              !rawDomain.contains("#"),
              !rawDomain.contains("@"),
              !rawDomain.contains(":"),
              !rawDomain.contains(where: { $0.isWhitespace }) else {
            throw TotpScanError.invalidQRCode("dom 必须是纯域名（不带 scheme 与路径）")
        }

        let submitPath = try QRJSON.requiredString(object, "path")
        guard !submitPath.isEmpty,
              submitPath.count <= 2048,
              submitPath.hasPrefix("/"),
              !submitPath.contains("#"),
              !submitPath.contains(where: { $0.isWhitespace }) else {
            throw TotpScanError.invalidQRCode("path 必须是以 / 开头的提交路径")
        }

        let submitURL = "https://\(rawDomain)\(submitPath)"
        let parsed: CanonicalURL
        do {
            parsed = try CanonicalURL.parse(submitURL)
        } catch {
            throw TotpScanError.invalidQRCode("dom 与 path 组合出的提交地址不合法")
        }

        let issuedAtSeconds = try QRJSON.requiredInt(object, "iat")
        let expiresAtSeconds = try QRJSON.optionalInt(object, "exp")
        let nowSeconds = Int(floor(now.timeIntervalSince1970))
        if let expiresAtSeconds, nowSeconds > expiresAtSeconds {
            throw TotpScanError.expiredQRCode
        }

        return BindingQRCode(
            bindingID: bindingID,
            issuer: issuer,
            account: account,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period,
            submitURL: submitURL,
            registrableDomain: parsed.registrableDomain,
            submitPath: submitPath,
            issuedAt: Date(timeIntervalSince1970: TimeInterval(issuedAtSeconds)),
            expiresAt: expiresAtSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}
