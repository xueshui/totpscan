package com.scanauth.sdk

import com.scanauth.sdk.internal.Base32
import com.scanauth.sdk.internal.Base64Codec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** Base32 / Base64 编解码基础测试。 */
class Base32Test {

    @Test
    fun rfc4648Vectors() {
        assertEquals("MZXW6YTBOI", Base32.encode("foobar".toByteArray(Charsets.US_ASCII)))
        assertEquals("foobar", String(Base32.decode("MZXW6YTBOI"), Charsets.US_ASCII))
        assertEquals("f", String(Base32.decode("MY======"), Charsets.US_ASCII))
        assertEquals("fo", String(Base32.decode("MZXQ===="), Charsets.US_ASCII))
    }

    @Test
    fun acceptsLowerCaseAndSeparators() {
        assertEquals(
            "12345678901234567890",
            String(Base32.decode("gezd-gnbv gy3t qojq gezd gnbvgy3tqojq"), Charsets.US_ASCII)
        )
    }

    @Test
    fun rejectsInvalidCharacter() {
        assertThrows(IllegalArgumentException::class.java) {
            Base32.decode("MZXW6YTBO1")
        }
    }

    @Test
    fun base64RoundTrip() {
        val data = ByteArray(64) { (it * 7).toByte() }
        assertArrayEquals(data, Base64Codec.decode(Base64Codec.encode(data)))
        assertEquals("", Base64Codec.encode(ByteArray(0)))
        assertEquals("Zm9vYmFy", Base64Codec.encode("foobar".toByteArray(Charsets.US_ASCII)))
    }
}
