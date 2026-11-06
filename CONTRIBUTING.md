# 贡献指南

## 仓库边界

| 目录 | 负责内容 |
| --- | --- |
| `spec/` | 协议规范、OpenAPI、JSON Schema、测试用例（唯一契约来源） |
| `server/` | Node.js 参考服务端与测试 |
| `docs/` | 接入指南（语言无关、Go 专篇） |
| `extension/` | Chrome / Edge Manifest V3 扩展 |
| `android/` | Kotlin SDK（AAR）与 App |
| `ios/` | SwiftUI App 与 Swift Package SDK |
| `harmony/` | ArkTS App 与 HAR 模块 |

修改客户端前先与对应目录的维护者对齐；跨目录改动请拆成独立 PR，避免一次 PR 同时改动 `spec/` 和多个客户端。

## 修改协议时的硬性要求

1. **不得擅自改变语义**：字段名、流程顺序、安全要求（S1–S18）与「地址仅用于比对、提交目标来自本地固化地址」的约定不能简化。
2. **同步三处**：任何字段或接口变更必须同时更新
   - `spec/totp-scan-v1.md`
   - `spec/schemas/*.schema.json` 与 `spec/openapi.yaml`
   - `server/` 实现及 `server/test/` 用例
3. **同步客户端**：会改变客户端行为的变更（字段、`dom` / `path` 判定、地址规范化规则、错误语义）必须同步更新受影响的 `extension/`、`android/`、`ios/`、`harmony/`，或明确在 PR 中标注待跟进项。
4. **版本规则**：新增可选字段不升 `v`；删除/重命名字段、改变地址规范化或提交目标推导规则必须升 `v`（见规范 §12.1）。
5. **不引入隐式信任**：v1 没有签名、`kid`、公钥分发与 TOFU；不要以兼容名义在客户端加入「自动信任扫码地址」或跳过用户确认的逻辑。

## 提交前检查

按改动涉及的目录执行：

```bash
# 服务端（Node.js ≥ 23.6）
cd server
npm test           # 单元 + 集成测试
npm run demo       # 端到端冒烟
npm run typecheck  # 需要先 npm install

# 浏览器扩展
cd extension
npm test           # 纯逻辑自测
npm run build      # 生成图标 + 打包 + 校验（会写入 dist/）

# Android
cd android
./gradlew :sdk:testDebugUnitTest :app:assembleDebug

# iOS（需要 macOS + Xcode）
cd ios
swift test --package-path TotpScanSDK

# 鸿蒙（需要 DevEco Studio）
cd harmony
./hvigorw assembleHap
```

构建产物（`dist/`、`build/`、`*.apk`、`*.hap`、`*.ipa` 等）不要提交，已在根 `.gitignore` 排除。

## 不得提交的内容

- 私钥、证书、keystore、`keystore.local.properties`、`.env` 等凭据；
- 真实的 TOTP 密钥、登录 `token`、账户数据、生产域名与内网地址；
- 构建产物、`node_modules/`、截图与浏览器 profile 等临时目录。

如果确实需要演示密钥，请使用明显标注的 `demo` / `test` 前缀，并在同目录 README 中说明「仅用于本地演示，禁止用于任何真实部署」。

## 安全相关变更

涉及下列内容时，PR 描述中必须说明威胁模型与回归用例：

- `scan_token` 的生成、存储、有效期、一次性、会话绑定、失败计数；
- TOTP 时间窗与重放记录；
- 地址规范化与比对（`server/src/core/canonical-url.ts` 及各端同名模块）；
- 统一错误响应（不得新增可区分失败原因的字段或文案）；
- 绑定 / 登录二维码字段、`exp` 校验与「不自动绑定」约束；
- 单账户 `otpauth://` 二维码导出与即时码显示开关（规范 §15、S15、S17、S18）；
- 日志、错误信息、示例代码中的密钥 / token 泄露风险。

安全漏洞请勿走私开 Issue，按 [SECURITY.md](SECURITY.md) 报告。

## 测试与文档

- 服务端用例编号与规范 §9 的 `TC-xx` 对应；新增用例请同时更新规范表格，保持文档与实现一致。
- 客户端自测脚本位于各自目录（扩展 `tests/selftest.mjs`、Android `sdk/src/test/`、iOS `TotpScanSDK/Tests/`、鸿蒙 `totpscan/src/ohosTest/`），新增行为请补对应断言。
