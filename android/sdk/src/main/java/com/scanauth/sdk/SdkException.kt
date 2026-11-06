package com.scanauth.sdk

/**
 * SDK 内部统一异常：携带确定的错误码，便于调用方做分支处理。
 *
 * 该异常不会跨线程抛给调用方，SDK 会把它转换成回调中的 [SdkError] + message。
 */
class SdkException(
    val error: SdkError,
    override val message: String? = error.defaultMessage,
    override val cause: Throwable? = null
) : RuntimeException(message, cause)

/** 便于 Java 调用方的适配基类，所有方法默认空实现。 */
abstract class BindListenerAdapter : BindListener {
    override fun onConfirmRequired(preview: BindPreview) = Unit
    override fun onBound(account: AccountSummary) = Unit
    override fun onFailure(error: SdkError, message: String?, cause: Throwable?) = Unit
}

/** 便于 Java 调用方的适配基类，所有方法默认空实现。 */
abstract class LoginScanListenerAdapter : LoginScanListener {
    override fun onReady(result: LoginScanResult) = Unit
    override fun onFailure(error: SdkError, message: String?, cause: Throwable?) = Unit
}

/** 便于 Java 调用方的适配基类，所有方法默认空实现。 */
abstract class LoginListenerAdapter : LoginListener {
    override fun onResult(result: SubmitResult) = Unit
    override fun onFailure(error: SdkError, message: String?, cause: Throwable?) = Unit
}

/** 便于 Java 调用方的适配基类，所有方法默认空实现。 */
abstract class BindingConfirmListenerAdapter : BindingConfirmListener {
    override fun onConfirmed(account: AccountSummary) = Unit
    override fun onFailure(error: SdkError, message: String?, cause: Throwable?) = Unit
}

/** 便于 Java 调用方的适配基类，所有方法默认空实现。 */
abstract class AccountOperationListenerAdapter : AccountOperationListener {
    override fun onSuccess(accounts: List<AccountSummary>) = Unit
    override fun onFailure(error: SdkError, message: String?, cause: Throwable?) = Unit
}
