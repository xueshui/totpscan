/**
 * TOTPSCAN/v1 载荷解析、校验与候选反查（规范 §4–§7、§13.1）。
 *
 * 安全要点：
 * - 二维码内容一律视为不可信输入；
 * - 绑定载荷不再携带签名/公钥，绑定的安全性来自用户在确认页核对 dom 与 path；
 * - 登录二维码中的 url 只用于注册域名比对，提交目标始终使用绑定时的 dom + path；
 * - 候选为 0 时调用方必须本地终止，不得发起任何请求。
 */

import { parseSubmitUrl, UrlCanonicalizationError } from "./canonical-url.js";
import { decodeBase32 } from "./base32.js";
import { registrableDomain } from "./site-filter.js";

export const PROTOCOL_VERSION = 1;

export class ProtocolError extends Error {
  constructor(code, message, detail = "") {
    super(message);
    this.name = "ProtocolError";
    this.code = code;
    this.detail = detail;
  }
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireString(value, code, message, minLength, maxLength) {
  if (typeof value !== "string" || value.length < minLength || value.length > maxLength) {
    throw new ProtocolError(code, message);
  }
  return value;
}

function requireInteger(value, code, message) {
  if (!Number.isInteger(value) || value < 0) {
    throw new ProtocolError(code, message);
  }
  return value;
}

function normalizeDisplayText(value, code, message, maxLength) {
  requireString(value, code, message, 1, maxLength);
  const normalized = value.normalize("NFC");
  if (normalized.length > maxLength || /[\u0000-\u001F\u007F]/.test(normalized)) {
    throw new ProtocolError(code, message);
  }
  return normalized;
}

function parseJsonText(text) {
  if (typeof text !== "string" || text.length === 0 || text.length > 8192) {
    throw new ProtocolError("INVALID_JSON", "二维码内容不是有效的 JSON");
  }
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new ProtocolError("INVALID_JSON", "二维码内容不是有效的 JSON");
  }
  if (!isPlainObject(parsed)) {
    throw new ProtocolError("INVALID_JSON", "二维码内容不是 JSON 对象");
  }
  return parsed;
}

/** 检测二维码文本的大致类型，供扫码结果列表展示（绝不展示 secret）。 */
export function detectQrKind(text) {
  if (typeof text !== "string") {
    return "unknown";
  }
  const trimmed = text.trim();
  if (trimmed.startsWith("{")) {
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && parsed.t === "totp-bind") {
        return "binding";
      }
      if (parsed && parsed.t === "totp-login") {
        return "login";
      }
    } catch {
      return "unknown";
    }
  }
  if (/^otpauth:\/\/totp/i.test(trimmed)) {
    return "otpauth";
  }
  if (/^otpauth-migration:\/\//i.test(trimmed)) {
    return "migration";
  }
  return "unknown";
}

/** 校验 host[:port]，不接受协议、路径或查询串。 */
function parseHostField(value, code, message) {
  const dom = requireString(value, code, message, 1, 255);
  if (/[\u0000-\u001F\u007F]/.test(dom) || /\s/.test(dom)) {
    throw new ProtocolError(code, message);
  }
  if (dom.includes("://") || dom.includes("/") || dom.includes("?") || dom.includes("#")) {
    throw new ProtocolError(code, message);
  }
  let url;
  try {
    url = new URL(`https://${dom}/`);
  } catch {
    throw new ProtocolError(code, message);
  }
  if (url.username !== "" || url.password !== "" || url.pathname !== "/" || url.search || url.hash) {
    throw new ProtocolError(code, message);
  }
  return { dom, host: url.hostname, port: url.port };
}

/** 绑定载荷中的 dom（host[:port]）。 */
function parseBindingDomain(value) {
  return parseHostField(value, "BAD_DOM", "绑定域名无效");
}

/** 校验绑定载荷中的 path（必须含前导 `/`，保留查询串，不允许片段）。 */
function parseBindingPath(value) {
  const path = requireString(value, "BAD_PATH", "绑定提交路径无效", 1, 1024);
  if (!path.startsWith("/")) {
    throw new ProtocolError("BAD_PATH", "绑定提交路径必须以 / 开头");
  }
  if (path.includes("#")) {
    throw new ProtocolError("BAD_PATH", "绑定提交路径不能包含片段");
  }
  if (/[\u0000-\u001F\u007F]/.test(path) || /\s/.test(path)) {
    throw new ProtocolError("BAD_PATH", "绑定提交路径包含空白或控制字符");
  }
  return path;
}

/**
 * 校验绑定二维码。
 *
 * 载荷字段只有：t / v / bid / iss / acc / sec / alg / dig / per / dom / path / iat / exp。
 * dep 的提交地址固定由 `https://${dom}${path}` 组成，并在绑定时原样保存。
 */
export function validateBindingPayload(text, options = {}) {
  const now = options.now ?? Math.floor(Date.now() / 1000);
  const raw = parseJsonText(text);

  if (raw.t !== "totp-bind") {
    throw new ProtocolError("BAD_TYPE", "不是绑定二维码");
  }
  if (raw.v !== PROTOCOL_VERSION) {
    throw new ProtocolError("BAD_VERSION", "二维码协议版本不受支持");
  }

  const payload = { t: "totp-bind", v: PROTOCOL_VERSION };
  payload.bid = requireString(raw.bid, "BAD_BID", "绑定标识无效", 1, 64);
  if (!/^b_[A-Za-z0-9_-]{16,64}$/.test(payload.bid)) {
    throw new ProtocolError("BAD_BID", "绑定标识格式无效");
  }
  payload.iss = normalizeDisplayText(raw.iss, "BAD_ISSUER", "签发方名称无效", 64);
  payload.acc = normalizeDisplayText(raw.acc, "BAD_ACCOUNT", "账户名称无效", 255);
  payload.sec = requireString(raw.sec, "BAD_SECRET", "密钥格式无效", 1, 103);
  if (!/^[A-Z2-7]+$/.test(payload.sec)) {
    throw new ProtocolError("BAD_SECRET", "密钥必须是大写 Base32 且无填充");
  }
  const secretBytes = decodeBase32(payload.sec);
  if (secretBytes.length < 16 || secretBytes.length > 64) {
    throw new ProtocolError("BAD_SECRET", "密钥长度必须在 16–64 字节之间");
  }

  if (raw.alg !== "SHA1" && raw.alg !== "SHA256" && raw.alg !== "SHA512") {
    throw new ProtocolError("BAD_ALGORITHM", "签名算法不受支持");
  }
  payload.alg = raw.alg;
  if (raw.dig !== 6 && raw.dig !== 8) {
    throw new ProtocolError("BAD_DIGITS", "动态码位数不受支持");
  }
  payload.dig = raw.dig;
  if (raw.per !== 30 && raw.per !== 60) {
    throw new ProtocolError("BAD_PERIOD", "时间步长不受支持");
  }
  payload.per = raw.per;

  const { dom } = parseBindingDomain(raw.dom);
  const path = parseBindingPath(raw.path);
  payload.dom = dom;
  payload.path = path;

  let target;
  try {
    target = parseSubmitUrl(`https://${dom}${path}`);
  } catch (error) {
    throw new ProtocolError(
      "BAD_SUBMIT_URL",
      "绑定提交地址无效",
      error instanceof UrlCanonicalizationError ? error.reason : "UNKNOWN",
    );
  }
  payload.submitUrl = target.submitUrl;

  payload.iat = requireInteger(raw.iat, "BAD_IAT", "签发时间无效");
  if (raw.exp !== undefined) {
    payload.exp = requireInteger(raw.exp, "BAD_EXP", "失效时间无效");
    if (now > payload.exp) {
      throw new ProtocolError("EXPIRED", "二维码已过期，请重新发起绑定");
    }
  }

  return {
    payload,
    submitUrl: target.submitUrl,
    target,
    summary: {
      issuer: payload.iss,
      account: payload.acc,
      submitUrl: target.submitUrl,
      submitPath: path,
      host: target.host,
      domain: target.domain,
      algorithm: payload.alg,
      digits: payload.dig,
      period: payload.per,
      expiresAt: payload.exp ?? null,
      bindingId: payload.bid,
    },
  };
}

/**
 * 校验登录二维码（不涉及任何网络）。
 *
 * 登录载荷只有：t / v / url / token / exp。
 * url 只是域名（不带协议、端口外路径或查询串），提交地址始终使用绑定时的 dom + path。
 */
export function validateLoginPayload(text, options = {}) {
  const now = options.now ?? Math.floor(Date.now() / 1000);
  const raw = parseJsonText(text);
  if (raw.t !== "totp-login") {
    throw new ProtocolError("BAD_TYPE", "不是登录二维码");
  }
  if (raw.v !== PROTOCOL_VERSION) {
    throw new ProtocolError("BAD_VERSION", "二维码协议版本不受支持");
  }
  const payload = { t: "totp-login", v: PROTOCOL_VERSION };
  const { dom, host } = parseHostField(raw.url, "BAD_SUBMIT_URL", "登录二维码域名无效");
  payload.url = dom;
  payload.host = host;
  payload.domain = registrableDomain(host);

  payload.token = requireString(raw.token, "BAD_TOKEN", "会话标识格式无效", 16, 24);
  if (!/^(?:[A-Za-z0-9_-]{16}|[A-Za-z0-9_-]{24})$/.test(payload.token)) {
    throw new ProtocolError("BAD_TOKEN", "会话标识格式无效");
  }

  payload.exp = requireInteger(raw.exp, "BAD_EXP", "失效时间无效");
  if (now > payload.exp) {
    throw new ProtocolError("EXPIRED", "二维码已过期，请在网页刷新二维码后重试");
  }
  if (payload.exp - now > 60) {
    throw new ProtocolError("BAD_EXP", "二维码有效期异常");
  }

  return {
    payload,
    summary: {
      url: dom,
      host,
      domain: payload.domain,
      token: payload.token,
      expiresAt: payload.exp,
    },
  };
}

/**
 * §6.2 A2–A6：按登录二维码的域名反查本地扫码型账户。
 *
 * 登录码只带域名；比对只使用注册域名，提交路径始终取绑定时的 path。
 * 同一注册域名可能有多个账户，全部返回交给用户选择。
 */
export function findScanCandidates(loginPayload, accounts) {
  const loginDomain = loginPayload?.domain ?? "";
  const hits = [];
  if (!loginDomain) {
    return [];
  }
  for (const account of accounts) {
    if (!account || account.type !== "scan" || account.status !== "confirmed") {
      continue;
    }
    let target;
    try {
      target = parseSubmitUrl(account.submitUrl);
    } catch {
      continue;
    }
    const accountDomain = account.siteDomain || target.domain;
    const accountPath = account.submitPath || target.path;
    if (accountDomain !== loginDomain) {
      continue;
    }
    if (typeof accountPath !== "string" || !accountPath.startsWith("/")) {
      continue;
    }
    hits.push({ account });
  }
  const latestByAccount = new Map();
  for (const hit of hits) {
    const key = `${hit.account.issuer}\u0000${hit.account.account}`;
    const previous = latestByAccount.get(key);
    const time = hit.account.confirmedAt ?? hit.account.updatedAt ?? 0;
    const previousTime = previous ? previous.account.confirmedAt ?? previous.account.updatedAt ?? 0 : -1;
    if (!previous || time >= previousTime) {
      latestByAccount.set(key, hit);
    }
  }
  return Array.from(latestByAccount.values()).sort(
    (a, b) => (b.account.confirmedAt ?? 0) - (a.account.confirmedAt ?? 0),
  );
}

/** 绑定确认接口位于固化地址同源的固定路径，不使用二维码中的地址。 */
export function buildBindingConfirmUrl(pinnedSubmitUrl, bindingId) {
  if (typeof bindingId !== "string" || !/^b_[A-Za-z0-9_-]{16,64}$/.test(bindingId)) {
    throw new ProtocolError("BAD_BID", "绑定标识格式无效");
  }
  try {
    const target = parseSubmitUrl(pinnedSubmitUrl);
    return `${target.origin}/totp/v1/bindings/${encodeURIComponent(bindingId)}/confirm`;
  } catch (error) {
    throw new ProtocolError(
      "BAD_SUBMIT_URL",
      "绑定提交地址无效",
      error instanceof UrlCanonicalizationError ? error.reason : "UNKNOWN",
    );
  }
}
