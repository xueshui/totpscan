import Foundation

/// 登录二维码（`t = totp-login`）解析结果。
///
/// 载荷只包含：
/// - `url`：域名（不带 scheme 与路径）；
/// - `token`：16 或 24 位会话标识；
/// - `exp`：过期时间（Unix 秒）。
internal struct LoginQRCode {
    /// 二维码中的原始域名。
    let loginDomain: String
    /// 由 `url` 推导出的注册域名（eTLD+1）。
    let registrableDomain: String
    let token: String
    let expiresAt: Date

    static func parse(_ text: String, now: Date) throws -> LoginQRCode {
        let object = try QRJSON.object(from: text)

        let type = try QRJSON.requiredString(object, "t")
        guard type == "totp-login" else {
            throw TotpScanError.invalidQRCode("二维码类型不是 totp-login")
        }
        let version = try QRJSON.requiredInt(object, "v")
        guard version == 1 else {
            throw TotpScanError.unsupportedVersion
        }

        let token = try QRJSON.requiredString(object, "token")
        guard QRJSON.matches(token, pattern: "^([A-Za-z0-9_-]{16}|[A-Za-z0-9_-]{24})$") else {
            throw TotpScanError.invalidQRCode("token 必须是 16 或 24 位会话标识")
        }

        let expiresAtSeconds = try QRJSON.requiredInt(object, "exp")
        let nowSeconds = Int(floor(now.timeIntervalSince1970))
        if nowSeconds > expiresAtSeconds {
            throw TotpScanError.expiredQRCode
        }
        guard expiresAtSeconds - nowSeconds <= 60 else {
            throw TotpScanError.invalidQRCode("登录二维码有效期超出协议上限")
        }

        let rawDomain = try QRJSON.requiredString(object, "url")
        guard !rawDomain.isEmpty,
              !rawDomain.contains("://"),
              !rawDomain.contains("/"),
              !rawDomain.contains("?"),
              !rawDomain.contains("#"),
              !rawDomain.contains("@"),
              !rawDomain.contains(":") else {
            throw TotpScanError.invalidQRCode("url 必须是纯域名（不带 scheme 与路径）")
        }
        let parsed: CanonicalURL
        do {
            parsed = try CanonicalURL.parse("https://\(rawDomain)/")
        } catch {
            throw TotpScanError.invalidQRCode("url 域名不合法")
        }

        return LoginQRCode(
            loginDomain: rawDomain,
            registrableDomain: parsed.registrableDomain,
            token: token,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAtSeconds))
        )
    }
}
