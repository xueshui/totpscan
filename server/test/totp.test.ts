import test from "node:test";
import assert from "node:assert/strict";
import { generateTotp, timeStepAt, verifyTotp, DEFAULT_TOTP_OPTIONS } from "../src/core/totp.ts";

const SHA1_SECRET = Buffer.from("12345678901234567890", "ascii");
const SHA256_SECRET = Buffer.from("12345678901234567890123456789012", "ascii");
const SHA512_SECRET = Buffer.from("1234567890123456789012345678901234567890123456789012345678901234", "ascii");

test("RFC 6238 附录 B 向量（SHA1 / 8 位）", () => {
  const vectors: Array<[number, string]> = [
    [59, "94287082"],
    [1111111109, "07081804"],
    [1111111111, "14050471"],
    [1234567890, "89005924"],
    [2000000000, "69279037"],
    [20000000000, "65353130"],
  ];
  for (const [seconds, expected] of vectors) {
    const step = timeStepAt(seconds * 1000, 30);
    assert.equal(generateTotp(SHA1_SECRET, step, { algorithm: "SHA1", digits: 8, period: 30 }), expected);
  }
});

test("RFC 6238 附录 B 向量（SHA256 / SHA512）", () => {
  const step = timeStepAt(59 * 1000, 30);
  assert.equal(
    generateTotp(SHA256_SECRET, step, { algorithm: "SHA256", digits: 8, period: 30 }),
    "46119246",
  );
  assert.equal(
    generateTotp(SHA512_SECRET, step, { algorithm: "SHA512", digits: 8, period: 30 }),
    "90693936",
  );
});

test("默认参数为 6 位 / 30 秒 / SHA1", () => {
  const step = timeStepAt(59 * 1000, 30);
  const code = generateTotp(SHA1_SECRET, step);
  assert.equal(code.length, 6);
  assert.equal(code, "287082");
  assert.deepEqual(DEFAULT_TOTP_OPTIONS, { algorithm: "SHA1", digits: 6, period: 30 });
});

test("校验只接受 t-1 / t / t+1", () => {
  const now = 1762396800000;
  const current = timeStepAt(now, 30);

  for (const offset of [-1, 0, 1]) {
    const code = generateTotp(SHA1_SECRET, current + offset);
    const result = verifyTotp(SHA1_SECRET, code, now);
    assert.equal(result.matched, true, `offset ${offset}`);
    assert.equal(result.timeStep, current + offset);
    assert.equal(result.windowOffset, offset);
  }

  for (const offset of [-2, 2]) {
    const code = generateTotp(SHA1_SECRET, current + offset);
    assert.equal(verifyTotp(SHA1_SECRET, code, now).matched, false, `offset ${offset}`);
  }
});

test("校验拒绝长度或字符非法的动态码", () => {
  const now = 1762396800000;
  const code = generateTotp(SHA1_SECRET, timeStepAt(now, 30));
  assert.equal(verifyTotp(SHA1_SECRET, code.slice(0, 5), now).matched, false);
  assert.equal(verifyTotp(SHA1_SECRET, "abcdef", now).matched, false);
});

test("时间步按周期正确换算", () => {
  assert.equal(timeStepAt(0, 30), 0);
  assert.equal(timeStepAt(59_999, 30), 1);
  assert.equal(timeStepAt(60_000, 30), 2);
  assert.equal(timeStepAt(60_000, 60), 1);
});
