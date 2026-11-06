# 扫码增强型 TOTP 认证 · Android 端

本目录实现规范 [`spec/totp-scan-v1.md`](../spec/totp-scan-v1.md) 的 Android 端：

- **`sdk/`**：可独立集成的 AAR。对外提供绑定、扫码登录、账户管理、解绑、错误码与回调，同时提供标准 RFC 6238 TOTP 能力。
- **`app/`**：可直接安装使用的正式 App，既是多站点扫码认证器，也是标准 TOTP 认证器。

> 目录边界：本实现只存在于 `android/`，不修改 `spec/`、`server/`、`ios/`、`harmony/`。

---

## 1. 模块结构

```
android/
├── settings.gradle.kts          # 仓库与镜像、include :sdk / :app
├── build.gradle.kts             # AGP / Kotlin / Compose 插件版本
├── gradle.properties            # 中文路径开关、SDK 发布坐标
├── package.ps1 / package.sh     # 一键打包脚本（AAR + POM + APK）
├── keystore/                    # 本地签名证书（已被 .gitignore 排除，不入库）
├── sdk/
│   ├── build.gradle.kts         # com.android.library + maven-publish
│   ├── consumer-rules.pro       # 消费方混淆规则
│   └── src/
│       ├── main/java/com/scanauth/sdk/
│       │   ├── ScanTotpClient.kt      # 唯一入口（回调式 API）
│       │   ├── ScanTotpConfig.kt      # 超时、时钟偏差、调试日志
│       │   ├── StandardTotp.kt        # 标准 TOTP：解析/生成 URI、算码、校验窗口
│       │   ├── Models.kt              # 账户、候选、提交结果、回调接口
│       │   ├── SdkError.kt            # 错误码枚举
│       │   ├── SdkException.kt        # 异常与各 ListenerAdapter
│       │   └── internal/
│       │       ├── CanonicalUrl.kt    # §7 C1–C7 规范化 + 注册域名比对
│       │       ├── RegisteredDomain.kt # PSL 子集注册域名推导
│       │       ├── BindingQr.kt       # totp-bind 解析（dom + path）
│       │       ├── LoginQr.kt         # totp-login 解析（url + token）
│       │       ├── PinnedEndpoint.kt  # 只允许由已固化地址构造
│       │       ├── Submitter.kt       # HTTPS 提交（不跟随重定向）
│       │       ├── SecureStore.kt     # Keystore + EncryptedSharedPreferences
│       │       ├── Totp.kt            # RFC 6238 / 4226
│       │       ├── Base32.kt / Base64Codec.kt / OtpauthUri.kt / QrJson.kt
│       │       └── SdkLog.kt
│       └── test/java/com/scanauth/sdk/   # 93 个纯 JVM 单元测试
└── app/
    └── src/main/java/com/scanauth/app/
        ├── MainActivity.kt        # FragmentActivity + Navigation
        ├── AppViewModel.kt        # 流程状态机
        ├── Settings.kt            # 主题 / 生物识别开关
        ├── camera/QrCodeAnalyzer.kt
        ├── biometric/BiometricGate.kt
        └── ui/                    # 首页、添加、扫码、绑定确认、登录、详情、设置
```

---

## 2. 环境要求

| 项 | 版本 / 说明 |
| --- | --- |
| JDK | 17 或以上（本机用 21 验证，`compileOptions`/`jvmTarget` 为 17） |
| Gradle | 8.11.1（仓库未携带 wrapper；可用系统 Gradle 或执行 `gradle wrapper` 生成） |
| Android Gradle Plugin | 8.7.3 |
| Kotlin | 2.0.21（含 compose compiler 插件） |
| compileSdk / targetSdk | 35 |
| buildToolsVersion | 35.0.1（显式指定，避免缺失 34.x） |
| minSdk | 23 |
| Android SDK | 需安装 Platform 35、Build-Tools 35.0.1、platform-tools |

`gradle.properties` 已设置：

```properties
android.overridePathCheck=true
scanTotp.group=com.scanauth
scanTotp.artifact=scan-totp-sdk
scanTotp.version=1.0.0
```

`android.overridePathCheck=true` 用于支持**含中文/空格的工程路径**（AGP 默认会拒绝非 ASCII 路径）。

`local.properties` 由本机生成（`sdk.dir=...`），已在 `.gitignore` 中排除。

### 网络受限环境

`settings.gradle.kts` 优先使用阿里云镜像，保留 `google()` / `mavenCentral()` 兜底：

```kotlin
maven("https://maven.aliyun.com/repository/gradle-plugin")
maven("https://maven.aliyun.com/repository/google")
maven("https://maven.aliyun.com/repository/public")
```

如果依赖已缓存、但 Google Maven 不可达，可改用离线构建：

```powershell
.\package.ps1 -Target all -Offline
```

---

## 3. 一键打包

```powershell
# Windows：构建 SDK（AAR + POM + sources）与 App（Release APK），并复制到 android\dist\
.\package.ps1
.\package.ps1 -Target sdk     # 只构建 SDK
.\package.ps1 -Target app     # 只构建 App
.\package.ps1 -Offline        # 离线模式
```

```bash
# macOS / Linux
./package.sh all
./package.sh sdk
./package.sh app
```

脚本内部执行：

```text
:sdk:assembleRelease
:sdk:publishReleasePublicationToMavenLocal
:app:assembleRelease
:app:assembleDebug
```

产出（`android/dist/`）：

```
scan-totp-sdk-1.0.0.aar
scan-totp-sdk-1.0.0.pom
scan-totp-sdk-1.0.0-sources.jar
scan-totp-sdk-1.0.0.module
scan-totp-app-1.0.0-signed.apk   # 已签名 Release，可直接安装
```

脚本结束时会打印每个 APK 的 SHA256。没有签名材料时脚本直接失败，不会产出未签名包。

### 3.1 签名说明（材料不入库）

`app/build.gradle.kts` 按以下顺序读取签名材料：

1. 环境变量：`ANDROID_KEYSTORE_PATH` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`；
2. 本地文件：`android/keystore.local.properties`（已被 `.gitignore` 排除，可从 `keystore.local.properties.example` 复制）。

```properties
storeFile=keystore/your-release.jks
storePassword=
keyAlias=
keyPassword=
```

任一材料缺失时，`:app:assembleRelease` / `:app:bundleRelease` 会在配置阶段直接失败，并提示缺失项；**不会**静默产出未签名包，也**不会**回退到 debug 签名。

签名证书与口令不得提交到版本库；仓库内的 `android/keystore/` 仅供本地联调，已在忽略列表中。

签名后自检（`apksigner` 与 `aapt2` 在 `$ANDROID_SDK/build-tools/35.0.1/`）：

```bash
apksigner verify --verbose --print-certs scan-totp-app-1.0.0-signed.apk
aapt2 dump badging scan-totp-app-1.0.0-signed.apk | head -3
```

期望输出：`Verifies` + v1/v2/v3 均为 `true`；`package: name='com.scanauth.app' versionCode='1' versionName='1.0.0'`。

### 3.2 安装步骤

1. 确认设备系统为 **Android 6.0（API 23）及以上**（`minSdk = 23`，`targetSdk = 35`）。
2. 把 `scan-totp-app-1.0.0-signed.apk` 传到手机（数据线 / 文件传输 / 网盘均可）。
3. 在系统「设置 → 应用 → 特殊应用权限 → 安装未知应用」中，允许所使用的文件管理器/浏览器安装应用；部分国产 ROM 还需关闭「纯净模式」（华为/荣耀）或「安全安装校验」。
4. 点击 APK 安装，首次启动后按引导授予相机权限（仅扫码时需要）。
5. 或用 adb 安装（推荐，能直接看到失败码）：

```bash
adb devices                                   # 确认设备已授权
adb install -r scan-totp-app-1.0.0-signed.apk # -r 覆盖安装，保留数据
```

签名冲突时先卸载再装：

```bash
adb uninstall com.scanauth.app
adb install scan-totp-app-1.0.0-signed.apk
```

debug 兜底包的包名是 `com.scanauth.app.debug`，可与 release 包共存：

```bash
adb install -r scan-totp-app-1.0.0-debug.apk
```

### 3.3 安装失败对照表

| 现象 / 错误码 | 原因 | 处理 |
| --- | --- | --- |
| 安装器提示「packageInfo is null」「解析包时出现问题」 | APK **未签名**（或签名块被破坏），`PackageManager` 取不到签名信息 | 改用本目录产出的 `-signed.apk` / `-debug.apk`；用 `apksigner verify` 自检 |
| `INSTALL_PARSE_FAILED_NO_CERTIFICATES` | 同上，未签名 | 同上 |
| `INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES` | 覆盖安装时新旧包证书不一致 | `adb uninstall com.scanauth.app` 后重装 |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 已装同包名应用由其他证书签名 | 卸载旧包后重装 |
| `INSTALL_FAILED_ALREADY_EXISTS` | 已存在同名包，未加 `-r` | 加 `adb install -r`，或先卸载 |
| `INSTALL_FAILED_OLDER_SDK` | 设备低于 `minSdk 23`（Android 6.0） | 换 6.0+ 设备或模拟器 |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | APK 缺少设备架构的 native 库 | 本包是 universal（`arm64-v8a` / `armeabi-v7a` / `x86` / `x86_64` 全含）；若自行裁剪，请保留目标 ABI |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | 存储空间不足 | 清理空间后重试 |
| `INSTALL_FAILED_INVALID_APK` | APK 文件损坏（传输截断、被杀软改写） | 用 3.4 的 sha256 校验，重新拷贝 |
| 点击安装无反应 / 提示「已阻止安装」 | 未知来源限制、纯净模式、企业设备管控 | 允许安装未知应用；关闭纯净模式；切换个人空间 |
| 安装成功但启动即闪退 | 与签名无关（多为设备兼容性问题） | `adb logcat` 抓日志反馈 |

### 3.4 完整性校验（sha256）

```powershell
# Windows PowerShell
Get-FileHash .\scan-totp-app-1.0.0-signed.apk -Algorithm SHA256
```

```bash
# macOS
shasum -a 256 scan-totp-app-1.0.0-signed.apk
# Linux
sha256sum scan-totp-app-1.0.0-signed.apk
```

把输出与本目录 README / 发布说明中记录的哈希逐位比对，不一致说明文件在传输或复制过程中损坏，需重新获取。

---

## 4. SDK 集成

### 4.1 方式 A：本地 AAR

1. 把 `scan-totp-sdk-1.0.0.aar` 放入宿主工程 `app/libs/`。
2. 在模块 `build.gradle.kts` 中：

```kotlin
dependencies {
    implementation(files("libs/scan-totp-sdk-1.0.0.aar"))
    // AAR 的公开 API 暴露了 EncryptedSharedPreferences 相关类型（security-crypto）
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}
```

### 4.2 方式 B：Maven 本地仓库

`package.ps1` 已执行 `publishReleasePublicationToMavenLocal`，随后：

```kotlin
repositories {
    mavenLocal()
    google()
    mavenCentral()
}

dependencies {
    implementation("com.scanauth:scan-totp-sdk:1.0.0")
}
```

### 4.3 权限与清单

宿主 App 至少需要：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<!-- 若由宿主负责扫码 -->
<uses-permission android:name="android.permission.CAMERA" />
```

SDK 自身不申请权限、不声明 Activity。建议同时设置：

```xml
<application android:allowBackup="false" android:fullBackupContent="false" />
```

### 4.4 初始化

```kotlin
val client = ScanTotpClient.create(
    context,
    ScanTotpConfig(
        connectTimeoutMs = 8_000,
        readTimeoutMs = 10_000,
        // 二维码过期判断允许的时钟偏差（秒），默认 0 = 严格按 exp
        clockSkewSeconds = 90
    )
)
```

`ScanTotpConfig` **刻意不提供提交地址配置**：提交地址只能来自绑定二维码的 `dom + path`，并由用户确认后固化。

> 绑定二维码不带签名、不需要配置任何信任根或公钥：解析阶段只校验字段格式与 `exp`，
> 是否信任该站点由用户在确认页核对 `dom` / `path` 后决定。

### 4.5 绑定（扫码 → 地址确认 → 保存 → 可选服务端确认）

```kotlin
client.beginBind(
    qrPayload = scannedText,
    listener = object : BindListener {
        override fun onConfirmRequired(preview: BindPreview) {
            // 必须把 preview.submitUrl 展示给用户确认；备注仅存本地（≤64 字符）
            client.confirmBind(preview, remark = "公司 VPN", listener = this)
        }

        override fun onBound(account: AccountSummary) {
            // 已写入安全存储；account.isConfirmed 表示服务端确认是否成功
        }

        override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
            // 字段非法 / exp 过期 / 地址不安全等
        }
    }
)
```

`confirmBind` 会重新解析原始载荷并复核 `dom` / `path`，不接受调用方传入的 URL。若服务端确认失败，账户仍会保存在本地（`isConfirmed = false`），可调用 `confirmBinding(localId, listener)` 重试；未确认账户不能用于登录。

### 4.6 扫码登录（按注册域名自动选账户）

```kotlin
client.verifyLoginQr(scannedText, object : LoginScanListener {
    override fun onReady(result: LoginScanResult) {
        when (result.candidates.size) {
            1 -> client.submitLogin(result, result.candidates[0].localId, loginListener)
            else -> {
                // 多个候选：注册域名相同，由用户在同域内选择
                showCandidatePicker(result.candidates) { picked ->
                    client.submitLogin(result, picked.localId, loginListener)
                }
            }
        }
    }

    override fun onFailure(error: SdkError, message: String?, cause: Throwable?) {
        // 0 候选 / 地址不匹配 / 过期：没有发起任何网络请求
    }
})
```

提交结果：

```kotlin
val loginListener = object : LoginListenerAdapter() {
    override fun onResult(result: SubmitResult) {
        // result.isAccepted、result.serverTimeOffsetSeconds（时间偏差）
    }

    override fun onFailure(error: SdkError, message: String?, cause: Throwable?) { }
}
```

> `submitLogin` 不暴露 URL 入参；内部只使用 `PinnedEndpoint`（由安全存储中的固化地址构造），
> 并在提交前重新解析二维码、二次比对注册域名与账户归属。

### 4.7 账户管理与解绑

```kotlin
val accounts: List<AccountSummary> = client.accounts()
val one = client.account(localId)

client.renameAccount(localId, "新备注", opListener)   // ≤64 字符，仅本地
client.removeAccount(localId, opListener)              // 删除本地密钥
client.unbindAll(opListener)                           // 清空并销毁 Keystore 主密钥
```

服务端解绑需要管理员令牌，App 不调用 revoke；界面会提示「服务端绑定需管理员解除」。

### 4.8 标准 TOTP（可单独使用）

```kotlin
// 解析 otpauth URI（支持 SHA1/256/512、6/8 位、任意 1–3600 秒周期）
val account = StandardTotp.parseOtpauthUri("otpauth://totp/Example:alice@example.com?secret=...")

// 按参数计算动态码
val code = StandardTotp.generateCode(account.secretBase32, account.parameters)

// 生成 URI（例如用户手动录入后回显）
val uri = StandardTotp.buildOtpauthUri(account)

// ±1 窗口校验，并返回偏差步数
val verify = StandardTotp.verifyCode(account.secretBase32, account.parameters, userInput)
```

标准型账户也可交由 SDK 管理：

```kotlin
client.addStandardAccount(otpauthUri, remark = "GitHub", listener)
client.addStandardAccount(
    issuer = "GitHub",
    accountId = "me@example.com",
    secretBase32 = "...",
    parameters = TotpParameters(TotpAlgorithm.SHA256, digits = 8, periodSeconds = 60),
    remark = "",
    listener = bindListener
)
client.standardCodeFor(localId)   // 仅标准型返回动态码；扫码型恒为 null
client.protocolCodeFor(localId)   // 扫码型动态码：仅在用户显式开启展示开关后调用
client.otpauthUriFor(localId)     // 单账户 otpauth 地址，仅供屏幕二维码展示（省略默认参数）
```

### 4.9 错误码

| 值 | 枚举 | 含义 |
| --- | --- | --- |
| 1001 | `NOT_INITIALIZED` | SDK 未初始化 |
| 1003 | `NOT_BOUND` | 本机未绑定该账户 |
| 1004 | `INVALID_ARGUMENT` | 入参不合法（如备注过长） |
| 1005 | `ACCOUNT_TYPE_MISMATCH` | 账户类型不支持该操作 |
| 1006 | `ACCOUNT_SELECTION_REQUIRED` | 存在多个候选账户，需显式选择 |
| 2001 | `INVALID_PAYLOAD` | 二维码/URI 内容非法 |
| 2002 | `UNSUPPORTED_VERSION` | `v != 1` |
| 2003 | `PAYLOAD_EXPIRED` | 二维码过期 |
| 2005 | `INSECURE_ADDRESS` | 地址不满足 C1–C7 |
| 2006 | `ADDRESS_MISMATCH` | 注册域名不匹配（零出站请求） |
| 2008 | `QR_TYPE_MISMATCH` | 绑定/登录二维码类型不符 |
| 3001 | `SECURE_STORAGE_ERROR` | 安全存储不可用或数据损坏 |
| 4001 | `NETWORK_ERROR` | 网络异常 |
| 4002 | `SERVER_REJECTED` | 服务端统一拒绝（401） |
| 4003 | `HTTP_ERROR` | 非预期 HTTP 状态 |
| 4004 | `RATE_LIMITED` | 429 限流 |
| 4005 | `SERVER_INVALID_REQUEST` | 400 请求格式无效 |
| 9001 | `INTERNAL_ERROR` | 其它内部错误 |

---

## 5. App 功能与异常路径

| 场景 | 行为 |
| --- | --- |
| 首页 | 顶部「扫码登录」入口；账户列表区分「扫码型 / 标准型」标签；扫码型默认**不出现动态码**（可在设置中开启） |
| 标准型账户 | 实时动态码 + 倒计时环，点击复制；详情页可改备注、删除、导出二维码 |
| 扫码型账户 | 只显示固化地址主机名、确认状态；详情页只读展示完整地址与备注，可重命名、删除、导出二维码、未确认时重试确认 |
| 导出二维码 | 详情页「导出二维码」→ 本地认证 → 确认（扫码型需勾选风险）→ 打开防截屏页面；默认模糊遮罩，点击显示清晰二维码，60 秒自动关闭 |
| 添加账户 | 三种入口：扫码绑定 / 手动输入 / otpauth 链接导入 |
| 绑定 | 扫码 → 地址确认（含备注输入）→ 保存 → 自动服务端确认；确认失败可重试或稍后处理 |
| 登录 | 权限申请 → 相机预览 → 解析校验 → 注册域名比对 → 候选选择（仅同域多账户）→ 生物识别 → 提交 → 结果 |
| 成功 | 显示服务器提示、请求编号；时间偏差 ≥30 秒时提示校准系统时间 |
| 失败 | 区分「地址不匹配（零请求）」「二维码过期」「网络错误（可重试）」「服务端拒绝」「限流」 |
| 相机权限被拒 | 说明原因；永久拒绝时提供「前往设置」；始终提供「手动粘贴二维码内容」 |
| 无相机 / 相机启动失败 | 明确提示并回退到手动粘贴 |
| 空状态 | 解释两类账户并给出添加入口 |
| 设置 | 主题（跟随系统/浅色/深色）、生物识别门禁开关、**显示扫码型账户的动态码**（默认关闭，开启需认证 + 风险确认）、安全说明、清除本机全部账户 |

---

## 6. 安全实现要点（对应规范第 5、7、8 节与 S1–S14）

### 6.1 地址规范化 C1–C7 与比对

实现在 [`CanonicalUrl.kt`](sdk/src/main/java/com/scanauth/sdk/internal/CanonicalUrl.kt) 与 [`RegisteredDomain.kt`](sdk/src/main/java/com/scanauth/sdk/internal/RegisteredDomain.kt)，唯一入口为 `CanonicalAddress.parse` / `matches`：

- C1 长度 1–2048，拒绝首尾空白与控制字符；
- C2 仅 `https`；`http` 仅允许 `localhost` / `127.0.0.1` / `[::1]`（联调）；
- C3 拒绝 userinfo、fragment；**查询串原样保留**（例如 `/dtm/ulr?ma=xxx`）；
- C4 host：IDNA→punycode、小写、去结尾点；IPv6 压缩小写并保留方括号；
- C5 去除默认端口 443/80；
- C6 路径：空→`/`、解码 unreserved、`%XX` 大写、合并重复 `/`、解析 `.`/`..`（不越根）、去尾斜杠（根除外）；
- C7 失败一律 `INSECURE_ADDRESS`。

比对（登录码只声明域名，路径不参与比较）：

- M1 取双方注册域名（PSL 子集推导：`dkn.example.com → example.com`），必须完全相等；
- M2 路径、scheme、端口均不参与登录码比对；提交目标固定使用绑定记录中的完整地址；
- M3 注册域名不同即不匹配，相似域名（`evil-example.com`、`example.com.evil.com`）一律视为不同域名；
- M4 不匹配时零出站请求。

**唯一实现**：绑定校验、登录比对、提交前复核全部复用同一份 `CanonicalAddress` / `RegisteredDomain`，代码中不存在后缀/通配/`contains` 判断。

### 6.2 绑定与登录载荷（§4.3 / §4.4）

绑定二维码（`t=totp-bind`）字段：

```
t / v / bid / iss / acc / sec / alg / dig / per / dom / path / iat / exp
```

- `dom`：提交域名（可以是子域名，如 `dkn.example.com`）；
- `path`：提交路径，保留查询串原样（如 `/dtm/ulr?ma=xxx`）；
- 完整提交地址由 `https://${dom}${path}` 构造并固化；解析阶段校验 `dom` 与 `path` 组合后的地址合法；
- **没有 `sig` / `kid`**，不做验签；信任决策来自用户在确认页核对 `dom` / `path`，以及 `exp` 过期校验。

登录二维码（`t=totp-login`）字段：

```
t / v / url / token / exp
```

- `url`：域名，**不带 scheme、端口与路径**；
- `token`：16 或 24 位会话标识（`[A-Za-z0-9_-]`）；
- `exp - now ≤ 60` 秒；
- 匹配时只比较 `url` 的注册域名与绑定 `dom` 的注册域名。

### 6.3 提交层（S1 / S11）

- `PinnedEndpoint` 构造函数私有，只能由 `SecureStore` 中已固化的地址创建；
- `Submitter.submitCode(pinned, token, code)` **没有 URL 参数**；
- 提交目标固定为绑定时的完整地址 `https://<dom><path>`，不使用登录二维码里的域名，也不改写为当前页面域名；
- 请求体 `{"code":"123456","token":"..."}`（不含 scan_token / account / device_id）；
- `instanceFollowRedirects = false`，禁止跟随 3xx；
- 不使用自定义 `TrustManager`，依赖系统 TLS；
- 不发送/保存 Cookie，`token` 不写日志；
- 401 统一映射为 `SERVER_REJECTED`，不依据响应体区分原因（S10）。

### 6.4 安全存储（S3）

`SecureStore`：

- Android Keystore AES-256-GCM 主密钥（alias `scan_totp_sdk_master_key`，不可导出）；
- `EncryptedSharedPreferences`（键 AES256_SIV / 值 AES256_GCM）；
- 账户列表序列化为单个加密 JSON（key `accounts_v3`）；
- `unbindAll` 同时删除 Keystore 主密钥；
- App 设置 `allowBackup=false`、`fullBackupContent=false`，不进入系统备份。

### 6.5 两类账户隔离（S13 / S14）

- SDK：`standardCodeFor` 对扫码型账户返回 `null`；扫码型动态码默认只在 `submitLogin` 内部计算并立即使用；
- 用户显式开启「显示扫码型账户的动态码」后，App 才调用 `protocolCodeFor` 展示/复制；关闭开关时立即返回 `null`，界面同步清空；
- App 默认不显示扫码型动态码，无复制入口；开启后仅展示与复制，扫码提交路径、候选匹配、提交目标完全不变；
- App/SDK 均**没有**备份、批量导入/导出或迁移入口；迁移仅在浏览器扩展提供（S14）；
- 单账户「导出二维码」是**屏幕展示**能力（`otpauthUriFor` → ZXing 本地渲染），与备份文件导出无关。

### 6.6 单账户二维码展示与防截屏

- SDK `otpauthUriFor(localId)` 只在内存中拼接 `otpauth://totp/...`，不写剪贴板、不写日志、不落盘；
- App 侧必须先通过 `BiometricPrompt`（或设备凭据）才允许进入二维码页；扫码型账户额外要求勾选风险确认；
- 二维码页对窗口设置 `FLAG_SECURE`（禁截屏/录屏/最近任务预览），页面销毁时清除；
- 默认显示 28×28 降采样再放大的模糊遮罩，点击后才渲染清晰位图；60 秒自动关闭并在 `onDispose` 回收 Bitmap；
- 页面无「复制密钥 / 复制链接」入口。

---

## 7. S1–S14 对照表

| 编号 | 要求摘要 | Android 端落实情况 |
| --- | --- | --- |
| S1 | 提交目标唯一来源 | `PinnedEndpoint` 只能由固化地址构造；`Submitter` 不接收 URL 参数；二维码地址仅参与比对 |
| S2 | 扫码地址仅用于比对 | `CanonicalAddress` + `RegisteredDomain` 只比较注册域名；0 候选立即回调失败，**零出站请求** |
| S3 | 密钥保护 | Keystore + EncryptedSharedPreferences；`SdkLog` 不输出 `sec`/`st`/动态码；密钥不写入剪贴板；绑定二维码仅展示一次 |
| S4 | 绑定完整性 | `BindingQrParser` 校验全部字段（含 `dom`/`path`）与 `exp`；失败不落库；无签名步骤 |
| S5 | 绑定信任来源 | 不预置公钥、不拉 well-known / JWKS；信任来自用户核对 `dom` / `path` 后的确认 |
| S6 | token 强度与时效 | `LoginQrParser` 校验 `token` 为 16 或 24 位 `[A-Za-z0-9_-]`，且 `exp` ≤60s；生成与绝对时钟由服务端负责 |
| S7 | 一次性与会话绑定 | 客户端不缓存/不复用 token；每次提交携带同一 `token`，成功与否都由服务端判定；跨会话由服务端拒绝 |
| S8 | 尝试次数与作废 | 服务端职责；客户端把 401 映射为 `SERVER_REJECTED`，提示重新扫码，不自动重试 |
| S9 | 时间窗与重放 | 按设备时间计算当前步长；不缓存动态码；`SubmitResult.serverTimeOffsetSeconds` 用于提示时钟偏差 |
| S10 | 错误统一 | 401 仅暴露统一失败码；App 不对 401 做原因区分 |
| S11 | 传输安全 | 强制 HTTPS（回环除外）；禁止重定向；`token`/`code` 只放在 JSON body；无 Cookie |
| S12 | 解绑与轮换 | `removeAccount` / `unbindAll` 删除本地密钥；App 不调用 revoke；不提供 sec 转换/导出入口 |
| S13 | 即时码隔离 | 默认：SDK 对扫码型返回 `null`、App 不展示不复制；用户显式开启「显示扫码型动态码」并完成本地认证后，才通过 `protocolCodeFor` 展示/复制，关闭即清空 |
| S14 | 备份与迁移作用域 | 移动端无备份/批量导入导出/迁移入口；单账户二维码为屏幕展示（`otpauthUriFor`，§15），不产出可分发文件 |

### 平台实现要点（原文档第 8 节）

| 要点 | 实现 |
| --- | --- |
| 强制 HTTPS | `network_security_config.xml` 默认禁明文；仅 `localhost/127.0.0.1` 例外；SDK 侧再次校验 |
| 禁止自定义 TrustManager | 全工程无 `TrustManager`/`HostnameVerifier` 自定义实现 |
| 禁止明文流量 | `usesCleartextTraffic="false"` |
| 密钥安全存储 | Keystore 主密钥 + EncryptedSharedPreferences |
| 禁止备份泄露 | `allowBackup=false`、`fullBackupContent=false` |
| 日志脱敏 | `SdkLog` 只输出阶段名；无 `Log.d(secret/code/token)` |
| 生物识别门禁 | `BiometricPrompt`（API 30+ 强生物识别 + 设备凭据，低版本弱生物识别） |
| 权限最小化 | 仅 CAMERA / INTERNET / USE_BIOMETRIC；相机可用 `required=false` |
| 剪贴板 | 标准型动态码可复制；扫码型默认不可复制，仅在设置开关开启后允许复制 |

---

## 8. 验证结果

| 检查项 | 命令 | 结果 |
| --- | --- | --- |
| SDK 单元测试 | `gradle :sdk:testDebugUnitTest` | **通过**：7 个测试类、93 个用例、0 失败 |
| App 扫码解码测试 | `gradle :app:testDebugUnitTest` | **通过**：2 个测试类、11 个用例、0 失败（含真实截样本 6 个） |
| 注册域名推导 | `RegisteredDomainTest` 6 个用例 | **通过**：`example.com` / `dkn.example.com` / `a.b.com.cn` / `co.uk` / `github.io` / localhost / IP / IDN / 相似域名 |
| 登录码匹配 | `LoginQrTest` + `CanonicalUrlTest` | **通过**：只比注册域名，相似与后缀伪装域名均拒绝 |
| 导出 URI 拼接 | `OtpauthUriTest` 中 7 个 `displayUri*` 用例 | **通过**：默认参数省略、非默认保留、label/issuer 编码、无 issuer 场景、round-trip |
| 防截屏 | 代码审查 + APK 反查 | `FLAG_SECURE` 仅在 `ExportQrScreen` 生命周期内加/清；页面无复制入口（截屏行为需真机复核） |
| App Debug 构建 | `gradle :app:assembleDebug` | **通过** |
| SDK Release / AAR / POM | `gradle :sdk:assembleRelease :sdk:publishReleasePublicationToMavenLocal` | **通过**，已产出 `scan-totp-sdk-1.0.0.aar` / `.pom` / `-sources.jar` |
| App Release（R8） | `gradle :app:assembleRelease` | **通过**（含 minify + resource shrink） |
| Release 签名 | `apksigner verify --verbose --print-certs` | **通过**：v1 / v2 / v3 均为 `true`，1 个签名者 `CN=Scan TOTP Dev` |
| APK 元数据 | `aapt2 dump badging` | `name='com.scanauth.app' versionCode='1' versionName='1.0.0'`，`minSdk 23` / `targetSdk 35` |
| APK 架构 | 解包检查 `lib/` | universal：`arm64-v8a` / `armeabi-v7a` / `x86` / `x86_64` 全含 |
| 一键打包脚本 | `package.ps1 -Target all` | **通过**，`dist/` 下 5 个产物齐全（签名 APK + AAR / POM / sources / module） |
| 真机 / 模拟器运行 | — | **未验证**（本机无已连接设备，也无 AVD） |

单元测试覆盖：

- RFC 6238 官方测试向量（SHA1 / SHA256 / SHA512）；
- §7.4 地址判定示例（大小写、默认端口、尾斜杠、子域名、IDNA、尾点、百分号归一、userinfo、回环 HTTP、查询串保留）；
- 注册域名推导：普通域名、多级公共后缀、托管平台私有后缀、localhost / IPv4 / IPv6、IDN、相似域名；
- 绑定二维码：有效载荷、`dom`/`path` 组合、查询串保留、未知字段（含已删除的 `sig`/`kid`）忽略、类型/版本/过期、小写 `sec`、不安全地址、控制字符、`digits=7`；
- 登录二维码：16/24 位 token、纯域名、拒绝 scheme/路径/端口、过期、`>60s`、类型/版本、非法 token；
- `otpauth` U1–U9：全参数、大小写算法、label issuer、issuer 冲突、重复参数、未知参数、`hotp`/`counter`、非法 digits/period、round-trip；
- 单账户导出 URI（`omitDefaults`）：默认值省略、非默认值保留、只偏离一项时其余省略、中文/`@`/空格编码、无 issuer、round-trip 共 7 例；
- TOTP 自定义参数（8 位、SHA256/512、非 30 秒周期）。

> 说明：本机工程路径含中文时，Android Gradle Plugin 的单测任务会出现 `ClassNotFoundException`；
> 已在 ASCII 路径副本下完成全部验证。交付源码本身不受影响。

---

## 9. 已知局限与未覆盖项

1. **未做真机/模拟器运行验证**：本机没有连接设备，也没有可用 AVD。相机、Keystore、生物识别、导航等运行时行为需要在设备上复验。
2. **签名材料不入库**：`android/keystore/` 与 `keystore.local.properties` 已被忽略，需本地自备；缺失时 release 构建直接失败，不提供未签名或 debug 兜底。
3. **绑定二维码不带签名**：SDK 不预置公钥、不拉取 well-known / JWKS，也不做 TOFU 固定；防钓鱼依赖用户核对确认页展示的 `dom` / `path`。若后续规范恢复签名，需要重新引入验签与信任根配置。
4. **无多语言**：界面文案仅中文；未提供 `values-en` 等资源。
5. **不含批量备份 / 导入 / 导出**：这是规范 S14 的强制要求（迁移只在浏览器扩展提供）。单账户「导出二维码」只是屏幕展示，不产出可分发文件。
6. **App 不持有网页会话 Cookie**：提交成功后需回到浏览器完成登录；SDK 也不处理跨会话状态。
7. **长期共享密钥**：协议账户的 `sec` 长期有效，轮换需服务端重新绑定并更换 `bid`（规范 §12）；客户端不提供轮换入口。
8. **6 位码空间较小**：安全性依赖服务端限流、失败计数作废（S8）与时间窗重放防护（S9）。
9. **仅 `http` 回环地址可用明文**：`localhost`/`127.0.0.1`/`[::1]` 专为本地联调保留，正式环境应全部使用 HTTPS。
10. **`FLAG_SECURE` 仅用于二维码展示页**：标准型动态码列表仍允许截图与复制（用户主动操作）；单账户导出二维码页面禁截屏，并在关闭时回收 Bitmap。
11. **相机与生物识别缺少自动化测试**：相关逻辑依赖设备能力，当前仅通过编译与代码审查验证。
