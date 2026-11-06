import test from "node:test";
import assert from "node:assert/strict";
import { generateToken, isTokenShaped, tokenDigest } from "../src/core/token.ts";

test("登录 token 为 24 个 base64url 字符", () => {
  for (let i = 0; i < 50; i += 1) {
    const token = generateToken();
    assert.match(token, /^[A-Za-z0-9_-]{24}$/);
    assert.equal(isTokenShaped(token), true);
  }
});

test("登录 token 具备足够随机性且不重复", () => {
  const tokens = new Set<string>();
  for (let i = 0; i < 500; i += 1) {
    tokens.add(generateToken());
  }
  assert.equal(tokens.size, 500);
});

test("存储摘要不等于明文，且长度固定", () => {
  const token = generateToken();
  const digest = tokenDigest(token);
  assert.notEqual(digest, token);
  assert.match(digest, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(tokenDigest(token), digest);
});

test("形态校验：只接受 16 或 24 个 base64url 字符", () => {
  assert.equal(isTokenShaped("a".repeat(16)), true);
  assert.equal(isTokenShaped("a".repeat(24)), true);
  assert.equal(isTokenShaped("short"), false);
  assert.equal(isTokenShaped("a".repeat(15)), false);
  assert.equal(isTokenShaped("a".repeat(17)), false);
  assert.equal(isTokenShaped("a".repeat(24) + "="), false);
  assert.equal(isTokenShaped(123), false);
  assert.equal(isTokenShaped(null), false);
});
