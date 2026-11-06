/**
 * 自测脚本（Node 20+）：只覆盖不依赖 chrome.* 的纯逻辑模块。
 * 运行：node tests/selftest.mjs
 */

import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

import { bytesToBase64, bytesToBase64url, base64ToBytes, utf8Encode } from "../common/base64.js";
import {
  decodeBase32,
  encodeBase32,
  normalizeBase32Loose,
  looksLikeBase32Secret,
} from "../common/base32.js";
import { generateTotp, formatCodeForDisplay, timeStepAt, secondsRemainingAt } from "../common/totp.js";
import { parseSubmitUrl, isTransportAllowed } from "../common/canonical-url.js";
import { parseOtpauthUri, buildOtpauthUri, buildOtpauthExportUri } from "../common/otpauth.js";
import {
  validateBindingPayload,
  validateLoginPayload,
  detectQrKind,
  findScanCandidates,
} from "../common/protocol.js";
import {
  normalizeSiteHost,
  normalizeSiteHosts,
  registrableDomain,
  isSameSite,
  orderAccountsBySite,
} from "../common/site-filter.js";
import {
  encryptBackup,
  decryptBackup,
  isEncryptedBackup,
  buildBackupPayload,
  buildTextExport,
} from "../common/backup.js";
import { analyzeImportText, parseMigrationUri } from "../common/import.js";
import { encodeQr } from "../vendor/qr-encode.js";

let passed = 0;
const failures = [];

async function test(name, fn) {
  try {
    await fn();
    passed += 1;
    console.log(`  通过  ${name}`);
  } catch (error) {
    failures.push({ name, error });
    console.log(`  失败  ${name}`);
    console.log(`        ${error?.message ?? error}`);
  }
}

function section(title) {
  console.log(`\n== ${title} ==`);
}

/* ------------------------------- Base32/Base64 ------------------------------- */

section("编码与 Base32");

await test("RFC 4648 Base32 向量 foobar", () => {
  assert.equal(encodeBase32(utf8Encode("foobar")), "MZXW6YTBOI");
  assert.equal(new TextDecoder().decode(decodeBase32("MZXW6YTBOI")), "foobar");
});

await test("Base32 宽松清洗（空格、短横线、小写、填充）", () => {
  assert.equal(normalizeBase32Loose("jbsw y3dp-ehpk_3pxp===="), "JBSWY3DPEHPK3PXP");
  assert.equal(encodeBase32(decodeBase32("JBSWY3DPEHPK3PXP")), "JBSWY3DPEHPK3PXP");
});

await test("looksLikeBase32Secret 阈值", () => {
  assert.equal(looksLikeBase32Secret("JBSW Y3DP EHPK 3PXP"), true);
  assert.equal(looksLikeBase32Secret("alice@example.com"), false);
  assert.equal(looksLikeBase32Secret("ABC"), false);
});

await test("Base64 / Base64URL 往返", () => {
  const bytes = new Uint8Array([0, 1, 2, 253, 254, 255]);
  assert.deepEqual(base64ToBytes(bytesToBase64(bytes)), bytes);
  assert.deepEqual(base64ToBytes(bytesToBase64url(bytes)), bytes);
});

/* ----------------------------------- TOTP ----------------------------------- */

section("TOTP（RFC 6238 全向量）");

const RFC_SECRETS = {
  SHA1: utf8Encode("12345678901234567890"),
  SHA256: utf8Encode("12345678901234567890123456789012"),
  SHA512: utf8Encode("1234567890123456789012345678901234567890123456789012345678901234"),
};

const RFC_VECTORS = [
  [59, { SHA1: "94287082", SHA256: "46119246", SHA512: "90693936" }],
  [1111111109, { SHA1: "07081804", SHA256: "68084774", SHA512: "25091201" }],
  [1111111111, { SHA1: "14050471", SHA256: "67062674", SHA512: "99943326" }],
  [1234567890, { SHA1: "89005924", SHA256: "91819424", SHA512: "93441116" }],
  [2000000000, { SHA1: "69279037", SHA256: "90698825", SHA512: "38618901" }],
  [20000000000, { SHA1: "65353130", SHA256: "77737706", SHA512: "47863826" }],
];

for (const [seconds, expected] of RFC_VECTORS) {
  await test(`RFC 6238 ${seconds}s`, async () => {
    for (const algorithm of ["SHA1", "SHA256", "SHA512"]) {
      const result = await generateTotp(RFC_SECRETS[algorithm], {
        algorithm,
        digits: 8,
        period: 30,
        timestampMs: seconds * 1000,
      });
      assert.equal(result.code, expected[algorithm], `${algorithm} @ ${seconds}s`);
      assert.equal(result.step, Math.floor(seconds / 30));
    }
  });
}

await test("6 位码与倒计时", async () => {
  const result = await generateTotp(RFC_SECRETS.SHA1, {
    digits: 6,
    period: 30,
    timestampMs: 59_000,
  });
  assert.equal(result.code.length, 6);
  assert.equal(result.remaining, 1);
  assert.equal(secondsRemainingAt(59_500, 30), 1);
  assert.equal(formatCodeForDisplay("123456"), "123 456");
  assert.equal(formatCodeForDisplay("12345678"), "1234 5678");
  assert.equal(timeStepAt(59_000, 30), 1);
});

/* -------------------------------- 地址解析 -------------------------------- */

section("提交地址解析");

await test("parseSubmitUrl 保留 path 与 query 原样", () => {
  const target = parseSubmitUrl("https://auth.example.com/dtm/ulr?ma=xxx&b=2");
  assert.equal(target.submitUrl, "https://auth.example.com/dtm/ulr?ma=xxx&b=2");
  assert.equal(target.path, "/dtm/ulr?ma=xxx&b=2");
  assert.equal(target.pathname, "/dtm/ulr");
  assert.equal(target.search, "?ma=xxx&b=2");
  assert.equal(target.domain, "example.com");
});

await test("parseSubmitUrl 拒绝不安全或非规范输入", () => {
  for (const bad of ["", "   https://a.test/x", "ftp://a.test/x", "http://example.com/x", "not a url", "https://a.test/x#f"]) {
    assert.throws(() => parseSubmitUrl(bad), bad);
  }
});

await test("传输层白名单", () => {
  assert.equal(isTransportAllowed("https://auth.example.com/totp/v1/verify"), true);
  assert.equal(isTransportAllowed("http://127.0.0.1:8123/totp/v1/verify"), true);
  assert.equal(isTransportAllowed("http://example.com/x"), false);
});

/* ---------------------------------- otpauth ---------------------------------- */

section("otpauth URI");

await test("解析完整参数", () => {
  const parsed = parseOtpauthUri(
    "otpauth://totp/Example:alice%40example.com?secret=jbsw%20y3dp%20ehpk%203pxp&issuer=Example&algorithm=SHA256&digits=8&period=60",
  );
  assert.equal(parsed.issuer, "Example");
  assert.equal(parsed.account, "alice@example.com");
  assert.equal(parsed.secret, "JBSWY3DPEHPK3PXP");
  assert.equal(parsed.algorithm, "SHA256");
  assert.equal(parsed.digits, 8);
  assert.equal(parsed.period, 60);
});

await test("拒绝 HOTP / issuer 冲突 / 缺 secret", () => {
  for (const uri of [
    "otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP&counter=1",
    "otpauth://totp/A:b?secret=JBSWY3DPEHPK3PXP&issuer=C",
    "otpauth://totp/A:b",
  ]) {
    assert.throws(() => parseOtpauthUri(uri));
  }
});

await test("生成后可重新解析", () => {
  const uri = buildOtpauthUri({
    issuer: "示例",
    account: "bob@example.com",
    secret: "JBSWY3DPEHPK3PXP",
    algorithm: "SHA1",
    digits: 6,
    period: 30,
  });
  const parsed = parseOtpauthUri(uri);
  assert.equal(parsed.issuer, "示例");
  assert.equal(parsed.account, "bob@example.com");
  assert.equal(parsed.secret, "JBSWY3DPEHPK3PXP");
});

await test("detectQrKind", () => {
  assert.equal(detectQrKind('{"t":"totp-bind"}'), "binding");
  assert.equal(detectQrKind('{"t":"totp-login"}'), "login");
  assert.equal(detectQrKind("otpauth://totp/a?secret=JBSWY3DPEHPK3PXP"), "otpauth");
  assert.equal(detectQrKind("otpauth-migration://offline?data=x"), "migration");
  assert.equal(detectQrKind("hello"), "unknown");
});

/* ---------------------------------- 协议解析 --------------------------------- */

section("绑定载荷（dom + path）与登录候选");

function makeBinding(overrides = {}) {
  return JSON.stringify({
    t: "totp-bind",
    v: 1,
    bid: `b_${"A1".repeat(12)}`,
    iss: "示例服务",
    acc: "alice@example.com",
    sec: "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP",
    alg: "SHA256",
    dig: 8,
    per: 30,
    dom: "auth.example.com",
    path: "/totp/v1/verify?tenant=acme",
    iat: 1762396800,
    exp: 1762397400,
    ...overrides,
  });
}

await test("绑定载荷解析 dom/path 并生成完整提交地址", () => {
  const result = validateBindingPayload(makeBinding(), { now: 1762396900 });
  assert.equal(result.summary.account, "alice@example.com");
  assert.equal(result.summary.algorithm, "SHA256");
  assert.equal(result.summary.domain, "example.com");
  assert.equal(result.summary.submitPath, "/totp/v1/verify?tenant=acme");
  assert.equal(result.submitUrl, "https://auth.example.com/totp/v1/verify?tenant=acme");
});

await test("绑定载荷不再要求 sig/kid", () => {
  const result = validateBindingPayload(makeBinding(), { now: 1762396900 });
  assert.equal("sig" in result.payload, false);
  assert.equal("kid" in result.payload, false);
});

await test("绑定载荷拒绝非法 dom/path 与过期", () => {
  assert.throws(
    () => validateBindingPayload(makeBinding({ dom: "https://auth.example.com" }), { now: 1762396900 }),
    (error) => error.code === "BAD_DOM",
  );
  assert.throws(
    () => validateBindingPayload(makeBinding({ dom: "auth.example.com/path" }), { now: 1762396900 }),
    (error) => error.code === "BAD_DOM",
  );
  assert.throws(
    () => validateBindingPayload(makeBinding({ path: "totp/v1" }), { now: 1762396900 }),
    (error) => error.code === "BAD_PATH",
  );
  assert.throws(
    () => validateBindingPayload(makeBinding({ path: "/totp/v1#frag" }), { now: 1762396900 }),
    (error) => error.code === "BAD_PATH",
  );
  assert.throws(() => validateBindingPayload(makeBinding(), { now: 1762397500 }), /过期/);
});

await test("登录载荷使用 url/token/exp", () => {
  const login = {
    t: "totp-login",
    v: 1,
    url: "auth.example.com",
    token: "A".repeat(16),
    exp: 1762396900,
  };
  const result = validateLoginPayload(JSON.stringify(login), { now: 1762396860 });
  assert.equal(result.payload.url, "auth.example.com");
  assert.equal(result.payload.domain, "example.com");
  assert.equal(result.payload.token, "A".repeat(16));
  assert.equal(result.summary.domain, "example.com");
  assert.throws(() => validateLoginPayload(JSON.stringify(login), { now: 1762396901 }), /过期/);
  const tooLong = { ...login, exp: 1762396900 + 120 };
  assert.throws(() => validateLoginPayload(JSON.stringify(tooLong), { now: 1762396860 }), /有效期/);
  assert.throws(() => validateLoginPayload(JSON.stringify({ ...login, token: "short" })));
  assert.throws(() =>
    validateLoginPayload(JSON.stringify({ ...login, url: "https://auth.example.com" })),
  );
});

await test("候选反查只按注册域名命中，路径取绑定值", () => {
  const payload = { domain: "example.com" };
  const accounts = [
    { id: "1", type: "scan", status: "confirmed", submitUrl: "https://auth.example.com/totp/v1", issuer: "A", account: "a", confirmedAt: 2 },
    { id: "2", type: "scan", status: "pending", submitUrl: "https://auth.example.com/totp/v1", issuer: "B", account: "b" },
    { id: "3", type: "scan", status: "confirmed", submitUrl: "https://auth.example.com.evil.com/totp/v1", issuer: "C", account: "c" },
    { id: "4", type: "standard", status: null, submitUrl: null, issuer: "D", account: "d" },
  ];
  const hits = findScanCandidates(payload, accounts);
  assert.equal(hits.length, 1);
  assert.equal(hits[0].account.id, "1");
});

await test("同注册域名多账户全部返回，跨注册域名不命中", () => {
  const accounts = [
    { id: "1", type: "scan", status: "confirmed", submitUrl: "https://auth.example.com/totp/v1", issuer: "A", account: "a" },
    { id: "2", type: "scan", status: "confirmed", submitUrl: "https://login.example.com/dtm/ulr?ma=x", issuer: "B", account: "b" },
    { id: "3", type: "scan", status: "confirmed", submitUrl: "https://auth.example.com.evil.com/totp/v1", issuer: "C", account: "c" },
  ];
  const hits = findScanCandidates({ domain: "example.com" }, accounts);
  assert.deepEqual(hits.map((hit) => hit.account.id).sort(), ["1", "2"]);
  assert.equal(findScanCandidates({ domain: "evil.com" }, accounts).length, 1);
});

/* ----------------------------------- 备份 ----------------------------------- */

section("备份加密与文本导出");

await test("口令加密往返，错误口令失败", async () => {
  const plain = JSON.stringify(buildBackupPayload([{ issuer: "A", account: "a", secret: "JBSWY3DPEHPK3PXP" }]));
  const envelope = await encryptBackup(plain, "correct horse battery staple");
  assert.equal(isEncryptedBackup(envelope), true);
  assert.equal(envelope.kdf.name, "PBKDF2");
  assert.equal(envelope.kdf.hash, "SHA-256");
  assert.equal(envelope.kdf.iterations, 600000);
  assert.equal(envelope.cipher.name, "AES-256-GCM");
  assert.equal(/^[A-Za-z0-9_-]{22}$/.test(envelope.kdf.salt), true);
  assert.equal(/^[A-Za-z0-9_-]{16}$/.test(envelope.cipher.iv), true);
  assert.equal(/^[A-Za-z0-9_-]{22}$/.test(envelope.cipher.tag), true);
  assert.equal(/^[A-Za-z0-9_-]+$/.test(envelope.ciphertext), true);
  assert.equal("data" in envelope.cipher, false);
  const decrypted = await decryptBackup(envelope, "correct horse battery staple");
  assert.equal(decrypted.accounts.length, 1);
  await assert.rejects(() => decryptBackup(envelope, "wrong password"), /备份无法解密或已损坏/);
  const tampered = { ...envelope, ciphertext: envelope.ciphertext.slice(0, -2) + "AA" };
  await assert.rejects(() => decryptBackup(tampered, "correct horse battery staple"), /备份无法解密或已损坏/);
});

await test("文本导出为 otpauth 行", () => {
  const text = buildTextExport([
    {
      issuer: "示例",
      account: "alice@example.com",
      secret: "JBSWY3DPEHPK3PXP",
      algorithm: "SHA1",
      digits: 6,
      period: 30,
    },
  ]);
  assert.equal(text.trim().startsWith("otpauth://totp/"), true);
  const parsed = parseOtpauthUri(text.trim());
  assert.equal(parsed.account, "alice@example.com");
});

/* ----------------------------------- 导入 ----------------------------------- */

section("第三方备份导入");

await test("逐行混合格式：otpauth / 冒号 / 分隔符 / 空格分组 / 失败行", async () => {
  const text = [
    "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example",
    "Example:bob@example.com:JBSWY3DPEHPK3PXP",
    "JBSWY3DPEHPK3PXP  carol@example.com  Example",
    "alice@example.com  JBSW Y3DP EHPK 3PXP",
    "这一行不是备份格式",
  ].join("\n");
  const result = await analyzeImportText(text);
  assert.equal(result.rows.length, 4);
  assert.equal(result.failures.length, 1);
  assert.equal(result.rows[0].issuer, "Example");
  assert.equal(result.rows[1].account, "bob@example.com");
  assert.equal(result.rows[2].account, "carol@example.com");
  assert.equal(result.rows[3].account, "alice@example.com");
  assert.equal(result.rows[3].secret, "JBSWY3DPEHPK3PXP");
});

await test("自家 JSON 与加密 JSON 导入", async () => {
  const payload = buildBackupPayload([
    {
      type: "standard",
      issuer: "示例",
      account: "alice@example.com",
      label: "工作",
      secret: "JBSWY3DPEHPK3PXP",
      algorithm: "SHA512",
      digits: 8,
      period: 60,
    },
  ]);
  const plain = await analyzeImportText(JSON.stringify(payload));
  assert.equal(plain.rows.length, 1);
  assert.equal(plain.rows[0].algorithm, "SHA512");
  assert.equal(plain.rows[0].label, "工作");

  const envelope = await encryptBackup(JSON.stringify(payload), "backup-password");
  await assert.rejects(() => analyzeImportText(JSON.stringify(envelope)), /口令/);
  const decrypted = await analyzeImportText(JSON.stringify(envelope), { password: "backup-password" });
  assert.equal(decrypted.rows.length, 1);
});

function varint(value) {
  const out = [];
  let remaining = value;
  while (remaining >= 0x80) {
    out.push((remaining & 0x7f) | 0x80);
    remaining = Math.floor(remaining / 128);
  }
  out.push(remaining);
  return out;
}

function fieldBytes(number, bytes) {
  return [...varint(number * 8 + 2), ...varint(bytes.length), ...bytes];
}

function fieldVarint(number, value) {
  return [...varint(number * 8), ...varint(value)];
}

await test("Google Authenticator 迁移数据", async () => {
  const secret = decodeBase32("JBSWY3DPEHPK3PXP");
  const inner = Uint8Array.from([
    ...fieldBytes(1, secret),
    ...fieldBytes(2, utf8Encode("Example:alice@example.com")),
    ...fieldBytes(3, utf8Encode("Example")),
    ...fieldVarint(4, 2),
    ...fieldVarint(5, 2),
    ...fieldVarint(6, 2),
  ]);
  const outer = Uint8Array.from(fieldBytes(1, inner));
  const uri = `otpauth-migration://offline?data=${encodeURIComponent(bytesToBase64(outer))}`;
  const direct = parseMigrationUri(uri);
  assert.equal(direct.rows.length, 1);
  assert.equal(direct.rows[0].issuer, "Example");
  assert.equal(direct.rows[0].account, "alice@example.com");
  assert.equal(direct.rows[0].algorithm, "SHA256");
  assert.equal(direct.rows[0].digits, 8);

  const analyzed = await analyzeImportText(uri);
  assert.equal(analyzed.rows.length, 1);
});

/* ---------------------------------- 多语言 ---------------------------------- */

section("多语言消息表");

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const EXPECTED_LOCALES = ["zh_CN", "en", "zh_TW", "ja"];

function readMessages(locale) {
  const file = path.join(rootDir, "_locales", locale, "messages.json");
  return JSON.parse(readFileSync(file, "utf8"));
}

function placeholdersOf(text) {
  return [...String(text).matchAll(/\{([A-Za-z0-9_]+)\}/g)]
    .map((match) => match[1])
    .sort()
    .join(",");
}

await test("_locales 仅包含四种受支持语言", () => {
  const locales = readdirSync(path.join(rootDir, "_locales")).filter((name) =>
    statSync(path.join(rootDir, "_locales", name)).isDirectory(),
  );
  assert.deepEqual(
    locales.sort(),
    [...EXPECTED_LOCALES].sort(),
    `实际：${locales.join(", ")}`,
  );
});

await test("四种语言 key 集合一致", () => {
  const base = readMessages("zh_CN");
  const baseKeys = Object.keys(base).sort();
  for (const locale of EXPECTED_LOCALES) {
    const keys = Object.keys(readMessages(locale)).sort();
    const missing = baseKeys.filter((key) => !keys.includes(key));
    const extra = keys.filter((key) => !baseKeys.includes(key));
    assert.deepEqual(missing, [], `${locale} 缺少：${missing.join(", ")}`);
    assert.deepEqual(extra, [], `${locale} 多出：${extra.join(", ")}`);
  }
});

await test("四种语言无空值且占位符一致", () => {
  const base = readMessages("zh_CN");
  for (const locale of EXPECTED_LOCALES) {
    const messages = readMessages(locale);
    for (const [key, value] of Object.entries(messages)) {
      assert.equal(typeof value?.message, "string", `${locale}.${key} 不是字符串`);
      assert.notEqual(value.message.trim(), "", `${locale}.${key} 为空`);
      if (base[key]) {
        assert.equal(
          placeholdersOf(value.message),
          placeholdersOf(base[key].message),
          `${locale}.${key} 占位符不一致`,
        );
      }
    }
  }
});

await test("清单占位符在四种语言中均可解析", () => {
  const manifest = JSON.parse(readFileSync(path.join(rootDir, "manifest.json"), "utf8"));
  assert.equal(manifest.default_locale, "zh_CN");
  const referenced = new Set(
    [manifest.name, manifest.description, manifest.action?.default_title]
      .filter((value) => typeof value === "string")
      .flatMap((value) => [...value.matchAll(/__MSG_([A-Za-z0-9_@]+)__/g)].map((match) => match[1])),
  );
  assert.ok(referenced.size > 0, "manifest 未使用 __MSG_ 引用");
  for (const locale of EXPECTED_LOCALES) {
    const messages = readMessages(locale);
    for (const key of referenced) {
      assert.equal(typeof messages[key]?.message, "string", `${locale} 缺少清单 key ${key}`);
    }
  }
});

/* ------------------------------ 单账户二维码导出 ------------------------------ */

section("单账户二维码导出");

const QR_EXPORT_TEXT =
  "otpauth://totp/GitHub:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub";

function loadJsQr() {
  const source = readFileSync(path.join(rootDir, "vendor", "jsQR.js"), "utf8");
  const module = { exports: {} };
  new Function("module", "exports", "self", source)(module, module.exports, undefined);
  return module.exports.default ?? module.exports;
}

function decodeQrWithJsQr(jsQR, text, scale = 4, margin = 4) {
  const qr = encodeQr(text);
  const count = qr.size + margin * 2;
  const pixel = count * scale;
  const data = new Uint8ClampedArray(pixel * pixel * 4);
  for (let y = 0; y < pixel; y++) {
    for (let x = 0; x < pixel; x++) {
      const mx = Math.floor(x / scale) - margin;
      const my = Math.floor(y / scale) - margin;
      const dark = mx >= 0 && my >= 0 && mx < qr.size && my < qr.size && qr.modules[my * qr.size + mx] === 1;
      const value = dark ? 0 : 255;
      const index = (y * pixel + x) * 4;
      data[index] = value;
      data[index + 1] = value;
      data[index + 2] = value;
      data[index + 3] = 255;
    }
  }
  const result = jsQR(data, pixel, pixel);
  return { text: result?.data ?? null, version: qr.version };
}

await test("otpauth 导出链接省略默认参数", () => {
  const uri = buildOtpauthExportUri({
    issuer: "GitHub",
    account: "alice@example.com",
    secret: "JBSWY3DPEHPK3PXP",
    algorithm: "SHA1",
    digits: 6,
    period: 30,
  });
  assert.equal(
    uri,
    "otpauth://totp/GitHub:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub",
  );
  const parsed = parseOtpauthUri(uri);
  assert.equal(parsed.issuer, "GitHub");
  assert.equal(parsed.account, "alice@example.com");
  assert.equal(parsed.secret, "JBSWY3DPEHPK3PXP");
});

await test("otpauth 导出链接保留非默认参数且无 issuer 时不带 issuer", () => {
  const uri = buildOtpauthExportUri({
    issuer: "",
    account: "用户甲",
    secret: "JBSWY3DPEHPK3PXP",
    algorithm: "SHA256",
    digits: 8,
    period: 60,
  });
  assert.ok(uri.startsWith("otpauth://totp/%E7%94%A8%E6%88%B7%E7%94%B2?secret="), uri);
  assert.ok(uri.includes("algorithm=SHA256"), uri);
  assert.ok(uri.includes("digits=8"), uri);
  assert.ok(uri.includes("period=60"), uri);
  assert.ok(!uri.includes("issuer="), uri);
  assert.equal(parseOtpauthUri(uri).account, "用户甲");
});

await test("本地二维码编码可被 jsQR 往返解码", () => {
  const jsQR = loadJsQr();
  const decoded = decodeQrWithJsQr(jsQR, QR_EXPORT_TEXT);
  assert.equal(decoded.text, QR_EXPORT_TEXT);
});

await test("较长 otpauth 链接自动选择更高版本且可解码", () => {
  const jsQR = loadJsQr();
  const longText = `otpauth://totp/AlibabaCloud:${"a".repeat(120)}%40corp.example?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=AlibabaCloud&algorithm=SHA256&digits=8&period=60`;
  const decoded = decodeQrWithJsQr(jsQR, longText);
  assert.equal(decoded.text, longText);
  assert.ok(decoded.version > 5, `版本 ${decoded.version}`);
});

await test("超长文本按 QR_TOO_LONG 拒绝", () => {
  assert.throws(
    () => encodeQr("x".repeat(500)),
    (error) => error?.code === "QR_TOO_LONG",
  );
});

/* -------------------------------- 站点初步筛选 -------------------------------- */

await test("站点域名规范化：协议、端口、大小写与路径", () => {
  assert.equal(normalizeSiteHost("HTTPS://Portal.Acme-Demo.NET:8443/login"), "portal.acme-demo.net");
  assert.equal(normalizeSiteHost("  acme-demo.net.  "), "acme-demo.net");
  assert.equal(normalizeSiteHost(""), "");
  assert.throws(() => normalizeSiteHost("*.acme-demo.net"), (error) => error?.code === "BAD_SITE_HOST");
  assert.throws(() => normalizeSiteHost("co.uk"), (error) => error?.code === "BAD_SITE_HOST");
  assert.deepEqual(normalizeSiteHosts(["A.acme-demo.net", "a.acme-demo.net", ""]), ["a.acme-demo.net"]);
});

await test("可注册域名推导：普通域与多标签公共后缀", () => {
  assert.equal(registrableDomain("a.b.acme-demo.net"), "acme-demo.net");
  assert.equal(registrableDomain("acme-demo.net"), "acme-demo.net");
  assert.equal(registrableDomain("a.b.acme-demo.co.uk"), "acme-demo.co.uk");
  assert.equal(registrableDomain("127.0.0.1"), "127.0.0.1");
});

await test("站点匹配：同域子域命中、根域命中、相似域名不命中", () => {
  assert.equal(isSameSite("portal.acme-demo.net", "a.b.acme-demo.net"), true);
  assert.equal(isSameSite("a.b.acme-demo.net", "acme-demo.net"), true);
  assert.equal(isSameSite("acme-demo.net", "portal.acme-demo.net"), true);
  assert.equal(isSameSite("evil-acme-demo.net", "portal.acme-demo.net"), false);
  assert.equal(isSameSite("acme-demo.net.attacker.example", "portal.acme-demo.net"), false);
  assert.equal(isSameSite("portal.acme-demo.net", "other-acme-demo.net"), false);
});

await test("站点排序：命中的排前且保持组内顺序", () => {
  const accounts = [
    { id: "a", siteHosts: [] },
    { id: "b", siteHosts: ["a.b.acme-demo.net"] },
    { id: "c", siteHosts: ["other.example"] },
    { id: "d", siteHosts: ["acme-demo.net"] },
  ];
  const view = orderAccountsBySite(accounts, "portal.acme-demo.net");
  assert.deepEqual(view.site.map((item) => item.id), ["b", "d"]);
  assert.deepEqual(view.rest.map((item) => item.id), ["a", "c"]);
  assert.deepEqual(view.all.map((item) => item.id), ["b", "d", "a", "c"]);
  assert.equal(view.hasMatches, true);
  assert.equal(orderAccountsBySite(accounts, "unrelated.example").hasMatches, false);
});

await test("扫码候选解析不复用站点筛选函数", () => {
  for (const file of ["protocol.js", "canonical-url.js"]) {
    const source = readFileSync(path.join(rootDir, "common", file), "utf8");
    assert.equal(source.includes("isSameSite"), false, `${file} 不应引用 isSameSite`);
    assert.equal(source.includes("accountMatchesSite"), false, `${file} 不应引用 accountMatchesSite`);
  }
});

await test("包内无签名/信任根代码残留", () => {
  const residues = [];
  for (const dir of ["common", "popup", "options", "content", "."]) {
    const base = path.join(rootDir, dir);
    for (const name of readdirSync(base)) {
      if (!name.endsWith(".js") && !name.endsWith(".mjs")) {
        continue;
      }
      const source = readFileSync(path.join(base, name), "utf8");
      if (/bindingSignatureInput|verifyStoredBinding|TRUSTED_BINDING_KEYS|trusted-keys|totpscan-keys\.json|nacl\.sign/.test(source)) {
        residues.push(path.join(dir, name));
      }
    }
  }
  assert.deepEqual(residues, [], residues.join(", "));
});

/* ----------------------------------- 汇总 ----------------------------------- */

console.log(`\n共 ${passed + failures.length} 项，通过 ${passed}，失败 ${failures.length}`);
if (failures.length > 0) {
  for (const failure of failures) {
    console.log(`\n[${failure.name}]`);
    console.log(failure.error?.stack ?? failure.error);
  }
  process.exit(1);
}
