// Command totpscan-example 是一个零第三方依赖的 TOTPSCAN/v1 最小服务端示例。
//
// 它演示四件事：
//  1. 绑定二维码载荷的生成（无签名，字段与 spec §4.3 一致）；
//  2. 登录 token 的签发（24 位 base64url、60 秒、与会话和账户绑定、只存摘要）；
//  3. POST /totp/v1/verify 的校验（TOTP ±1 窗口、一次性、5 次失败作废）；
//  4. 站点域名规范化与注册域名比对（App 侧逻辑，本示例用于自检和测试）。
//
// 运行（Windows PowerShell）：
//
//	$env:ADMIN_TOKEN = "<用 openssl rand -hex 32 生成的 64 位随机串>"  # >= 32 字符
//	go run .
//
// 然后按 docs/integration-guide.md 的 curl 步骤联调。生产环境必须置于 HTTPS 之后。
package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/sha512"
	"crypto/subtle"
	"encoding/base32"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	protocolVersion = 1
	sessionCookie   = "tsid"

	tokenTTL           = 60 * time.Second
	bindingTTL         = 10 * time.Minute
	maxTokenFailures   = 5
	maxBindingFailures = 5
	totpWindow         = 1
	maxIssuePerMinute  = 5
)

// Config 是示例服务的运行时配置。生产环境应从环境变量或配置中心读取，
// 并且 ADMIN_TOKEN 必须 fail-closed（未配置或过短时拒绝启动）。
type Config struct {
	AdminToken string
	SiteDom    string // 绑定二维码里的 dom：host[:port]
	SubmitPath string // 绑定二维码里的 path：提交路径（含查询串时原样保留）
	Issuer     string
	ListenAddr string
}

func loadConfig() (Config, error) {
	cfg := Config{
		AdminToken: os.Getenv("ADMIN_TOKEN"),
		SiteDom:    getenv("SITE_DOM", "localhost:8080"),
		SubmitPath: getenv("SUBMIT_PATH", "/totp/v1/verify"),
		Issuer:     getenv("ISSUER", "Example Corp"),
		ListenAddr: getenv("LISTEN_ADDR", "127.0.0.1:8080"),
	}
	if len(cfg.AdminToken) < 32 {
		return Config{}, errors.New("ADMIN_TOKEN 必须设置且长度 >= 32 字符（fail-closed）")
	}
	if _, err := normalizeHost(cfg.SiteDom, true); err != nil {
		return Config{}, fmt.Errorf("SITE_DOM 不合法: %w", err)
	}
	if cfg.SiteDom != strings.ToLower(cfg.SiteDom) || strings.HasSuffix(cfg.SiteDom, ".") {
		return Config{}, errors.New("SITE_DOM 必须是小写 IDNA A-label，且不带结尾的点")
	}
	if !strings.HasPrefix(cfg.SubmitPath, "/") || strings.ContainsAny(cfg.SubmitPath, "# \t\r\n") {
		return Config{}, errors.New("SUBMIT_PATH 必须以 / 开头，且不得含空白或 #")
	}
	return cfg, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// Binding 是一条已确认或待确认的扫码型账户绑定。
type Binding struct {
	ID          string
	Issuer      string
	Account     string
	Secret      []byte
	Alg         string
	Digits      int
	Period      int
	Dom         string
	Path        string
	CreatedAt   time.Time
	ExpiresAt   time.Time
	Confirmed   bool
	ConfirmedAt time.Time
	Invalid     bool
	Revoked     bool
	Failures    int
}

type tokenState int

const (
	tokenIssued tokenState = iota
	tokenConsumed
	tokenExhausted
)

// tokenRecord 只保存 token 的 SHA-256 摘要作为 map key，不保存明文。
type tokenRecord struct {
	Account   string
	SessionID string
	BindingID string
	ExpiresAt time.Time
	State     tokenState
	Failures  int
}

type Session struct {
	ID            string
	Authenticated bool
	BindingID     string
	ExpiresAt     time.Time
}

// Server 用一把互斥锁保护全部状态，保证 token 的一次性消费、失败计数和
// 重放记录在并发提交下是原子的。生产环境应换成 Redis / SQL 的原子操作。
type Server struct {
	cfg Config
	now func() time.Time

	mu        sync.Mutex
	bindings  map[string]*Binding
	tokens    map[[32]byte]*tokenRecord
	sessions  map[string]*Session
	usedSteps map[string]time.Time
	issueLog  map[string][]time.Time
}

func NewServer(cfg Config) *Server {
	return &Server{
		cfg:       cfg,
		now:       time.Now,
		bindings:  make(map[string]*Binding),
		tokens:    make(map[[32]byte]*tokenRecord),
		sessions:  make(map[string]*Session),
		usedSteps: make(map[string]time.Time),
		issueLog:  make(map[string][]time.Time),
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("POST /totp/v1/bindings", s.requireAdmin(s.handleBind))
	mux.HandleFunc("POST /totp/v1/bindings/{binding_id}/confirm", s.handleBindConfirm)
	mux.HandleFunc("POST /totp/v1/bindings/{binding_id}/revoke", s.requireAdmin(s.handleRevoke))
	mux.HandleFunc("POST /totp/v1/login/token", s.handleLoginToken)
	mux.HandleFunc("POST /totp/v1/verify", s.handleVerify)
	mux.HandleFunc("GET /totp/v1/session", s.handleSession)
	mux.HandleFunc("POST /totp/v1/logout", s.handleLogout)
	return withRequestContext(mux)
}

type ctxKey string

const requestIDKey ctxKey = "request_id"

func withRequestContext(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := newRequestID()
		w.Header().Set("X-Request-Id", id)
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), requestIDKey, id)))
	})
}

func newRequestID() string {
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		return "req_randomunavailable"
	}
	return "req_" + hex.EncodeToString(b)
}

func requestID(r *http.Request) string {
	if id, ok := r.Context().Value(requestIDKey).(string); ok {
		return id
	}
	return newRequestID()
}

// ---- HTTP 基础设施 ----

type apiError struct {
	Error     string `json:"error"`
	Message   string `json:"message"`
	RequestID string `json:"request_id"`
}

func (s *Server) fail(w http.ResponseWriter, r *http.Request, status int, code, message string) {
	writeJSON(w, status, apiError{Error: code, Message: message, RequestID: requestID(r)})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(v)
}

func decodeJSON(r *http.Request, dst any) error {
	dec := json.NewDecoder(io.LimitReader(r.Body, 64<<10))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return err
	}
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		return errors.New("请求体只能包含一个 JSON 对象")
	}
	return nil
}

func (s *Server) requireAdmin(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		const prefix = "Bearer "
		auth := r.Header.Get("Authorization")
		got := strings.TrimSpace(strings.TrimPrefix(auth, prefix))
		if !strings.HasPrefix(auth, prefix) ||
			subtle.ConstantTimeCompare([]byte(got), []byte(s.cfg.AdminToken)) != 1 {
			s.fail(w, r, 401, "forbidden", "无权访问")
			return
		}
		next(w, r)
	}
}

// ---- 绑定 ----

// BindingQR 是绑定二维码的 JSON 载荷（spec §4.3）。v1 无签名、无公钥字段。
type BindingQR struct {
	T    string `json:"t"`
	V    int    `json:"v"`
	Bid  string `json:"bid"`
	Iss  string `json:"iss"`
	Acc  string `json:"acc"`
	Sec  string `json:"sec"`
	Alg  string `json:"alg"`
	Dig  int    `json:"dig"`
	Per  int    `json:"per"`
	Dom  string `json:"dom"`
	Path string `json:"path"`
	Iat  int64  `json:"iat"`
	Exp  int64  `json:"exp,omitempty"`
}

func (s *Server) handleBind(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Issuer    string `json:"issuer"`
		Account   string `json:"account"`
		Algorithm string `json:"algorithm"`
		Digits    int    `json:"digits"`
		Period    int    `json:"period"`
	}
	if err := decodeJSON(r, &req); err != nil {
		s.fail(w, r, 400, "invalid_request", "请求格式无效")
		return
	}
	req.Account = strings.TrimSpace(req.Account)
	req.Issuer = strings.TrimSpace(req.Issuer)
	if req.Algorithm == "" {
		req.Algorithm = "SHA1"
	}
	if req.Digits == 0 {
		req.Digits = 6
	}
	if req.Period == 0 {
		req.Period = 30
	}
	if !validAccount(req.Account) || !validIssuer(req.Issuer) || !validTOTPParams(req.Algorithm, req.Digits, req.Period) {
		s.fail(w, r, 400, "invalid_request", "请求格式无效")
		return
	}

	secret := make([]byte, 20) // 160 bit，满足规范 >=128 bit 的建议
	if _, err := rand.Read(secret); err != nil {
		s.fail(w, r, 500, "internal_error", "服务暂时不可用")
		return
	}
	bid := "b_" + randomToken(16) // b_ + 22 字符，符合 ^b_[A-Za-z0-9_-]{16,64}$
	now := s.now()
	binding := &Binding{
		ID:        bid,
		Issuer:    req.Issuer,
		Account:   req.Account,
		Secret:    secret,
		Alg:       req.Algorithm,
		Digits:    req.Digits,
		Period:    req.Period,
		Dom:       s.cfg.SiteDom,
		Path:      s.cfg.SubmitPath,
		CreatedAt: now,
		ExpiresAt: now.Add(bindingTTL),
	}

	s.mu.Lock()
	s.bindings[bid] = binding
	s.mu.Unlock()

	payload := BindingQR{
		T:    "totp-bind",
		V:    protocolVersion,
		Bid:  bid,
		Iss:  req.Issuer,
		Acc:  req.Account,
		Sec:  encodeBase32(secret),
		Alg:  req.Algorithm,
		Dig:  req.Digits,
		Per:  req.Period,
		Dom:  binding.Dom,
		Path: binding.Path,
		Iat:  now.Unix(),
		Exp:  binding.ExpiresAt.Unix(),
	}
	text, err := compactJSON(payload)
	if err != nil {
		s.fail(w, r, 500, "internal_error", "服务暂时不可用")
		return
	}
	writeJSON(w, 201, map[string]any{
		"binding_id":      bid,
		"status":          "pending",
		"expires_at":      binding.ExpiresAt.Unix(),
		"binding_qr":      payload,
		"binding_qr_text": text,
	})
}

func (s *Server) handleBindConfirm(w http.ResponseWriter, r *http.Request) {
	bid := r.PathValue("binding_id")
	var req struct {
		Code string `json:"code"`
	}
	if err := decodeJSON(r, &req); err != nil || !strings.HasPrefix(bid, "b_") || req.Code == "" {
		s.fail(w, r, 400, "invalid_request", "请求格式无效")
		return
	}
	now := s.now()

	s.mu.Lock()
	defer s.mu.Unlock()

	b := s.bindings[bid]
	if b == nil || b.Revoked || b.Invalid || b.Confirmed || now.After(b.ExpiresAt) {
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}
	if len(req.Code) != b.Digits || !allDigits(req.Code) {
		b.Failures++
		if b.Failures >= maxBindingFailures {
			b.Invalid = true
		}
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}
	offset, ok := totpValidate(b.Secret, req.Code, now, b.Period, b.Digits, b.Alg, totpWindow)
	if !ok {
		b.Failures++
		if b.Failures >= maxBindingFailures {
			b.Invalid = true
		}
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}
	step := now.Unix()/int64(b.Period) + int64(offset)
	key := replayKey(b.ID, step)
	if _, used := s.usedSteps[key]; used {
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}
	s.usedSteps[key] = now
	b.Confirmed = true
	b.ConfirmedAt = now
	writeJSON(w, 200, map[string]any{
		"binding_id":   b.ID,
		"status":       "confirmed",
		"confirmed_at": now.Unix(),
	})
}

func (s *Server) handleRevoke(w http.ResponseWriter, r *http.Request) {
	bid := r.PathValue("binding_id")
	if bid == "" {
		s.fail(w, r, 400, "invalid_request", "请求格式无效")
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	b := s.bindings[bid]
	if b == nil {
		s.fail(w, r, 404, "not_found", "资源不存在")
		return
	}
	now := s.now()
	b.Revoked = true
	for _, rec := range s.tokens {
		if rec.BindingID == b.ID && rec.State == tokenIssued {
			rec.State = tokenExhausted
		}
	}
	for k := range s.usedSteps {
		if strings.HasPrefix(k, b.ID+":") {
			delete(s.usedSteps, k)
		}
	}
	writeJSON(w, 200, map[string]any{
		"binding_id": b.ID,
		"status":     "revoked",
		"revoked_at": now.Unix(),
	})
}

// ---- 登录 ----

// LoginQR 是登录二维码的 JSON 载荷（spec §6.4）：url 只有域名，没有路径。
type LoginQR struct {
	T     string `json:"t"`
	V     int    `json:"v"`
	URL   string `json:"url"`
	Token string `json:"token"`
	Exp   int64  `json:"exp"`
}

func (s *Server) handleLoginToken(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Account string `json:"account"`
	}
	if err := decodeJSON(r, &req); err != nil || !validAccount(strings.TrimSpace(req.Account)) {
		s.fail(w, r, 400, "invalid_request", "请求格式无效")
		return
	}
	account := strings.TrimSpace(req.Account)
	sess := s.ensureSession(w, r)
	now := s.now()

	s.mu.Lock()
	defer s.mu.Unlock()

	// 单会话 5 次 / 60 秒的签发限流。
	times := s.issueLog[sess.ID]
	kept := times[:0]
	cutoff := now.Add(-time.Minute)
	for _, ts := range times {
		if ts.After(cutoff) {
			kept = append(kept, ts)
		}
	}
	s.issueLog[sess.ID] = kept
	if len(kept) >= maxIssuePerMinute {
		s.fail(w, r, 429, "rate_limited", "请求过于频繁")
		return
	}

	b := s.findConfirmedBindingLocked(account)
	if b == nil {
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}

	token := randomToken(18) // 24 个 base64url 字符
	digest := sha256.Sum256([]byte(token))
	expiresAt := now.Add(tokenTTL)
	s.tokens[digest] = &tokenRecord{
		Account:   account,
		SessionID: sess.ID,
		BindingID: b.ID,
		ExpiresAt: expiresAt,
		State:     tokenIssued,
	}
	s.issueLog[sess.ID] = append(s.issueLog[sess.ID], now)

	payload := LoginQR{
		T:     "totp-login",
		V:     protocolVersion,
		URL:   hostOnly(s.cfg.SiteDom),
		Token: token,
		Exp:   expiresAt.Unix(),
	}
	text, err := compactJSON(payload)
	if err != nil {
		s.fail(w, r, 500, "internal_error", "服务暂时不可用")
		return
	}
	writeJSON(w, 200, map[string]any{
		"token":         token,
		"expires_at":    expiresAt.Unix(),
		"expires_in":    int(tokenTTL / time.Second),
		"login_qr":      payload,
		"login_qr_text": text,
	})
}

func (s *Server) handleVerify(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code  string `json:"code"`
		Token string `json:"token"`
	}
	if err := decodeJSON(r, &req); err != nil || req.Code == "" || !validTokenShape(req.Token) {
		s.fail(w, r, 400, "invalid_request", "请求格式无效")
		return
	}
	now := s.now()
	digest := sha256.Sum256([]byte(req.Token))

	s.mu.Lock()
	defer s.mu.Unlock()

	rec := s.tokens[digest]
	if rec == nil {
		// 未知 token 也执行一次等价 HMAC，避免通过响应时间判断 token 是否存在。
		_, _ = totpValidate([]byte("timing-equalizer-secret"), "000000", now, 30, 6, "SHA1", totpWindow)
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
	if b == nil || !b.Confirmed || b.Revoked || b.Invalid || len(req.Code) != b.Digits || !allDigits(req.Code) {
		s.failToken(rec)
		s.fail(w, r, 401, "authentication_failed", "认证失败，请重新发起登录")
		return
	}
	offset, ok := totpValidate(b.Secret, req.Code, now, b.Period, b.Digits, b.Alg, totpWindow)
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

	// 成功路径：标记 token 已消费、写入重放记录、认证 token 所属会话，三步在同一临界区。
	s.usedSteps[key] = now
	rec.State = tokenConsumed
	if sess := s.sessions[rec.SessionID]; sess != nil {
		sess.Authenticated = true
		sess.BindingID = b.ID
		sess.ExpiresAt = now.Add(time.Hour)
	}
	s.pruneUsedStepsLocked(now)
	writeJSON(w, 200, map[string]any{"status": "ok", "authenticated": true})
}

func (s *Server) failToken(rec *tokenRecord) {
	rec.Failures++
	if rec.Failures >= maxTokenFailures {
		rec.State = tokenExhausted
	}
}

func (s *Server) findConfirmedBindingLocked(account string) *Binding {
	var best *Binding
	for _, b := range s.bindings {
		if b.Account != account || !b.Confirmed || b.Revoked || b.Invalid {
			continue
		}
		if best == nil || b.ConfirmedAt.After(best.ConfirmedAt) {
			best = b
		}
	}
	return best
}

func replayKey(bindingID string, step int64) string {
	return bindingID + ":" + strconv.FormatInt(step, 10)
}

func (s *Server) pruneUsedStepsLocked(now time.Time) {
	cutoff := now.Add(-10 * time.Minute)
	for k, usedAt := range s.usedSteps {
		if usedAt.Before(cutoff) {
			delete(s.usedSteps, k)
		}
	}
}

func (s *Server) handleSession(w http.ResponseWriter, r *http.Request) {
	c, err := r.Cookie(sessionCookie)
	if err != nil {
		writeJSON(w, 200, map[string]any{"authenticated": false, "binding_id": nil})
		return
	}

	s.mu.Lock()
	out := map[string]any{"authenticated": false, "binding_id": nil}
	if sess := s.sessions[c.Value]; sess != nil && sess.Authenticated {
		out["authenticated"] = true
		out["binding_id"] = sess.BindingID
		out["expires_at"] = sess.ExpiresAt.Unix()
	}
	s.mu.Unlock()

	writeJSON(w, 200, out)
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	c, err := r.Cookie(sessionCookie)
	if err == nil {
		s.mu.Lock()
		for _, rec := range s.tokens {
			if rec.SessionID == c.Value && rec.State == tokenIssued {
				rec.State = tokenExhausted
			}
		}
		delete(s.sessions, c.Value)
		delete(s.issueLog, c.Value)
		s.mu.Unlock()
	}
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Secure:   r.TLS != nil,
	})
	writeJSON(w, 200, map[string]string{"status": "ok"})
}

func (s *Server) ensureSession(w http.ResponseWriter, r *http.Request) *Session {
	if c, err := r.Cookie(sessionCookie); err == nil {
		s.mu.Lock()
		sess := s.sessions[c.Value]
		s.mu.Unlock()
		if sess != nil {
			return sess
		}
	}
	sess := &Session{ID: randomToken(18), ExpiresAt: s.now().Add(time.Hour)}
	s.mu.Lock()
	s.sessions[sess.ID] = sess
	s.mu.Unlock()
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    sess.ID,
		Path:     "/",
		MaxAge:   3600,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Secure:   r.TLS != nil,
	})
	return sess
}

// ---- TOTP（RFC 6238） ----

var errUnsupportedAlg = errors.New("unsupported TOTP algorithm")

// hotp 实现 RFC 4226 的动态截断；digits 为 6 或 8。
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
		return "", errUnsupportedAlg
	}
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], counter)
	if _, err := mac.Write(msg[:]); err != nil {
		return "", err
	}
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

// totpCode 计算某一时刻的动态码，便于服务端自检和测试。
func totpCode(secret []byte, at time.Time, period, digits int, alg string) (string, error) {
	if period <= 0 {
		return "", errors.New("period must be positive")
	}
	return hotp(secret, uint64(at.Unix()/int64(period)), digits, alg)
}

// totpValidate 只接受 t-1 / t / t+1 三个时间步，返回命中窗口的偏移（-1/0/+1）。
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

// ---- 地址规范化与注册域名比对（spec §7.2 D1–D5 / §7.3 M1–M3） ----

// multiLabelPublicSuffixes 只覆盖少量常见的多段公共后缀。
//
// 注意：协议要求客户端使用完整 PSL（ICANN + PRIVATE）。生产环境请使用
// golang.org/x/net/publicsuffix 或等价实现，本节仅用于让示例保持零依赖。
var multiLabelPublicSuffixes = map[string]bool{
	"com.cn": true, "net.cn": true, "org.cn": true, "gov.cn": true,
	"edu.cn": true, "ac.cn": true,
	"co.uk": true, "org.uk": true, "ac.uk": true, "gov.uk": true,
	"com.au": true, "net.au": true, "org.au": true,
	"co.jp": true, "ne.jp": true, "or.jp": true,
	"com.hk": true, "com.tw": true, "co.kr": true,
	"com.sg": true, "com.br": true, "com.mx": true, "co.in": true,
}

// normalizeHost 实现 D1–D5：
//
//	D1 字符串、长度 1–255、无前后空白、无控制字符
//	D2 无 scheme / 路径 / 查询串 / fragment / userinfo
//	D3 转小写、去掉结尾的点（本例只接受 ASCII A-label，非 ASCII 需先 IDNA ToASCII）
//	D4 结果非空
//	D5 输出仅域名；dom 允许非默认端口，登录 url 不允许端口
func normalizeHost(raw string, allowPort bool) (string, error) {
	if raw == "" || len(raw) > 255 {
		return "", errors.New("长度必须在 1–255 之间")
	}
	if strings.TrimSpace(raw) != raw {
		return "", errors.New("不得有前后空白")
	}
	for _, r := range raw {
		if r < 0x20 || r == 0x7f {
			return "", errors.New("不得含控制字符")
		}
	}
	if strings.Contains(raw, "://") {
		return "", errors.New("不得含 scheme")
	}
	if strings.ContainsAny(raw, "/?#@") {
		return "", errors.New("不得含路径、查询串、fragment 或 userinfo")
	}

	host := raw
	if strings.Contains(raw, ":") {
		if !allowPort {
			return "", errors.New("登录 url 不得带端口")
		}
		h, p, err := net.SplitHostPort(raw)
		if err != nil {
			return "", errors.New("端口格式无效")
		}
		if !allDigits(p) || len(p) > 5 {
			return "", errors.New("端口格式无效")
		}
		n, err := strconv.Atoi(p)
		if err != nil || n < 1 || n > 65535 {
			return "", errors.New("端口超出范围")
		}
		host = h
	}
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	if host == "" {
		return "", errors.New("域名为空")
	}
	if len(host) > 253 {
		return "", errors.New("域名过长")
	}
	if net.ParseIP(host) != nil {
		return host, nil
	}
	for _, label := range strings.Split(host, ".") {
		if label == "" || len(label) > 63 {
			return "", errors.New("域名标签无效")
		}
		if strings.HasPrefix(label, "-") || strings.HasSuffix(label, "-") {
			return "", errors.New("域名标签不得以 - 开头或结尾")
		}
		for _, r := range label {
			if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' {
				continue
			}
			return "", errors.New("本例只处理 ASCII A-label 域名，非 ASCII 请先做 IDNA ToASCII")
		}
	}
	return host, nil
}

// registeredDomain 推导注册域名（eTLD+1）。生产环境请换成完整 PSL 实现。
func registeredDomain(host string) string {
	if net.ParseIP(host) != nil {
		return host
	}
	labels := strings.Split(host, ".")
	if len(labels) <= 2 {
		return host
	}
	suffix := strings.Join(labels[len(labels)-2:], ".")
	n := 2
	if multiLabelPublicSuffixes[suffix] {
		n = 3
	}
	if n > len(labels) {
		n = len(labels)
	}
	return strings.Join(labels[len(labels)-n:], ".")
}

// compareSite 是 App 侧 M1–M3 的最小实现：规范化后比较注册域名。
// 服务端不需要用它来决定提交目标；它只用于自检、测试或管理端校验。
func compareSite(loginURL, pinnedDom string) (bool, string) {
	u, err := normalizeHost(loginURL, false)
	if err != nil {
		return false, "登录 url 不合规: " + err.Error()
	}
	d, err := normalizeHost(pinnedDom, true)
	if err != nil {
		return false, "绑定 dom 不合规: " + err.Error()
	}
	ur, dr := registeredDomain(u), registeredDomain(d)
	if ur != dr {
		return false, fmt.Sprintf("注册域名不同: %s != %s", ur, dr)
	}
	return true, "命中: " + ur
}

// ---- 小工具 ----

func validTokenShape(tok string) bool {
	if len(tok) != 16 && len(tok) != 24 {
		return false
	}
	for _, r := range tok {
		switch {
		case r >= 'A' && r <= 'Z':
		case r >= 'a' && r <= 'z':
		case r >= '0' && r <= '9':
		case r == '-', r == '_':
		default:
			return false
		}
	}
	return true
}

func randomToken(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		// CSPRNG 不可用时必须失败关闭，不能退化成弱随机。
		panic("crypto/rand unavailable: " + err.Error())
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

func allDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func hasControl(s string) bool {
	for _, r := range s {
		if r < 0x20 || r == 0x7f {
			return true
		}
	}
	return false
}

func validAccount(s string) bool {
	return len(s) >= 1 && len(s) <= 255 && !hasControl(s)
}

func validIssuer(s string) bool {
	return len(s) >= 1 && len(s) <= 64 && !hasControl(s)
}

func validTOTPParams(alg string, digits, period int) bool {
	if alg != "SHA1" && alg != "SHA256" && alg != "SHA512" {
		return false
	}
	if digits != 6 && digits != 8 {
		return false
	}
	return period == 30 || period == 60
}

func hostOnly(hostport string) string {
	if h, _, err := net.SplitHostPort(hostport); err == nil {
		return strings.Trim(h, "[]")
	}
	return strings.Trim(hostport, "[]")
}

func compactJSON(v any) (string, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return "", err
	}
	return strings.TrimSuffix(buf.String(), "\n"), nil
}

func encodeBase32(b []byte) string {
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b)
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("配置错误: %v", err)
	}
	srv := NewServer(cfg)
	httpSrv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("TOTPSCAN 示例服务监听 http://%s", cfg.ListenAddr)
	log.Printf("绑定载荷将使用 dom=%s path=%s", cfg.SiteDom, cfg.SubmitPath)
	log.Fatal(httpSrv.ListenAndServe())
}
