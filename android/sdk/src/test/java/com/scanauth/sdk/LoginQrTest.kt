package com.scanauth.sdk

import com.scanauth.sdk.internal.LoginQrParser
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 登录二维码解析测试。
 *
 * 登录载荷：`t / v / url（域名，不带 scheme 与路径）/ token（16 或 24 位）/ exp`。
 */
class LoginQrTest {

    private val now = 1_700_000_000L
    private val token16 = "Abcdefgh12345678"
    private val token24 = "Abcdefgh12345678Abcdefgh"

    @Test
    fun parsesValidLoginPayload() {
        val data = LoginQrParser.parse(buildPayload(), now)
        assertEquals(token16, data.token)
        assertEquals(now + 50, data.expiresAt)
        assertEquals("auth.example.com", data.host)
        assertEquals("example.com", data.registeredDomain)
    }

    @Test
    fun acceptsTwentyFourCharacterToken() {
        val data = LoginQrParser.parse(buildPayload(token = token24), now)
        assertEquals(token24, data.token)
    }

    @Test
    fun derivesRegistrableDomainFromSubdomain() {
        val data = LoginQrParser.parse(buildPayload(url = "dkn.example.com"), now)
        assertEquals("dkn.example.com", data.host)
        assertEquals("example.com", data.registeredDomain)
    }

    @Test
    fun normalizesUppercaseDomain() {
        val data = LoginQrParser.parse(buildPayload(url = "Auth.Example.COM"), now)
        assertEquals("auth.example.com", data.host)
    }

    @Test
    fun ignoresUnknownFields() {
        val json = JSONObject(buildPayload()).put("unknown", 1)
        LoginQrParser.parse(json.toString(), now)
    }

    @Test
    fun rejectsExpiredToken() {
        val payload = buildPayload(exp = now - 1)
        assertError(SdkError.PAYLOAD_EXPIRED) { LoginQrParser.parse(payload, now) }
    }

    @Test
    fun rejectsTokenLifetimeOverSixtySeconds() {
        val payload = buildPayload(exp = now + 61)
        assertError(SdkError.INVALID_PAYLOAD) { LoginQrParser.parse(payload, now) }
    }

    @Test
    fun rejectsWrongType() {
        val json = JSONObject(buildPayload()).put("t", "totp-bind")
        assertError(SdkError.QR_TYPE_MISMATCH) { LoginQrParser.parse(json.toString(), now) }
    }

    @Test
    fun rejectsUnsupportedVersion() {
        val json = JSONObject(buildPayload()).put("v", 2)
        assertError(SdkError.UNSUPPORTED_VERSION) { LoginQrParser.parse(json.toString(), now) }
    }

    @Test
    fun rejectsTokenWithWrongLength() {
        listOf("Abcdefgh1234567", "Abcdefgh123456789", "Abcdefgh12345678Abcdefg").forEach { bad ->
            assertError(SdkError.INVALID_PAYLOAD) {
                LoginQrParser.parse(buildPayload(token = bad), now)
            }
        }
    }

    @Test
    fun rejectsTokenWithIllegalCharacters() {
        assertError(SdkError.INVALID_PAYLOAD) {
            LoginQrParser.parse(buildPayload(token = "Abcdefgh1234 678"), now)
        }
    }

    @Test
    fun rejectsDomainCarryingSchemeOrPath() {
        listOf(
            "https://auth.example.com",
            "auth.example.com/totp/v1",
            "auth.example.com?x=1",
            "auth.example.com:8443"
        ).forEach { bad ->
            assertError(SdkError.INVALID_PAYLOAD) {
                LoginQrParser.parse(buildPayload(url = bad), now)
            }
        }
    }

    private fun buildPayload(
        exp: Long = now + 50,
        token: String = token16,
        url: String = "auth.example.com"
    ): String = JSONObject()
        .put("t", "totp-login")
        .put("v", 1)
        .put("url", url)
        .put("token", token)
        .put("exp", exp)
        .toString()

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
