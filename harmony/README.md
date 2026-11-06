# 扫码增强型 TOTP 认证器 · 鸿蒙端（HarmonyOS / ArkTS）

本目录是「扫码增强型 TOTP 认证」的鸿蒙端实现，包含两个可独立使用的部分：

- `entry/`：面向真实用户的 ArkTS/ArkUI 应用（Stage 模型）。
- `totpscan/`：可集成的 HAR 模块，同时提供 TOTPSCAN/v1 扫码提交能力与标准 RFC 6238 TOTP 能力。

契约来源为仓库根目录的 `spec/totp-scan-v1.md`、`spec/schemas/*.json`、`spec/openapi.yaml`。本目录只实现客户端，不包含服务端，也不修改 `spec/`。

> 作用域说明：按规范 S14 与产品范围修正，账户**备份 / 导入 / 导出文件 / 迁移**仅由浏览器扩展提供。本 App 与 HAR 不提供任何备份文件能力。App 提供的是**单账户 otpauth 二维码的屏幕展示**（仅供其他认证器扫码导入，不生成文件、不写剪贴板），见 §3.5。

---

## 1. 目录结构

```
harmony/
├── AppScope/                       应用级配置（bundleName、图标、名称）
├── build-profile.json5             产品与模块构建配置
├── hvigorfile.ts                   appTasks
├── oh-package.json5                工程级依赖
├── hvigor/hvigor-config.json5      hvigor 配置
├── hvigorw / hvigorw.bat           一键构建转发脚本
├── scripts/
│   ├── build.ps1                   Windows 构建入口
│   └── build.sh                    macOS / Linux 构建入口
├── entry/
│   ├── build-profile.json5
│   ├── hvigorfile.ts               hapTasks
│   ├── oh-package.json5            依赖 totpscan
│   └── src/main/
│       ├── module.json5            EntryAbility、权限
│       ├── ets/
│       │   ├── entryability/EntryAbility.ets
│       │   ├── common/AppContext.ets       TotpScanClient 单例与初始化重试
│       │   ├── common/ExportGrant.ets      导出二维码的一次性内存授权
│       │   ├── common/Ui.ets               toast、错误文案、host 展示
│       │   ├── components/QrScanner.ets    Scan Kit + 系统扫码兜底
│       │   └── pages/
│       │       ├── Index.ets               账户列表：两类账户、标准码、倒计时
│       │       ├── Login.ets               扫码登录、候选选择、提交反馈
│       │       ├── BindScan.ets            绑定扫码与预览
│       │       ├── BindConfirm.ets         地址确认、备注、写入安全存储
│       │       ├── AddAccount.ets          添加入口
│       │       ├── StandardAdd.ets         标准账户：otpauth 导入 / 手动录入
│       │       ├── AccountDetail.ets       账户详情、导出二维码、重命名、删除、重试确认
│       │       ├── ExportQr.ets            单账户 otpauth 二维码（隐私模式 + 模糊遮罩）
│       │       └── Settings.ets            生物识别、动态码显示开关、校时、已绑定站点、清空数据
│       └── resources/                      字符串、颜色、图标、路由表
└── totpscan/                       HAR
    ├── Index.ets                   公开 API 出口
    ├── oh-package.json5
    └── src/
        ├── main/ets/
        │   ├── client/             TotpScanClient、配置
        │   ├── core/               Base32、Base64Url、Bytes、JSON、错误
        │   ├── totp/               TotpCalculator、TotpOptions、OtpauthUri
        │   ├── qr/                 BindingPayload、LoginPayload
        │   ├── security/           CanonicalUrl、RegisteredDomain、PinnedUrl、
        │   │                       AddressMatcher、CandidateResolver、PinnedEndpoint、生物识别
        │   ├── store/              Vault、VaultStore（Asset Store）
        │   ├── clock/              ClockService
        │   ├── net/                HttpClient、Submitter
        │   └── model/              Types、Models
        └── ohosTest/               Hypium 单元测试（见 §8）
```

---

## 2. 环境与构建

要求：DevEco Studio 5.0（HarmonyOS NEXT，`compatibleSdkVersion` 为 `5.0.0(12)`）、API 12 SDK、Node.js（DevEco 自带即可）。

### 2.1 DevEco Studio

1. 用 DevEco Studio 打开 `harmony/` 目录，等待自动 Sync。
2. 配置签名（`Project Structure → Signing Configs`，可使用自动签名）。
3. `Build → Build Hap(s)/APP(s) → Build Hap(s)`。
4. 产物通常在 `entry/build/default/outputs/default/`。

### 2.2 命令行

```powershell
# Windows（PowerShell 或 cmd）
cd harmony
hvigorw.bat assembleHap

# 或直接调用脚本
powershell -ExecutionPolicy Bypass -File scripts\build.ps1
```

```bash
# macOS / Linux
cd harmony
./hvigorw assembleHap
# 或
bash scripts/build.sh
```

脚本行为：

- 优先使用显式传入的 `-HvigorPath` / `HVIGOR_PATH`；
- 其次查找 DevEco Studio 自带的 `tools/hvigor/bin/hvigorw(.bat)`；
- 再次使用项目内 `hvigor/hvigor-wrapper.js`（若存在）；
- 都找不到时打印明确提示并以非 0 退出，不会静默成功。

> 本仓库提交的 `hvigorw` / `hvigorw.bat` 是转发脚本。DevEco Studio 打开工程后，可能会用官方 wrapper 覆盖这两个文件，这是预期行为。

---

## 3. 应用行为

### 3.1 两类账户

| 类型 | 来源 | 界面 | 是否参与扫码提交 |
| --- | --- | --- | --- |
| 标准 TOTP | `otpauth://totp` 导入、手动录入 | 显示 6/8 位动态码、倒计时环；点击复制；时间偏差提示 | 否 |
| 增强型（扫码） | `totp-bind` 二维码绑定 | 默认**不显示、不复制**动态码；只显示站点、绑定状态与「扫码提交」。可在设置中显式开启显示（默认关闭，见 §3.6） | 是 |

标准账户完全遵循 RFC 6238：`algorithm` 支持 SHA1/SHA256/SHA512，`digits` 支持 6/8，`period` 支持 1–3600 秒，均按 `otpauth` 参数工作。

### 3.2 绑定流程

1. 首页「添加」→「扫码绑定」。
2. `BindScan` 扫码后调用 `prepareBinding`：解析紧凑 JSON，校验 `dom`（提交域名）与 `path`（提交路径，含查询串），在本地拼出 `https://<dom><path>`。**不做签名与验签**。失败时不写入任何字段、不发网络请求。
3. `BindConfirm` 展示注册域名（PSL 级，例如 `dkn.example.com` → `example.com`）、提交路径、完整提交地址、算法、位数、步长、有效期；与已有站点相似时只做提示，不拦截。
4. 用户可填写本地备注（≤64 字符，NFC 规范化后保存；**不进二维码、不上送服务器**）。
5. 确认后写入 Asset Store，并调用 `/totp/v1/bindings/{bid}/confirm` 做可选绑定确认。确认失败时账户仍保留在本地，可在详情页重试。

### 3.3 扫码登录（按注册域名选账户）

1. `Login` 扫码 → `prepareLogin` 解析 `totp-login`：`url`（域名，不带 scheme 与路径）、`token`（16 或 24 位会话标识）、`exp`（`exp - now ≤ 60`）。
2. 由 `url` 推导 PSL 级注册域名，只保留注册域名相同的已确认绑定：
   - 0 个候选：本地终止，界面明确提示「未发送任何请求」，零出站；
   - 1 个候选：自动选中；
   - 多个候选：只在同一注册域名内单选，**不会跨不同域名混列**。
3. 生物识别（可在设置中关闭）→ 计算动态码 → POST 到绑定时的完整提交地址 `https://<dom><path>`。
4. 请求体固定为 `{"code":"123456","token":"..."}`，不再发送 `scan_token`、`account` 或 `device_id`；登录二维码的 `url` 只用于选账户，永远不是提交目标。

### 3.4 异常与空态

- 相机权限被拒：提示去系统设置授权，并提供系统扫码兜底。
- 相机不可用：切换到系统扫码能力，不阻塞流程。
- 安全存储不可用：首页显示错误与「重试」，不降级到明文存储。
- 二维码过期、域名不匹配、网络失败、限流：均有独立中文文案。
- 增强型账户离线不可用；标准账户离线仍可生成动态码。

### 3.5 单账户导出 otpauth 二维码（屏幕展示）

入口在账户详情页「导出二维码」，标准账户与增强型账户都可用：

1. **先做本地身份验证**（生物识别，设备未录入时回退锁屏密码）；未通过不进入导出页。
2. 增强型账户额外弹出确认，明确「导出后该账户的防钓鱼优势失效，任何扫码者都能独立生成动态码」。
3. 校验通过后只向 `ExportQr` 传入 `localId`（不传密钥或 URI）；URI 在页面内即时拼接：
   `otpauth://totp/{issuer}:{account}?secret=...&algorithm=...&digits=...&period=...&issuer=...`
   （label 的两部分分别做 URI 编码，参数取账户真实值）。
4. 二维码由系统 Scan Kit 的 `scanBarcode.generateBarcode` **离线生成**（本地系统能力，不联网、不做运行时下载）。
5. 页面开启窗口隐私模式（`setWindowPrivacyMode(true)`）防截屏；二维码默认模糊遮罩，点击后显示，60 秒自动关闭并释放位图。
6. **只展示二维码**：不提供「复制密钥 / 复制链接」，不写剪贴板、不写日志、不落盘。生成后立即丢弃内存中的 URI 字符串。

### 3.6 「显示扫码型账户的动态码」开关（默认关闭）

位置：设置页「安全」分组。

- 默认 `false`，状态保存在加密保险库的 `settings.revealScanCodes`。
- 开启流程：风险说明 + 勾选确认 → 本地身份验证（生物识别/锁屏密码）→ 写入设置。任一环节失败都保持关闭。
- 开启后：首页与账户详情显示扫码型账户的六位码、倒计时环，可点击复制；扫码提交路径完全不变。
- 关闭：界面立即隐藏，下一次取码会被 HAR 拒绝（`SCAN_CODE_HIDDEN`）。

---

## 4. HAR 集成

### 4.1 声明依赖

在宿主模块的 `oh-package.json5` 中：

```json5
{
  "dependencies": {
    "totpscan": "file:../totpscan"
  }
}
```

也可以把 `totpscan/` 复制进宿主工程后使用相对路径。HAR 不依赖页面或 Ability 生命周期。

### 4.2 初始化

```ts
import { TotpScanClient } from 'totpscan';

const client = TotpScanClient.create(); // 可传入 TotpScanConfig
await client.init();                     // 读取/创建加密保险库
```

### 4.3 标准 TOTP

```ts
import { OtpauthUri, TotpCalculator } from 'totpscan';

// 解析 otpauth URI（拒绝 hotp、重复参数、issuer 冲突、非法 secret）
const input = OtpauthUri.parse(uriText);
const account = await client.addStandardAccount(input);

// 或手动录入
await client.addStandardAccount({
  issuer: 'Example',
  account: 'alice@example.com',
  secretBase32: 'JBSWY3DPEHPK3PXP',
  algorithm: 'SHA1',
  digits: 6,
  period: 30,
  note: '工作账号'
});

const snapshot = client.code(account.localId); // 仅标准账户可用
```

底层也可完全脱离客户端使用：

```ts
const code = TotpCalculator.generateBase32(secretBase32, Date.now(), {
  algorithm: 'SHA256',
  digits: 8,
  period: 60
});
```

### 4.4 增强型账户绑定与登录

```ts
// 绑定
const preview = await client.prepareBinding(qrText);
// preview 不含密钥，可安全展示
const outcome = await client.confirmBinding(preview.previewId, '办公室账号');

// 登录
const login = await client.prepareLogin(qrText); // 0 候选会抛 ADDRESS_MISMATCH
if (login.candidates.length > 1) {
  client.selectLoginCandidate(login.loginId, chosenLocalId);
}
const result = await client.authorizeLogin(login.loginId);
// result.success / result.message
```

`client.code(localId)` 对增强型账户抛出 `NOT_STANDARD_ACCOUNT`。增强型账户的动态码只能通过 `scanCode(localId)` 获取，且必须先在宿主界面完成开关开启（`setScanCodeRevealEnabled(true)`），否则抛 `SCAN_CODE_HIDDEN`。

单账户导出（仅返回内存字符串，不写文件/剪贴板/日志）：

```ts
const uri = client.exportOtpauthUri(account.localId); // 标准账户与增强型账户都可用
// 宿主自行离线渲染二维码；本 App 使用 Scan Kit 的 generateBarcode
```

### 4.5 主要公开 API

| 分组 | API |
| --- | --- |
| 生命周期 | `TotpScanClient.create(config?)`、`init()` |
| 账户 | `accounts()`、`scanAccounts()`、`account(id)`、`addStandardAccount(input)`、`importOtpauthUri(uri)`、`buildOtpauthUri(id)`、`exportOtpauthUri(id)`、`renameAccount(id, note)`、`removeAccount(id)`、`clearAll()` |
| 标准码 | `code(id)`（增强型账户拒绝） |
| 扫码账户动态码 | `scanCode(id)`（仅开关开启时可用）、`scanCodeRevealEnabled()`、`setScanCodeRevealEnabled(bool)` |
| 绑定 | `prepareBinding(qr)`、`confirmBinding(previewId, note)`、`retryBindingConfirm(id)`、`discardBinding(previewId)` |
| 登录 | `prepareLogin(qr)`、`selectLoginCandidate(loginId, id)`、`authorizeLogin(loginId, id?)`、`discardLogin(loginId)` |
| 设置 | `biometricRequired()`、`setBiometricRequired(bool)`、`clockStatus()`、`calibrateClock()`、`trustedSites()`、`maxNoteLength()` |
| 工具 | `OtpauthUri.parse/build`、`TotpCalculator.*`、`Base32`、`Base64Url`、`CanonicalUrl`、`AddressMatcher`、`CandidateResolver` |

公开错误类型为 `TotpError`，`code` 为稳定的 `TotpErrorCode`，`userMessage` 为可直接展示的中文文案。`message` 仅用于开发排查，不含密钥、`token` 或动态码。

---

## 5. 权限

`entry/src/main/module.json5` 声明：

| 权限 | 用途 |
| --- | --- |
| `ohos.permission.INTERNET` | 提交动态码、绑定确认、校时 |
| `ohos.permission.CAMERA` | Scan Kit 相机预览与扫码 |
| `ohos.permission.ACCESS_BIOMETRIC` | 提交前的系统身份验证 |

`CAMERA` 与 `ACCESS_BIOMETRIC` 均带中文 `reason` 和 `usedScene`（`inuse`）。权限被拒时 App 不崩溃，走 §3.4 的降级路径。

---

## 6. 安全要求对应（S1–S14）

| 编号 | 落实位置 | 说明 |
| --- | --- | --- |
| S1 提交目标唯一来源 | `PinnedEndpoint`、`Submitter` | 提交层只接受 `PinnedEndpoint`，没有 URL 字符串入参；地址只来自绑定解析后写入的保险库。登录二维码 `url` 只参与注册域名比对。 |
| S2 域名与路径约束 | `RegisteredDomain`、`PinnedUrl`、`AddressMatcher`、`CandidateResolver` | 绑定固定注册域名 + path/query；登录只按注册域名选账户，提交固定使用绑定的完整地址；0 候选立即终止，不提供“继续提交”。 |
| S3 密钥保护 | `VaultStore`、`TotpError`、`Ui.errorText` | 整个保险库作为 Asset Store `SECRET` 条目加密保存；日志/异常消息不含 `sec`、`token`、动态码；备注只存本地。 |
| S4 绑定完整性 | `BindingPayload` | 校验 `v`/`dom`/`path`/`sec`/`alg`/`dig`/`per`/`iat`，在本地拼出 `https://<dom><path>`；任一失败不落盘。载荷不含 `sig`/`kid`，不做验签。 |
| S5 公钥来源约束 | 不适用 | 已取消签名与公钥机制，不存在预置公钥、well-known 或 JWKS 路径。 |
| S6 token 强度与时效 | `LoginPayload` | 校验 `token` 为 16 或 24 位 `[A-Za-z0-9_-]`、`exp - now ≤ 60`、过期即拒绝；`token` 只在内存 `PendingLogin` 中。 |
| S7 一次性与会话绑定 | `TotpScanClient.authorizeLogin`、`discardLogin` | 每次提交结束（成功/失败/网络异常）都从内存删除 pending；服务端负责会话 Cookie 绑定。 |
| S8 失败次数与作废 | 服务端职责；客户端不重试 | App 不自动重试同一 `token`；失败后提示重新扫码。 |
| S9 时间窗与重放 | `TotpCalculator`、`ClockService` | 动态码按 RFC 6238 计算；使用服务器 `Date` 头校准偏移（钳制 ±1 小时）；重放防护由服务端实施。 |
| S10 错误统一 | `Submitter.mapResponse`、`TotpError` | 客户端不区分 401 的具体原因，统一展示“认证失败”；不记录响应体。 |
| S11 传输安全 | `HttpClient` | 仅系统 TLS；`CanonicalUrl` 拒绝非 HTTPS（localhost 例外）；不跟随 3xx；`token`/`code` 只放 JSON body，不放 query。 |
| S12 解绑与轮换 | `removeAccount`、`clearAll` | 本机删除立即移除密钥与固化地址；服务端解绑需站点操作。 |
| S13 即时码隔离 | `TotpScanClient.code`/`scanCode`、`Index`、`AccountDetail`、`Login` | `code()` 对增强型账户抛错；`scanCode()` 仅在用户显式开启「显示扫码型账户的动态码」后可用（默认关闭，开启需本地认证 + 风险确认）；关闭时列表/详情不取码、不保留。 |
| S14 备份作用域 | 全工程 | App 与 HAR 不提供备份/导入/迁移文件能力；仅提供单账户 otpauth 二维码的屏幕展示（§3.5），不落盘、不写剪贴板。 |

补充：

- **多站点候选**：`CandidateResolver` 只遍历 `AccountKind.SCAN` 且 `bindingConfirmed === true` 的账户，只比较注册域名；不看 `iss`/`acc`/`bid`/路径。候选集合天然按注册域名分组，不会跨域名混合。`authorizeLogin` 在提交前还会二次校验 `bindingConfirmed`，未确认绑定一律拒绝（`NOT_BOUND`）。
- **提交体**：固定为 `{"code":"123456","token":"..."}`，不再发送 `scan_token`、`account` 或 `device_id`。提交目标固定为绑定时保存的 `https://<dom><path>`，登录二维码的 `url` 只用于选账户。
- **备注**：只在 `confirmBinding(previewId, note)` 和 `renameAccount(id, note)` 中写入 `displayName`；二维码与提交体都没有备注字段。

---

## 7. 安全存储与密码学实现

- **安全存储**：`@kit.AssetStoreKit`，别名 `totpscan.vault.v1`，访问级别 `DEVICE_FIRST_UNLOCKED`。整个保险库（所有账户与设置）作为一个加密 `SECRET` 条目保存；不存在明文 `preferences` 回退。
- **TOTP**：`@kit.CryptoArchitectureKit` 的 `createMac('SHA1'|'SHA256'|'SHA512')`，不自实现 HMAC；RFC 4226 动态截断。
- **随机数**：`createRandom().generateRandomSync()`，用于本地 ID。
- **网络**：`@kit.NetworkKit` 的 `http`，系统默认证书校验，无自定义 CA、无“信任所有证书”配置。
- **生物识别**：`@kit.UserAuthenticationKit`，指纹/人脸，ATL3；不可用时 fail-closed，用户可在设置中显式关闭门禁。导出二维码与开启「显示扫码型账户的动态码」使用 `authenticateStrong`：优先生物识别，设备未录入时回退锁屏密码（PIN）。
- **扫码**：Scan Kit `customScan` + `XComponent`；权限被拒或相机不可用时退回 `scanBarcode.startScanForResult` 系统扫码；扫码结果只回传原文，不写日志。
- **二维码生成**：导出页使用 Scan Kit `scanBarcode.generateBarcode`（本地系统能力，离线生成），不使用在线服务，也不在运行时下载编码库。
- **防截屏**：导出页在 `aboutToAppear` 调用 `setWindowPrivacyMode(true)`，`aboutToDisappear` 关闭。

---

## 8. 单元测试

测试位于 `totpscan/src/ohosTest/ets/test/`，使用 Hypium：

| 套件 | 覆盖 |
| --- | --- |
| `Totp.test.ets` | RFC 6238 SHA1/SHA256/SHA512 六组时间向量；6 位/60 秒；`timeStep`/`remainingSeconds`；Base32 RFC 4648；Base64Url |
| `Address.test.ets` | 规范化表；注册域名 + path/query 前缀判定；非后缀/非包含；`PinnedEndpoint` 保留原始 path/query 并拒绝非规范形式 |
| `Payload.test.ets` | 绑定 `dom`/`path` 解析与拼接；非法域名/路径；过期；未知字段（含旧 `sig`/`kid`）忽略；登录 `url`/`token`/`exp`、TTL、域名形态校验 |
| `Otpauth.test.ets` | 完整 URI、默认值、15 秒步长、issuer 冲突、重复参数、hotp/counter、非法参数、弱密钥、build/parse 往返且备注不进入 URI |
| `Candidate.test.ets` | 0/1/多候选；同注册域名多账户；不同注册域名不混合；标准账户永不入选；未确认绑定不入选（`bindingConfirmed === false`） |

运行方式：在 DevEco Studio 中对 `totpscan` 的 `ohosTest` 运行测试；或使用 hvigor 测试任务（具体任务名随 DevEco 版本略有差异）。

> 本轮开发在无鸿蒙工具链的机器上进行，Hypium 测试**未在本机实际执行**；但测试向量与 §7.4 判定表已用独立 Node/OpenSSL 实现交叉核对（0 失败），见 §10。

---

## 9. 已知局限

1. **不是抗钓鱼的强认证**：绑定已取消签名，若攻击者伪造同注册域名的登录二维码并中继自己的 `token`，域名比对会命中，协议无法阻断。详见规范 §10。
2. **共享密钥仍在绑定二维码中**：绑定二维码必须一次性、短时、在可信设备上展示。
3. **增强型账户不支持离线**：必须把动态码提交到固化地址；离线时无法认证。
4. **标准账户没有地址防护**：用户可能在钓鱼页手工输入标准账户动态码；标准账户与扫码提交相互独立。
5. **无设备证明**：不检测 root/越狱、不校验 App 签名；安全强度依赖系统安全存储与 TLS。
6. **TLS 是必要条件**：若绑定域名的源被可信证书中间人攻击，全部防护失效。
7. **绑定二维码不做真伪校验**：没有签名、没有预置公钥；首次绑定完全信任扫描到的二维码，需确保二维码来自可信来源。
8. **不做自动重试**：失败后要求重新扫码，避免消耗服务端失败次数。
9. **无备份/导入/导出文件**：按 S14，移动端不提供备份文件能力；单账户 otpauth 二维码导出会完整暴露该账户密钥（增强型账户因此失去防钓鱼优势），仅在用户认证与确认后于屏幕短暂展示。
10. **校时依赖已绑定站点的 `/healthz`**：没有绑定增强型账户时无法校准；标准账户只使用设备时间。
11. **「显示扫码型账户的动态码」是显式降级**：开启后动态码可被旁人看到或复制，防钓鱼优势下降；默认关闭，开启需本地认证与风险确认。

---

## 10. 本机未执行验证的项

开发机未安装 DevEco Studio / hvigor，以下项目**未在本机实际执行**：

- `hvigorw assembleHap` 编译、HAP 产出与签名；
- Hypium 单元测试的实际运行；
- 真机/模拟器上的页面渲染与交互；
- Scan Kit 相机预览、系统扫码兜底、权限弹窗；
- Scan Kit `scanBarcode.generateBarcode` 的二维码渲染与 `image.PixelMap.release`；
- `setWindowPrivacyMode` 的防截屏效果、模糊遮罩与 60 秒自动关闭；
- `authenticateStrong` 的锁屏密码（PIN）回退路径；
- Asset Store 读写、生物识别 ATL3 流程；
- 真机 HTTPS 请求与服务器时间校准。

已完成且可复核的验证：

- 用独立 Node 镜像实现核对 RFC 6238 三算法时间向量、Base32/Base64url、注册域名推导与 path/query 前缀判定、otpauth 期望行为，全部通过；
- 全量 ArkTS 源码做了人工类型与 API 自查；若首次在 DevEco 中编译出现少量 API 签名差异（最可能是 `cryptoFramework` 同步/异步方法名或 Scan Kit `customScan` 参数），按编译错误提示做局部调整即可，不涉及协议逻辑。
