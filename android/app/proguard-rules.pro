# 应用自身不保留任何调试符号之外的额外信息；SDK 已提供 consumer rules。
-keep class com.scanauth.sdk.** { *; }

# security-crypto 依赖 Tink，其编译期注解在运行时不存在（R8 会报 missing class），
# 这些注解不影响运行逻辑，直接忽略即可。
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn javax.annotation.concurrent.**
