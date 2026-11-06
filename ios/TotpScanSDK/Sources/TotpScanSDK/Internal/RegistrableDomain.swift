import Foundation

/// 注册域名（eTLD+1）推导。
///
/// 使用内置的 PSL 级后缀表：取最长匹配的公共后缀，再向右取一个标签。
/// 例如 `dkn.example.com` → `example.com`、`a.b.co.uk` → `b.co.uk`。
/// 表中未收录的后缀按 PSL 的默认规则 `*` 处理（最后一段视为公共后缀）。
/// 这是安全判定的一部分，因此不做任何“相似即相等”的降级。
internal enum RegistrableDomain {
    /// 常用多段公共后缀。单段后缀由默认规则覆盖，无需在此列出。
    /// 仅收录协议实际可能遇到的常用组合；未收录时按单段后缀处理（失败关闭）。
    private static let multiLabelSuffixes: Set<String> = [
        // 中国大陆
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "ac.cn",
        // 中国香港 / 澳门 / 台湾
        "com.hk", "net.hk", "org.hk", "edu.hk", "gov.hk",
        "com.mo", "net.mo", "org.mo", "edu.mo", "gov.mo",
        "com.tw", "net.tw", "org.tw", "edu.tw", "gov.tw",
        // 英国
        "co.uk", "org.uk", "me.uk", "ltd.uk", "plc.uk", "net.uk", "ac.uk", "gov.uk",
        // 日本 / 韩国
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp",
        "co.kr", "or.kr", "ne.kr", "go.kr",
        // 澳新
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.nz", "net.nz", "org.nz", "govt.nz",
        // 东南亚与南亚
        "com.sg", "net.sg", "org.sg", "edu.sg", "gov.sg",
        "com.my", "net.my", "org.my", "gov.my", "edu.my",
        "co.id", "net.id", "or.id", "web.id", "ac.id", "go.id",
        "co.th", "in.th", "or.th", "ac.th", "go.th",
        "com.vn", "net.vn", "org.vn", "edu.vn", "gov.vn",
        "com.ph", "net.ph", "org.ph", "gov.ph",
        "co.in", "net.in", "org.in", "firm.in", "gen.in", "ind.in",
        "com.pk", "net.pk", "org.pk", "edu.pk", "gov.pk",
        "com.bd", "net.bd", "org.bd", "edu.bd", "gov.bd",
        // 中东
        "co.il", "org.il", "net.il", "ac.il", "gov.il",
        "co.ae", "net.ae", "org.ae", "ac.ae", "gov.ae",
        "com.sa", "net.sa", "org.sa", "edu.sa", "gov.sa",
        "com.tr", "net.tr", "org.tr", "gov.tr", "edu.tr",
        "com.eg", "net.eg", "org.eg", "edu.eg", "gov.eg",
        // 欧洲
        "com.es", "nom.es", "org.es", "gob.es", "edu.es",
        "com.pl", "net.pl", "org.pl",
        "com.ru", "net.ru", "org.ru",
        "com.ua", "net.ua", "org.ua", "gov.ua",
        // 美洲 / 非洲
        "com.br", "net.br", "org.br", "gov.br",
        "com.mx", "net.mx", "org.mx", "gob.mx", "edu.mx",
        "com.ar", "net.ar", "org.ar", "gob.ar", "edu.ar",
        "co.za", "net.za", "org.za", "gov.za", "ac.za",
        "co.ke", "or.ke", "ne.ke", "go.ke", "ac.ke",
        "com.ng", "net.ng", "org.ng", "edu.ng", "gov.ng",
    ]

    /// `host` 必须是已经规范化的 ASCII/punycode 小写主机名。
    static func of(host: String) -> String {
        let normalized = host.lowercased()
        guard !normalized.isEmpty else { return normalized }
        if normalized == "localhost" { return normalized }
        if isIPAddress(normalized) { return normalized }

        let labels = normalized.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count > 1 else { return normalized }

        var suffixLength = 1 // PSL 默认规则：`*`
        for index in 0..<labels.count {
            let candidate = labels[index...].joined(separator: ".")
            if multiLabelSuffixes.contains(candidate) {
                suffixLength = labels.count - index
                break
            }
        }

        guard labels.count > suffixLength else { return normalized }
        return labels[(labels.count - suffixLength - 1)...].joined(separator: ".")
    }

    private static func isIPAddress(_ host: String) -> Bool {
        if host.hasPrefix("[") && host.hasSuffix("]") { return true }
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return false }
        return pieces.allSatisfy { piece in
            !piece.isEmpty && piece.allSatisfy { $0.isNumber } && (Int(piece) ?? 256) <= 255
        }
    }

}
