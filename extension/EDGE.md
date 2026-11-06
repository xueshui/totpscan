# Microsoft Edge 加载项提审核对（TOTP 认证器）

本文面向 Microsoft Partner Center → Microsoft Edge 加载项提审，基于当前 `extension/` 代码逐项核对。所有字段值以本仓库 `manifest.json` 为准。

- 扩展名：`TOTP 认证器`
- 版本：`1.0.3`
- 版权署名：`© bili觅果呀`
- 运行方式：Manifest V3，无构建步骤，源码即产物

---

## 0. 结论

1. 当前源码可以提交：无 `update_url`、无 `_metadata`、无远程代码、无 `<all_urls>`。源码 `manifest.json` 含固定的 `key` 供自用侧载；**上传商店必须用 `--store` 产出的包，该包已移除 `key`**。
2. `name` 与 `description` 已改为 `__MSG_extName__` / `__MSG_extDesc__`，由 `_locales` 提供文案；简体中文下名称为「TOTP 认证器」，描述 58 个字符（含标点），低于 132 字符上限。
3. 已设置 `default_locale: "zh_CN"` 并提供 `_locales` 的 `zh_CN`、`en`、`zh_TW`、`ja` 四种语言。**`_locales` 仅用于清单名称与描述，扩展内界面文案仍为简体中文**，商店页面不要据此宣称界面已本地化。
4. 本次没有添加 `author` 字段。Edge 的清单文档虽然列有 `author`，但扩展管理页与商店署名来自 Partner Center 发布者信息，清单里的 `author` 不用于展示；版权改为放在设置页底部与 README，避免无效字段。
5. 最大的提审风险不是代码，而是 `host_permissions` 中的 `https://*/*`。这是“向任意已绑定固化地址提交验证码”这一产品能力决定的，无法在构建时枚举域名。下面提供了可直接粘贴给审核员的英文说明；如果后续希望进一步降低安装时授权范围，可改为 `optional_host_permissions` + 绑定时动态授权（本次未改，避免影响现有绑定/导入流程）。

---

## 1. manifest.json 逐项核对

| 字段 | 当前值 | 是否需要改 | 最终值 / 说明 |
| --- | --- | --- | --- |
| `manifest_version` | `3` | 否 | Edge 当前要求 MV3，保持 |
| `name` | `__MSG_extName__` | 已改 | 由 `_locales` 解析：简体中文为 `TOTP 认证器`（8 个字符，上限 45）；英文为 `TOTP Authenticator` |
| `short_name` | 未设置 | 否 | 可选字段；名称本身只有 8 个字符，不需要短名，避免重复 |
| `version` | `1.0.3` | 否 | 三段式数字，符合 Edge 要求。每次提审必须严格递增（见第 4 节） |
| `description` | `__MSG_extDesc__` | 已改 | 由 `_locales` 解析：简体中文 58 个字符（上限 132）。文案见 `_locales/zh_CN/messages.json` |
| `icons` | 16/32/48/128 PNG | 否 | 已包含 128；PNG 签名与尺寸由打包校验脚本检查 |
| `action.default_icon` | 同上四尺寸 | 否 | 与 `icons` 一致 |
| `action.default_popup` | `popup/popup.html` | 否 | Edge 支持 |
| `action.default_title` | `__MSG_extName__` | 已改 | 与扩展名同源，悬浮提示显示当前语种名称 |
| `background.service_worker` | `background.js` | 否 | Edge 102+ 支持 MV3 service worker |
| `background.type` | `module` | 否 | Edge 支持 ES Module service worker |
| `options_ui` | `options/options.html` | 否 | Edge 支持；`open_in_tab: true` |
| `permissions` | `storage`、`activeTab`、`scripting`、`clipboardWrite` | 否 | 逐条用途见第 2 节 |
| `host_permissions` | `https://*/*`、`http://localhost/*`、`http://127.0.0.1/*` | 否 | 未使用 `<all_urls>`；未申请任意 `http://` 站点；用途见第 2 节 |
| `content_security_policy.extension_pages` | `script-src 'self'; object-src 'self'; base-uri 'self'` | 否 | 无远程代码；jsQR 为本地文件 |
| `minimum_chrome_version` | `102` | 否 | Edge 的清单文档明确支持该字段；Edge 102（2022 年）已满足 MV3 + `chrome.scripting` 要求 |
| `update_url` | 不存在 | 否 | 提审包**必须不包含**；Edge 商店负责更新 |
| `key` | 源码与商店包均不含 | 商店包必须不含 | 源码 manifest 不写 `key`；dev 包由 `tools/pack.mjs` 从本地 `keys/extension-public-key.der` 临时注入，`--store` 产物不含 `key` |
| `default_locale` | `zh_CN` | 已改 | 已提供 `_locales` 四种语言，`name`/`description` 使用 `__MSG_...__`。`_locales` 仅用于清单名称与描述，界面文案仍为简体中文 |
| `author` | 不存在 | 否 | 见第 0 节第 4 条 |
| `homepage_url` | 不存在 | 否 | 可选。没有真实官网时不要填商店链接或占位地址；Partner Center 的 Website 字段同样可留空 |
| `content_scripts` | 不存在 | 否 | 使用 `activeTab` + `chrome.scripting` 按需注入，安装时不常驻所有页面，权限更窄 |
| `web_accessible_resources` | 不存在 | 否 | jsQR 由 `chrome.scripting.executeScript` 注入，不需要暴露给网页 |
| `_metadata` 目录 | 不存在 | 否 | Chrome/Edge 商店包不应包含 |

### 1.1 `default_locale` 与 `_locales` 的当前状态

**已设置 `default_locale: "zh_CN"`，并提供四种语言的清单文案。**

| 语种 | `extName` | `extDesc` 字数 |
| --- | --- | --- |
| `zh_CN` | TOTP 认证器 | 58 |
| `en` | TOTP Authenticator | 129 |
| `zh_TW` | TOTP 驗證器 | 61 |
| `ja` | TOTP 認証アプリ | 75 |

要点：

- `name`、`description`、`action.default_title` 均使用 `__MSG_extName__` / `__MSG_extDesc__`；缺少占位符或 messages.json 不合法会导致扩展加载失败，打包校验脚本会逐语种检查覆盖情况与 45/132 字符上限；
- 浏览器按界面语言匹配，未匹配到 `_locales` 中的语种时回落到 `zh_CN`；
- **界面文案与清单共用同一套 `_locales` 消息表**：`chrome.i18n` 只用于判定浏览器界面语言，界面在运行时按用户设置加载对应语种的 messages.json，因此设置页可与清单语言保持一致，也支持运行时切换；
- Edge 提审不要求扩展必须做多语言，但本扩展的弹窗、设置页、错误提示均已支持 `zh_CN` / `en` / `zh_TW` / `ja` 四种语言。

---

## 2. 权限用途逐条说明（可直接粘贴到 Partner Center）

| 权限 | 代码中的实际用途 | 审核说明（中文） |
| --- | --- | --- |
| `storage` | 保存主题/明暗设置、账户元数据与加密后的密钥；主密钥在扩展专属 IndexedDB | 仅保存用户自己的认证器配置，不同步、不上传 |
| `activeTab` | 用户点击扩展后读取当前标签页，用于二维码识别与把动态码填入当前聚焦输入框 | 仅在用户主动点击扩展时临时访问当前标签页，不常驻、不后台浏览 |
| `scripting` | 按需向当前标签页注入 `content/content.js` 与本地 `vendor/jsQR.js` | 注入发生在用户点击“扫码”或点击账户填充时，用于读取页面中的二维码图片/画布和写入验证码输入框 |
| `clipboardWrite` | 复制标准型账户动态码；找不到输入框时静默复制 | 仅写入用户主动请求复制的 6/8 位动态码 |
| `https://*/*` | 向账户已绑定的固化地址提交一次性验证码（后台 `fetch` 回退） | 提交地址来自用户在绑定阶段确认的域名与路径，构建时无法枚举；扩展不读取该权限下网页内容，页面识别只发生在 `activeTab` |
| `http://localhost/*`、`http://127.0.0.1/*` | 本地参考服务端联调；协议允许 http 回环地址 | 仅回环地址，不包含任意 http 站点 |

### 2.1 英文版权限说明（建议直接粘贴）

```text
storage — Stores the user's own authenticator settings, account metadata, and
encrypted secrets locally. No synchronization or upload.

activeTab — When the user clicks the extension, temporarily accesses the active
tab to detect QR codes and fill the current one-time code into the focused input.

scripting — Injects the packaged content script and the locally bundled jsQR
library into the active tab on demand (after a user click).

clipboardWrite — Copies the current one-time code when the user requests it, or
when no fillable input exists on the page.

Host permissions — The extension must POST a one-time code to the origin of an
account's bound submit URL. That origin is pinned from the binding QR code the
user reviews and confirms, so it cannot be enumerated at build time. The extension does not
read or modify page content under these host permissions; page scanning is
limited to the active tab via activeTab + scripting. http://localhost and
http://127.0.0.1 are included only for the local reference server.
```

### 2.2 关于“收窄授权”

当前没有使用 `<all_urls>`，也没有申请任意 `http://` 站点。真正宽的是 `https://*/*`，它对应“任意 HTTPS 固化地址”的产品能力。

如果审核要求进一步收窄，可行方案是把 `https://*/*` 从 `host_permissions` 移到 `optional_host_permissions`，在用户确认绑定或导入备份时对具体 origin 调用 `chrome.permissions.request()`。代价是：

- 绑定/导入流程需要新增一次授权交互；
- 用户拒绝授权时，只能依赖登录页同源内容脚本提交，跨源后台回退会失效；
- 需要额外处理“已授权 origin 列表”的持久化与撤销。

本次未做该改造，避免影响已经验证过的绑定与提交链路。提审时先用第 2.1 节说明解释必要性。

---

## 3. Partner Center 材料清单

### 3.1 账号与发布者

- 使用 Microsoft 账号注册 Partner Center 的 Microsoft Edge 计划（免费）。
- 发布者显示名建议：`bili觅果呀`。
- 发布者信息会显示在商店列表；manifest 不再重复写 `author`。

### 3.2 包

- 上传 `extension/dist/totpscan-extension-v1.0.3-store.zip`（**不要**上传 `-dev.zip`，后者带 `key`，仅用于本地加载）。
- zip 根目录直接是 `manifest.json`，不是再套一层文件夹。
- 不包含签名文件、`.pem`、`.crx`、`_metadata`、`tests/`、`tools/`、`EDGE.md`。
- 当前包约 160 KB，远低于商店上传体积限制；实际以 Partner Center 校验为准。

### 3.3 Properties（属性）

| 字段 | 建议值 |
| --- | --- |
| Category | `Productivity`（生产力工具） |
| Website | 留空，或填写真实的产品/帮助页面；不要填 Edge 商店链接 |
| Support contact detail | 填写可用的支持邮箱或帮助页；没有可留空 |
| Mature content | 不勾选 |

### 3.4 Privacy（隐私）

| 字段 | 填写 |
| --- | --- |
| Single purpose | `生成标准 TOTP 动态码，并在用户扫码登录时向账户已绑定的固定地址提交一次性验证码。` |
| Permission justification | 使用第 2.1 节的英文逐条说明 |
| Remote code | **No**。jsQR 随包分发，CSP 为 `script-src 'self'` |
| Data usage | **不收集、不出售、不向第三方传输个人数据**；无遥测、无广告、无分析 SDK |
| Privacy policy requirements | 选择 **No**（不访问/收集/传输个人信息给开发者）。若选择 Yes，必须提供可公开访问的隐私政策 URL，否则无法提交 |

补充说明（如审核问询）：

- TOTP 密钥只保存在本机，落盘前使用 AES-GCM-256 加密；主密钥为 `extractable: false` 的 WebCrypto 密钥，存放在扩展专属 IndexedDB。
- 唯一的出站请求是向用户账户自己的固化地址 `POST` 一次性验证码；不包含任何开发者服务器、统计或云同步。
- 因此本扩展没有“收集数据”的隐私政策强制要求。仍建议准备一个简短隐私声明页面备用，内容说明“不收集、不上传、仅本地存储与向用户指定地址提交验证码”。

### 3.5 Store listing（商店列表）

| 项目 | 建议 |
| --- | --- |
| Language | Chinese (Simplified) / 中文（简体） |
| Extension name | 由 manifest 自动带出，只读：`TOTP 认证器` |
| Description | 由 manifest 自动带出，只读：见第 1 节 58 字描述 |
| Store logo | `store-v2/<lang>/store-logo-300.png`（300×300 PNG） |
| Screenshots | `store-v2/<lang>/screenshot-1.png` ~ `screenshot-4.png`，均为 1280×800 PNG |
| Small promotional tile | `store-v2/<lang>/promo-small-440x280.png`（440×280） |
| Large promotional tile | `store-v2/<lang>/promo-marquee-1400x560.png`（1400×560，Chrome Web Store 用；Edge 不强制） |
| YouTube video | 不需要 |
| Search terms | 建议 5 个：`TOTP`、`2FA`、`双重验证`、`验证码`、`扫码登录` |

截图内容（均为按对应语言渲染真实扩展界面后合成，演示账户使用固定假密钥）：

1. `screenshot-1.png`：弹窗主界面（浅色），4 个演示账户与倒计时环；
2. `screenshot-2.png`：同一界面深色模式；
3. `screenshot-3.png`：设置页「备份与迁移」（三条导出路径与导入区）；
4. `screenshot-4.png`：设置页账户管理（排序手柄、置顶、备注、扫码绑定提示）。

商店长描述草稿（如 Partner Center 提供单独的长描述字段）：

```text
TOTP 认证器是一款纯本地的双重验证工具。支持标准 TOTP（RFC 6238 / RFC 4226），
兼容 SHA1 / SHA256 / SHA512、6 / 8 位动态码与 30 / 60 秒周期；可通过 otpauth
链接、手动输入或网页二维码添加账户，并在弹窗中查看动态码与倒计时。

同时支持扫码增强登录：在登录页自动识别二维码，按账户已绑定的固化地址提交
一次性验证码。增强型账户不在界面展示、不允许复制动态码，只允许扫码提交。

所有密钥在写入本地前使用 AES-GCM 加密，主密钥保存在扩展专属 IndexedDB 且
不可导出。扩展不包含遥测、广告或远程代码；除向账户自己的固化地址提交验证码
外，不发起任何网络请求。

版权：© bili觅果呀
```

### 3.6 Certification testing notes（认证测试说明）

```text
No account or network service is required to verify the core TOTP functionality.

1. Load the extension, open the popup, then open Settings → Accounts.
2. Add a standard account manually:
   Issuer: EdgeTest
   Account: reviewer@example.com
   Secret: JBSWY3DPEHPK3PXP
   Algorithm: SHA1, Digits: 6, Period: 30
3. The popup shows a 6-digit code and a countdown ring; the code changes every
   30 seconds. Click the code to copy it.
4. To test QR detection, open any page containing an otpauth:// QR code, click
   the floating "扫码" button, and follow the preview dialog.
5. Scan-enhanced login requires a compatible binding server that issues binding
   QR codes with `dom` + `path`. The extension sends nothing when no matching
   local account exists; standard TOTP can be reviewed independently of that server.
6. No remote code, analytics, or developer-operated network endpoints exist.
```

---

## 4. 上传包注意事项

- **不要自带签名。** 上传 zip 即可，Edge 会重新签名并分配扩展 ID；不要在包内放 `.pem`、`.crx`、`signature` 文件。
- **不要包含 `update_url`。** 商店托管的扩展由 Edge 负责更新；`update_url` 只用于企业自托管。
- **不要包含 `key`。** 包内 `key` 会干扰商店签名/ID；`--store` 模式已自动移除，自用 `-dev.zip` 保留。上传时只选 `-store.zip`。
- **版本必须递增。** `version` 为 1–4 段数字（每段 0–65535，首段不能为 0）。已提交/已发布的版本不能重复使用；修复被拒包后重新上传也应递增，例如：
  - `1.0.0` → `1.0.1`（修复）
  - `1.0.1` → `1.1.0`（功能）
  - `1.1.0` → `2.0.0`（不兼容变更）
- **zip 结构。** `manifest.json` 必须在 zip 根目录；不要出现 `__MACOSX/`、`.DS_Store`、`_metadata/`。
- **体积。** 当前约 160 KB；Edge 上传页会做包校验，若超限会直接提示。
- **可复现打包。** 每次提交前执行：

```powershell
cd extension
tools\pack.cmd
# 等价于：生成图标 → 打 -dev 与 -store 两个包 → 分别校验
```

`tools/pack.mjs` 已排除 `tests/`、`tools/`、`dist/`、`keys/`、`package.json`、`EDGE.md`，并使用固定 DOS 时间戳与正斜杠路径。`keys/` 整个目录不入库，私钥不随任何 zip 分发；dev 包只在打包时读取本地公钥并注入 manifest。

### 4.1 自用包与商店包：ID 与数据互不相通

| 场景 | 扩展 ID | 数据 |
| --- | --- | --- |
| 本地加载 `-dev.zip` 解压目录（含本地公钥注入的 `key`） | 由本地公钥决定，固定不变 | 按该 ID 存储，换目录/换机器都保留（只要 profile 不变） |
| 直接加载源码 `extension/` 目录（源码不含 `key`） | 随目录路径变化 | 不可用于长期保存数据，请改用 `-dev.zip` |
| 上传 Edge Add-ons 后安装的商店版 | Edge 分配的全新 ID | 独立存储，**看不到**自用版数据 |
| 同一份包上传 Chrome Web Store | Chrome 分配的另一个 ID | 与 Edge 版也互不相通 |

结论：自用版和商店版是两条独立的数据线；切换前请先用「导出 JSON」备份，再在新版里导入。版本号在两种渠道都只能递增，不能回退。

---

## 5. 仅自己使用的替代路径

### 5.1 开发者模式加载解压目录（推荐）

1. 打开 `edge://extensions`。
2. 打开“开发人员模式”。
3. 点击“加载解压缩的扩展”，选择 `extension/` 目录（含 `manifest.json` 的那一层）。
4. 修改源码后点击扩展卡片上的“重新加载”。

优点：不需要商店审核、不需要签名；适合自用、内测、频繁改代码。缺点：Edge 会显示“已解压的扩展程序”提示；换电脑/换路径需要重新加载。

### 5.2 打包 .crx 的策略限制

- `edge://extensions` → “打包扩展程序”可以生成 `.crx` 和 `.pem`。
- 但 Edge 稳定版默认**不允许**直接拖拽安装本地 `.crx`；这与 Chrome 移除站外安装的限制一致。
- 自托管 `.crx` 通常需要企业策略（如 `ExtensionInstallForcelist` / `ExtensionSettings`）配合 `update_url`，并自行维护更新 XML；个人自用不建议走这条路。
- 因此：
  - 自己用：优先“加载解压缩的扩展”；
  - 小范围分发：用 Partner Center 的 **Hidden** 可见性，分享商店列表链接，仍然走 Edge 签名与更新；
  - 企业内分发：使用 Edge 企业策略 + 自托管 CRX/更新源。

### 5.3 只想私有发布

Partner Center → Availability → Visibility 选择 `Hidden`。扩展不会出现在搜索/分类中，但拿到列表链接的人可以安装；仍需通过认证，后续更新仍按版本递增上传。

---

## 6. `chrome.*` API 在 Edge 上的兼容性

当前代码使用的 API 均为 Edge（Chromium）原生支持：

| API | 用途 | Edge 兼容性 |
| --- | --- | --- |
| `chrome.storage.local` / `onChanged` | 设置、账户、跨页面同步 | 支持 |
| `chrome.runtime.sendMessage` / `onMessage` / `getManifest` | 弹窗、设置页与 service worker 通信；读取版本号 | 支持 |
| `chrome.tabs.query` | 获取当前标签页 | 支持（配合 `activeTab`） |
| `chrome.tabs.sendMessage` | 向内容脚本发送填充/扫码指令 | 支持 |
| `chrome.scripting.executeScript` | 按需注入内容脚本与 jsQR | 支持（MV3） |
| `navigator.clipboard.writeText` | 复制动态码 | 支持；扩展页/内容脚本按 `clipboardWrite` 授权 |
| `IndexedDB` / `crypto.subtle` | 主密钥与 AES-GCM | 支持 |

补充：

- `chrome.*` 的 Promise 形式在 Edge 88+ 可用；本扩展最低要求 102，无需回调兼容层。
- **不需要 `browser` 兼容层。** Edge 与 Chrome 一样直接提供 `chrome.*`；引入 webextension-polyfill 只会增加包体和一层无意义封装。
- `BarcodeDetector` 在 Edge 桌面版并非所有版本都可用；代码已优先尝试它，缺失时回退本地 jsQR，不影响功能。
- `chrome.permissions` 当前未使用；如果未来改用 `optional_host_permissions`，Edge 同样支持。

---

## 7. 提审前的最后检查清单

- [ ] `manifest.json` 的 `name` 为 `TOTP 认证器`，`version` 大于上一次提交值。
- [ ] 执行 `tools\pack.cmd`，确认校验全部通过。
- [ ] zip 根目录有 `manifest.json`；无 `key`、`update_url`、`_metadata`、`.pem`、`.crx`。
- [ ] Partner Center 的 Privacy 页选择“不收集数据”，Remote code 选择 No。
- [ ] 权限说明逐条粘贴第 2.1 节。
- [ ] 商店 logo 300×300、截图 1280×800（至少 1 张）已准备。
- [ ] 认证测试说明使用第 3.6 节，明确标准 TOTP 无需服务端。
- [ ] 设置页底部显示 `© bili觅果呀` 与版本号。

---

## 8. 参考

- Microsoft Edge 扩展清单格式：<https://learn.microsoft.com/microsoft-edge/extensions/getting-started/manifest-format>
- 发布 Microsoft Edge 扩展：<https://learn.microsoft.com/microsoft-edge/extensions/publish/publish-extension>
- Edge 扩展 API 支持列表：<https://learn.microsoft.com/microsoft-edge/extensions/developer-guide/api-support>
- Chrome 扩展 CSP（MV3）：<https://developer.chrome.com/docs/extensions/reference/manifest/content-security-policy>
