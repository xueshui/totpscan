package com.scanauth.sdk

import com.scanauth.sdk.internal.Totp
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * RFC 6238 附录 B 全部算法的标准测试向量。
 *
 * SHA1  密钥 = ASCII "12345678901234567890"（20 字节）
 * SHA256 密钥 = ASCII "12345678901234567890123456789012"（32 字节）
 * SHA512 密钥 = ASCII "1234567890123456789012345678901234567890123456789012345678901234"（64 字节）
 */
class TotpRfc6238Test {

    private val secretSha1: ByteArray = "12345678901234567890".toByteArray(Charsets.US_ASCII)
    private val secretSha256 = "12345678901234567890123456789012".toByteArray(Charsets.US_ASCII)
    private val secretSha512 =
        "1234567890123456789012345678901234567890123456789012345678901234".toByteArray(Charsets.US_ASCII)

    private val times = listOf(
        59L, 1_111_111_109L, 1_111_111_111L, 1_234_567_890L, 2_000_000_000L, 20_000_000_000L
    )

    @Test
    fun appendixB_sha1_8digits() {
        val expected = listOf("94287082", "07081804", "14050471", "89005924", "69279037", "65353130")
        times.forEachIndexed { index, time ->
            assertEquals(
                "T=$time",
                expected[index],
                Totp.generate(secretSha1, time, TotpAlgorithm.SHA1, 8, 30)
            )
        }
    }

    @Test
    fun appendixB_sha256_8digits() {
        val expected = listOf("46119246", "68084774", "67062674", "91819424", "90698825", "77737706")
        times.forEachIndexed { index, time ->
            assertEquals(
                "T=$time",
                expected[index],
                Totp.generate(secretSha256, time, TotpAlgorithm.SHA256, 8, 30)
            )
        }
    }

    @Test
    fun appendixB_sha512_8digits() {
        val expected = listOf("90693936", "25091201", "99943326", "93441116", "38618901", "47863826")
        times.forEachIndexed { index, time ->
            assertEquals(
                "T=$time",
                expected[index],
                Totp.generate(secretSha512, time, TotpAlgorithm.SHA512, 8, 30)
            )
        }
    }

    @Test
    fun appendixB_sha1_6digits() {
        // 6 位是 8 位结果对 10^6 取模（同一动态截断值）
        val expected = listOf("287082", "081804", "050471", "005924", "279037", "353130")
        times.forEachIndexed { index, time ->
            assertEquals("T=$time", expected[index], Totp.generate(secretSha1, time))
        }
    }

    @Test
    fun defaultParameters_are30SecondsAnd6Digits() {
        assertEquals(30L, Totp.PERIOD_SECONDS)
        assertEquals(6, Totp.DIGITS)
        assertEquals(
            Totp.generate(secretSha1, 1_700_000_000L),
            Totp.generate(secretSha1, 1_700_000_009L)
        )
        assertEquals(
            false,
            Totp.generate(secretSha1, 1_700_000_000L) == Totp.generate(secretSha1, 1_700_000_030L)
        )
    }

    @Test
    fun supportsCustomPeriodAndDigits() {
        val params = TotpParameters(TotpAlgorithm.SHA1, 8, 60)
        // 步长 60：59 秒与 0 秒同属步长 0
        assertEquals(
            Totp.generate(secretSha1, 0L, TotpAlgorithm.SHA1, 8, 60),
            Totp.generate(secretSha1, 59L, TotpAlgorithm.SHA1, 8, 60)
        )
        val code = StandardTotp.generateCode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", params, 59L)
        assertEquals(8, code.length)
    }

    @Test
    fun verifyWindowAcceptsAdjacentSteps() {
        val params = TotpParameters(TotpAlgorithm.SHA1, 6, 30)
        val secretBase32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        val now = 1_700_000_000L
        val previous = StandardTotp.generateCode(secretBase32, params, now - 30)
        val result = StandardTotp.verifyCode(secretBase32, params, previous, now, 1)
        assertEquals(true, result.matched)
        assertEquals(-1, result.offsetSteps)
    }

    @Test
    fun verifyWindowRejectsOutOfRangeStep() {
        val params = TotpParameters(TotpAlgorithm.SHA1, 6, 30)
        val secretBase32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        val now = 1_700_000_000L
        val farAway = StandardTotp.generateCode(secretBase32, params, now - 90)
        assertEquals(false, StandardTotp.verifyCode(secretBase32, params, farAway, now, 1).matched)
    }
}
