# TOTPSCAN/v1 接入指南

面向已经有一个网站、想接入「扫码辅助提交 TOTP + 绑定地址固化」的服务端开发者。

- 规范来源：[spec/totp-scan-v1.md](../spec/totp-scan-v1.md)
- 可运行示例：[examples/go/main.go](examples/go/main.go)
- 本文按 2026-11 的新协议编写。旧版文档中的 `sig`、`scan_token`、`sub` 整串比对、预置公钥、JWKS **全部作废**，不要再实现。

---

## 0. 一句话结论

服务端生成 TOTP 共享密钥，把「密钥 + 站点域名 + 提交路径」放进绑定二维码交给 App 固化；登录时网页只展示一个短效 `token` 和一个**仅供比对**的域名，App 命中本地固化记录后，把 `{code, token}` 提交到固化地址。

它**不是**：

| 常见误解 | 实际情况 |
| --- | --- |
| 扫码登录 / OAuth | 不签发任何长期 bearer token。二维码里没有可直接换取登录态的凭据，真正凭据仍是一次性 TOTP 动态码 |
| WebAuthn / FIDO2 | 没有 origin 级公钥绑定，不抗「真地址 + token 中继」钓鱼 |
| 可以防密钥泄露 | `sec` 是长期共享密钥，客户端或服务端任一泄露即账户失守 |
| 二维码里带登录链接 | 登录二维码的 `url` 不参与任何网络请求，只用于和固化的 `dom` 比对 |
| 协议强制一次性 / 限流 | 规范只约定「两端怎么对上」。token 时效、一次性、失败计数、限流、日志、存储全部由接入方自定 |

---

## 1. 两条链路

### 1.1 首次绑定

```
用户                 网页 / 服务端                          App
 |                      |                                   |
 |-- 主认证（密码等） -->|                                   |
 |                      | 1. 生成 sec（20 字节）、bid        |
 |                      | 2. 组装绑定载荷（无签名）           |
 |<-- 展示绑定二维码 ----|                                   |
 |--------- 扫码 ------------------------------------------->|
 |                      |                    3. 解析 JSON、校验字段/exp
 |                      |                    4. 展示确认页：iss / acc / dom / path
 |                      |                    5. 用户确认后本地固化 sec/dom/path/bid
 |                      |<-- 6. POST https://<dom>/totp/v1/bindings/<bid>/confirm {code}
 |                      | 7. 三时间窗校验 TOTP               |
 |                      | 8. binding 置为 confirmed          |
```

要点：

1. 绑定载荷**不签名**，App 也不验签；首次信任完全依赖用户核对确认页上的 `iss`、`acc`、`dom`、`path`（§5）。
2. 服务端生成 `sec` 后只通过二维码交付，不写日志、不返回给网页以外的第三方（§4.1、§11 S13）。
3. 绑定确认使用 `POST https://<dom>/totp/v1/bindings/{binding_id}/confirm`，请求体只有 `{code}`，`binding_id` 来自路径；该路径由 [spec/openapi.yaml](../spec/openapi.yaml) 定义。
4. `bid` 一次性：确认后不得再次确认；未确认的绑定不得用于登录（§4.1、§8.1）。

### 1.2 日常扫码登录

```
浏览器（网页）              服务端                        App
 |                           |                            |
 |-- 1. POST /totp/v1/login/token ----->|                            |
 |   {account}               | 2. 生成 token（16/24 字符） |
 |                           |    绑定 session + account   |
 |<-- 3. token + 登录二维码 --|                            |
 |   展示二维码（可倒计时）    |                            |
 |--------- 扫码 ---------------------------------------->|
 |                           |          4. 校验 t/v/exp
 |                           |          5. url 的注册域名 vs 本地 dom 的注册域名
 |                           |             0 候选 → 本地终止，零出站
 |                           |          6. 用本地 sec 计算 TOTP
 |                           |<-- 7. POST https://<dom><path> {code, token}
 |                           | 8. 校验 token + TOTP + 重放  |
 |<-- 9. GET /totp/v1/session -| 10. 标记该 token 所属会话已认证
 |    已认证，跳转            |
```

要点：

1. 网页请求必须携带 `account`，服务端据此找到已确认绑定并签发 token（§6.1）。
2. `token` 与**浏览器会话**和 `account` 同时绑定；App 提交时没有 Cookie，所以服务端靠 token 记录里的 `session_id` 找回会话（§8.2、§8.3）。
3. App 的提交目标只来自绑定阶段固化的 `dom + path`。登录二维码里的 `url` 在任何情况下都不得作为提交目标，路径也不来自登录码（§6.1）。
4. `path` 可以包含查询串，绑定时原样保存，提交时原样拼接。

### 1.3 职责划分

| 动作 | 网页 | 服务端 | App |
| --- | --- | --- | --- |
| 生成 `sec` / `bid` / 绑定载荷 |  | 必须 |  |
| 展示绑定二维码 | 展示 | 下发 |  |
| 核对 `iss/acc/dom/path` |  |  | 必须（用户确认） |
| 固化 `dom` 注册域名与 `path` |  |  | 必须 |
| 签发登录 `token` | 请求 | 必须 |  |
| 反查本地账户、比对域名 |  |  | 必须 |
| 计算 TOTP |  |  | 必须（本地） |
| 提交 `{code,token}` |  | 接收 | 发起 |
| TOTP 校验、token 消费 |  | 必须 |  |
| 标记会话已认证 | 轮询 | 必须 |  |

---

## 2. 二维码载荷

两种二维码都是 **UTF-8 紧凑 JSON**：无 BOM、无换行、字段间无多余空白。App 必须严格解析，不做宽松修复（§4.2、§6.3）。

### 2.1 绑定二维码

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `t` | string | 是 | 固定 `"totp-bind"` |
| `v` | integer | 是 | 固定 `1` |
| `bid` | string | 是 | `b_` + base64url(16 字节随机)；长度 24–64；仅 `[A-Za-z0-9_-]`；不得含用户身份信息 |
| `iss` | string | 是 | 签发方展示名，1–64 字符；NFC；禁止换行与控制字符 |
| `acc` | string | 是 | 账户标识，1–255 字符；NFC；禁止换行与控制字符 |
| `sec` | string | 是 | TOTP 共享密钥；RFC 4648 Base32，**大写、无 `=`**；解码后 16–64 字节（≥128 bit，推荐 20 字节） |
| `alg` | string | 是 | `SHA1` / `SHA256` / `SHA512`，默认 `SHA1` |
| `dig` | integer | 是 | `6` 或 `8`，默认 `6` |
| `per` | integer | 是 | `30` 或 `60`，默认 `30` |
| `dom` | string | 是 | 站点域名 `host[:port]`；IDNA A-label 小写；不得含 scheme、路径、userinfo、查询串、fragment |
| `path` | string | 是 | 提交路径，含查询串、原样保留；必须以 `/` 开头；不得含 fragment、空白、控制字符 |
| `iat` | integer | 是 | 签发时间，Unix 秒 |
| `exp` | integer | 否 | 失效时间，Unix 秒；存在时 App 必须拒绝 `now > exp` |

示例（可直接复制）：

```json
{"t":"totp-bind","v":1,"bid":"b_tWLDXC1h4LQQv7sekJ8IeA","iss":"Example Corp","acc":"alice@example.com","sec":"RVA7NU2NAVQDSDWLMV5VYZTWUVTJU32Q","alg":"SHA1","dig":6,"per":30,"dom":"auth.example.com","path":"/totp/v1/verify","iat":1762396800,"exp":1762397400}
```

绑定载荷**不得**包含 `sig`、`kid`、`pub` 或任何公钥字段。v1 没有签名密钥，也没有 JWKS 端点（§5）。

### 2.2 登录二维码

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `t` | string | 是 | 固定 `"totp-login"` |
| `v` | integer | 是 | 固定 `1` |
| `url` | string | 是 | 站点域名，如 `qq.example.com`；**不带 scheme、路径、查询串、userinfo、端口**；只用于比对 |
| `token` | string | 是 | 会话标识，16 或 24 个 base64url 字符（`[A-Za-z0-9_-]`） |
| `exp` | integer | 是 | 失效时间，Unix 秒；`exp - now ≤ 60` |

示例：

```json
{"t":"totp-login","v":1,"url":"qq.example.com","token":"3YWpb-SAJHxnipC3ar1jssu9","exp":1762396860}
```

登录二维码**不得**包含：`sec`、密码、会话 Cookie、用户真实身份信息、任何长期凭据；也不得包含 `sub`、`st`、`n`、`bid`、`device_id`（§6.4）。

> 注意 `url` 与 `dom` 的分工：`dom` 是绑定时固化的提交域名，可以带非默认端口；`url` 是登录页声明的站点域名，只是比对输入。两者都**不是**提交目标——提交目标永远是 `https://<dom><path>`。

---

## 3. 地址规范化、比对与提交

### 3.1 为什么不能直接比字符串

- `QQ.Example.COM` 与 `qq.example.com` 是同一站点，逐字比较会把合法登录拒掉。
- 用「包含 / 后缀」比较会放过 `qq.example.com.evil.test`。
- 正确做法：**先规范化，再比较注册域名**（§7.1）。

### 3.2 规范化 D1–D5（§7.2）

输入是登录二维码的 `url`，或绑定载荷 `dom` 的 host 部分。

| 规则 | 内容 |
| --- | --- |
| D1 | 必须是字符串；长度 1–255；无前后空白；无控制字符 |
| D2 | 不得包含 scheme（`://`）、路径（`/`）、查询串（`?`）、fragment（`#`）、userinfo（`@`） |
| D3 | Unicode 域名按 IDNA ToASCII 转 punycode；转小写；去掉结尾的 `.` |
| D4 | 结果不得为空；IPv6 用压缩小写并保留方括号 |
| D5 | 输出仅域名；`dom` 可带非默认端口（端口不参与比对）；登录 `url` 不得带端口 |

`path` 单独校验：以 `/` 开头，可含查询串且原样保留（不排序、不重编码），不得含 fragment、空白、控制字符。

### 3.3 比对 M1–M3（§7.3）

设登录二维码声明的站点域名为 `U`，绑定阶段固化的站点域名为 `dom`：

| 规则 | 内容 |
| --- | --- |
| M1 | `U` 必须符合 §7.2 的域名形式，否则不匹配 |
| M2 | 用客户端完整 PSL（ICANN + PRIVATE）分别推导 `U` 与 `dom` 的注册域名，二者必须完全相等 |
| M3 | 任一不满足 → 不匹配；App 立即终止，不计算动态码、不发起任何请求 |

服务端**不承担**这个推导与比对（§7.3）。服务端的职责是：

1. 绑定时把正确的 `dom`、`path` 写进载荷并落库；
2. 提交时只按 token 绑定的账户选择密钥，**不接受**请求里的提交目标，也不根据 `account` 改写或重定向目标（§8.3）；
3. 解绑时按 `binding_id` 操作，不按客户端传来的 URL 操作（S12）。

### 3.4 判定示例

| 钉住 `dom` | 登录 `url` | 结果 | 原因 |
| --- | --- | --- | --- |
| `qq.example.com` | `qq.example.com` | 命中 | 完全相同 |
| `qq.example.com` | `QQ.Example.COM` | 命中 | D3 小写化 |
| `qq.example.com` | `qq.example.com.` | 命中 | D3 去掉结尾的点 |
| `qq.example.com` | `login.example.com` | 命中 | 注册域名同为 `example.com` |
| `auth.example.com:8443` | `auth.example.com` | 命中 | 端口不参与比对（D5） |
| `qq.example.com` | `qq.example.com.evil.test` | 拒绝 | 注册域名为 `evil.test` |
| `qq.example.com` | `evil-example.com` | 拒绝 | 注册域名不同 |
| `qq.example.com` | `example.com.evil.com` | 拒绝 | 注册域名为 `evil.com` |
| `example.com` | `sub.example.com` | 命中 | 注册域名同为 `example.com` |
| `qq.example.com` | `qq.example.com/login` | 拒绝 | D2 含路径 |
| `qq.example.com` | `https://qq.example.com` | 拒绝 | D2 含 scheme |
| `qq.example.com` | `user@qq.example.com` | 拒绝 | D2 含 userinfo |
| `qq.example.com` | `qq.example.com:443` | 拒绝 | D5 登录 `url` 不得带端口 |

路径不参与比对：登录码里没有路径，提交路径永远取绑定阶段固化的 `path`。

### 3.5 提交契约

```
POST https://<dom><path> HTTP/1.1
Content-Type: application/json

{"code":"123456","token":"3YWpb-SAJHxnipC3ar1jssu9"}
```

| 约束 | 说明 |
| --- | --- |
| 目标 | 只能是 `https://` + 固化的 `dom` + 固化的 `path` |
| 方法 | `POST` |
| 请求体 | 只含 `code` 与 `token` 两个字符串字段；不接受 `account`、`url`、`next` 等额外字段 |
| 传输 | HTTPS；校验证书；不跟随重定向 |
| 位置 | `code` / `token` 不得出现在 URL query、Referer 或日志中 |
| 成功 | `200`，响应体 `{"status":"ok","authenticated":true}` |
| 认证失败 | 统一 `401` + 固定文案，不区分 token 未知 / 过期 / 已消费 / 跨会话 / 验证码错误 / 重放 |
| 格式错误 | `400`，仅表示请求体不合法，不暗示 token 状态 |
| 限流 | `429`，不得透露 token 是否存在 |

---

## 4. 最小服务端实现

示例路由与 [spec/openapi.yaml](../spec/openapi.yaml) 完全一致（`/totp/v1/verify` 必须与绑定载荷里的 `path` 完全相同）：

| 方法 | 路径 | 请求体 | 成功响应 | 鉴权 |
| --- | --- | --- | --- | --- |
| POST | `/totp/v1/bindings` | `{issuer, account, algorithm?, digits?, period?}` | `201` `{binding_id, status:"pending", expires_at, binding_qr, binding_qr_text}` | 管理员令牌 |
| POST | `/totp/v1/bindings/{binding_id}/confirm` | `{code}` | `200` `{binding_id, status:"confirmed", confirmed_at}` | 无（App 调用） |
| POST | `/totp/v1/bindings/{binding_id}/revoke` | 无 | `200` `{binding_id, status:"revoked", revoked_at}` | 管理员令牌 |
| POST | `/totp/v1/login/token` | `{account}` | `200` `{token, expires_at, expires_in, login_qr, login_qr_text}` | 浏览器会话 |
| POST | `/totp/v1/verify` | `{code, token}` | `200` `{status:"ok", authenticated:true}` | 无 Cookie，凭 token |
| GET | `/totp/v1/session` | — | `200` `{authenticated, binding_id?, expires_at?}` | 浏览器会话 |
| POST | `/totp/v1/logout` | — | `200` `{status:"ok"}` | 浏览器会话 |
| GET | `/healthz` | — | `200` `{status:"ok"}` | 无 |

完整可运行代码见 [examples/go/main.go](examples/go/main.go)，测试见 [examples/go/main_test.go](examples/go/main_test.go)。下面只摘录三个最容易写错的地方。

### 4.1 签发 token（60 秒、一次性、绑定会话与账户）

```go
// 24 个 base64url 字符 = 18 字节 CSPRNG，满足 >=128 bit。
func randomToken(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand unavailable: " + err.Error())
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

token := randomToken(18)
digest := sha256.Sum256([]byte(token))
expiresAt := now.Add(60 * time.Second)

// 只存摘要；明文 token 只出现在响应体与二维码里。
s.tokens[digest] = &tokenRecord{
	Account:   account,      // 签发时确定的账户
	SessionID: session.ID,   // 浏览器会话
	BindingID: binding.ID,   // 签发所用的已确认绑定
	ExpiresAt: expiresAt,
	State:     tokenIssued,
}
```

响应体与登录二维码：

```go
payload := LoginQR{
	T: "totp-login", V: 1,
	URL:   hostOnly(s.cfg.SiteDom), // 只放域名，不能带端口/路径
	Token: token,
	Exp:   expiresAt.Unix(),
}

writeJSON(w, 200, map[string]any{
	"token":         token,
	"expires_at":    expiresAt.Unix(),
	"expires_in":    int(tokenTTL / time.Second),
	"login_qr":      payload,
	"login_qr_text": text,
})
```

### 4.2 校验提交（TOTP ±1、5 次失败作废、统一错误）

```go
func (s *Server) handleVerify(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code  string `json:"code"`
		Token string `json:"token"`
	}
	if err := decodeJSON(r, &req); err != nil ||
		req.Code == "" || !validTokenShape(req.Token) {
		s.fail(w, r, 400, "invalid_request", "请求格式无效")
		return
	}

	now := s.now()
	digest := sha256.Sum256([]byte(req.Token))

	s.mu.Lock()
	defer s.mu.Unlock()

	rec := s.tokens[digest]
	if rec == nil {
		// 未知 token 也做一次等价 HMAC，避免计时差异泄露 token 是否存在。
		_, _ = totpValidate([]byte("timing-equalizer-secret"), "000000", now, 30, 6, "SHA1", 1)
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}
	if rec.State != tokenIssued || now.After(rec.ExpiresAt) {
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}
	if _, ok := s.sessions[rec.SessionID]; !ok {
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}

	b := s.bindings[rec.BindingID]
	if b == nil || !b.Confirmed || b.Revoked || b.Invalid ||
		len(req.Code) != b.Digits || !allDigits(req.Code) {
		s.failToken(rec)
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}
	offset, ok := totpValidate(b.Secret, req.Code, now, b.Period, b.Digits, b.Alg, 1)
	if !ok {
		s.failToken(rec)
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}

	step := now.Unix()/int64(b.Period) + int64(offset)
	key := replayKey(b.ID, step)
	if _, used := s.usedSteps[key]; used {
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}

	// 成功路径必须原子完成：写重放记录 + 消费 token + 认证会话。
	s.usedSteps[key] = now
	rec.State = tokenConsumed
	if sess := s.sessions[rec.SessionID]; sess != nil {
		sess.Authenticated = true
		sess.BindingID = b.ID
		sess.ExpiresAt = now.Add(time.Hour)
	}
	writeJSON(w, 200, map[string]any{"status": "ok", "authenticated": true})
}

func (s *Server) failToken(rec *tokenRecord) {
	rec.Failures++
	if rec.Failures >= 5 {
		rec.State = tokenExhausted
	}
}
```

### 4.3 TOTP 校验（RFC 6238，SHA1/256/512、6/8 位、任意周期）

```go
func hotp(secret []byte, counter uint64, digits int, alg string) (string, error) {
	var mac hash.Hash
	switch alg {
	case "SHA1":
		mac = hmac.New(sha1.New, secret)
	case "SHA256":
		mac = hmac.New(sha256.New, secret)
	case "SHA512":
		mac = hmac.New(sha512.New, secret)
	default:
		return "", errors.New("unsupported algorithm")
	}
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], counter)
	_, _ = mac.Write(msg[:])
	sum := mac.Sum(nil)

	offset := sum[len(sum)-1] & 0x0f
	bin := (uint32(sum[offset])&0x7f)<<24 |
		uint32(sum[offset+1])<<16 |
		uint32(sum[offset+2])<<8 |
		uint32(sum[offset+3])

	mod := uint32(1)
	for i := 0; i < digits; i++ {
		mod *= 10
	}
	return fmt.Sprintf("%0*d", digits, bin%mod), nil
}

// 只接受 t-1 / t / t+1，返回命中的偏移。
func totpValidate(secret []byte, code string, at time.Time, period, digits int, alg string, window int) (int, bool) {
	if period <= 0 || window < 0 {
		return 0, false
	}
	counter := at.Unix() / int64(period)
	for off := -window; off <= window; off++ {
		c := counter + int64(off)
		if c < 0 {
			continue
		}
		want, err := hotp(secret, uint64(c), digits, alg)
		if err != nil {
			return 0, false
		}
		if subtle.ConstantTimeCompare([]byte(want), []byte(code)) == 1 {
			return off, true
		}
	}
	return 0, false
}
```

### 4.4 校验顺序

对应规范 §8.3，建议严格按下面顺序，任一失败即失败：

1. 请求体只含 `token` 与 `code`，都是字符串；
2. `token` 形状合法（16 或 24 个 base64url 字符）；
3. 按 SHA-256 摘要查到 token 记录；
4. 状态为 `issued` 且 `now <= expires_at`；
5. token 记录的 `session_id` 对应一个仍存在的会话；
6. 按 token 记录里的 `binding_id`（或签发时的 `account`）找到**已确认、未解绑、未失效**的绑定；
7. `code` 位数与绑定的 `dig` 一致（6 或 8 位纯数字）；
8. TOTP 在 `t-1 / t / t+1` 命中，算法与周期取自绑定记录，**不取自请求**；
9. 该 `(binding_id, timestep)` 未被成功使用过；
10. 成功：原子消费 token、写重放记录、标记 token 所属会话已认证。

### 4.5 统一错误响应

```json
{"error":"authentication_failed","message":"认证失败，请重新发起登录","request_id":"req_fb7e3c4a824f9228ba0e9a66"}
```

- `401` 覆盖 token 未知、过期、已消费、已作废、绑定不存在、未确认、验证码错误、重放、次数耗尽；
- `400` 只表示请求体格式错误，文案固定 `请求格式无效`；
- `429` 只表示限流，不区分 token 是否有效；
- `request_id` 只用于日志关联，不得编码失败原因；
- 未知 token 也要执行一次等价 HMAC，避免计时旁路（§8.5）。

---

## 5. 数据模型

### 5.1 需要落库的字段

| 表 | 字段 | 说明 |
| --- | --- | --- |
| 账户 | `account_id`、`account` | 登录名或邮箱；与站内用户表关联 |
| TOTP 绑定 | `binding_id`、`account_id`、`secret`、`alg`、`digits`、`period` | `secret` 是长期共享密钥；建议加密存储，至少限制读权限 |
| 固化地址 | `dom`、`path` | 绑定时写入；`path` 含查询串、原样保存；之后不得被请求参数覆盖 |
| 绑定状态 | `status`、`created_at`、`confirmed_at`、`failures` | `pending / confirmed / invalid / revoked` |
| 会话 | `session_id`、`account_id`、`authenticated_at`、`expires_at` | 浏览器 HttpOnly Cookie |
| 登录 token | `token_hash`、`session_id`、`account_id`、`binding_id`、`issued_at`、`expires_at`、`state`、`failures` | 只存 SHA-256 摘要；`state = issued / consumed / exhausted / revoked` |
| 重放记录 | `binding_id`、`timestep`、`used_at` | 唯一约束 `(binding_id, timestep)` |

PostgreSQL 参考 DDL（MySQL 把 `bytea` 换成 `VARBINARY`、`timestamptz` 换成 `DATETIME(6)`、`text` 换成 `VARCHAR` 即可）：

```sql
CREATE TABLE totp_bindings (
  binding_id    text PRIMARY KEY,
  account_id    bigint NOT NULL,
  secret        bytea NOT NULL,
  alg           text NOT NULL DEFAULT 'SHA1',
  digits        smallint NOT NULL DEFAULT 6,
  period        smallint NOT NULL DEFAULT 30,
  dom           text NOT NULL,
  path          text NOT NULL,
  status        text NOT NULL DEFAULT 'pending',
  failures      smallint NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  confirmed_at  timestamptz
);

CREATE TABLE login_tokens (
  token_hash    bytea PRIMARY KEY,
  session_id    text NOT NULL,
  account_id    bigint NOT NULL,
  binding_id    text NOT NULL,
  state         text NOT NULL DEFAULT 'issued',
  failures      smallint NOT NULL DEFAULT 0,
  issued_at     timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  consumed_at   timestamptz
);

CREATE TABLE totp_replay (
  binding_id    text NOT NULL,
  timestep      bigint NOT NULL,
  used_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (binding_id, timestep)
);
```

### 5.2 token 状态机

```
                 签发
                  |
                  v
              +---------+   校验成功     +-----------+
              | issued  | -------------> | consumed  |
              +---------+                +-----------+
                |    |
      5 次失败  |    | now > expires_at
                v    v
          +-----------+  +---------+
          | exhausted |  | expired |
          +-----------+  +---------+
                |
                +---- 登出 / 解绑 ----> revoked
```

状态一旦离开 `issued` 就不可恢复；任何失败都不得续期或重置计数（§8.1）。

### 5.3 并发与多实例

单进程的内存 map + 互斥锁只能用于本地演示。多实例部署必须共享存储，否则「一次性」「5 次作废」「重放记录」全部失效，表现为随机 401 或同一 token 被消费两次（§10(14)）。

**Redis：原子消费**

```
-- KEYS[1] = totpscan:token:<sha256>
-- 返回 1 表示消费成功；0 表示不存在/已消费/已过期
local v = redis.call('GET', KEYS[1])
if not v then return 0 end
redis.call('DEL', KEYS[1])
return 1
```

签发时用 `SET key value NX EX 60`；失败计数用 `HINCRBY`，第 5 次失败时 `DEL` 或写入 `exhausted` 标记。注意不要把「读状态 → 判断 → 写状态」拆成多条命令。

**SQL：条件更新**

```sql
UPDATE login_tokens
SET state = 'consumed', consumed_at = now()
WHERE token_hash = $1
  AND state = 'issued'
  AND expires_at > now()
RETURNING account_id, session_id;
```

返回 0 行即失败。失败计数同样用一条条件更新完成：

```sql
UPDATE login_tokens
SET failures = failures + 1,
    state = CASE WHEN failures + 1 >= 5 THEN 'exhausted' ELSE state END
WHERE token_hash = $1 AND state = 'issued'
RETURNING failures, state;
```

时钟：服务端时钟是唯一权威。部署方应启用 NTP；`period=30` 时 ±1 窗口意味着最多容忍约 ±30 秒偏差，**不得**因为客户端偏差把窗口放宽到 ±2。重放键使用服务端计算出的时间步，不使用客户端时间（§13.7）。

---

## 6. 安全边界（必须向业务方说明）

1. **TOTP 根凭证仍是长期共享密钥**：`sec` 一旦泄露，攻击者可以离线生成任意动态码。这不是「无密码」方案。
2. **不防服务器被攻破**：服务端持有 `sec` 与全部校验逻辑，服务器失守等同账户失守，客户端无法从协议层识别。
3. **不是抗钓鱼强认证**：地址比对只能阻断「假地址」；攻击者可以在钓鱼页展示**真实的** `url`，把受害者的动态码中继到真实服务端，同时让 `token` 属于攻击者自己的浏览器会话。本协议不解决这种「真地址中继」（§10(1)）。
4. **绑定二维码是「扫到什么信什么」**：v1 不签名，能替换二维码的人就能注入自己的 `sec` 与提交地址；只能靠用户在确认页核对 `iss/acc/dom/path`（§5、§10(2)）。
5. **动态码空间小**：6 位只有 10^6 种；每次提交可命中 `t-1/t/t+1` 三个时间步，单次尝试命中概率约为 3/10^6。必须用「≤5 次失败作废 + 限流」兜底，否则可被在线枚举（§10(5)）。
6. **TLS 是必要条件**：必须全站 HTTPS、HSTS、校验证书、禁止提交时跟随重定向；否则中间人可以改写二维码或请求（§10(7)）。
7. **会话安全同样重要**：Cookie 使用 `HttpOnly; Secure; SameSite=Lax`；否则会话固定、CSRF 或 Cookie 作用域缺陷会绕过 token 的会话绑定（§10(8)）。
8. **日志即泄露面**：`sec`、`code`、`token` 都不得进入访问日志、错误日志、APM、崩溃报告或分析事件。

---

## 7. 常见错误排查

| 症状 | 可能原因 | 处理 |
| --- | --- | --- |
| App 提示「未找到与该二维码匹配的站点」 | `url` 与固化的 `dom` 注册域名不同；`url` 带了端口/路径/scheme；或本地 PSL 推导错误 | 按 §7.2 规范化；确认 `url` 只写域名；检查 PSL 是否包含 PRIVATE 段 |
| 绑定二维码扫了没反应 / 提示载荷非法 | 字段缺失、`alg/dig/per` 非法、`sec` 带 `=` 或小写、`path` 不以 `/` 开头、`exp` 已过期 | 用 §4.3 的字段表逐项校验；生成时统一 Base32 大写无填充 |
| 提交后一直 401 | token 已过期（>60s）、已消费、已作废；账户没有已确认绑定；`account` 与 token 绑定不一致；TOTP 参数取自请求而非绑定记录 | 重新签发 token；确认绑定状态；核对服务端使用的 `alg/dig/per` 与绑定记录一致 |
| 第 5 次错误后正确码也失败 | 设计如此：5 次失败后 token 置 `exhausted` | 重新签发 token；不要重置失败计数 |
| 偶发 429 | 签发或校验触发限流；多标签页/多实例共享了计数键 | 不要复用同一 token 重试；退避后重新签发；检查 Redis key 维度 |
| 多实例部署下随机 401 或同一 token 成功两次 | token、失败计数、重放记录存在进程内存里，实例之间不共享 | 换成 Redis / SQL 共享存储，并用原子操作消费（见 §5.3） |
| 时间窗边缘偶发失败 | 设备或服务端时钟漂移超过一个 `period` | 启用 NTP；不要扩大窗口到 ±2；检查 `period` 是否按绑定记录取值 |
| 换子域后登录被拒 | 子域的注册域名不同（例如 `a.example.com` 与 `a.example.co.uk`） | 这是预期行为；同一注册域名下的子域才会命中 |
| 浏览器端提交被 CORS 拦截 | 用网页 JS 直接 POST 到站点 | 正常链路是 App 提交，不经过浏览器；如果是自研网页客户端，显式配置 CORS，但不要因此放宽 token 校验 |
| 日志里出现 token / code / sec | 日志中间件打印了完整请求体或 URL | 只记录 `request_id`、状态码、耗时；请求体字段白名单；`sec` 永不入库日志 |
| 绑定确认后立刻登录失败 | 确认与登录使用了同一个时间步，被重放记录拒绝 | App 等一个 `period` 或用下一个时间步的码；服务端重放记录按 `(binding_id, timestep)` 设计（§13.7） |
| 解绑后旧 token 仍能用 | 解绑只改了绑定状态，没有作废该账户的未消费 token | 解绑时同时把相关 token 置 `revoked`，并清理重放记录（S12） |

---

## 8. 接入 checklist

- [ ] 1. 全站 HTTPS + HSTS；提交端点校验证书、禁止跟随重定向（S11）。
- [ ] 2. 管理员令牌 fail-closed：未配置或 <32 字符拒绝启动，所有管理路由复用同一校验（S14）。
- [ ] 3. 绑定二维码一次性展示，`exp` 建议 ≤600 秒；`bid` 确认后不可重复确认（S13）。
- [ ] 4. `dom` 来自服务端配置，`path` 绑定时原样落库；任何请求参数都不能覆盖提交目标（S1、S3）。
- [ ] 5. 登录二维码的 `url` 只写域名（无 scheme、路径、端口、userinfo），且从不作为提交目标（S2、S3）。
- [ ] 6. `token` 用 CSPRNG ≥128 bit（建议 18 字节 → 24 字符），TTL ≤60 秒，服务端时钟判定（S6）。
- [ ] 7. 存储与日志只出现 token 的 SHA-256 摘要，不出现明文 token；`sec` / `code` 同样不入日志（S6、S11、S13）。
- [ ] 8. token 同时绑定 `session_id` 与 `account`；成功即原子消费；解绑作废相关 token 与重放记录（S7、S12）。
- [ ] 9. 单 token 失败 5 次即 `exhausted`；绑定确认同样 5 次失败即 `invalid`（S8）。
- [ ] 10. TOTP 只接受 `t-1/t/t+1`；同一 `(binding_id, timestep)` 成功一次即写重放记录（S4、S9）。
- [ ] 11. 所有认证失败返回同一 `401` 响应体；未知 token 也执行等价 HMAC（S10）。
- [ ] 12. 多实例共享存储，消费/计数/重放写入原子；服务端启用 NTP（§10(14)、§13.7）。

---

## 9. 验证记录

本文与 [examples/go/main.go](examples/go/main.go) 中的代码在本机实际执行过：

- Go 版本：`go1.23.4 windows/amd64`
- `gofmt -l .`：无输出
- `go vet ./...`：通过（退出码 0）
- `go build ./...`：通过（退出码 0）
- `go test ./... -count=1 -v`：**9 个测试全部通过**
  - RFC 6238 官方向量（SHA1 / SHA256 / SHA512，8 位）
  - 地址规范化与注册域名比对判定表
  - TOTP ±1 窗口
  - 绑定 → 确认 → 登录 → 提交全链路
  - token 过期、重放
  - 连续 5 次错误码后作废
  - 16 个并发提交同一 token 只有 1 个成功
  - 统一错误响应体
  - 签发限流（第 6 次 429）
- 本地 HTTP 端到端（`http://127.0.0.1:18080`，`SITE_DOM=localhost:18080`、`SUBMIT_PATH=/totp/v1/verify`）：
  - `GET /healthz` → 200 `{"status":"ok"}`
  - `POST /totp/v1/bindings` → 201，返回 `{binding_id, status:"pending", expires_at, binding_qr, binding_qr_text}`
  - `POST /totp/v1/bindings/{binding_id}/confirm` → 200 `{"binding_id":"...","status":"confirmed","confirmed_at":...}`
  - `POST /totp/v1/login/token` → 200，返回 `{token, expires_at, expires_in:60, login_qr, login_qr_text}`，`login_qr.url` 为纯域名
  - `POST /totp/v1/verify` → 200 `{"status":"ok","authenticated":true}`
  - 同一 token 重放 → 401
  - `GET /totp/v1/session` → `{"authenticated":true,"binding_id":"...","expires_at":...}`
  - `POST /totp/v1/logout` → 200 `{"status":"ok"}`；随后 `GET /totp/v1/session` → `{"authenticated":false,"binding_id":null}`

未验证部分：真实 HTTPS 证书、Redis / SQL 实现、完整 PSL（示例只内置少量多段公共后缀）、各客户端 App 的扫码与固化逻辑。文档中标注为「示例」的片段均来自上述已编译文件；未单独运行的 SQL / Lua 片段为静态检查。

---

## 附录：单账户 `otpauth://` 导出

标准型账户或需要迁移的单账户，可导出标准 URI（§13.2）：

```
otpauth://totp/Example%20Corp:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example%20Corp&algorithm=SHA1&digits=6&period=30
```

- 单账户导出是**明文标准 URI**；本地存储可以加密，但导出内容本身不加密。
- 导出后的副本没有固化地址与地址比对能力，防钓鱼增强失效，必须向用户明确提示。
- `sec` 不得写入日志、剪贴板（用户主动粘贴除外）、分析事件或长期明文界面。
