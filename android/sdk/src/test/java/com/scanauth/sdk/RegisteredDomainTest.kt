package com.scanauth.sdk

import com.scanauth.sdk.internal.RegisteredDomain
import org.junit.Assert.assertEquals
import org.junit.Test

/** 注册域名推导（PSL 子集）测试。 */
class RegisteredDomainTest {

    @Test
    fun plainDomainKeepsTwoLabels() {
        assertEquals("example.com", RegisteredDomain.of("example.com"))
        assertEquals("example.com", RegisteredDomain.of("example.com"))
    }

    @Test
    fun subdomainCollapsesToRegistrableDomain() {
        assertEquals("example.com", RegisteredDomain.of("dkn.example.com"))
        assertEquals("example.com", RegisteredDomain.of("a.b.c.example.com"))
    }

    @Test
    fun multiLabelPublicSuffixIsRespected() {
        assertEquals("example.com.cn", RegisteredDomain.of("www.example.com.cn"))
        assertEquals("b.com.cn", RegisteredDomain.of("a.b.com.cn"))
        assertEquals("example.co.uk", RegisteredDomain.of("auth.example.co.uk"))
        assertEquals("example.co.jp", RegisteredDomain.of("www.example.co.jp"))
    }

    @Test
    fun privateHostingSuffixIsRespected() {
        assertEquals("alice.github.io", RegisteredDomain.of("alice.github.io"))
        assertEquals("alice.github.io", RegisteredDomain.of("www.alice.github.io"))
    }

    @Test
    fun localhostAndIpAddressesAreReturnedAsIs() {
        assertEquals("localhost", RegisteredDomain.of("localhost"))
        assertEquals("127.0.0.1", RegisteredDomain.of("127.0.0.1"))
        assertEquals("[::1]", RegisteredDomain.of("[::1]"))
    }

    @Test
    fun idnIsConvertedToPunycode() {
        assertEquals("xn--mnchen-3ya.de", RegisteredDomain.of("MÜNCHEN.de"))
        assertEquals("xn--mnchen-3ya.de", RegisteredDomain.of("www.münchen.de"))
    }

    @Test
    fun lookalikeDomainsStayDistinct() {
        assertEquals("example.com", RegisteredDomain.of("auth.example.com"))
        assertEquals("evil.com", RegisteredDomain.of("auth.example.com.evil.com"))
        assertEquals("evil-example.com", RegisteredDomain.of("auth.evil-example.com"))
    }
}
