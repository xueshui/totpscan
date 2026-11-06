# 开源前脱敏清单

审计时间：2026-11-06。范围：仓库根目录全部源码、文档、测试与二进制样例（排除 `node_modules/`、`build/`、`dist/` 等生成目录）。
原则：本清单只描述「哪类内容被替换成哪类内容」，不记录原始真实值。

## 1. 总览

| 类别 | 处理方式 | 结果 |
| --- | --- | --- |
| 真实域名与真实提交路径 | 统一替换为 `example.com` / `example.org` 示例域 | 全仓库已无真实域名残留 |
| 真实凭据样例（`sec` / `bid` / 登录 token / 账户名 / 发行方） | 替换为随机生成的假值 | 测试与文档不再包含真实账户数据 |
| 含真实载荷的二维码样例 | 用脱敏载荷重新生成 PNG 与亮度帧 | 解码结果已核对为假值 |
| Android 签名材料 | 不入库，改为环境变量 / 本地文件读取，release 缺失即失败 | `keystore/` 与本地口令文件均在忽略列表 |
| 服务端示例密钥 | 代码无默认值，文档改为生成命令/占位符 | `ADMIN_TOKEN` 未配置或过短时拒绝启动 |
| 扩展固定 ID 的 `key` | 从源码 manifest 移除，dev 打包时从本地公钥注入 | 源码与 store 包均无 `key` |
| 构建产物与本机路径 | 根 `.gitignore` 统一排除 | 首次提交不含任何产物或绝对路径 |

## 2. 域名与路径替换

替换映射（原始值不在此列出）：

| 原类别 | 替换为 |
| --- | --- |
| 真实主域名 | `example.com` |
| 真实登录子域 | `dkn.example.com` |
| 真实站点子域 | `qq.example.com` / `login.example.com` / `other.example.com` |
| 相似但不同的真实域名（负向用例） | `example.org` |
| 真实提交路径（含租户前缀） | `/totp/v1/verify` |
| 全大写对照形式 | `QQ.Example.COM` / `DKN.Example.COM` |

涉及文件（按组件）：

| 组件 | 文件 |
| --- | --- |
| `spec/` | `spec/totp-scan-v1.md`、`spec/openapi.yaml`、`spec/schemas/login-qr.schema.json` |
| `server/` | `server/test/canonical-url.test.ts` |
| `docs/` | `docs/integration-guide.md`、`docs/examples/go/main.go`、`docs/examples/go/main_test.go` |
| `extension/` | `extension/README.md`、`extension/EDGE.md` |
| `android/` | `README.md`、`sdk/src/main/java/.../Models.kt`、`internal/CanonicalUrl.kt`、`internal/RegisteredDomain.kt`、`sdk/src/test/.../{BindingQrTest,LoginQrTest,RegisteredDomainTest,CanonicalUrlTest,OtpauthUriTest}.kt`、`app/src/test/.../QrImageDecoderTest.kt`、`app/src/test/.../RealSampleQrAcceptanceTest.kt` |
| `ios/` | `ios/README.md`、`TotpScanSDK/Sources/TotpScanSDK/Internal/{BindingQRCode,RegistrableDomain}.swift`、`TotpScanSDK/Tests/.../{BindingQRCodeTests,CanonicalURLTests,LoginQRCodeTests,RegistrableDomainTests,TotpScanClientTests}.swift` |
| `harmony/` | `harmony/README.md`、`totpscan/src/main/ets/{model/Models,model/Types,qr/BindingPayload,qr/LoginPayload,security/PinnedEndpoint,security/RegisteredDomain}.ets`、`totpscan/src/ohosTest/ets/test/{Address,Candidate,Payload}.test.ets` |
| 根目录 | `README.md` |

> 说明：上表为实际发生替换的文件；仓库中另有少量文件原本就使用 `example.com` 作为示例，未改动。

## 3. 凭据样例替换

| 文件 | 被替换内容类别 | 处理 |
| --- | --- | --- |
| `android/app/src/test/java/com/scanauth/app/camera/QrImageDecoderTest.kt` | 绑定载荷中的 `bid`、`sec`（Base32）、`iss`、`acc` | 全部替换为随机假值；`sec` 为 32 位 Base32 假串 |
| `android/app/src/test/java/com/scanauth/app/camera/RealSampleQrAcceptanceTest.kt` | 登录载荷中的 `token` 与域名 | 替换为 24 位随机假 token + 示例域名 |
| `android/app/src/test/resources/qr-samples/real-login-qr.png` | 二维码图形（可解出真实载荷） | 按脱敏载荷重新生成 |
| `android/app/src/test/resources/qr-samples/real-login-qr.luma` | 亮度帧（同上） | 按脱敏载荷重新生成，233×224、41×41 模块 |
| `harmony/totpscan/src/ohosTest/ets/test/Candidate.test.ets` | 测试账户的域名分组 | 拆成 `example.com` / `example.org` 两个注册域，保持原断言语义 |
| `docs/examples/go/main.go` | 文档中的 `ADMIN_TOKEN` 示例字面量 | 改为「用 `openssl rand -hex 32` 生成」占位符 |

校验结果：重新生成的亮度帧用 `jsQR` 解码，输出为 `dkn.example.com` + 假 token；已知真实 `sec` / `bid` / token 片段在全仓库检索为 0 命中。

## 4. Android 签名

| 项 | 处理 |
| --- | --- |
| `android/keystore/` | 保留在本地，整体加入 `.gitignore`，不进入提交 |
| `android/keystore/keystore.properties` | 删除；改为 `android/keystore.local.properties`（已忽略） |
| `android/keystore.local.properties.example` | 新增，只含字段名与空值 |
| `android/app/build.gradle.kts` | 依次读取环境变量与本地文件；`assembleRelease` / `bundleRelease` 缺少任一材料时在配置阶段抛错 |
| `android/package.ps1` / `package.sh` | 只复制已签名 Release APK；找不到即失败，不再产出未签名包或 debug 兜底 |
| `android/README.md` | 删除明文口令、证书指纹与硬编码签名命令，改为配置说明 |

环境变量：`ANDROID_KEYSTORE_PATH` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`。

## 5. 服务端与扩展

| 项 | 处理 |
| --- | --- |
| `server/src/config.ts` | `ADMIN_TOKEN` 无默认值，未配置或少于 32 字符时拒绝启动 |
| `server/src/demo.ts` | 演示令牌在进程内随机生成，不落盘、不打印 |
| `extension/manifest.json` | 删除 `key` 字段 |
| `extension/tools/pack.mjs` | dev 包从 `keys/extension-public-key.der` 注入 `key`；文件缺失时给出提示并退出；store 包恒不含 `key` |
| `extension/tools/verify-pack.mjs` | 改为校验「源码无 key、dev 包含注入的 key、store 不含 key」 |
| `extension/README.md` / `EDGE.md` | 补充本地生成密钥对与加载 `-dev.zip` 的说明 |

`extension/keys/` 整目录被忽略，私钥与公钥都不入库。

## 6. 构建产物与本机路径

根 `.gitignore` 覆盖：`build/`、`dist/`、`node_modules/`、`*.apk`、`*.aab`、`*.zip`、`*.jar`（保留 Gradle wrapper）、`*.hap`、`*.har`、`*.ipa`、`*.jks`、`*.keystore`、`*.pem`、`.env*`、`local.properties`、`keystore.local.properties`、`.screenshots/`、`.trae*/`、IDE 配置与覆盖率目录。

本机绝对路径仅出现在 `.screenshots/` 的浏览器驱动配置与 `android/build/` 的构建报告中，两处均在忽略目录。源码与文档中未发现仓库所在盘符路径或用户主目录路径。

## 7. 本轮验证

| 检查 | 结果 |
| --- | --- |
| 真实域名 / 路径残留检索 | 0 命中 |
| 已知真实 `sec` / `bid` / token / 发行方片段 | 0 命中 |
| `server`：`node --test test/*.test.ts` | 50/50 通过 |
| `extension`：`node tests/selftest.mjs` | 44/44 通过 |
| `extension`：dev 打包 + 校验 / store 打包 + 校验 | 均通过；dev 含注入 key，store 不含 |
| 脱敏二维码样例解码 | 成功，内容为假值 |
| Android 单元测试 | 未在本轮复跑（Windows 中文路径已知会影响部分测试） |
| iOS / 鸿蒙构建 | 本机缺少 Xcode / DevEco Studio，未编译 |

## 8. 仓库与推送

- 已初始化本地仓库并完成首次提交，**未配置远端、未推送**；
- 托管平台与仓库名尚未确定，请确认后执行：

```bash
git remote add origin <你的仓库地址>
git push -u origin main
```

- 首次提交前已用 `git status --short` 核对：不包含 `keystore`、`*.pem`、`.env`、`build/`、`dist/`、`node_modules/`、`.screenshots/`。

## 9. 待确认

1. **许可证**：`LICENSE` 目前是占位文本，请在 MIT 与 Apache-2.0 之间确认后再替换为正式全文；
2. **仓库地址**：未提供，推送命令中的远端保持占位；
3. **二进制发布**：APK / AAR / 扩展 zip 是否需要挂到 Release（当前全部不入库）。
