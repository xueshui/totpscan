/**
 * otpauth://totp URI 解析与生成（规范 §13.2 U1–U9）。
 * 导入采用宽松但确定的规则：拒绝 HOTP、重复参数与 issuer 冲突。
 */

import { decodeBase32, encodeBase32, normalizeBase32Loose } from "./base32.js";
import { labels } from "./labels.js";

export class OtpAuthError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "OtpAuthError";
    this.code = code;
  }
}

const ALGORITHMS = ["SHA1", "SHA256", "SHA512"];

function normalizeText(value, field, maxLength) {
  if (typeof value !== "string") {
    throw new OtpAuthError("BAD_FIELD", `${field} 不是字符串`);
  }
  const normalized = value.normalize("NFC");
  if (normalized.length === 0 || normalized.length > maxLength) {
    throw new OtpAuthError("BAD_FIELD", `${field} 长度必须在 1–${maxLength} 之间`);
  }
  if (/[\u0000-\u001F\u007F]/.test(normalized)) {
    throw new OtpAuthError("BAD_FIELD", `${field} 含控制字符`);
  }
  return normalized;
}

function parseDigits(raw) {
  if (raw === null || raw === undefined) {
    return 6;
  }
  if (raw !== "6" && raw !== "8") {
    throw new OtpAuthError("BAD_DIGITS", "位数只支持 6 或 8");
  }
  return Number(raw);
}

function parsePeriod(raw) {
  if (raw === null || raw === undefined) {
    return 30;
  }
  if (!/^\d+$/.test(raw)) {
    throw new OtpAuthError("BAD_PERIOD", "周期必须是正整数秒");
  }
  const period = Number(raw);
  if (!Number.isInteger(period) || period < 1 || period > 3600) {
    throw new OtpAuthError("BAD_PERIOD", "周期必须在 1–3600 秒之间");
  }
  return period;
}

function collectQuery(pairs) {
  const map = new Map();
  for (let i = 0; i < pairs.length; i += 1) {
    const key = pairs[i][0].toLowerCase();
    if (map.has(key)) {
      throw new OtpAuthError("DUPLICATE_PARAM", `参数 ${key} 重复出现`);
    }
    map.set(key, pairs[i][1]);
  }
  return map;
}

/**
 * 解析 otpauth://totp/...，返回标准型账户字段。
 * secret 以规范 Base32（大写、无填充）返回，同时保留原始字节。
 */
export function parseOtpauthUri(uri) {
  if (typeof uri !== "string" || uri.trim() === "") {
    throw new OtpAuthError("EMPTY_URI", "链接为空");
  }
  let url;
  try {
    url = new URL(uri.trim());
  } catch {
    throw new OtpAuthError("BAD_URI", "不是合法的 otpauth 链接");
  }
  if (url.protocol.toLowerCase() !== "otpauth:") {
    throw new OtpAuthError("BAD_SCHEME", "只支持 otpauth:// 链接");
  }
  if (url.hostname.toLowerCase() !== "totp") {
    throw new OtpAuthError("NOT_TOTP", "只支持 TOTP，不支持 HOTP 或其他类型");
  }

  const pairs = Array.from(url.searchParams.entries());
  const query = collectQuery(pairs);
  if (query.has("counter")) {
    throw new OtpAuthError("HOTP_COUNTER", "包含 HOTP 计数器，已拒绝导入");
  }

  let label;
  try {
    label = decodeURIComponent(url.pathname.replace(/^\//, ""));
  } catch {
    throw new OtpAuthError("BAD_LABEL", "标签编码无效");
  }
  if (label === "") {
    throw new OtpAuthError("BAD_LABEL", "标签为空");
  }

  const colonIndex = label.indexOf(":");
  const labelIssuer = colonIndex >= 0 ? label.slice(0, colonIndex) : "";
  let account = colonIndex >= 0 ? label.slice(colonIndex + 1) : label;
  const issuerParam = query.get("issuer") ?? "";
  if (labelIssuer !== "" && issuerParam !== "" && labelIssuer.normalize("NFC") !== issuerParam.normalize("NFC")) {
    throw new OtpAuthError("ISSUER_CONFLICT", "标签中的签发方与 issuer 参数不一致");
  }
  const issuer = issuerParam || labelIssuer;
  if (account === "") {
    account = issuer === "" ? labels.unnamedAccount : issuer;
    if (colonIndex >= 0 && labelIssuer !== "" && issuer !== "") {
      throw new OtpAuthError("BAD_LABEL", "账户名为空");
    }
  }

  const secretRaw = query.get("secret");
  if (secretRaw === null || secretRaw === undefined || secretRaw.trim() === "") {
    throw new OtpAuthError("MISSING_SECRET", "缺少 secret 参数");
  }
  let secretCanonical;
  let secretBytes;
  try {
    secretCanonical = normalizeBase32Loose(secretRaw);
    secretBytes = decodeBase32(secretCanonical);
  } catch {
    throw new OtpAuthError("BAD_SECRET", "secret 不是合法的 Base32");
  }
  if (secretBytes.length < 10) {
    throw new OtpAuthError("SHORT_SECRET", "密钥长度不足 10 字节");
  }
  if (secretBytes.length > 128) {
    throw new OtpAuthError("LONG_SECRET", "密钥长度异常（超过 128 字节）");
  }

  const algorithmRaw = (query.get("algorithm") ?? "SHA1").toUpperCase();
  if (!ALGORITHMS.includes(algorithmRaw)) {
    throw new OtpAuthError("BAD_ALGORITHM", "只支持 SHA1 / SHA256 / SHA512");
  }

  const digits = parseDigits(query.get("digits"));
  const period = parsePeriod(query.get("period"));

  return {
    issuer: issuer === "" ? labels.unnamedIssuer : normalizeText(issuer, "签发方", 64),
    account: normalizeText(account, "账户", 255),
    secret: encodeBase32(secretBytes),
    secretBytes,
    algorithm: algorithmRaw,
    digits,
    period,
    weak: secretBytes.length < 16,
  };
}

/** 生成标准型账户的 otpauth:// 链接（导出用）。 */
export function buildOtpauthUri(account) {
  const issuer = account.issuer === labels.unnamedIssuer ? "" : account.issuer;
  const label = issuer ? `${issuer}:${account.account}` : account.account;
  const params = new URLSearchParams();
  params.set("secret", account.secret);
  if (issuer) {
    params.set("issuer", issuer);
  }
  params.set("algorithm", account.algorithm);
  params.set("digits", String(account.digits));
  params.set("period", String(account.period));
  return `otpauth://totp/${encodeURIComponent(label)}?${params.toString()}`;
}

/**
 * 生成二维码展示用的 otpauth:// 链接（仅内存使用）。
 * 与备份文本导出的 buildOtpauthUri 分开：默认参数（SHA1 / 6 位 / 30 秒）省略，
 * label 保留 issuer 与 account 之间的冒号，其余字符按 URI 规范百分号编码。
 */
export function buildOtpauthExportUri(account) {
  const issuer = account.issuer === labels.unnamedIssuer ? "" : String(account.issuer ?? "");
  const accountName = String(account.account ?? "");
  const label = issuer
    ? `${encodeURIComponent(issuer)}:${encodeURIComponent(accountName)}`
    : encodeURIComponent(accountName);

  const params = [`secret=${encodeURIComponent(account.secret ?? "")}`];
  if (issuer) {
    params.push(`issuer=${encodeURIComponent(issuer)}`);
  }
  const algorithm = String(account.algorithm ?? "SHA1").toUpperCase();
  if (algorithm !== "SHA1") {
    params.push(`algorithm=${encodeURIComponent(algorithm)}`);
  }
  const digits = Number(account.digits ?? 6);
  if (digits !== 6) {
    params.push(`digits=${digits}`);
  }
  const period = Number(account.period ?? 30);
  if (period !== 30) {
    params.push(`period=${period}`);
  }
  return `otpauth://totp/${label}?${params.join("&")}`;
}

/** 手动录入的字段归一化（U9）。 */
export function normalizeManualEntry(input) {
  const issuer = normalizeText(input.issuer?.trim() || labels.unnamedIssuer, "签发方", 64);
  const account = normalizeText(input.account?.trim() || labels.unnamedAccount, "账户", 255);
  let secretCanonical;
  let secretBytes;
  try {
    secretCanonical = normalizeBase32Loose(input.secret ?? "");
    secretBytes = decodeBase32(secretCanonical);
  } catch {
    throw new OtpAuthError("BAD_SECRET", "密钥不是合法的 Base32");
  }
  if (secretBytes.length < 10) {
    throw new OtpAuthError("SHORT_SECRET", "密钥长度不足 10 字节");
  }
  if (secretBytes.length > 128) {
    throw new OtpAuthError("LONG_SECRET", "密钥长度异常（超过 128 字节）");
  }
  const algorithm = (input.algorithm ?? "SHA1").toUpperCase();
  if (!ALGORITHMS.includes(algorithm)) {
    throw new OtpAuthError("BAD_ALGORITHM", "只支持 SHA1 / SHA256 / SHA512");
  }
  const digits = Number(input.digits ?? 6);
  if (digits !== 6 && digits !== 8) {
    throw new OtpAuthError("BAD_DIGITS", "位数只支持 6 或 8");
  }
  const period = Number(input.period ?? 30);
  if (!Number.isInteger(period) || period < 1 || period > 3600) {
    throw new OtpAuthError("BAD_PERIOD", "周期必须在 1–3600 秒之间");
  }
  return {
    issuer,
    account,
    secret: encodeBase32(secretBytes),
    secretBytes,
    algorithm,
    digits,
    period,
    weak: secretBytes.length < 16,
  };
}
