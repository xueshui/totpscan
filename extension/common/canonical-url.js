/**
 * 提交地址解析。
 *
 * 绑定模型钉「注册域名 + 提交路径（path + query）」：
 * - 提交目标始终由绑定时的 `https://${dom}${path}` 组成并原样保存；
 * - 登录二维码只带域名，绝不把登录二维码里的 host 当作提交目标。
 *
 * 任何解析失败都必须视为不合法，禁止降级为字符串包含/后缀判断。
 */

import { registrableDomain } from "./site-filter.js";

const MAX_URL_LENGTH = 2048;
const LOOPBACK_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]", "::1"]);

export class UrlCanonicalizationError extends Error {
  constructor(reason) {
    super(reason);
    this.name = "UrlCanonicalizationError";
    this.reason = reason;
  }
}

function normalizeHostname(hostname) {
  let host = String(hostname ?? "").toLowerCase();
  while (host.endsWith(".")) {
    host = host.slice(0, -1);
  }
  return host;
}

/**
 * 解析并校验提交地址，保留 path 与 query 原样。
 * 返回的 submitUrl 是输入字符串本身，供落库与提交直接使用。
 */
export function parseSubmitUrl(raw) {
  if (typeof raw !== "string") {
    throw new UrlCanonicalizationError("NOT_A_STRING");
  }
  if (raw.length < 1 || raw.length > MAX_URL_LENGTH) {
    throw new UrlCanonicalizationError("LENGTH_OUT_OF_RANGE");
  }
  if (raw !== raw.trim()) {
    throw new UrlCanonicalizationError("SURROUNDING_WHITESPACE");
  }
  if (/[\u0000-\u001F\u007F]/.test(raw)) {
    throw new UrlCanonicalizationError("CONTROL_CHARACTER");
  }

  let url;
  try {
    url = new URL(raw);
  } catch {
    throw new UrlCanonicalizationError("NOT_ABSOLUTE_URL");
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new UrlCanonicalizationError("UNSUPPORTED_SCHEME");
  }
  if (url.username !== "" || url.password !== "") {
    throw new UrlCanonicalizationError("USERINFO_PRESENT");
  }
  if (url.hash !== "") {
    throw new UrlCanonicalizationError("FRAGMENT_PRESENT");
  }
  if (url.protocol === "http:" && !LOOPBACK_HOSTS.has(url.hostname.toLowerCase())) {
    throw new UrlCanonicalizationError("INSECURE_HTTP");
  }

  const host = normalizeHostname(url.hostname);
  if (host === "") {
    throw new UrlCanonicalizationError("EMPTY_HOST");
  }
  const domain = registrableDomain(host);
  if (domain === "") {
    throw new UrlCanonicalizationError("EMPTY_HOST");
  }

  const pathname = url.pathname === "" ? "/" : url.pathname;
  const search = url.search;
  return {
    submitUrl: raw,
    scheme: url.protocol,
    host,
    port: url.port,
    origin: url.origin,
    pathname,
    search,
    path: `${pathname}${search}`,
    domain,
  };
}

/** 仅允许 https，或 http 回环地址；用于提交前的最后一道防线。 */
export function isTransportAllowed(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return false;
  }
  if (url.protocol === "https:") {
    return true;
  }
  return url.protocol === "http:" && LOOPBACK_HOSTS.has(url.hostname.toLowerCase());
}
