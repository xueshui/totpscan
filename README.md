# totpscan

在标准 TOTP（RFC 6238）之上，把「扫码」限定为一次地址核对：绑定阶段把提交地址（域名 + 路径）钉在客户端本地，登录扫码时只有二维码里的地址与本地记录**完全一致**才计算并提交动态码。

> 二维码只用于比对。提交目标永远来自绑定阶段保存在本地的地址，而不是二维码里写的地址。

**English summary** — `totpscan` is a TOTP anti-phishing add-on: during binding, the client stores the issuer's submit origin (host + path) locally; during login, a scanned QR is only used to compare against that pinned origin. If it does not match exactly, the client stops locally and sends nothing. It is **not** WebAuthn, **not** OAuth/QR sign-in, and does not protect against key leakage or a compromised server.

## 项目定位

它解决的是「二维码里的域名被换成钓鱼域名，用户把动态码交出去」这一类问题：

- 假地址直接本地终止：域名或路径不匹配时不计算动态码，不发起任何网络请求；
- 绑定阶段由用户核对 `iss` / `acc` / `dom` / `path`，确认后写入本地安全存储；
- 同一客户端也能作为普通 TOTP 认证器使用，不参与扫码提交；
- 协议不依赖签名、`kid`、公钥分发或 TOFU；首次信任完全来自用户的确认动作。

它**不**解决：密钥泄露、服务器被攻破、真地址 + token 中继、6 位码在线爆破。完整边界见 [SECURITY.md](SECURITY.md) 与 [spec §10](spec/totp-scan-v1.md#10-已知局限)。

## 协议一句话

绑定二维码携带 `dom`（注册域名）与 `path`（提交路径）；登录二维码只携带 `url` 与一次性 `token`；客户端按本地固化的 `dom + path` 拼出提交地址，向该地址 `POST {code, token}`。

字段、地址规范化规则、错误码与测试用例以 [`spec/`](spec/) 为唯一来源。

## 六端在哪

| 端 | 目录 | 形态 | 当前状态 |
| --- | --- | --- | --- |
| 协议 | [`spec/`](spec/) | 规范、OpenAPI、JSON Schema、TC 用例 | v1 定稿 |
| 参考服务端 | [`server/`](server/) | Node.js ≥23.6 + TypeScript，零运行时依赖 | 50 个测试通过；内存存储，仅参考 |
| 浏览器扩展 | [`extension/`](extension/) | Chrome / Edge Manifest V3 | 44 项自测通过；可打 dev / store 包 |
| Android | [`android/`](android/) | Kotlin SDK（AAR）+ App | 已构建签名 APK / AAR；未真机验证 |
| iOS | [`ios/`](ios/) | SwiftUI App + Swift Package | 仅源码，未在 macOS 编译 |
| 鸿蒙 | [`harmony/`](harmony/) | ArkTS App + HAR | 仅源码，未在 DevEco 构建 |

接入文档在 [`docs/`](docs/)：[语言无关接入指南](docs/integration-guide.md)；Go 最小示例见 [`docs/examples/go`](docs/examples/go)。

## 最小可跑示例

要求 Node.js ≥ 23.6（原生运行 TypeScript）。服务端默认不提供任何管理令牌，必须显式设置 ≥32 字符的 `ADMIN_TOKEN`。

macOS / Linux：

```bash
cd server
export ADMIN_TOKEN=$(openssl rand -hex 32)
npm test        # 50 个用例
npm run demo    # 绑定 → 确认 → 登录 token → 比对 → 提交 → 重放拒绝
npm start       # 默认 http://127.0.0.1:8080
```

Windows PowerShell：

```powershell
cd server
$env:ADMIN_TOKEN = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
npm test
npm run demo
npm start
```

确认服务存活：

```bash
curl http://127.0.0.1:8080/healthz
```

主要端点：

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| `POST` | `/totp/v1/bindings` | 创建绑定（需 `Authorization: Bearer <ADMIN_TOKEN>`） |
| `POST` | `/totp/v1/bindings/{bid}/confirm` | 用动态码确认绑定 |
| `POST` | `/totp/v1/login/token` | 签发登录二维码与一次性 token |
| `POST` | `/totp/v1/verify` | 提交 `{code, token}` |
| `GET` | `/totp/v1/session` | 查询当前登录会话 |
| `POST` | `/totp/v1/logout` | 退出会话 |

配置项：`HOST` / `PORT` / `PUBLIC_BASE_URL` / `ADMIN_TOKEN` / `SECURE_COOKIES` / `SCAN_TOKEN_TTL` / `SESSION_TTL` / `BINDING_TTL`。参考实现使用内存存储，生产部署必须替换。

## 构建方式

**浏览器扩展**

```bash
cd extension
npm test                 # 纯逻辑自测
npm run build            # 图标 + 双包 + 校验；dev 包需要本地 keys/
node tools/pack.mjs --store   # 没有本地密钥时，只打商店包
```

源码 `manifest.json` 不含 `key`。需要固定扩展 ID 时，在本地生成密钥对后打包（步骤见 [extension/README.md](extension/README.md#7-自测与打包)），`keys/` 不入库。

**Android**

```bash
cd android
cp keystore.local.properties.example keystore.local.properties  # 填写签名材料
./gradlew :sdk:assembleRelease :app:assembleRelease
./package.sh            # Windows 用 package.ps1
```

缺少签名材料时 release 构建会直接失败，不会回退到未签名或 debug 签名。

**iOS**（需要 macOS + Xcode）

```bash
cd ios
swift test --package-path TotpScanSDK
xcodebuild -project TotpScanApp.xcodeproj -scheme TotpScanApp build
```

**鸿蒙**（需要 DevEco Studio）

```bash
cd harmony
./hvigorw assembleHap
```

## 安全边界与已知局限

- 地址比对是字符串级防护，不是密码学绑定；不抗「真地址 + token 中继」。
- `sec` 长期有效，轮换需要重新绑定；不防客户端或服务端任一方的密钥泄露。
- 6 位动态码空间小，服务端必须实现 token 一次性、≤60 秒、会话绑定、失败作废与时间步重放防护。
- 绑定与登录二维码均不签名；不要引入「扫码即自动绑定」，必须由用户核对 `iss` / `acc` / `dom` / `path`。
- 参考服务端是演示实现；iOS / 鸿蒙尚未在本仓库环境编译，Android 未上真机，扩展未上架。
- 详细威胁模型与各端差异见 [SECURITY.md](SECURITY.md)。

## 参与贡献

目录边界、协议改动要求与提交前检查见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请走私密渠道，见 [SECURITY.md](SECURITY.md)。

## 许可证

待定（MIT 或 Apache-2.0），当前 [LICENSE](LICENSE) 仅为占位，未授予任何开源许可；确认后再替换为正式文本。
