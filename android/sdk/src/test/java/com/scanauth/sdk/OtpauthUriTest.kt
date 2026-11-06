package com.scanauth.sdk

import com.scanauth.sdk.internal.OtpauthUri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `otpauth://totp` 解析 / 生成测试（规范 §13.2 U1–U9）。
 */
class OtpauthUriTest {

    @Test
    fun parsesGoogleAuthenticatorStyleUri() {
        val account = StandardTotp.parseOtpauthUri(
            "otpauth://totp/ACME%20Co:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME%20Co"
        )
        assertEquals("ACME Co", account.issuer)
        assertEquals("alice@example.com", account.accountId)
        assertEquals("JBSWY3DPEHPK3PXP", account.secretBase32)
        assertEquals(TotpAlgorithm.SHA1, account.parameters.algorithm)
        assertEquals(6, account.parameters.digits)
        assertEquals(30L, account.parameters.periodSeconds)
    }

    @Test
    fun parsesAllParameters() {
        val account = StandardTotp.parseOtpauthUri(
            "otpauth://totp/Example:bob?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP" +
                "&issuer=Example&algorithm=SHA256&digits=8&period=60"
        )
        assertEquals(TotpAlgorithm.SHA256, account.parameters.algorithm)
        assertEquals(8, account.parameters.digits)
        assertEquals(60L, account.parameters.periodSeconds)
    }

    @Test
    fun algorithmIsCaseInsensitive() {
        val account = StandardTotp.parseOtpauthUri(
            "otpauth://totp/Example:bob?secret=JBSWY3DPEHPK3PXP&algorithm=sha512"
        )
        assertEquals(TotpAlgorithm.SHA512, account.parameters.algorithm)
    }

    @Test
    fun labelPrefixBecomesIssuerWhenParamMissing() {
        val account = StandardTotp.parseOtpauthUri(
            "otpauth://totp/Example%20Inc:bob@example.com?secret=JBSWY3DPEHPK3PXP"
        )
        assertEquals("Example Inc", account.issuer)
        assertEquals("bob@example.com", account.accountId)
    }

    @Test
    fun supportsLowercaseSchemeAndTotp() {
        val account = StandardTotp.parseOtpauthUri(
            "OTPAUTH://TOTP/Example:bob?secret=JBSWY3DPEHPK3PXP&issuer=Example"
        )
        assertEquals("bob", account.accountId)
    }

    @Test
    fun normalizesSecretToUppercaseWithoutPadding() {
        val account = StandardTotp.parseOtpauthUri(
            "otpauth://totp/Example:bob?secret=jbswy3dpehpk3pxpjbswy3dpehpk3pxp%3D%3D"
        )
        assertEquals("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP", account.secretBase32)
    }

    @Test
    fun rejectsHotp() {
        val e = assertThrows(SdkException::class.java) {
            StandardTotp.parseOtpauthUri("otpauth://hotp/Example:bob?secret=JBSWY3DPEHPK3PXP&counter=1")
        }
        assertEquals(SdkError.INVALID_PAYLOAD, e.error)
    }

    @Test
    fun rejectsTotpWithCounterParameter() {
        val e = assertThrows(SdkException::class.java) {
            StandardTotp.parseOtpauthUri("otpauth://totp/Example:bob?secret=JBSWY3DPEHPK3PXP&counter=1")
        }
        assertEquals(SdkError.INVALID_PAYLOAD, e.error)
    }

    @Test
    fun rejectsMissingSecret() {
        val e = assertThrows(SdkException::class.java) {
            StandardTotp.parseOtpauthUri("otpauth://totp/Example:bob?issuer=Example")
        }
        assertEquals(SdkError.INVALID_PAYLOAD, e.error)
    }

    @Test
    fun rejectsShortSecret() {
        val e = assertThrows(SdkException::class.java) {
            StandardTotp.parseOtpauthUri("otpauth://totp/Example:bob?secret=JBSWY3DP")
        }
        assertEquals(SdkError.INVALID_PAYLOAD, e.error)
    }

    @Test
    fun rejectsUnsupportedAlgorithm() {
        val e = assertThrows(SdkException::class.java) {
            StandardTotp.parseOtpauthUri(
                "otpauth://totp/Example:bob?secret=JBSWY3DPEHPK3PXP&algorithm=MD5"
            )
        }
        assertEquals(SdkError.INVALID_PAYLOAD, e.error)
    }

    @Test
    fun rejectsInvalidDigitsAndPeriod() {
        listOf("digits=4", "digits=7", "digits=9", "period=0", "period=3601").forEach { bad ->
            val e = assertThrows("应拒绝 $bad", SdkException::class.java) {
                StandardTotp.parseOtpauthUri("otpauth://totp/Example:bob?secret=JBSWY3DPEHPK3PXP&$bad")
            }
            assertTrue(e.error == SdkError.INVALID_PAYLOAD || e.error == SdkError.INVALID_ARGUMENT)
        }
    }

    @Test
    fun rejectsIssuerConflictBetweenLabelAndQuery() {
        val e = assertThrows(SdkException::class.java) {
            StandardTotp.parseOtpauthUri(
                "otpauth://totp/ACME:alice?secret=JBSWY3DPEHPK3PXP&issuer=Other"
            )
        }
        assertEquals(SdkError.INVALID_PAYLOAD, e.error)
    }

    @Test
    fun rejectsDuplicatedQueryParameter() {
        val e = assertThrows(SdkException::class.java) {
            StandardTotp.parseOtpauthUri(
                "otpauth://totp/Example:bob?secret=JBSWY3DPEHPK3PXP&secret=JBSWY3DPEHPK3PXP"
            )
        }
        assertEquals(SdkError.INVALID_PAYLOAD, e.error)
    }

    @Test
    fun ignoresUnknownParameters() {
        val account = StandardTotp.parseOtpauthUri(
            "otpauth://totp/Example:bob?secret=JBSWY3DPEHPK3PXP&image=https://example.com/x.png"
        )
        assertEquals("bob", account.accountId)
    }

    @Test
    fun buildThenParseRoundTrip() {
        val original = OtpauthAccount(
            issuer = "示例公司",
            accountId = "alice@example.com",
            secretBase32 = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP",
            parameters = TotpParameters(TotpAlgorithm.SHA512, 8, 45)
        )
        val uri = StandardTotp.buildOtpauthUri(original)
        assertTrue(uri.startsWith("otpauth://totp/"))
        val parsed = StandardTotp.parseOtpauthUri(uri)
        assertEquals(original.issuer, parsed.issuer)
        assertEquals(original.accountId, parsed.accountId)
        assertEquals(original.secretBase32, parsed.secretBase32)
        assertEquals(original.parameters, parsed.parameters)
    }

    @Test
    fun generatedUriIsEncodedNotRawSpaces() {
        val uri = StandardTotp.buildOtpauthUri(
            OtpauthAccount("ACME Co", "alice@example.com", "JBSWY3DPEHPK3PXP")
        )
        assertTrue(uri.contains("ACME%20Co"))
        assertTrue(!uri.contains(" "))
    }

    // ------------------------------------------------ 单账户导出（屏幕展示，省略默认参数）

    private fun displayUri(
        issuer: String,
        accountId: String,
        parameters: TotpParameters = TotpParameters(),
        secret: String = "JBSWY3DPEHPK3PXP"
    ): String = OtpauthUri.build(
        OtpauthAccount(issuer, accountId, secret, parameters),
        omitDefaults = true
    )

    @Test
    fun displayUriOmitsDefaultParameters() {
        val uri = displayUri("ACME", "alice@example.com")
        assertEquals("otpauth://totp/ACME:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME", uri)
        assertTrue(!uri.contains("algorithm="))
        assertTrue(!uri.contains("digits="))
        assertTrue(!uri.contains("period="))
    }

    @Test
    fun displayUriKeepsNonDefaultParameters() {
        val uri = displayUri("ACME", "bob", TotpParameters(TotpAlgorithm.SHA256, 8, 60))
        assertTrue(uri.contains("&algorithm=SHA256"))
        assertTrue(uri.contains("&digits=8"))
        assertTrue(uri.contains("&period=60"))
    }

    @Test
    fun displayUriOmitsOnlyDefaults() {
        // 只有 digits 偏离默认值，其余参数仍应省略
        val uri = displayUri("ACME", "bob", TotpParameters(TotpAlgorithm.SHA1, 8, 30))
        assertTrue(!uri.contains("algorithm="))
        assertTrue(uri.contains("&digits=8"))
        assertTrue(!uri.contains("period="))
    }

    @Test
    fun displayUriEncodesLabelSeparatorAndIssuer() {
        val uri = displayUri("示例 公司", "alice@example.com")
        assertTrue(uri.contains("otpauth://totp/%E7%A4%BA%E4%BE%8B%20%E5%85%AC%E5%8F%B8:alice%40example.com?"))
        assertTrue(uri.contains("&issuer=%E7%A4%BA%E4%BE%8B%20%E5%85%AC%E5%8F%B8"))
        assertTrue(!uri.contains(" "))
    }

    @Test
    fun displayUriWithoutIssuerHasNoIssuerParameterOrColon() {
        val uri = displayUri("", "bob")
        assertEquals("otpauth://totp/bob?secret=JBSWY3DPEHPK3PXP", uri)
    }

    @Test
    fun displayUriRoundTripsThroughParser() {
        val original = OtpauthAccount(
            issuer = "示例公司",
            accountId = "alice@example.com",
            secretBase32 = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP",
            parameters = TotpParameters(TotpAlgorithm.SHA512, 8, 45)
        )
        val parsed = StandardTotp.parseOtpauthUri(
            OtpauthUri.build(original, omitDefaults = true)
        )
        assertEquals(original.issuer, parsed.issuer)
        assertEquals(original.accountId, parsed.accountId)
        assertEquals(original.secretBase32, parsed.secretBase32)
        assertEquals(original.parameters, parsed.parameters)
    }

    @Test
    fun displayUriDefaultsRoundTripAsDefaults() {
        val normalized = OtpauthAccount("ACME", "bob", "JBSWY3DPEHPK3PXP")
        val parsed = StandardTotp.parseOtpauthUri(
            OtpauthUri.build(normalized, omitDefaults = true)
        )
        assertEquals(TotpParameters(), parsed.parameters)
    }
}
