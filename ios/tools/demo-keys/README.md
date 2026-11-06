# 演示密钥已移除（安全公告）

本目录原先包含 `bk-demo-1.json`（含完整 Ed25519 私钥）、由该私钥签名的
`sample-binding-qr.txt` 以及生成脚本 `generate-binding-qr.mjs`。

这些文件**已经进入过仓库历史，必须视为永久泄露**：

- `bk-demo-1` 私钥不得用于任何真实环境、测试环境或生产环境；
- 任何仍接受 `bk-demo-1` 的旧安装包都应视为可被伪造绑定二维码，需重新构建分发。

## 当前协议状态

iOS 端的绑定/登录协议**不携带签名**：

- 绑定二维码只提供 `dom` 与 `path`，没有 `sig` / `kid`；
- 不预置公钥，不读取 `trust-anchors.json`，不访问 well-known / JWKS；
- 不再需要 Ed25519 密钥，也不需要任何证书或凭据文件。

本目录不再承载任何配置职责，保留 README 仅为记录历史密钥泄露事件。

不要在本目录提交任何 `*.json`、`*.pem`、`*.p8`、`*.key` 或 `*.mobileprovision` 凭据文件。
