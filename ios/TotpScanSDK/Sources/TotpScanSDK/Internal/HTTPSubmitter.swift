import Foundation

/// 禁止跟随重定向：提交请求一旦被重定向，token 与动态码可能被带到非固化地址。
internal final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    static let shared = RedirectBlocker()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // 不跟随，直接把 3xx 响应交回调用方。
        completionHandler(nil)
    }
}

/// 安全提交层。
///
/// - 公开 API 不接受 URL 参数，只接受 `LoginApproval` 或账户 ID；
/// - 实际目标从 Keychain 中的固化地址重新读取，二维码地址永远不会到达这里；
/// - 请求体只包含 `token` 与动态码，使用 JSON body，绝不写入 URL query；
/// - 不跟随重定向、不使用 Cookie、不缓存；
/// - 不实现任何“信任所有证书”的 URLSessionDelegate。
internal final class HTTPSubmitter {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(
            configuration: configuration,
            delegate: RedirectBlocker.shared,
            delegateQueue: nil
        )
    }

    func submit(token: String, code: String, endpoint: PinnedEndpoint) async throws -> SubmitOutcome {
        let body: [String: String] = [
            "token": token,
            "code": code,
        ]
        return try await post(
            url: endpoint.submitURL,
            body: body,
            authorization: nil
        )
    }

    func confirmBinding(bindingID: String, code: String, endpoint: PinnedEndpoint) async throws -> SubmitOutcome {
        guard let url = endpoint.protocolEndpoint(path: "/totp/v1/bindings/\(bindingID)/confirm") else {
            throw TotpScanError.networkFailure("无法生成绑定确认地址")
        }
        return try await post(url: url, body: ["code": code], authorization: nil)
    }

    func revokeBinding(bindingID: String, adminToken: String, endpoint: PinnedEndpoint) async throws -> SubmitOutcome {
        guard let url = endpoint.protocolEndpoint(path: "/totp/v1/bindings/\(bindingID)/revoke") else {
            throw TotpScanError.networkFailure("无法生成解绑地址")
        }
        return try await post(url: url, body: [:], authorization: adminToken, allowsEmptyBody: true)
    }

    /// 仅用于时间偏差检查：向固化地址的同源 `/healthz` 发送 HEAD，不携带任何凭据。
    func serverDate(endpoint: PinnedEndpoint) async -> Date? {
        guard let url = endpoint.protocolEndpoint(path: "/healthz") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  let header = http.value(forHTTPHeaderField: "Date") else {
                return nil
            }
            return Self.httpDateFormatter.date(from: header)
        } catch {
            return nil
        }
    }

    private func post(
        url: URL,
        body: [String: String],
        authorization: String?,
        allowsEmptyBody: Bool = false
    ) async throws -> SubmitOutcome {
        guard url.scheme == "https" || isLoopback(url) else {
            throw TotpScanError.insecureAddress("提交目标必须是 HTTPS 或回环地址")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        if let authorization {
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }
        if !body.isEmpty || !allowsEmptyBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TotpScanError.networkFailure(Self.safeNetworkMessage(error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw TotpScanError.networkFailure("服务器响应无法识别")
        }
        if (300..<400).contains(http.statusCode) {
            throw TotpScanError.networkFailure("服务器返回了重定向，已拒绝跟随")
        }

        let message = Self.serverMessage(from: data)
        if http.statusCode == 429 {
            throw TotpScanError.rateLimited
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw TotpScanError.serverRejected
        }
        return SubmitOutcome(
            httpStatus: http.statusCode,
            accepted: (200..<300).contains(http.statusCode),
            serverMessage: message
        )
    }

    private func isLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http", let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func serverMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String else {
            return nil
        }
        // 只展示有长度上限的通用文案，避免异常响应撑爆界面。
        return String(message.prefix(200))
    }

    private static func safeNetworkMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        return "网络请求失败"
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}
