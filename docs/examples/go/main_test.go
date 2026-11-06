package main

import (
	"encoding/base32"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func newTestServer(t *testing.T) *Server {
	t.Helper()
	return NewServer(Config{
		AdminToken: strings.Repeat("a", 32),
		SiteDom:    "localhost:8080",
		SubmitPath: "/totp/v1/verify",
		Issuer:     "Test Corp",
		ListenAddr: "127.0.0.1:0",
	})
}

func doJSON(t *testing.T, s *Server, method, path string, body any, sid string, admin bool) *httptest.ResponseRecorder {
	t.Helper()
	var reader io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal: %v", err)
		}
		reader = strings.NewReader(string(raw))
	}
	req := httptest.NewRequest(method, path, reader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if sid != "" {
		req.AddCookie(&http.Cookie{Name: sessionCookie, Value: sid})
	}
	if admin {
		req.Header.Set("Authorization", "Bearer "+s.cfg.AdminToken)
	}
	rr := httptest.NewRecorder()
	s.Handler().ServeHTTP(rr, req)
	return rr
}

func decodeSecret(t *testing.T, enc string) []byte {
	t.Helper()
	raw, err := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(strings.ToUpper(enc))
	if err != nil {
		t.Fatalf("base32 decode: %v", err)
	}
	return raw
}

func createBinding(t *testing.T, s *Server, account string) (string, []byte) {
	t.Helper()
	rr := doJSON(t, s, http.MethodPost, "/totp/v1/bindings", map[string]string{
		"issuer":  "Test Corp",
		"account": account,
	}, "", true)
	if rr.Code != http.StatusCreated {
		t.Fatalf("bind: status=%d body=%s", rr.Code, rr.Body.String())
	}
	var resp struct {
		BindingID string    `json:"binding_id"`
		Status    string    `json:"status"`
		QR        BindingQR `json:"binding_qr"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("bind decode: %v", err)
	}
	if resp.Status != "pending" {
		t.Fatalf("unexpected binding status: %q", resp.Status)
	}
	if resp.QR.T != "totp-bind" || resp.QR.V != 1 || resp.QR.Dom != s.cfg.SiteDom || resp.QR.Path != s.cfg.SubmitPath {
		t.Fatalf("unexpected binding payload: %+v", resp.QR)
	}
	return resp.BindingID, decodeSecret(t, resp.QR.Sec)
}

func confirmBinding(t *testing.T, s *Server, bid string, secret []byte, at time.Time) {
	t.Helper()
	code, err := totpCode(secret, at, 30, 6, "SHA1")
	if err != nil {
		t.Fatalf("totp: %v", err)
	}
	rr := doJSON(t, s, http.MethodPost, "/totp/v1/bindings/"+bid+"/confirm", map[string]string{"code": code}, "", false)
	if rr.Code != http.StatusOK {
		t.Fatalf("confirm: status=%d body=%s", rr.Code, rr.Body.String())
	}
}

func issueToken(t *testing.T, s *Server, account, sid string) (string, string) {
	t.Helper()
	rr := doJSON(t, s, http.MethodPost, "/totp/v1/login/token", map[string]string{"account": account}, sid, false)
	if rr.Code != http.StatusOK {
		t.Fatalf("login token: status=%d body=%s", rr.Code, rr.Body.String())
	}
	var resp struct {
		Token     string  `json:"token"`
		ExpiresIn int     `json:"expires_in"`
		LoginQR   LoginQR `json:"login_qr"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("login decode: %v", err)
	}
	if resp.ExpiresIn <= 0 || resp.ExpiresIn > 60 {
		t.Fatalf("unexpected expires_in: %d", resp.ExpiresIn)
	}
	if resp.LoginQR.Token != resp.Token || resp.LoginQR.URL != "localhost" {
		t.Fatalf("unexpected login payload: %+v", resp.LoginQR)
	}
	if sid == "" {
		for _, c := range rr.Result().Cookies() {
			if c.Name == sessionCookie {
				sid = c.Value
			}
		}
	}
	if sid == "" {
		t.Fatal("missing session cookie")
	}
	return resp.Token, sid
}

func verify(t *testing.T, s *Server, token, code string) *httptest.ResponseRecorder {
	t.Helper()
	return doJSON(t, s, http.MethodPost, "/totp/v1/verify", map[string]string{"token": token, "code": code}, "", false)
}

func TestRFC6238Vectors(t *testing.T) {
	cases := []struct {
		alg    string
		secret []byte
		at     int64
		want   string
	}{
		{"SHA1", []byte("12345678901234567890"), 59, "94287082"},
		{"SHA1", []byte("12345678901234567890"), 1111111109, "07081804"},
		{"SHA1", []byte("12345678901234567890"), 1111111111, "14050471"},
		{"SHA1", []byte("12345678901234567890"), 1234567890, "89005924"},
		{"SHA1", []byte("12345678901234567890"), 2000000000, "69279037"},
		{"SHA1", []byte("12345678901234567890"), 20000000000, "65353130"},
		{"SHA256", []byte("12345678901234567890123456789012"), 59, "46119246"},
		{"SHA256", []byte("12345678901234567890123456789012"), 1111111109, "68084774"},
		{"SHA256", []byte("12345678901234567890123456789012"), 20000000000, "77737706"},
		{"SHA512", []byte("1234567890123456789012345678901234567890123456789012345678901234"), 59, "90693936"},
		{"SHA512", []byte("1234567890123456789012345678901234567890123456789012345678901234"), 1111111109, "25091201"},
		{"SHA512", []byte("1234567890123456789012345678901234567890123456789012345678901234"), 20000000000, "47863826"},
	}
	for _, tc := range cases {
		got, err := totpCode(tc.secret, time.Unix(tc.at, 0), 30, 8, tc.alg)
		if err != nil {
			t.Fatalf("%s/%d: %v", tc.alg, tc.at, err)
		}
		if got != tc.want {
			t.Errorf("%s/%d: got %s want %s", tc.alg, tc.at, got, tc.want)
		}
	}
}

func TestCompareSite(t *testing.T) {
	cases := []struct {
		pinned string
		login  string
		want   bool
	}{
		{"qq.example.com", "qq.example.com", true},
		{"qq.example.com", "QQ.Example.COM", true},
		{"qq.example.com", "qq.example.com.", true},
		{"qq.example.com", "login.example.com", true},
		{"auth.example.com:8443", "auth.example.com", true},
		{"qq.example.com", "qq.example.com.evil.test", false},
		{"qq.example.com", "evil.test", false},
		{"qq.example.com", "qq.example.com/login", false},
		{"qq.example.com", "https://qq.example.com", false},
		{"qq.example.com", "user@qq.example.com", false},
		{"qq.example.com", "qq.example.com:443", false},
		{"qq.example.com", "qq.example.com?x=1", false},
		{"example.co.uk", "login.example.co.uk", true},
	}
	for _, tc := range cases {
		got, reason := compareSite(tc.login, tc.pinned)
		if got != tc.want {
			t.Errorf("compare(%q, %q)=%v (%s), want %v", tc.login, tc.pinned, got, reason, tc.want)
		}
	}
}

func TestTOTPWindow(t *testing.T) {
	secret := []byte("12345678901234567890")
	now := time.Unix(1762396800, 0)
	for _, offset := range []int64{-30, 0, 30} {
		code, err := totpCode(secret, now.Add(time.Duration(offset)*time.Second), 30, 6, "SHA1")
		if err != nil {
			t.Fatal(err)
		}
		if _, ok := totpValidate(secret, code, now, 30, 6, "SHA1", 1); !ok {
			t.Errorf("offset %d should be accepted", offset)
		}
	}
	for _, offset := range []int64{-60, 60} {
		code, err := totpCode(secret, now.Add(time.Duration(offset)*time.Second), 30, 6, "SHA1")
		if err != nil {
			t.Fatal(err)
		}
		if _, ok := totpValidate(secret, code, now, 30, 6, "SHA1", 1); ok {
			t.Errorf("offset %d should be rejected", offset)
		}
	}
}

func TestBindingAndVerifyFlow(t *testing.T) {
	s := newTestServer(t)
	now := time.Unix(1762396800, 0)
	s.now = func() time.Time { return now }

	bid, secret := createBinding(t, s, "alice@example.com")
	confirmBinding(t, s, bid, secret, now)

	now = now.Add(30 * time.Second) // 避免确认用掉的时间步与首次登录相同
	token, sid := issueToken(t, s, "alice@example.com", "")
	code, err := totpCode(secret, now, 30, 6, "SHA1")
	if err != nil {
		t.Fatal(err)
	}
	if rr := verify(t, s, token, code); rr.Code != http.StatusOK {
		t.Fatalf("verify: status=%d body=%s", rr.Code, rr.Body.String())
	}

	rr := doJSON(t, s, http.MethodGet, "/totp/v1/session", nil, sid, false)
	var sess struct {
		Authenticated bool   `json:"authenticated"`
		BindingID     string `json:"binding_id"`
		ExpiresAt     int64  `json:"expires_at"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &sess); err != nil {
		t.Fatal(err)
	}
	if !sess.Authenticated || sess.BindingID != bid || sess.ExpiresAt == 0 {
		t.Fatalf("session not authenticated: %+v", sess)
	}

	// 重放同一 token：必须 401，即使码仍然有效。
	if rr := verify(t, s, token, code); rr.Code != http.StatusUnauthorized {
		t.Fatalf("replay: status=%d, want 401", rr.Code)
	}
}

func TestTokenExpiry(t *testing.T) {
	s := newTestServer(t)
	now := time.Unix(1762396800, 0)
	s.now = func() time.Time { return now }

	bid, secret := createBinding(t, s, "alice@example.com")
	confirmBinding(t, s, bid, secret, now)

	now = now.Add(30 * time.Second)
	token, _ := issueToken(t, s, "alice@example.com", "")

	now = now.Add(61 * time.Second)
	code, err := totpCode(secret, now, 30, 6, "SHA1")
	if err != nil {
		t.Fatal(err)
	}
	if rr := verify(t, s, token, code); rr.Code != http.StatusUnauthorized {
		t.Fatalf("expired token: status=%d, want 401", rr.Code)
	}
}

func TestFailuresExhaustToken(t *testing.T) {
	s := newTestServer(t)
	now := time.Unix(1762396800, 0)
	s.now = func() time.Time { return now }

	bid, secret := createBinding(t, s, "alice@example.com")
	confirmBinding(t, s, bid, secret, now)

	now = now.Add(30 * time.Second)
	token, _ := issueToken(t, s, "alice@example.com", "")
	real, err := totpCode(secret, now, 30, 6, "SHA1")
	if err != nil {
		t.Fatal(err)
	}
	wrong := "000000"
	if real == wrong {
		wrong = "111111"
	}
	for i := 0; i < maxTokenFailures; i++ {
		if rr := verify(t, s, token, wrong); rr.Code != http.StatusUnauthorized {
			t.Fatalf("attempt %d: status=%d, want 401", i+1, rr.Code)
		}
	}
	if rr := verify(t, s, token, real); rr.Code != http.StatusUnauthorized {
		t.Fatalf("exhausted token accepted correct code: status=%d", rr.Code)
	}
}

func TestConcurrentVerifyOnlyOneSucceeds(t *testing.T) {
	s := newTestServer(t)
	now := time.Unix(1762396800, 0)
	s.now = func() time.Time { return now }

	bid, secret := createBinding(t, s, "alice@example.com")
	confirmBinding(t, s, bid, secret, now)

	now = now.Add(30 * time.Second)
	token, _ := issueToken(t, s, "alice@example.com", "")
	code, err := totpCode(secret, now, 30, 6, "SHA1")
	if err != nil {
		t.Fatal(err)
	}

	var success int32
	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			rr := verify(t, s, token, code)
			if rr.Code == http.StatusOK {
				atomic.AddInt32(&success, 1)
			}
		}()
	}
	wg.Wait()
	if success != 1 {
		t.Fatalf("success count=%d, want exactly 1", success)
	}
}

func TestUnifiedErrorBody(t *testing.T) {
	s := newTestServer(t)
	now := time.Unix(1762396800, 0)
	s.now = func() time.Time { return now }

	unknown := verify(t, s, "AAAAAAAAAAAAAAAAAAAAAAAA", "123456")
	if unknown.Code != http.StatusUnauthorized {
		t.Fatalf("unknown token status=%d", unknown.Code)
	}

	bid, secret := createBinding(t, s, "alice@example.com")
	confirmBinding(t, s, bid, secret, now)
	now = now.Add(30 * time.Second)
	token, _ := issueToken(t, s, "alice@example.com", "")
	now = now.Add(61 * time.Second)
	expired := verify(t, s, token, "123456")
	if expired.Code != http.StatusUnauthorized {
		t.Fatalf("expired token status=%d", expired.Code)
	}

	var a, b apiError
	if err := json.Unmarshal(unknown.Body.Bytes(), &a); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(expired.Body.Bytes(), &b); err != nil {
		t.Fatal(err)
	}
	if a.Error != b.Error || a.Message != b.Message {
		t.Fatalf("error bodies differ: %+v vs %+v", a, b)
	}
	if !strings.HasPrefix(a.RequestID, "req_") {
		t.Fatalf("bad request_id: %q", a.RequestID)
	}
}

func TestIssueRateLimit(t *testing.T) {
	s := newTestServer(t)
	now := time.Unix(1762396800, 0)
	s.now = func() time.Time { return now }

	bid, secret := createBinding(t, s, "alice@example.com")
	confirmBinding(t, s, bid, secret, now)
	now = now.Add(30 * time.Second)

	var sid string
	for i := 0; i < maxIssuePerMinute; i++ {
		_, gotSID := issueToken(t, s, "alice@example.com", sid)
		sid = gotSID
	}
	rr := doJSON(t, s, http.MethodPost, "/totp/v1/login/token", map[string]string{"account": "alice@example.com"}, sid, false)
	if rr.Code != http.StatusTooManyRequests {
		t.Fatalf("rate limit status=%d, want 429", rr.Code)
	}
}
