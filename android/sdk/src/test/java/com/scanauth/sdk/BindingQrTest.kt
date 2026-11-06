package com.scanauth.sdk

import com.scanauth.sdk.internal.BindingQrParser
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/**
 * 绑定二维码解析测试。
 *
 * 绑定载荷：`t / v / bid / iss / acc / sec / alg / dig / per / dom / path / iat / exp`。
 * 不包含签名（`sig` / `kid`），解析阶段不做验签。
 */
class BindingQrTest {

    private val parser = BindingQrParser()
    private val now = 1_700_000_100L

    @Test
    fun parsesValidBindingPayload() {
        val data = parser.parse(buildPayload(), now)
        assertEquals("b_3nS0kq9uV2xJ0mQw1sT4aA", data.bindingId)
        assertEquals("Example Corp", data.issuer)
        assertEquals("alice@example.com", data.account)
        assertEquals("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP", data.secretBase32)
        assertEquals(TotpAlgorithm.SHA1, data.algorithm)
        assertEquals(6, data.digits)
        assertEquals(30L, data.periodSeconds)
        assertEquals("auth.example.com", data.submitUrl.host)
        assertEquals("https://auth.example.com/totp/v1/verify", data.submitUrl.canonical)
        assertEquals("example.com", data.registeredDomain)
        assertEquals("/totp/v1/verify", data.submitPath)
    }

    @Test
    fun preservesQueryStringInSubmitPath() {
        val data = parser.parse(
            buildPayload(dom = "auth.example.com", path = "/dtm/ulr?ma=xxx"),
            now
        )
        assertEquals("/dtm/ulr", data.submitUrl.path)
        assertEquals("ma=xxx", data.submitUrl.query)
        assertEquals("/dtm/ulr?ma=xxx", data.submitPath)
        assertEquals("https://auth.example.com/dtm/ulr?ma=xxx", data.submitUrl.canonical)
    }

    @Test
    fun derivesRegistrableDomainFromSubdomain() {
        val data = parser.parse(
            buildPayload(dom = "dkn.example.com", path = "/dtm/ulr?ma=xxx"),
            now
        )
        assertEquals("dkn.example.com", data.submitUrl.host)
        assertEquals("example.com", data.registeredDomain)
    }

    @Test
    fun normalizesDomAndPath() {
        val data = parser.parse(
            buildPayload(dom = "Auth.Example.com", path = "/totp//v1/verify/"),
            now
        )
        assertEquals("auth.example.com", data.submitUrl.host)
        assertEquals("https://auth.example.com/totp/v1/verify", data.submitUrl.canonical)
    }

    @Test
    fun ignoresUnknownFieldsIncludingRemovedSignatureFields() {
        val payload = JSONObject(buildPayload())
            .put("kid", "bk-test-01")
            .put("sig", "ignored")
            .put("extra", "ignored")
            .toString()
        assertNotNull(parser.parse(payload, now))
    }

    @Test
    fun rejectsPathNotStartingWithSlash() {
        assertError(SdkError.INVALID_PAYLOAD) {
            parser.parse(buildPayload(path = "totp/v1/verify"), now)
        }
    }

    @Test
    fun rejectsPathWithWhitespaceOrFragment() {
        assertError(SdkError.INVALID_PAYLOAD) {
            parser.parse(buildPayload(path = "/totp/v1 verify"), now)
        }
        assertError(SdkError.INVALID_PAYLOAD) {
            parser.parse(buildPayload(path = "/totp/v1#frag"), now)
        }
    }

    @Test
    fun rejectsDomCarryingSchemeOrPath() {
        assertError(SdkError.INVALID_PAYLOAD) {
            parser.parse(buildPayload(dom = "https://auth.example.com"), now)
        }
        assertError(SdkError.INVALID_PAYLOAD) {
            parser.parse(buildPayload(dom = "auth.example.com/evil"), now)
        }
    }

    @Test
    fun rejectsWrongType() {
        val payload = JSONObject(buildPayload()).put("t", "totp-login").toString()
        assertError(SdkError.QR_TYPE_MISMATCH) { parser.parse(payload, now) }
    }

    @Test
    fun rejectsUnsupportedVersion() {
        val payload = JSONObject(buildPayload()).put("v", 2).toString()
        assertError(SdkError.UNSUPPORTED_VERSION) { parser.parse(payload, now) }
    }

    @Test
    fun rejectsExpiredPayload() {
        assertError(SdkError.PAYLOAD_EXPIRED) {
            parser.parse(buildPayload(exp = 1_700_000_000L), now)
        }
    }

    @Test
    fun acceptsPayloadWithoutExpiry() {
        assertNotNull(parser.parse(buildPayload(exp = null), now))
    }

    @Test
    fun rejectsLowercaseSecret() {
        assertError(SdkError.INVALID_PAYLOAD) {
            parser.parse(buildPayload(secret = "jbswy3dpehpk3pxpjbswy3dpehpk3pxp"), now)
        }
    }

    @Test
    fun rejectsControlCharactersInIssuer() {
        assertError(SdkError.INVALID_PAYLOAD) {
            parser.parse(buildPayload(issuer = "Example\nCorp"), now)
        }
    }

    @Test
    fun rejectsNonSixOrEightDigits() {
        assertError(SdkError.INVALID_PAYLOAD) {
            parser.parse(buildPayload(digits = 7), now)
        }
    }

    @Test
    fun rejectsUnsupportedPeriod() {
        assertError(SdkError.INVALID_PAYLOAD) {
            parser.parse(buildPayload(period = 45L), now)
        }
    }

    // ------------------------------------------------------------------ 工具

    private fun buildPayload(
        bindingId: String = "b_3nS0kq9uV2xJ0mQw1sT4aA",
        issuer: String = "Example Corp",
        account: String = "alice@example.com",
        secret: String = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP",
        algorithm: TotpAlgorithm = TotpAlgorithm.SHA1,
        digits: Int = 6,
        period: Long = 30,
        dom: String = "auth.example.com",
        path: String = "/totp/v1/verify",
        issuedAt: Long = 1_700_000_000L,
        exp: Long? = 1_900_000_000L
    ): String {
        val json = JSONObject()
            .put("t", "totp-bind")
            .put("v", 1)
            .put("bid", bindingId)
            .put("iss", issuer)
            .put("acc", account)
            .put("sec", secret)
            .put("alg", algorithm.uriName)
            .put("dig", digits)
            .put("per", period)
            .put("dom", dom)
            .put("path", path)
            .put("iat", issuedAt)
        if (exp != null) json.put("exp", exp)
        return json.toString()
    }

    private fun assertError(expected: SdkError, block: () -> Unit) {
        try {
            block()
        } catch (e: SdkException) {
            assertEquals(expected, e.error)
            return
        }
        throw AssertionError("应当抛出 $expected")
    }
}
