package com.scanauth.app.camera

/**
 * 相机分析帧的一档尺寸。
 *
 * 不直接用 `android.util.Size`，是为了让分档规则能在纯 JVM 单测里验证。
 */
internal data class AnalysisSize(val width: Int, val height: Int) {

    val pixels: Long get() = width.toLong() * height

    override fun toString(): String = "${width}x$height"
}

/**
 * 分析分辨率分档：默认档 + 逐级升档的候选。
 *
 * 取舍：解码开销随像素数近似线性增长，而实际扫码速度是「帧率 × 单帧成功率」，
 * 所以默认档不取设备最大档。码清楚的时候，1080p 的帧率远高于 4K 档，
 * 综合速度更快；只有连续解不出（典型是 dense 码占屏太小）时，才逐档升到
 * 更大的分辨率去换单帧成功率，识别成功后立刻回到默认档，避免长时间高分辨率
 * 带来的发热、降频与掉帧。
 */
internal class AnalysisTiers private constructor(
    /** 面积降序的全部候选档；下标越小分辨率越高。 */
    val descending: List<AnalysisSize>,
    /** 默认档下标（不超过 1920×1080 的最大一档）。 */
    val defaultIndex: Int
) {

    val default: AnalysisSize get() = descending[defaultIndex]

    /** 当前档是否还能继续升档。 */
    fun canEscalate(currentIndex: Int): Boolean = currentIndex > 0

    /** 升一档（面积更大的下一档）；已在最大档返回 null。 */
    fun next(currentIndex: Int): AnalysisSize? = descending.getOrNull(currentIndex - 1)

    companion object {

        /** 默认档上限：1920×1080。 */
        const val DEFAULT_MAX_PIXELS: Long = 1920L * 1080L

        /** 拿不到设备能力时的兜底档，沿用改造前的请求值。 */
        private val FALLBACK = listOf(
            AnalysisSize(1920, 1080),
            AnalysisSize(1280, 720),
            AnalysisSize(640, 480)
        )

        fun fromSupported(sizes: List<AnalysisSize>): AnalysisTiers {
            val sorted = sizes
                .filter { it.width > 0 && it.height > 0 }
                .distinct()
                .sortedWith(
                    compareByDescending<AnalysisSize> { it.pixels }.thenByDescending { it.width }
                )
            val usable = sorted.ifEmpty { FALLBACK }
            val index = usable.indexOfFirst { it.pixels <= DEFAULT_MAX_PIXELS }
            // 设备最高档都不超过 1080p 时，默认档即最大档（无从再升）
            return AnalysisTiers(usable, if (index >= 0) index else 0)
        }
    }
}
