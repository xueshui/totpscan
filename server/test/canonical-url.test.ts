import test from "node:test";
import assert from "node:assert/strict";
import {
  canonicalizeSubmitUrl,
  normalizeBindDomain,
  normalizeBindPath,
  splitCanonicalUrl,
  UrlCanonicalizationError,
} from "../src/core/canonical-url.ts";

test("规范化：host 小写、去默认端口、去尾斜杠、合并重复斜杠", () => {
  assert.equal(
    canonicalizeSubmitUrl("https://Auth.Example.COM:443//totp//v1/"),
    "https://auth.example.com/totp/v1",
  );
  assert.equal(canonicalizeSubmitUrl("https://auth.example.com"), "https://auth.example.com/");
  assert.equal(canonicalizeSubmitUrl("https://auth.example.com:0443/x"), "https://auth.example.com/x");
});

test("规范化：保留非默认端口", () => {
  assert.equal(canonicalizeSubmitUrl("https://auth.example.com:8443/x"), "https://auth.example.com:8443/x");
  assert.equal(canonicalizeSubmitUrl("http://127.0.0.1:8080/x"), "http://127.0.0.1:8080/x");
});

test("规范化：Unicode 域名转 punycode、去掉 host 结尾点", () => {
  assert.equal(canonicalizeSubmitUrl("https://例え.テスト/x"), "https://xn--r8jz45g.xn--zckzah/x");
  assert.equal(canonicalizeSubmitUrl("https://Example.COM./x"), "https://example.com/x");
});

test("规范化：IPv6 与 http 回环例外", () => {
  assert.equal(canonicalizeSubmitUrl("https://[::1]:443/x"), "https://[::1]/x");
  assert.equal(canonicalizeSubmitUrl("http://localhost:80/x"), "http://localhost/x");
  assert.throws(() => canonicalizeSubmitUrl("http://auth.example.com/x"), UrlCanonicalizationError);
});

test("规范化：百分号编码与点段解析（仅路径）", () => {
  assert.equal(canonicalizeSubmitUrl("https://example.com/%7Ealice/%2f"), "https://example.com/~alice/%2F");
  assert.equal(canonicalizeSubmitUrl("https://example.com/totp/v1/../v2"), "https://example.com/totp/v2");
  assert.equal(canonicalizeSubmitUrl("https://example.com/a/./b/"), "https://example.com/a/b");
});

test("规范化：查询串允许且原样保留（不排序、不重编码）", () => {
  assert.equal(
    canonicalizeSubmitUrl("https://auth.example.com/dtm/ulr?ma=xxx"),
    "https://auth.example.com/dtm/ulr?ma=xxx",
  );
  assert.equal(
    canonicalizeSubmitUrl("https://auth.example.com/dtm/ulr?b=2&a=%2f&a=1"),
    "https://auth.example.com/dtm/ulr?b=2&a=%2f&a=1",
  );
  assert.equal(canonicalizeSubmitUrl("https://auth.example.com/x?"), "https://auth.example.com/x");
});

test("规范化：非法输入一律失败（userinfo / fragment 仍拒绝）", () => {
  const invalid = [
    "ftp://example.com/x",
    "https://user:pw@example.com/x",
    "https://example.com/x#frag",
    "https://example.com/x?y=1#frag",
    "/relative/path",
    " https://example.com/x",
    "https://example.com/x ",
    "",
    "not a url",
  ];
  for (const value of invalid) {
    assert.throws(() => canonicalizeSubmitUrl(value), UrlCanonicalizationError, value);
  }
});

test("绑定 dom：只接受 host[:port]，小写并省略默认端口", () => {
  assert.equal(normalizeBindDomain("example.com"), "example.com");
  assert.equal(normalizeBindDomain("DKN.Example.COM"), "dkn.example.com");
  assert.equal(normalizeBindDomain("localhost:8080"), "localhost:8080");
  assert.equal(normalizeBindDomain("auth.example.com:443"), "auth.example.com");
  for (const value of ["https://example.com", "example.com/x", "user@example.com", "example.com?x=1", ""]) {
    assert.throws(() => normalizeBindDomain(value), UrlCanonicalizationError, value);
  }
});

test("绑定 path：必须绝对、可带查询串、原样保留", () => {
  assert.equal(normalizeBindPath("/totp/v1/verify"), "/totp/v1/verify");
  assert.equal(normalizeBindPath("/dtm/ulr?ma=xxx"), "/dtm/ulr?ma=xxx");
  for (const value of ["verify", "/x#frag", "/x y", " /x", ""]) {
    assert.throws(() => normalizeBindPath(value), UrlCanonicalizationError, value);
  }
});

test("拆分规范形式便于逐项比较", () => {
  assert.deepEqual(splitCanonicalUrl("https://auth.example.com:8443/totp/v1"), {
    scheme: "https:",
    host: "auth.example.com",
    port: "8443",
    path: "/totp/v1",
    query: "",
    pathQuery: "/totp/v1",
  });
  assert.deepEqual(splitCanonicalUrl("https://auth.example.com/dtm/ulr?ma=xxx"), {
    scheme: "https:",
    host: "auth.example.com",
    port: "",
    path: "/dtm/ulr",
    query: "ma=xxx",
    pathQuery: "/dtm/ulr?ma=xxx",
  });
});
