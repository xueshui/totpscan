package com.scanauth.app.biometric

import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/**
 * 生物识别门禁。
 *
 * - API 30+：优先强生物识别，并允许设备凭据（PIN/图案）兜底；
 * - API 23–29：使用弱生物识别，不提供设备凭据组合（兼容库限制）；
 * - 设备没有任何可用认证方式时，回调 [onUnavailable]，由 UI 决定是否降级。
 */
object BiometricGate {

    fun canAuthenticate(activity: FragmentActivity): Boolean =
        managerState(activity) == BiometricManager.BIOMETRIC_SUCCESS

    fun authenticate(
        activity: FragmentActivity,
        title: String,
        subtitle: String,
        onSuccess: () -> Unit,
        onFailure: (String) -> Unit,
        onUnavailable: (String) -> Unit
    ) {
        val state = managerState(activity)
        if (state != BiometricManager.BIOMETRIC_SUCCESS) {
            onUnavailable(unavailableMessage(state))
            return
        }

        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(
            activity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    onSuccess()
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    onFailure(errString.toString())
                }

                override fun onAuthenticationFailed() {
                    // 单次识别失败，系统会允许重试，不中断流程
                }
            }
        )

        val infoBuilder = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setConfirmationRequired(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            infoBuilder.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL
            )
        } else {
            infoBuilder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
            infoBuilder.setNegativeButtonText("取消")
        }

        prompt.authenticate(infoBuilder.build())
    }

    private fun managerState(activity: FragmentActivity): Int {
        val authenticators = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        } else {
            BiometricManager.Authenticators.BIOMETRIC_WEAK
        }
        return BiometricManager.from(activity).canAuthenticate(authenticators)
    }

    private fun unavailableMessage(state: Int): String = when (state) {
        BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> "本机没有可用的生物识别硬件"
        BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "尚未录入指纹或面容，请先在系统设置中录入"
        BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "生物识别暂时不可用，请稍后重试"
        else -> "本机不支持生物识别"
    }
}
