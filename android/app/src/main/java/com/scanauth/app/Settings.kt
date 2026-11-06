package com.scanauth.app

import android.content.Context

/** 主题模式（只影响本机展示，不涉及安全策略）。 */
enum class ThemeMode {
    SYSTEM,
    LIGHT,
    DARK
}

/** 应用设置。安全相关策略（HTTPS、地址比对）不可由用户关闭。 */
data class AppSettings(
    val theme: ThemeMode = ThemeMode.SYSTEM,
    /** 扫码提交前是否要求生物识别门禁；设备不支持时自动降级为不拦截。 */
    val biometricEnabled: Boolean = true,
    /**
     * 是否在列表 / 详情中显示扫码型（协议）账户的动态码。
     *
     * 默认关闭。开启需本地认证 + 风险确认；关闭后立即隐藏已展示的动态码。
     * 只影响展示，不改变扫码提交路径与地址匹配。
     */
    val showProtocolCodes: Boolean = false
)

/** 设置持久化：使用普通 SharedPreferences（不含任何敏感数据）。 */
class SettingsStore(context: Context) {

    private val prefs = context.getSharedPreferences("scan_totp_app_settings", Context.MODE_PRIVATE)

    fun load(): AppSettings {
        val theme = runCatching {
            ThemeMode.valueOf(prefs.getString(KEY_THEME, ThemeMode.SYSTEM.name)!!)
        }.getOrDefault(ThemeMode.SYSTEM)
        return AppSettings(
            theme = theme,
            biometricEnabled = prefs.getBoolean(KEY_BIOMETRIC, true),
            showProtocolCodes = prefs.getBoolean(KEY_SHOW_PROTOCOL_CODES, false)
        )
    }

    fun save(settings: AppSettings) {
        prefs.edit()
            .putString(KEY_THEME, settings.theme.name)
            .putBoolean(KEY_BIOMETRIC, settings.biometricEnabled)
            .putBoolean(KEY_SHOW_PROTOCOL_CODES, settings.showProtocolCodes)
            .apply()
    }

    companion object {
        private const val KEY_THEME = "theme"
        private const val KEY_BIOMETRIC = "biometric"
        private const val KEY_SHOW_PROTOCOL_CODES = "show_protocol_codes"
    }
}
