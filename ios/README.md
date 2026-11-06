# iOS 端：扫码增强型 TOTP 认证器

本目录是「扫码增强型 TOTP 认证协议 v1（TOTPSCAN/v1）」的 iOS 实现，包含：

1. `TotpScan/`：可直接侧载的 SwiftUI 正式 App（中文界面）。
2. `TotpScanSDK/`：可独立集成的 Swift Package，提供标准 TOTP、二维码解析、注册域名比对、Keychain 存储与受控提交。
3. `TotpScan.xcodeproj`：App 工程（iOS 16+），通过本地 Swift Package 引用 SDK。
4. `scripts/`：未签名 IPA / 签名 IPA / SDK 单测脚本。
5. `tools/demo-keys/`：安全公告。原演示私钥已删除并被视为泄露，目录内不含任何密钥。

契约来源：`../spec/totp-scan-v1.md`、`../spec/schemas/*.json`、`../spec/openapi.yaml`。本目录不修改 `spec/` 与 `server/`。

> 说明：绑定/登录载荷以本文件第 9 节为准（`dom` + `path` / `url` + `token` + `exp`），
> 协议不携带签名，也不再使用 `sig` / `kid` / 信任根。

---

## 1. 两类账户

| | 标准 TOTP 账户 | 扫码绑定账户（增强型） |
| --- | --- | --- |
| 创建方式 | `otpauth://totp` 导入 / 手动输入 | 扫描 `totp-bind` 二维码（`dom` + `path`） |
| 提交地址 | 无 | 绑定后固化为 `https://<dom><path>`，存 Keychain，不可被二维码覆盖 |
| 动态码 | 显示 + 倒计时环 + 点击复制 | **默认不显示**；可在设置中显式开启（需认证 + 风险确认） |
| 导出 | 详情页「导出二维码」，认证后屏幕展示 | 同样支持，但需额外确认「防钓鱼优势失效」 |
| 扫码登录 | 不参与 | 唯一参与者 |
| 列表标识 | `标准 TOTP` 标签 | `扫码提交` 标签 |

两类账户可以并存。默认情况下协议绑定账户的动态码只在 SDK 内部计算并直接提交，SDK 的 `code(for:)` 对绑定账户返回 `boundAccountCodeNotAvailable`；只有调用显式的 `revealedCode(for:)` 才能取得其动态码。

扫码登录按注册域名自动选账户（不使用“当前选中账户”）：

1. 解析登录二维码，得到 `url`（域名）与 `token`（16 或 24 位会话标识）。
2. 用 `url` 推导注册域名（PSL 级 eTLD+1），与本地**所有**已确认绑定账户的注册域名比较；相等即为候选。
3. 0 个 → 本地终止，**零出站请求**（没有 DNS、没有 HTTP）。
4. 1 个 → 直接进入确认与提交。
5. 多个（同注册域名）→ 只展示这些候选让用户选择；不跨不同注册域名混列；每个候选始终提交到**它自己的** `https://<dom><path>`。
6. 登录二维码中的域名永远只用于比对；提交目标固定为绑定时的完整地址，路径只使用绑定的 `path`。

---

## 2. 目录结构

```
ios/
├── TotpScanSDK/
│   ├── Package.swift
│   ├── Sources/TotpScanSDK/
│   │   ├── Public/
│   │   │   ├── TOTP.swift                 RFC 6238 计算（SHA1/256/512，6/8 位，任意步长）
│   │   │   ├── Base32.swift               RFC 4648 Base32
│   │   │   ├── OTPAuthURI.swift           otpauth://totp 解析与生成
│   │   │   ├── Models.swift               账户摘要、绑定/登录上下文、来源
│   │   │   ├── TotpScanClient.swift        唯一编排入口
│   │   │   ├── AccountStore.swift          Keychain 存储
│   │   │   ├── DeviceAuthenticator.swift   Face ID / Touch ID / 设备密码门禁
│   │   │   ├── QRPayloadInspector.swift    二维码类型分流
│   │   │   ├── SDKLog.swift                固定字段日志（不含敏感数据）
│   │   │   └── TotpScanError.swift         统一中文错误
│   │   └── Internal/
│   │       ├── CanonicalURL.swift          地址规范化与注册域名推导入口
│   │       ├── RegistrableDomain.swift     PSL 级后缀表（dkn.example.com → example.com）
│   │       ├── Punycode.swift              IDNA ToASCII（RFC 3492）
│   │       ├── QRJSON.swift                严格 JSON 解析
│   │       ├── BindingQRCode.swift         totp-bind 解析（dom + path，无签名）
│   │       ├── LoginQRCode.swift           totp-login 解析（url + token + exp）
│   │       ├── StoredAccount.swift         Keychain 记录与校验
│   │       ├── PinnedEndpoint.swift        唯一提交目标
│   │       └── HTTPSubmitter.swift         禁止重定向、无 Cookie、TLS 1.2+
│   └── Tests/TotpScanSDKTests/
│       ├── TOTPRFC6238Tests.swift          RFC 测试向量
│       ├── Base32Tests.swift
│       ├── CanonicalURLTests.swift         规范化与非法地址
│       ├── RegistrableDomainTests.swift    PSL 后缀表与 IP/localhost
│       ├── OTPAuthURITests.swift
│       ├── BindingQRCodeTests.swift        绑定载荷 dom/path、提交地址推导、过期
│       ├── LoginQRCodeTests.swift          登录载荷 url/token/exp、裸域名校验
│       └── TotpScanClientTests.swift       候选 0/1/多、去重、码隔离、备注、otpauth 导出
├── TotpScan/
│   ├── App/                                入口、AppModel、Tab 根视图
│   ├── Views/                              账户、详情、绑定、登录、扫码、设置
│   │   ├── ExportQRCodeView.swift          单账户 otpauth 二维码（模糊遮罩、60 秒自动关闭）
│   │   └── BoundCodeRiskView.swift         显示扫码型账户动态码的风险确认
│   ├── Services/                           相机、图片二维码、剪贴板、离线二维码生成
│   └── Resources/                          Info.plist、Assets
├── TotpScan.xcodeproj/
├── scripts/
└── tools/demo-keys/                       仅安全公告 README，无密钥文件
```

---

## 3. 构建与侧载

### 3.1 环境要求

- macOS 13+ 与 Xcode 15+（Swift 5.9）。
- 构建 App：iOS 16.0+ 真机或模拟器。
- 运行 SDK 单测：`swift test`（macOS 主机即可，不需要模拟器）。

### 3.2 在 Xcode 中运行

```bash
open ios/TotpScan.xcodeproj
```

选择 `TotpScan` scheme 与真机，配置自己的 Team（`Signing & Capabilities`）后运行。工程已通过 `XCLocalSwiftPackageReference` 引用本地 `TotpScanSDK`，无需额外拉取依赖。

### 3.3 构建未签名 IPA

```bash
chmod +x scripts/*.sh
./scripts/build-unsigned-ipa.sh
# 产物：build/TotpScan-unsigned.ipa
```

脚本使用 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` 编译，打包 `Payload/TotpScan.app`。

### 3.4 构建签名 IPA

```bash
TEAM_ID=你的TeamID BUNDLE_ID=com.example.totpscan ./scripts/build-signed-ipa.sh
```

需要 Xcode 已登录开发者账号并具备有效证书/描述文件。`METHOD` 可设为 `development` / `ad-hoc` / `app-store`。

### 3.5 可行安装路径与真实限制

| 路径 | 可行性 | 关键限制 |
| --- | --- | --- |
| **TrollStore** 安装未签名 IPA | 仅特定系统版本 | 仅在 TrollStore 官方支持的系统上可用（常见为 iOS 14.0–16.6.1、16.7 RC、17.0；以官方支持列表为准）。不支持的系统无法用未签名 IPA 安装。 |
| **AltStore / SideStore** 重签安装 | 需要电脑或配对 | 免费 Apple ID 签发的证书 **7 天过期**，需每 7 天刷新；同时最多 3 个自签 App；每 7 天最多注册 10 个 App ID；AltStore 需要同一网络下的 AltServer，SideStore 需要配对文件。 |
| **付费开发者账号** | 需要年费 | 开发/Ad Hoc 证书有效期约 1 年；Ad Hoc 每类设备最多 100 台；TestFlight 构建 90 天有效。 |
| **Xcode 直接安装** | 需要 Mac | 免费账号同样是 7 天有效期；付费账号 1 年。 |
| **未签名 IPA 直接安装** | **不可行** | 普通非越狱设备会拒绝安装未签名或签名无效的包。 |

其他实际情况：

- iOS 16+ 使用开发签名安装时，需要在「设置 → 隐私与安全性 → 开发者模式」开启开发者模式并重启设备。
- 首次打开自签 App 需要在「设置 → 通用 → VPN 与设备管理」中信任对应开发者证书。
- 重签时必须保证 `PRODUCT_BUNDLE_IDENTIFIER` 与描述文件中的 App ID 一致；修改 bundle ID 会导致 Keychain 数据被视为新 App。
- App 未做 App Store 分发配置（无推送、无 Associated Domains），侧载即可用。

---

## 4. SDK 集成

### 4.1 添加依赖

Xcode：`File → Add Package Dependencies… → Add Local…`，选择 `ios/TotpScanSDK`。

`Package.swift`：

```swift
.package(path: "../ios/TotpScanSDK")
```

### 4.2 标准 TOTP（可脱离绑定单独使用）

```swift
import TotpScanSDK

// 解析 otpauth://totp
let parsed = try OTPAuthURI.parse("otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA256&digits=8&period=60")

// 直接计算
let parameters = try TotpParameters(algorithm: parsed.parameters.algorithm,
                                    digits: parsed.parameters.digits,
                                    period: parsed.parameters.period)
let code = TOTP.code(secret: parsed.secret, at: Date(), parameters: parameters)

// 生成 otpauth URI
let uri = OTPAuthURI.build(issuer: "Example",
                           account: "alice@example.com",
                           secret: parsed.secret,
                           parameters: parameters)
```

支持的参数：`SHA1/SHA256/SHA512`、`6/8` 位、`1...3600` 秒步长；`hotp`、重复参数、issuer 冲突、`counter` 一律拒绝。

### 4.3 账户与扫码

```swift
let client = TotpScanClient()

// 标准账户
let standard = try client.addStandardAccount(
    issuer: "Example", account: "alice@example.com",
    secretBase32: "JBSWY3DPEHPK3PXP", digits: 6, period: 30
)
let current = try client.code(for: standard.id)   // 仅标准账户可用

// 绑定：preview 中的 submitURL 为 https://<dom><path>
let preview = try client.previewBinding(qrText: scannedText)
// 把 preview.submitURL、preview.registrableDomain、preview.submitPath 展示给用户确认
let bound = try client.commitBinding(preview, displayName: "工作账号")
try await client.confirmBinding(accountID: bound.id)

// 扫码登录
do {
    let approval = try client.prepareLogin(qrText: loginText)
    let outcome = try await client.submit(approval)
} catch TotpScanError.multipleMatchingAccounts(let candidates) {
    // 只在同注册域名的 candidates 内选择，并把所选账户 id 传回：
    let approval = try client.prepareLogin(qrText: loginText,
                                           preferredAccountID: chosen.id)
    _ = try await client.submit(approval)
} catch TotpScanError.noMatchingAccount {
    // 本地终止：SDK 未发起任何网络请求
}
```

关键公开 API：

- `TOTP` / `TotpParameters` / `OTPAuthURI`：标准 TOTP。
- `TotpScanClient.loadAccounts() / code(for:)`：`code(for:)` 对绑定账户抛错。
- `previewBinding / commitBinding / confirmBinding`：绑定。
- `prepareLogin / submit`：候选反查与提交；`submit` 之前会从 Keychain 重新读取固化地址并再次核对注册域名。
- `renameAccount(id:displayName:)`：本地备注（≤64 字符，NFC，去控制字符，可清空）。
- `deleteAccount / clearAllAccounts`。
- `otpauthURI(for:)`：生成单账户标准 `otpauth://totp/...` 明文 URI，仅内存拼接；包含密钥，调用方必须先做本地认证，并且只能用于屏幕展示。
- `revealedCode(for:)`：**显式高风险 API**，允许读取扫码型账户的动态码；只在用户主动开启“显示扫码型账户动态码”后调用。默认的 `code(for:)` 仍然拒绝绑定账户。

### 4.4 存储与网络约束

- Keychain：`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`、`kSecAttrSynchronizable=false`、`kSecUseDataProtectionKeychain=true`。
- 提交：仅 HTTPS（`http` 仅用于 localhost/127.0.0.1/[::1] 开发）、禁止重定向、无 Cookie、无缓存、15 秒超时、TLS 1.2+。
- 未实现“信任所有证书”的 `URLSessionDelegate`，使用系统默认 ATS 校验。
- 日志：`SDKLog` 只记录固定事件名，不接收自由文本，不包含密钥、会话 token、动态码。

### 4.5 单账户导出与“显示扫码型账户动态码”

- 导出入口位于账户详情页。打开前必须通过本地认证；扫码型账户还要先确认「导出后防钓鱼优势失效」。
- 导出内容为标准明文 `otpauth://totp/...`（不加密、不混淆、不加包装），任何标准认证器都可导入。
- 二维码用 Core Image 在本地生成，只用于屏幕展示：不提供复制密钥/链接，不写剪贴板、日志或文件。
- 默认带模糊遮罩，点击后显示；60 秒自动关闭并清空画布。iOS 无法阻止系统截图，界面会明确提示这一点。
- 设置页「安全」分组提供「显示扫码型账户的动态码」开关，默认关闭，状态存 `UserDefaults`。开启需要本地认证 + 勾选风险确认；开启后扫码型账户显示动态码与倒计时并可复制，扫码提交路径不变；关闭立即隐藏并清空。

---

## 5. Info.plist 权限项

| Key | 文案用途 |
| --- | --- |
| `NSCameraUsageDescription` | 扫描绑定/登录二维码 |
| `NSFaceIDUsageDescription` | 提交动态码前的身份确认 |
| `NSPhotoLibraryUsageDescription` | 相机不可用时从相册识别二维码 |
| `NSAppTransportSecurity` | `NSAllowsArbitraryLoads=false`，`NSAllowsLocalNetworking=true` |
| `UISupportedInterfaceOrientations` | 仅竖屏 |
| `UILaunchScreen` | 使用 `LaunchBackground` 颜色资源 |

---

## 6. S1–S13 对应实现

| 要求 | 实现位置 |
| --- | --- |
| **S1** 提交目标唯一来源 | `PinnedEndpoint` + `HTTPSubmitter`；`TotpScanClient.submit` 提交前从 Keychain 重读 `pinnedSubmitURL`；公开 API 不接受 URL |
| **S2** 扫码域名仅用于比对 | `RegistrableDomain` + `prepareLogin`；不计算码、不发请求；不提供“继续提交”入口 |
| **S3** 密钥保护 | `AccountStore` 仅写 Keychain；`SDKLog` 固定事件；绑定账户密钥/动态码默认不展示；导出二维码只在认证后屏幕展示且 60 秒自动清空；剪贴板只用于动态码且 60 秒过期 |
| **S4** 绑定完整性 | `BindingQRCode.parse` 校验 `t/v/bid/iss/acc/sec/alg/dig/per/dom/path/iat`，`dom` 必须是裸域名、`path` 必须以 `/` 开头且无 `#`/空白；失败不落盘 |
| **S5** 公钥/签名 | 协议不携带签名，不预置公钥、不读取 `trust-anchors.json`、不访问 well-known/JWKS；该项在本实现中不再适用 |
| **S6** token 强度与时效 | App 侧校验 `token` 为 16 或 24 位 `[A-Za-z0-9_-]`、`exp - now ≤ 60`；有效期由服务端权威判定 |
| **S7** 一次性与会话绑定 | App 不缓存/复用 `token`；每次扫码重新解析，提交后丢弃 |
| **S8** 尝试次数与作废 | 由服务端执行；App 不重试同一个 token，失败后要求重新扫码 |
| **S9** 时间窗与重放 | App 使用 RFC 6238 当前步计算；服务端负责 ±1 窗口与重放记录 |
| **S10** 错误统一 | App 不解析具体失败原因，统一展示“未能完成扫码登录”；服务端错误见 §8 |
| **S11** 传输安全 | `HTTPSubmitter`：HTTPS、JSON body、禁止重定向、无 Cookie；token/动态码不进 URL、不写日志 |
| **S12** 解绑与轮换 | App 删除本机记录即不再参与候选；服务端撤销接口由管理员调用（App 不保存 admin token） |
| **S13** 增强型账户即时码隔离 | 默认路径：`code(for:)` 对 `kind == .bound` 抛 `boundAccountCodeNotAvailable`，界面不显示码。仅当用户在设置中通过本地认证 + 风险确认开启开关后，App 才使用 `revealedCode(for:)`；关闭开关立即清空。导出二维码必须额外确认「防钓鱼优势失效」，且不提供复制密钥/链接 |

---

## 7. 测试

```bash
./scripts/run-sdk-tests.sh
# 或
swift test --package-path TotpScanSDK
```

覆盖：

- RFC 6238 官方向量（SHA1/SHA256/SHA512）。
- Base32 宽松/严格解码与往返。
- 地址规范化、非法地址、IPv4/IPv6/IDN。
- 注册域名推导（`dkn.example.com → example.com`、多段后缀、localhost/IP）。
- `otpauth://` 的 U1–U9 边界。
- 绑定二维码字段校验（缺 `dom` / `path` 拒绝）、提交地址推导、过期。
- 登录二维码 `url` 裸域名校验、token 16/24 位、`exp` 超过 60 秒拒绝。
- 候选 0/1/多、同域多账户选择、不同注册域名不混列、跨域拒绝、A3 去重、标准账户与未确认账户不进入候选、绑定账户码隔离、备注规范化与重复绑定拒绝。
- 单账户 otpauth 导出（标准/绑定均可往返解析）、默认 API 仍拒绝绑定账户码、显式 `revealedCode` 可用。

---

## 8. 已知局限

1. **协议不签名**：绑定二维码的可信度完全依赖扫码时的物理/信道安全与用户确认展示的 `dom`、`path`、完整提交地址；二维码被替换时 SDK 无法从密码学上识别。
2. **无法防御“真实域名中继钓鱼”**：注册域名比对只能证明登录二维码声称的站点与本地绑定一致，不能证明用户当前浏览器就是该站点。攻击者若在自己的真实域名下架设中继页面，仍可能诱导提交。协议本身不提供 WebAuthn 级别的抗钓鱼保证。
3. **相似域名只提示不拦截**：注册域名不同即不匹配；界面上的相似域名提示仅用于提醒用户，不作为拦截依据。
4. **提交体固定为 `{code, token}`**：不再上送 `scan_token` / `account` / `device_id`；服务端需按 `token` 定位会话。
5. **时间偏差检测依赖服务端 `/healthz`**：只有存在“已确认绑定账户”时才能测量；标准 TOTP 账户没有服务端参照，只显示设备时间与通用建议。
6. **不提供备份文件**：`ThisDeviceOnly` Keychain 在卸载 App 或更换设备后不可恢复。账户详情页只提供单账户 otpauth 二维码的屏幕展示（不是备份文件），不提供复制密钥/链接，也不写剪贴板或文件；iOS 无法阻止用户对屏幕截图，界面只能提示风险。
7. **App 不执行服务端解绑**：删除本机账户只清除本地数据；服务端 `revoke` 需要管理员 token，App 不保存该凭据。
8. **模拟器无相机**：扫码页会显示“相机不可用”，可用相册图片或粘贴二维码文本继续调试。
9. **未做 App Store 分发与公证**：无推送、无后台任务、无 Associated Domains；侧载可用。
10. **界面仅中文**：未提供本地化资源文件。
11. **本机未实际编译验证**：当前交付环境为 Windows，没有 macOS/Xcode，`swift test` 与 `xcodebuild` 未执行；工程与源码已按可编译结构组织，需在 macOS 上首次构建确认。

---

## 9. 载荷格式与匹配规则

### 9.1 绑定二维码 `totp-bind`

```json
{
  "t": "totp-bind",
  "v": 1,
  "bid": "b_0123456789abcdefghijkl",
  "iss": "Example Corp",
  "acc": "alice@example.com",
  "sec": "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP",
  "alg": "SHA1",
  "dig": 6,
  "per": 30,
  "dom": "dkn.example.com",
  "path": "/dtm/ulr?ma=xxx",
  "iat": 1700000000,
  "exp": 1800000000
}
```

- `dom` 必须是裸域名（不带 scheme、路径、查询串、端口、userinfo）。
- `path` 必须以 `/` 开头，保留查询串原样，不允许 `#` 与空白。
- 提交目标 = `https://<dom><path>`，原样写入 Keychain。
- 没有 `sig` / `kid`，也没有任何签名校验。

### 9.2 登录二维码 `totp-login`

```json
{
  "t": "totp-login",
  "v": 1,
  "url": "login.example.com",
  "token": "0123456789abcdef",
  "exp": 1700000030
}
```

- `url` 是裸域名（不带 scheme 与路径）。
- `token` 为 16 或 24 位 `[A-Za-z0-9_-]`。
- `exp` 为 Unix 秒；本地额外限制 `exp - now ≤ 60`。

### 9.3 匹配与提交

1. `RegistrableDomain.of(login.url) == RegistrableDomain.of(binding.dom)`；例如 `login.example.com` 与 `dkn.example.com` 都得到 `example.com`。
2. 路径**不**参与匹配，提交只使用绑定时的 `path`。
3. 命中 1 个账户直接提交；同注册域名多个账户由用户选择；0 个本地终止且零出站。
4. 提交：`POST https://<dom><path>`，请求体 `{"code":"123456","token":"..."}`。
