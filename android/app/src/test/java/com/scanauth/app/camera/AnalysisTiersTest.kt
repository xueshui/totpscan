package com.scanauth.app.camera

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 分析分辨率分档：默认档不取最大档，失败时按面积逐档升。 */
class AnalysisTiersTest {

    private val typical = listOf(
        AnalysisSize(640, 480),
        AnalysisSize(1280, 720),
        AnalysisSize(1600, 1200),
        AnalysisSize(1920, 1080),
        AnalysisSize(3840, 2160),
        AnalysisSize(4000, 3000),
        AnalysisSize(1920, 1080) // 重复项
    )

    @Test
    fun defaultIsLargestSizeNotExceeding1080p() {
        val tiers = AnalysisTiers.fromSupported(typical)
        assertEquals(AnalysisSize(1920, 1080), tiers.default)
        assertEquals(2, tiers.defaultIndex)
        assertTrue("默认档不应超过 1080p", tiers.default.pixels <= AnalysisTiers.DEFAULT_MAX_PIXELS)
        assertEquals("候选应去重", 6, tiers.descending.size)
    }

    @Test
    fun escalationGoesUpOneTierAtATimeUntilDeviceMax() {
        val tiers = AnalysisTiers.fromSupported(typical)
        val d = tiers.defaultIndex

        assertTrue(tiers.canEscalate(d))
        assertEquals(AnalysisSize(3840, 2160), tiers.next(d))
        assertEquals(AnalysisSize(4000, 3000), tiers.next(d - 1))
        assertNull(tiers.next(0))
        assertFalse(tiers.canEscalate(0))
    }

    @Test
    fun deviceWithoutLargerSizesStaysAtItsMaximum() {
        val tiers = AnalysisTiers.fromSupported(
            listOf(AnalysisSize(640, 480), AnalysisSize(1280, 720))
        )
        assertEquals(AnalysisSize(1280, 720), tiers.default)
        assertEquals(0, tiers.defaultIndex)
        assertFalse("最大档即默认档时无从升档", tiers.canEscalate(tiers.defaultIndex))
    }

    @Test
    fun emptyCapabilityFallsBackToThePreviousRequestSize() {
        val tiers = AnalysisTiers.fromSupported(emptyList())
        assertEquals(AnalysisSize(1920, 1080), tiers.default)
        assertEquals(0, tiers.defaultIndex)
    }
}
