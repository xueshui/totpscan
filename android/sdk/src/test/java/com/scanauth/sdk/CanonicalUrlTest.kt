package com.scanauth.sdk

import com.scanauth.sdk.internal.CanonicalAddress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 地址规范化（C1–C7）与比对（M1–M4）测试。
 *
 * 逐条覆盖规范 §7.4 的判定示例，并补充 §9 中 TC-14（规范化）与 TC-15（比对）的用例。
 */
class CanonicalUrlTest {

    // ---------------------------------------------------------------- §7.4 判定示例

    @Test
    fun exactMatchAfterNormalization() {
        val result = CanonicalAddress.matches(
            "https://auth.example.com/totp/v1/verify",
            "https://Auth.Example.com:443/totp/v1/verify/"
        )
        assertTrue(result.matched)
        assertFalse(result.lenientRoot)
    }

    @Test
    fun sameRegistrableDomainMatchesRegardlessOfPath() {
        // 登录码只声明域名；路径来自绑定记录，不参与比对
        assertTrue(
            CanonicalAddress.matches(
                "https://auth.example.com/totp/v1",
                "https://auth.example.com/totp/v1/verify"
            ).matched
        )
        assertTrue(
            CanonicalAddress.matches(
                "https://auth.example.com/totp/v1",
                "https://auth.example.com/other/path"
            ).matched
        )
    }

    @Test
    fun evilDomainSuffixIsRejected() {
        val result = CanonicalAddress.matches(
            "https://auth.example.com/totp/v1",
            "https://auth.example.com.evil.com/totp/v1"
        )
        assertFalse(result.matched)
    }

    @Test
    fun similarLookingDomainIsRejected() {
        val result = CanonicalAddress.matches(
            "https://auth.example.com/totp/v1",
            "https://evil-example.com/totp/v1"
        )
        assertFalse(result.matched)
    }

    @Test
    fun subdomainOfSameRegistrableDomainMatches() {
        val result = CanonicalAddress.matches(
            "https://auth.example.com/totp/v1",
            "https://sub.auth.example.com/totp/v1"
        )
        assertTrue(result.matched)
        assertEquals("example.com", result.registeredDomain)
    }

    @Test
    fun queryStringDoesNotAffectDomainMatching() {
        assertTrue(
            CanonicalAddress.matches(
                "https://auth.example.com/dtm/ulr?ma=xxx",
                "https://auth.example.com/any/other?x=1"
            ).matched
        )
    }

    @Test
    fun schemeMismatchIsRejected() {
        // 远端 http 在 C2 阶段就会被拒绝
        val error = assertThrowsSdk {
            CanonicalAddress.matches(
                "https://auth.example.com/totp/v1",
                "http://auth.example.com/totp/v1"
            )
        }
        assertEquals(SdkError.INSECURE_ADDRESS, error.error)

        // 两端都可解析时只比较注册域名，scheme 不参与比对
        val result = CanonicalAddress.matches(
            "https://localhost/totp/v1",
            "http://localhost/totp/v1"
        )
        assertTrue(result.matched)
    }

    @Test
    fun portIsIgnoredForLoginMatching() {
        // 提交目标始终是绑定时的完整地址；二维码端口只参与域名/路径判定
        val result = CanonicalAddress.matches(
            "https://auth.example.com/totp/v1",
            "https://auth.example.com:8443/totp/v1"
        )
        assertTrue(result.matched)
    }

    @Test
    fun dotSegmentIsResolvedDuringParsing() {
        val parsed = CanonicalAddress.parse("https://auth.example.com/totp/v1/../v2")
        assertEquals("/totp/v2", parsed.path)
        assertTrue(
            CanonicalAddress.matches(
                CanonicalAddress.parse("https://auth.example.com/totp/v1"), parsed
            ).matched
        )
    }

    @Test
    fun duplicateSlashesAreMerged() {
        val result = CanonicalAddress.matches(
            "https://auth.example.com/totp/v1",
            "https://auth.example.com//totp//v1/"
        )
        assertTrue(result.matched)
    }

    @Test
    fun bareOriginMatchesSameDomain() {
        val result = CanonicalAddress.matches(
            "https://auth.example.com",
            "https://auth.example.com/anything"
        )
        assertTrue(result.matched)
        assertFalse(result.lenientRoot)
    }

    @Test
    fun userInfoIsRejected() {
        val error = assertThrowsSdk {
            CanonicalAddress.parse("https://user:pw@auth.example.com/totp/v1")
        }
        assertEquals(SdkError.INSECURE_ADDRESS, error.error)
    }

    // ---------------------------------------------------------------- C1–C7 规范化

    @Test
    fun lowercasesHostAndRemovesDefaultPortAndTrailingSlash() {
        val parsed = CanonicalAddress.parse("HTTPS://Auth.Example.COM:443/TOTP/V1/")
        assertEquals("https", parsed.scheme)
        assertEquals("auth.example.com", parsed.host)
        assertEquals(-1, parsed.port)
        assertEquals("/TOTP/V1", parsed.path)
        assertEquals("https://auth.example.com/TOTP/V1", parsed.canonical)
    }

    @Test
    fun nonDefaultPortIsPreserved() {
        assertEquals(
            "https://auth.example.com:8443/totp/v1",
            CanonicalAddress.parse("https://auth.example.com:08443/totp/v1/").canonical
        )
    }

    @Test
    fun httpIsOnlyAllowedForLoopback() {
        assertEquals(
            "http://127.0.0.1:8080/totp/v1/verify",
            CanonicalAddress.parse("http://127.0.0.1:8080/totp/v1/verify").canonical
        )
        assertEquals(
            "http://localhost/totp",
            CanonicalAddress.parse("http://localhost:80/totp").canonical
        )
        assertEquals(
            "http://[::1]:8080/totp",
            CanonicalAddress.parse("http://[0:0:0:0:0:0:0:1]:8080/totp").canonical
        )
        val error = assertThrowsSdk { CanonicalAddress.parse("http://example.com/totp") }
        assertEquals(SdkError.INSECURE_ADDRESS, error.error)
    }

    @Test
    fun queryIsPreservedAndFragmentWhitespaceRejected() {
        val parsed = CanonicalAddress.parse("https://auth.example.com/totp?x=1&y=2")
        assertEquals("/totp", parsed.path)
        assertEquals("x=1&y=2", parsed.query)
        assertEquals("/totp?x=1&y=2", parsed.submitPath)
        assertEquals("https://auth.example.com/totp?x=1&y=2", parsed.canonical)

        assertThrowsSdk { CanonicalAddress.parse("https://auth.example.com/totp#frag") }
        assertThrowsSdk { CanonicalAddress.parse(" https://auth.example.com/totp") }
        assertThrowsSdk { CanonicalAddress.parse("https://auth.example.com/to\u0000tp") }
        assertThrowsSdk { CanonicalAddress.parse("https://auth.example.com/totp?x= 1") }
    }

    @Test
    fun emptyQueryIsDropped() {
        val parsed = CanonicalAddress.parse("https://auth.example.com/totp?")
        assertEquals(null, parsed.query)
        assertEquals("/totp", parsed.submitPath)
    }

    @Test
    fun idnaHostIsConvertedToPunycode() {
        val parsed = CanonicalAddress.parse("https://MÜNCHEN.de/totp/v1")
        assertEquals("xn--mnchen-3ya.de", parsed.host)
    }

    @Test
    fun trailingDotIsRemoved() {
        assertEquals(
            "https://auth.example.com/totp/v1",
            CanonicalAddress.parse("https://auth.example.com./totp/v1").canonical
        )
    }

    @Test
    fun percentEncodingOfUnreservedCharsIsDecoded() {
        assertEquals(
            "https://auth.example.com/totp/v1",
            CanonicalAddress.parse("https://auth.example.com/totp/%76%31").canonical
        )
        // 保留字符的百分号编码统一为大写
        assertEquals(
            "https://auth.example.com/a%2Fb",
            CanonicalAddress.parse("https://auth.example.com/a%2fb").canonical
        )
    }

    @Test
    fun emptyPathBecomesRoot() {
        assertEquals("/", CanonicalAddress.parse("https://auth.example.com").path)
        assertEquals("/", CanonicalAddress.parse("https://auth.example.com:443").path)
    }

    @Test
    fun dotDotCannotEscapeRoot() {
        assertEquals("/v1", CanonicalAddress.parse("https://auth.example.com/../../v1").path)
    }

    private fun assertThrowsSdk(block: () -> Unit): SdkException {
        try {
            block()
        } catch (e: SdkException) {
            return e
        }
        throw AssertionError("应当抛出 SdkException")
    }
}
