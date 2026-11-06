# TOTP 认证器（扫码增强认证器 · Chrome / Edge · Manifest V3）

纯本地的标准 TOTP 认证器，同时支持「扫码增强协议 v1」：在网页 DOM 中自动识别二维码、把动态码填入当前聚焦输入框，并按 `spec/totp-scan-v1.md` 的地址固化规则提交登录验证码。扩展不使用构建工具，源码即产物，可直接「加载已解压的扩展程序」运行。

版权署名：© bili觅果呀

- 全中文界面（弹窗、选项页、提示与错误文案）
- 标准 TOTP：RFC 6238 / RFC 4226，兼容 `otpauth://totp`，支持 SHA1 / SHA256 / SHA512、6 / 8 位、任意周期（1–3600 秒）
- 页面二维码识别：自动遍历当前页面与同源/跨域 iframe 中的 `img`、`canvas`、`svg`、`video`，优先 BarcodeDetector，缺失时回退内置 jsQR；无需截图或手动框选
- 增强型账户：不展示动态码、不提供复制，只提供扫码提交；提交目标永远是本地固化地址
- 主题色预设 + 自定义取色，明暗模式支持自动 / 手动浅色 / 手动深色
- 备份与迁移：JSON、`authenticator.txt`、可选口令加密（PBKDF2-SHA256 + AES-GCM），兼容 Google Authenticator 迁移数据

---

## 1. 安装

1. 打开 `chrome://extensions`（Edge 为 `edge://extensions`）。
2. 打开右上角「开发者模式」。
3. 点击「加载已解压的扩展程序」，选择本目录 `extension/`（包含 `manifest.json` 的那一层）。
4. 修改源码后，在扩展卡片上点击「重新加载」；弹窗重新打开即可生效。

要求：Chrome 102+ / Edge 102+。无需 Node.js 即可运行扩展；Node.js 只用于自测与打包。

## 2. 权限说明

| 权限 | 用途 |
| --- | --- |
| `storage` | 保存账户（密钥以 AES-GCM 密文落盘）、主题色与明暗偏好 |
| `activeTab` | 用户点击扩展时临时访问当前标签页，用于扫码与自动填入 |
| `scripting` | 按需注入 `content/content.js` 与本地 `vendor/jsQR.js` |
| `clipboardWrite` | 复制标准型账户的动态码 |
| `host_permissions`（`https://*/*`、`http://localhost/*`、`http://127.0.0.1/*`） | 仅用于向账户的本地固化地址提交验证码（优先由登录页同源内容脚本提交，失败时后台回退） |

扩展**不加载远程代码**：`vendor/jsQR.js`（jsQR 1.4.0）随扩展本地分发；CSP 为 `script-src 'self'`。

除向账户自己的固化地址提交验证码外，扩展不发起任何外部网络请求，也没有分析、遥测或云端同步。

### 隐私政策页

[`privacy.html`](privacy.html) 是可直接托管的单文件隐私政策页：CSS 与脚本全部内联，不加载外部字体、脚本、图片或 CDN，也不引用扩展内其它文件。页面打开时按浏览器语言自动选择简体中文、繁體中文、English 或日本語（`ko`、`ar`、`ru` 等其它语言回落简体中文），右上角可手动切换并记住选择，「跟随浏览器」会恢复自动判断。

`privacy.zh-CN.html`、`privacy.zh-TW.html`、`privacy.en.html`、`privacy.ja.html` 是同一模板生成的四个静态变体：`privacy.html` 是自动版，四个变体仅强制初始语言（分别锁定简体、繁體、English、日本語），正文与隐私承诺同源，仍保留手动切换与「跟随浏览器」，可独立直链。各页面的手动选择分别写入 `localStorage`，互不影响。

## 3. 使用说明

### 3.1 添加标准型账户

- 弹窗不再提供添加入口；请打开设置页「账户」标签，手动输入，或粘贴 `otpauth://totp/...` 链接预览后添加。
- 手动输入支持宽松 Base32（空格、短横线、下划线、小写、尾部 `=` 均可）。
- 账户卡片显示分组动态码与圆形倒计时；点击卡片或复制按钮可复制，也可点击卡片右侧按钮把当前码填入网页中**当前聚焦**的输入框。
- 页面中没有可填写的输入框时，会直接静默复制到剪贴板，只在卡片上短暂显示「已复制」；只有剪贴板权限被拒等真实失败才会提示。
- 账户卡片悬停时出现 `⋯` 快捷菜单，也支持右键：重命名、编辑备注、置顶 / 取消置顶、删除；删除前会显示账户名称二次确认，扫码型账户会额外提示固化地址一并移除。
- 点击弹窗头部的排序按钮进入编辑态后，拖动卡片左侧手柄即可排序，也可用手柄上的 ↑ / ↓ 键调整；顺序保存到本地，弹窗与设置页账户列表共用同一份顺序。

### 3.2 扫码

1. 打开含二维码的网页（登录页、绑定页等）。
2. 点击弹窗底部悬浮的「扫码」按钮（滚动账户列表时保持可见）。
3. 扩展自动扫描当前页面的图片、画布、SVG 与视频帧：
   - 识别到多个二维码时列出候选，由用户选择；
   - 绑定二维码：展示签发方/账户/固化地址与提交路径，二次确认后添加，并立即向固化地址提交一次确认码；
   - 登录二维码：按地址规则反查本地增强型账户；
   - `otpauth` 链接：预览后可添加为标准型账户；
   - Google 迁移数据：引导到设置页「备份与迁移」中预览导入。

### 3.3 增强型账户（绑定固化地址）

- 列表中以「扫码型账户」标识，显示固化域名与绑定状态，**不展示 6 位动态码、不提供复制或导出按钮**。
- 仅提供「扫码提交」：登录页二维码中的域名与本地绑定的注册域名一致时，后台计算动态码并按绑定的提交路径直接提交；动态码不会返回给界面。
- 绑定失败可在设置页重试确认；本地备注 `label` 仅保存在本地，≤64 字符，不写入二维码、不上送、不写日志。

### 3.4 外观

设置页「外观」：8 个预设主题色 + 自定义 `#RRGGBB` 取色；明暗模式三档（自动跟随系统 / 手动浅色 / 手动深色），全部持久化。弹窗右上角按钮可循环切换三档。

### 3.5 备份与迁移

设置页「备份与迁移」：

- **JSON 备份**：包含 `issuer/account/secret/algorithm/digits/period/label`；增强型账户额外包含 `submitUrl/bid/iat/status/confirmedAt`。
- **加密 JSON**：使用口令派生密钥（PBKDF2-SHA256，600000 次，随机盐）后以 AES-256-GCM 加密，并按 `spec` §14.3 生成 AAD；文件名为 `totpscan-backup-encrypted-*.json`，界面会标明「需要口令」。导出时在同一弹窗内设置并二次确认口令，导入时输错口令会保留输入框供重试。
- **authenticator.txt**：每行一个 `otpauth://totp/...`，仅包含标准型账户（纯文本无法表达固化地址）。
- 导出前必须二次确认；文件含增强型账户时会额外提示「备份文件含密钥，泄露即可生成动态码」。
- 导入支持：自家 JSON / 加密 JSON、`otpauth://totp/...` 逐行、`issuer:account:secret`、`secret  account  issuer`、Tab/逗号/分号分隔、Base32 空格分组、`otpauth-migration://offline?data=...`。
- 导入前展示预览（名称/账户/算法/位数/周期），失败行单独列出原因且不阻断其他条目；同 `account + issuer` 重复项可选「跳过 / 覆盖 / 保留两份」。
- 增强型账户导入后会重新解析绑定地址，导入后仍可正常扫码提交。

## 4. 与协议规范的对齐

实现依据 `spec/totp-scan-v1.md` 与 `spec/schemas/*.json`、`spec/openapi.yaml`。

### 4.1 绑定二维码

必填字段：`t="totp-bind"`、`v=1`、`bid`（`b_` + 16–64 位 URL-safe 字符）、`iss`、`acc`、`sec`、`alg`、`dig`、`per`、`dom`、`path`、`iat`；`exp` 可选。

- `sec` 必须是严格 Base32（大写、无填充），解码后 16–64 字节；`alg` 仅 SHA1/SHA256/SHA512；`dig` 仅 6/8；`per` 仅 30/60。
- `dom` 只能是 `host[:port]`，不接受协议、路径、查询串或片段；`path` 必须以 `/` 开头，**查询串原样保留**，不接受片段与空白。
- 绑定不携带签名或公钥，安全边界是用户在确认页核对显示的域名与提交路径。
- 完整提交地址由 `https://${dom}${path}` 组成，绑定时**原样保存**，后续所有提交都只用这份地址，不再使用二维码里的任何地址。
- 绑定确认固定发往 `origin(固化地址) + /totp/v1/bindings/{bid}/confirm`。

### 4.2 登录二维码

必填字段：`t="totp-login"`、`v=1`、`url`、`token`、`exp`。

- `url` 只是域名（`host[:port]`），不带协议、路径或查询串；仅用于注册域名比对。
- `token` 为 16 位或 24 位 URL-safe 字符（`A-Z a-z 0-9 _ -`）。
- `exp` 已过期即拒绝；距当前时间不得超过 60 秒。
- `url` 与 `token` 都**不作为提交目标**：提交地址只取绑定时的 `dom + path`。

### 4.3 注册域名与路径规则

| 规则 | 实现 |
| --- | --- |
| 注册域名 | 用 PSL 级后缀表推导，例如 `dkn.example.cn → example.cn`、`example.cn.evil.com → evil.com`；IP 原样返回 |
| 域名比对 | 登录码 `url` 的注册域名 == 绑定 `dom` 的注册域名 |
| 路径 | 只用绑定时的 `path`（含查询串），提交时拼接为 `https://${dom}${path}` |
| 传输 | 仅 `https`；`http` 只允许 localhost / 127.0.0.1 / `[::1]` |
| 相似域名 | 仅做提示（如 `example.cn` 与 `example.com.cn`），不拦截 |
| 不匹配 | 立即本地终止，不计算动态码、不发起任何请求 |

### 4.4 扫码登录流程

1. 识别登录二维码并校验字段/有效期。
2. 按登录码 `url` 的注册域名筛选本地**已确认**的增强型账户，并要求账户存在绑定 `path`；0 个候选 → 本地终止（**零出站**）；1 个 → 直接提交；多个同域账户 → 让用户在同域内选择。
3. 动态码在后台计算，不返回 UI（S13）。
4. 提交目标固定为绑定时的完整地址 `https://${dom}${path}`，请求体为 `{"code":"123456","token":"..."}`；优先由登录页同源内容脚本 `fetch`（携带 Cookie、`redirect: "manual"`），失败回退后台 `fetch`。
5. 服务端返回 200/400/401/429 时展示统一中文错误文案。

## 5. 备份格式

明文 JSON：

```json
{
  "format": "totpscan-backup",
  "version": 1,
  "encrypted": false,
  "exportedAt": 1767225600,
  "accounts": [
    {
      "type": "standard",
      "issuer": "示例",
      "account": "alice@example.com",
      "label": "工作",
      "secret": "JBSWY3DPEHPK3PXP",
      "algorithm": "SHA1",
      "digits": 6,
      "period": 30
    }
  ]
}
```

加密信封：`format/version/encrypted/kdf{name,salt,hash,iterations}/cipher{name,iv,tag}/ciphertext`，字段与 `spec/schemas/backup.schema.json` 一致；AAD 为 `TOTPSCAN-BACKUP-V1\nversion=1\nkdf=PBKDF2\nsalt=<salt>\niv=<iv>`。明文对象 `encrypted` 固定为 `false`，`exportedAt` 为 Unix 秒。口令不写入文件、不保存在扩展中；口令丢失无法恢复。

## 6. 工程结构

```text
extension/
├─ manifest.json
├─ background.js                 MV3 service worker：唯一密钥与网络编排入口
├─ common/
│  ├─ base64.js / base32.js      编码工具
│  ├─ totp.js                    RFC 6238 / 4226
│  ├─ otpauth.js                 otpauth 解析与生成
│  ├─ canonical-url.js           C1–C7 / M1–M4
│  ├─ protocol.js                载荷校验、域名/路径比对、候选反查
│  ├─ vault.js                   IndexedDB 主密钥 + AES-GCM 密钥加密
│  ├─ accounts.js                账户仓储、扫码提交、备份导入导出
│  ├─ backup.js                  备份格式与口令加密
│  ├─ import.js                  宽松导入解析（含迁移 protobuf）
│  ├─ settings.js / ui.js / base.css
├─ content/content.js            页面二维码识别、聚焦回填、同源提交
├─ popup/                        弹窗
├─ options/                      设置页
├─ vendor/                       jsQR（本地）
├─ _locales/                     界面与清单共用的四语种消息表（zh_CN、en、zh_TW、ja）
├─ icons/                        16/32/48/128 PNG + icon.svg（可改色源文件）
├─ store-v2/                     四语言商店素材（截图、徽标、促销图），不参与打包
├─ tests/selftest.mjs            纯逻辑自测
└─ tools/                        图标生成、打包与产物校验
```

## 7. 自测与打包

```powershell
# 自测（Node 20+，需要 WebCrypto）
node tests/selftest.mjs

# 一键：生成图标 → 打两种包 → 分别校验
tools\pack.cmd
# 或分别执行
npm run icons    # 生成 icons/icon.svg 与四个 PNG
npm run pack     # 同时输出自用包与商店包
npm run verify   # 分别校验两种 zip
```

产物有两个，用途不同：

| 包 | 路径 | manifest.key | 扩展 ID | 用途 |
| --- | --- | --- | --- | --- |
| 自用包 | `dist/totpscan-extension-v1.0.3-dev.zip` | 打包时从本地公钥注入 | 由本地公钥决定，固定不变 | 解压后「加载已解压的扩展程序」、侧载自更新 |
| 商店包 | `dist/totpscan-extension-v1.0.3-store.zip` | **不含** | 由 Chrome Web Store / Edge Add-ons 分配 | 上传提审，**不要**用自用包上传 |

源码 `manifest.json` **不包含** `key`，公开仓库里也没有任何密钥。需要固定 ID 时，在本地生成一对密钥：

```bash
mkdir -p extension/keys
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -out extension/keys/extension-private-key.pem
openssl rsa -in extension/keys/extension-private-key.pem -pubout -form DER \
  -out extension/keys/extension-public-key.der
```

`keys/` 已被 `.gitignore` 排除，打包脚本只读取公钥、把它注入 dev 包的 manifest，不会写回源码，也不会把私钥放进任何 zip。直接加载源码目录时没有 key，扩展 ID 会随路径变化；需要稳定 ID 请加载 `-dev.zip` 解压后的目录。

商店给同一扩展在 Chrome 和 Edge 分配的是**两个不同 ID**，两边数据不互通。

自用更新：把新代码覆盖到当前加载的同一目录，打开 `chrome://extensions`（Edge 为 `edge://extensions`）点该扩展卡片上的「重新加载」。ID 由本地公钥决定、不会变，账户与设置保留；只有此前用过「ID 会变」的版本时，旧数据无法迁移，需要用 JSON 备份导出再导入。

图标生成脚本 [tools/build-icons.mjs](tools/build-icons.mjs) 只使用 Node 内置的 `zlib/fs`，不依赖任何 npm 包；PNG 由脚本栅格化生成，SVG 与 PNG 使用同一套几何参数。改色只需修改脚本顶部的 `C.accent` / `C.accentLight`，再运行 `npm run icons`，`icon.svg` 与四个 PNG 会同步更新。

打包脚本排除 `tests/`、`tools/`、`store/`、`store-v2/`、`dist/` 与 `package.json`；zip 条目统一使用正斜杠，避免部分解压工具产生错误路径。`npm run verify` 会检查条目路径、manifest 引用、HTML 本地资源、四个 PNG 的签名与尺寸、`_locales` 四语种的 key 集合/空值/占位符一致性、全量 CRC，以及是否误打包测试/工具/素材文件。解压后按第 1 节加载。

### 界面与清单多语言（_locales）

`manifest.json` 已设置 `default_locale: "zh_CN"`，`name`、`description` 与 `action.default_title` 分别引用 `__MSG_extName__` / `__MSG_extDesc__`。当前提供 `zh_CN`、`en`、`zh_TW`、`ja` 四种语言：

| 语种 | 名称 |
| --- | --- |
| `zh_CN` | TOTP 认证器 |
| `en` | TOTP Authenticator |
| `zh_TW` | TOTP 驗證器 |
| `ja` | TOTP 認証アプリ |

界面与清单共用同一套 `_locales/<locale>/messages.json`：`chrome.i18n` 受浏览器 UI 语言限制、无法在运行时切换，因此界面文案由 `common/i18n.js` 在运行时 `fetch` 对应语种的消息表。设置页「外观 → 语言」可选「跟随浏览器」（默认）或固定语种，切换后立即重绘，无需刷新；已经是打开状态的弹窗、右键菜单与 toast 会被安全关闭，避免残留旧语言。

默认语言取 `chrome.i18n.getUILanguage()`（不可用时回退 `navigator.language`），匹配规则：`zh-CN`/`zh-Hans` → `zh_CN`；`zh-TW`/`zh-HK`/`zh-Hant` → `zh_TW`；`ja*` → `ja`；`en*` → `en`；其余（含 `ko`、`ar`、`ru`）→ `zh_CN`。数字、日期与时间统一通过 `Intl` 按当前语种格式化。

## 8. 安全说明与局限

**已做的缓解：**

- 密钥落盘前用 AES-GCM-256 加密；主密钥由 WebCrypto 生成且 `extractable: false`，保存在扩展专属 IndexedDB（`totpscan-vault`）。
- 动态码全程本地计算；增强型账户的动态码不进入 UI 消息，只在后台内存中产生并直接提交。
- 截图、屏幕采集、远程代码、分析上报均不存在。
- 扫码结果、导入失败行、日志均不输出密钥；失败行预览会脱敏。
- 绑定二维码中的地址只在绑定时由用户确认，之后提交永远使用本地保存的 `https://${dom}${path}`；登录二维码只提供域名与 token，不参与提交目标。
- 绑定不依赖任何预置公钥、信任根或网络下载的公钥；相似域名只做提示，不做拦截。

**必须如实说明的局限：**

1. **没有硬件 Keystore/TPM 保护。** 浏览器扩展无法访问操作系统级密钥库，主密钥只能存放在浏览器扩展的 IndexedDB 中。能读取该浏览器配置文件、或在扩展页面上下文执行代码的攻击者，可以解密密钥。建议使用独立浏览器配置文件、开启全盘加密，并只安装可信扩展。
2. **密钥会在内存与备份中出现。** 计算动态码时必须解密到内存；备份文件（尤其是明文与 `authenticator.txt`）包含可直接生成动态码的密钥。请离线保管，不要通过聊天工具或邮件传输。
3. **增强型账户密钥默认随 JSON 备份导出。** 这是按产品需求对规范 S13「不导出」的有意放宽；导出前有二次确认与显著风险提示。纯文本导出不包含增强型账户。
4. **域名比对不能防钓鱼中继。** 注册域名比对保证验证码不会发往二维码里的地址，但无法阻止攻击者伪造一个外观相同的登录页并诱导用户在其页面输入其他凭据；也不会校验页面证书以外的业务身份。
5. **设备时钟偏差会导致认证失败。** TOTP 依赖本地时间，请保持系统时间同步。
6. **部分二维码无法读取。** 跨域图片污染 canvas、DRM 视频、关闭的 Shadow DOM、受保护的内嵌页面等可能无法取像素；此时扩展会明确提示未找到二维码。
7. **`host_permissions` 范围较宽（`https://*/*`）。** 这是为了在登录页与固化地址不同源时仍能由后台完成提交；代码中不存在其他外部请求路径。
8. **绑定二维码没有签名。** 绑定字段完全由二维码提供，安全性依赖用户在确认页核对域名与提交路径；不要在未核对的页面上确认绑定。
9. **备份口令强度决定加密强度。** 口令仅用于 PBKDF2 派生，扩展不保存口令；弱口令可被离线暴力破解。
