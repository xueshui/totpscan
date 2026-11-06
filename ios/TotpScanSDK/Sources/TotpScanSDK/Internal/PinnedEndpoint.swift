import Foundation

/// 唯一允许作为提交目标的、已经固化并再次校验过的地址。
/// 只能由 Keychain 记录或绑定预览构造，公开 API 不接受任意 URL。
internal struct PinnedEndpoint {
    /// 绑定时的完整 submit URL（path + query 原样保留）。
    let url: URL
    let canonical: CanonicalURL

    init?(rawURL: String) {
        guard let url = URL(string: rawURL),
              let canonical = try? CanonicalURL.parse(rawURL) else {
            return nil
        }
        self.url = url
        self.canonical = canonical
    }

    var submitURL: URL { url }

    func protocolEndpoint(path: String) -> URL? {
        URL(string: canonical.origin + path)
    }
}
