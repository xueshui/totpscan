package com.scanauth.sdk.internal

import java.net.IDN
import java.util.Locale

/**
 * 注册域名（可注册后缀 + 一级标签）推导。
 *
 * 说明：为了避免在移动端内置完整 PSL（体积大且需要定期更新），这里使用一份
 * **常用多级公共后缀子集**。规则与 PSL 一致：
 * - 若域名尾部命中后缀表中的多级后缀，则注册域名 = 该后缀 + 1 个标签；
 * - 否则注册域名 = 最后两个标签；
 * - 单标签主机（如 localhost）、IPv4 / IPv6 原样返回。
 *
 * 示例：`example.com -> example.com`、`dkn.example.com -> example.com`、`a.b.com.cn -> b.com.cn`。
 */
internal object RegisteredDomain {

    /**
     * 常见多级公共后缀（PSL 子集）。
     *
     * 覆盖中国内地、港澳台、日韩、东南亚、欧洲、美洲、非洲的主要 `ccTLD` 二级后缀，
     * 以及常见的托管平台私有后缀（`github.io` 等）。
     */
    private val MULTI_LABEL_SUFFIXES: Set<String> = setOf(
        // 中国
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "ac.cn", "mil.cn",
        "bj.cn", "sh.cn", "tj.cn", "cq.cn", "he.cn", "sx.cn", "nm.cn", "ln.cn",
        "jl.cn", "hl.cn", "js.cn", "zj.cn", "ah.cn", "fj.cn", "jx.cn", "sd.cn",
        "ha.cn", "hb.cn", "hn.cn", "gd.cn", "gx.cn", "hi.cn", "sc.cn", "gz.cn",
        "yn.cn", "xz.cn", "sn.cn", "gs.cn", "qh.cn", "nx.cn", "xj.cn", "tw.cn",
        "hk.cn", "mo.cn",
        // 港澳台
        "com.hk", "net.hk", "org.hk", "edu.hk", "gov.hk", "idv.hk",
        "com.tw", "net.tw", "org.tw", "edu.tw", "gov.tw", "idv.tw",
        "com.mo", "net.mo", "org.mo", "edu.mo", "gov.mo",
        // 日韩
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp", "ad.jp", "ed.jp", "gr.jp", "lg.jp",
        "co.kr", "ne.kr", "or.kr", "re.kr", "pe.kr", "go.kr", "mil.kr", "ac.kr",
        // 英国
        "co.uk", "org.uk", "me.uk", "ltd.uk", "plc.uk", "net.uk", "ac.uk", "gov.uk",
        "sch.uk", "nhs.uk", "police.uk",
        // 大洋洲
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "asn.au", "id.au",
        "co.nz", "net.nz", "org.nz", "govt.nz", "ac.nz", "geek.nz", "maori.nz", "iwi.nz",
        // 美洲
        "com.br", "net.br", "org.br", "gov.br", "edu.br",
        "com.mx", "net.mx", "org.mx", "gob.mx", "edu.mx",
        "com.ar", "net.ar", "org.ar", "gov.ar", "edu.ar",
        "com.co", "net.co", "org.co", "gov.co", "edu.co",
        "com.pe", "net.pe", "org.pe", "gob.pe", "edu.pe",
        "com.ve", "net.ve", "org.ve", "gob.ve", "edu.ve",
        "com.ec", "net.ec", "org.ec", "gob.ec", "edu.ec",
        "com.uy", "net.uy", "org.uy", "gob.uy", "edu.uy",
        // 南亚 / 东南亚
        "co.in", "net.in", "org.in", "firm.in", "gen.in", "ind.in", "gov.in", "ac.in", "edu.in", "res.in",
        "co.id", "net.id", "org.id", "web.id", "ac.id", "sch.id", "go.id", "mil.id",
        "com.sg", "net.sg", "org.sg", "gov.sg", "edu.sg", "per.sg",
        "com.my", "net.my", "org.my", "gov.my", "edu.my",
        "co.th", "in.th", "ac.th", "go.th", "net.th", "or.th",
        "com.vn", "net.vn", "org.vn", "edu.vn", "gov.vn",
        "com.ph", "net.ph", "org.ph", "gov.ph", "edu.ph",
        "com.pk", "net.pk", "org.pk", "gov.pk", "edu.pk",
        "com.bd", "net.bd", "org.bd", "gov.bd", "edu.bd",
        "com.np", "net.np", "org.np", "gov.np", "edu.np",
        "com.lk", "net.lk", "org.lk", "gov.lk", "edu.lk",
        "com.mm", "net.mm", "org.mm", "gov.mm", "edu.mm",
        "com.kh", "net.kh", "org.kh", "gov.kh", "edu.kh",
        "com.la", "net.la", "org.la", "gov.la", "edu.la",
        // 中东 / 非洲
        "co.il", "org.il", "net.il", "ac.il", "gov.il", "edu.il",
        "com.sa", "net.sa", "org.sa", "gov.sa", "edu.sa",
        "com.tr", "net.tr", "org.tr", "gov.tr", "edu.tr",
        "com.eg", "net.eg", "org.eg", "gov.eg", "edu.eg",
        "co.za", "net.za", "org.za", "gov.za", "ac.za",
        "co.ke", "or.ke", "ne.ke", "go.ke", "ac.ke", "sc.ke",
        "com.ng", "net.ng", "org.ng", "gov.ng", "edu.ng",
        "co.zw", "org.zw", "gov.zw", "ac.zw",
        "com.gh", "org.gh", "gov.gh", "edu.gh",
        "co.tz", "co.ug", "co.zm", "co.bw", "co.mz", "co.ao",
        // 欧洲（非 ccTLD 直挂）
        "co.at", "or.at", "ac.at", "gv.at",
        "com.pl", "net.pl", "org.pl", "gov.pl", "edu.pl",
        "com.es", "org.es", "nom.es", "gob.es", "edu.es",
        "com.ru", "net.ru", "org.ru",
        "com.ua", "net.ua", "org.ua", "gov.ua", "edu.ua",
        // 常见托管平台（PSL private section）
        "github.io", "gitlab.io", "pages.dev", "workers.dev", "vercel.app",
        "netlify.app", "herokuapp.com", "appspot.com", "web.app", "firebaseapp.com",
        "azurewebsites.net", "cloudfront.net", "s3.amazonaws.com"
    )

    /**
     * 推导注册域名。输入可以是已规范化的 punycode 主机，也可以是用户输入（含 IDN）。
     */
    fun of(host: String): String {
        val normalized = normalize(host)
        if (normalized.isEmpty()) return normalized
        if (normalized.startsWith("[") || isIpv4(normalized)) return normalized

        val labels = normalized.split('.').filter { it.isNotEmpty() }
        if (labels.size <= 1) return normalized

        var suffixLabels = 0
        for (suffix in MULTI_LABEL_SUFFIXES) {
            val parts = suffix.split('.')
            if (parts.size > labels.size) continue
            if (labels.subList(labels.size - parts.size, labels.size) == parts) {
                if (parts.size == labels.size) return normalized
                if (parts.size > suffixLabels) suffixLabels = parts.size
            }
        }

        // 未命中多级后缀时，注册域名固定为最后两个标签
        val take = if (suffixLabels == 0) 2 else suffixLabels + 1
        if (take >= labels.size) return normalized
        return labels.subList(labels.size - take, labels.size).joinToString(".")
    }

    /** 主机名规范化：IDN -> punycode、小写、去结尾点。 */
    fun normalize(host: String): String {
        val trimmed = host.trim()
        if (trimmed.isEmpty()) return ""
        val ascii = runCatching {
            IDN.toASCII(trimmed, IDN.ALLOW_UNASSIGNED)
        }.getOrDefault(trimmed)
        return ascii.lowercase(Locale.ROOT).trimEnd('.')
    }

    /** 是否为 IPv4 字面量（仅用于域名推导，不做严格校验）。 */
    private fun isIpv4(host: String): Boolean {
        val parts = host.split('.')
        if (parts.size != 4) return false
        return parts.all { part ->
            part.isNotEmpty() && part.length <= 3 && part.all { it.isDigit() } &&
                part.toIntOrNull() in 0..255
        }
    }
}
