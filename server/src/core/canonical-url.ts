/**
 * 提交地址规范化（规范 §7）。
 *
 * 职责边界（重要）：
 * - 本模块只负责 URL 规范化：小写 host、去默认端口、去尾斜杠、拒绝 userinfo / fragment，
 *   并原样保留查询串。
 * - 本模块**不做**注册域名推导，也不做任何域名比对。注册域名由客户端用完整 PSL 推导；
 *   参考服务端不承担 pin 校验（规范 §5.3、§7.3）。
 */

export class UrlCanonicalizationError extends Error {
  readonly reason: string;

  constructor(reason: string) {
    super(reason);
    this.name = "UrlCanonicalizationError";
    this.reason = reason;
  }
}

const MAX_URL_LENGTH = 2048;

/** 判定是否回环地址（允许 http 的唯一场景）。 */
function isLoopbackHost(hostname: string): boolean {
  const host = hostname.toLowerCase();
  return host === "localhost" || host === "127.0.0.1" || host === "[::1]" || host === "::1";
}

/** 解码 unreserved 字符的百分号编码，其余 %XX 统一大写。 */
function normalizePercentEncoding(path: string): string {
  return path.replace(/%([0-9A-Fa-f]{2})/g, (_match, hex: string) => {
    const code = Number.parseInt(hex, 16);
    const char = String.fromCharCode(code);
    if (/[A-Za-z0-9\-._~]/.test(char)) {
      return char;
    }
    return "%" + hex.toUpperCase();
  });
}

/** 合并连续斜杠。 */
function collapseSlashes(path: string): string {
  return path.replace(/\/{2,}/g, "/");
}

/** 解析 `.` 与 `..` 段，`..` 不得越过根。 */
function resolveDotSegments(path: string): string {
  const input = path.split("/");
  const output: string[] = [];
  for (const segment of input) {
    if (segment === "" || segment === ".") {
      continue;
    }
    if (segment === "..") {
      if (output.length > 0) {
        output.pop();
      }
      continue;
    }
    output.push(segment);
  }
  const prefix = path.startsWith("/") ? "/" : "";
  return prefix + output.join("/");
}

/** 去除末尾斜杠（根路径保留 `/`）。 */
function stripTrailingSlash(path: string): string {
  if (path === "/") {
    return "/";
  }
  const trimmed = path.replace(/\/+$/g, "");
  return trimmed === "" ? "/" : trimmed;
}

/** 校验并规范化 host[:port]，用于绑定载荷的 `dom` 字段。 */
export function normalizeBindDomain(raw: unknown): string {
  if (typeof raw !== "string" || raw.length < 1 || raw.length > 255) {
    throw new UrlCanonicalizationError("DOM_LENGTH_OUT_OF_RANGE");
  }
  if (raw !== raw.trim() || /[\u0000-\u001F\u007F]/.test(raw)) {
    throw new UrlCanonicalizationError("DOM_INVALID_CHARACTER");
  }
  if (raw.includes("@") || raw.includes("/") || raw.includes("?") || raw.includes("#")) {
    throw new UrlCanonicalizationError("DOM_INVALID_CHARACTER");
  }

  let url: URL;
  try {
    url = new URL(`https://${raw}`);
  } catch {
    throw new UrlCanonicalizationError("DOM_NOT_A_HOST");
  }
  if (url.username !== "" || url.password !== "" || url.pathname !== "/" || url.search !== "" || url.hash !== "") {
    throw new UrlCanonicalizationError("DOM_NOT_A_HOST");
  }

  let host = url.hostname.toLowerCase();
  while (host.endsWith(".")) {
    host = host.slice(0, -1);
  }
  if (host === "") {
    throw new UrlCanonicalizationError("EMPTY_HOST");
  }
  if (host.includes(":") && !host.startsWith("[")) {
    host = `[${host}]`;
  }
  const port = url.port === "443" ? "" : url.port;
  return port === "" ? host : `${host}:${port}`;
}

/**
 * 校验绑定载荷的 `path` 字段：必须是以 `/` 开头的提交路径，可带查询串。
 * 路径与查询串**原样保留**，不做解码、重编码、排序或点段解析（规范 §7.2 C6）。
 */
export function normalizeBindPath(raw: unknown): string {
  if (typeof raw !== "string" || raw.length < 1 || raw.length > MAX_URL_LENGTH) {
    throw new UrlCanonicalizationError("PATH_LENGTH_OUT_OF_RANGE");
  }
  if (raw !== raw.trim() || /[\u0000-\u001F\u007F\s]/.test(raw)) {
    throw new UrlCanonicalizationError("PATH_INVALID_CHARACTER");
  }
  if (!raw.startsWith("/")) {
    throw new UrlCanonicalizationError("PATH_NOT_ABSOLUTE");
  }
  if (raw.includes("#")) {
    throw new UrlCanonicalizationError("FRAGMENT_PRESENT");
  }
  return raw;
}

/**
 * 将提交地址规范化为 `scheme://host[:port]path[?query]`（§7.2 C1–C7）。
 * 查询串原样保留；失败时抛出 UrlCanonicalizationError。
 */
export function canonicalizeSubmitUrl(raw: unknown): string {
  if (typeof raw !== "string") {
    throw new UrlCanonicalizationError("NOT_A_STRING");
  }
  if (raw.length < 1 || raw.length > MAX_URL_LENGTH) {
    throw new UrlCanonicalizationError("LENGTH_OUT_OF_RANGE");
  }
  if (raw !== raw.trim()) {
    throw new UrlCanonicalizationError("SURROUNDING_WHITESPACE");
  }
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001F\u007F]/.test(raw)) {
    throw new UrlCanonicalizationError("CONTROL_CHARACTER");
  }
  if (raw.includes("#")) {
    throw new UrlCanonicalizationError("FRAGMENT_PRESENT");
  }

  // 先切出原始查询串，避免 WHATWG URL 对其重新编码（C3：允许 query，原样保留）。
  const queryIndex = raw.indexOf("?");
  const baseRaw = queryIndex >= 0 ? raw.slice(0, queryIndex) : raw;
  const query = queryIndex >= 0 ? raw.slice(queryIndex + 1) : "";

  let url: URL;
  try {
    url = new URL(baseRaw);
  } catch {
    throw new UrlCanonicalizationError("NOT_ABSOLUTE_URL");
  }

  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new UrlCanonicalizationError("UNSUPPORTED_SCHEME");
  }
  if (url.username !== "" || url.password !== "") {
    throw new UrlCanonicalizationError("USERINFO_PRESENT");
  }
  if (url.protocol === "http:" && !isLoopbackHost(url.hostname)) {
    throw new UrlCanonicalizationError("INSECURE_HTTP");
  }

  // C4：host 由 WHATWG URL 完成 IDNA ToASCII，这里补小写与结尾点处理。
  let host = url.hostname.toLowerCase();
  while (host.endsWith(".")) {
    host = host.slice(0, -1);
  }
  if (host === "") {
    throw new UrlCanonicalizationError("EMPTY_HOST");
  }
  if (host.includes(":") && !host.startsWith("[")) {
    host = `[${host}]`;
  }

  // C5：去掉默认端口与端口前导零。
  const defaultPort = url.protocol === "https:" ? "443" : "80";
  let port = url.port;
  if (port !== "") {
    port = String(Number.parseInt(port, 10));
    if (port === defaultPort) {
      port = "";
    }
  }

  // C6：路径规范化（查询串不参与）。
  let path = normalizePercentEncoding(url.pathname);
  path = collapseSlashes(path);
  path = resolveDotSegments(path);
  path = stripTrailingSlash(path);
  if (!path.startsWith("/")) {
    path = "/" + path;
  }

  const suffix = query === "" ? "" : `?${query}`;
  return `${url.protocol}//${host}${port === "" ? "" : ":" + port}${path}${suffix}`;
}

export interface CanonicalUrlParts {
  scheme: string;
  host: string;
  port: string;
  path: string;
  /** 原始查询串（不含 `?`），无查询串时为空字符串。 */
  query: string;
  /** `path` + `?query`，用于前缀比对。 */
  pathQuery: string;
}

/** 拆分规范形式，便于读取 host / path / query。 */
export function splitCanonicalUrl(canonical: string): CanonicalUrlParts {
  const queryIndex = canonical.indexOf("?");
  const baseRaw = queryIndex >= 0 ? canonical.slice(0, queryIndex) : canonical;
  const query = queryIndex >= 0 ? canonical.slice(queryIndex + 1) : "";
  const url = new URL(baseRaw);
  return {
    scheme: url.protocol,
    host: url.hostname.toLowerCase(),
    port: url.port,
    path: url.pathname,
    query,
    pathQuery: url.pathname + (query === "" ? "" : `?${query}`),
  };
}
