# 消费方混淆规则：保留 SDK 公开 API（回调接口、模型与枚举）。
# SDK 内部类不在此列，允许被 R8 裁剪/重命名。
-keep public class com.scanauth.sdk.ScanTotpClient { public *; }
-keep public class com.scanauth.sdk.StandardTotp { public *; }
-keep public class com.scanauth.sdk.ScanTotpConfig { *; }
-keep public class com.scanauth.sdk.SdkException { *; }
-keep public enum com.scanauth.sdk.SdkError { *; }
-keep public enum com.scanauth.sdk.AccountType { *; }
-keep public enum com.scanauth.sdk.TotpAlgorithm { *; }
-keep public interface com.scanauth.sdk.*Listener { *; }
-keep public class com.scanauth.sdk.*ListenerAdapter { *; }
-keep public class com.scanauth.sdk.AccountSummary { *; }
-keep public class com.scanauth.sdk.BindPreview { *; }
-keep public class com.scanauth.sdk.LoginCandidate { *; }
-keep public class com.scanauth.sdk.LoginScanResult { *; }
-keep public class com.scanauth.sdk.SubmitResult { *; }
-keep public class com.scanauth.sdk.OtpauthAccount { *; }
-keep public class com.scanauth.sdk.TotpParameters { *; }
-keep public class com.scanauth.sdk.TotpVerifyResult { *; }

# security-crypto 依赖 Tink，其编译期注解在运行时不存在，忽略缺失告警即可。
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn javax.annotation.concurrent.**
