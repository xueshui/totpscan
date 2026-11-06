/**
 * 站点初步筛选：仅用于弹窗中的显示顺序与可见性。
 *
 * 安全边界（务必保持）：
 * - 本模块只接收「账户展示字段」和「当前标签页 host」，输出用于排序/过滤的布尔结果；
 * - 本模块的站点筛选函数（isSameSite/accountMatchesSite）不得被提交路径复用；
 * - 仅注册域名推导函数 registrableDomain 可供提交比对复用。
 *
 * 匹配规则：分别从账户保存的 host 与当前 host 推导可注册域名，再比较是否同一站点。
 * 只按域名标签边界比较，绝不做字符串包含，也不支持 `*` 通配符。
 */

/** 常见的多标签公共后缀（不追求完整 PSL，只覆盖常见的注册域名结构）。 */
const MULTI_LABEL_SUFFIXES = new Set([
  "com.cn",
  "net.cn",
  "org.cn",
  "gov.cn",
  "edu.cn",
  "ac.cn",
  "com.hk",
  "net.hk",
  "org.hk",
  "com.tw",
  "net.tw",
  "org.tw",
  "com.mo",
  "co.uk",
  "org.uk",
  "ac.uk",
  "gov.uk",
  "co.jp",
  "ne.jp",
  "or.jp",
  "com.au",
  "net.au",
  "org.au",
  "co.nz",
  "com.sg",
  "com.br",
  "com.mx",
  "co.kr",
  "or.kr",
]);

const MAX_SITE_HOSTS = 20;
const MAX_HOST_LENGTH = 253;

function invalidHost() {
  const error = new Error("站点域名格式无效");
  error.code = "BAD_SITE_HOST";
  return error;
}

/**
 * 规范化单个站点域名：只保留小写 host，去掉协议、路径、端口与末尾点。
 * 空值返回 ""；含通配符、空白、非法字符或是公共后缀本身时抛 BAD_SITE_HOST。
 */
export function normalizeSiteHost(input) {
  if (input === undefined || input === null) {
    return "";
  }
  if (typeof input !== "string") {
    throw invalidHost();
  }
  let text = input.trim();
  if (!text) {
    return "";
  }
  if (/[\s*@]/.test(text)) {
    throw invalidHost();
  }
  if (!text.includes("://")) {
    text = `http://${text}`;
  }
  let host;
  try {
    host = new URL(text).hostname;
  } catch {
    throw invalidHost();
  }
  host = host.toLowerCase().replace(/\.+$/, "").replace(/^\.+/, "");
  if (!host || host.length > MAX_HOST_LENGTH || host.includes(":") || host.includes("*")) {
    throw invalidHost();
  }
  if (!/^[a-z0-9.-]+$/.test(host) || !host.includes(".")) {
    throw invalidHost();
  }
  for (const label of host.split(".")) {
    if (!label || label.length > 63 || label.startsWith("-") || label.endsWith("-")) {
      throw invalidHost();
    }
  }
  if (MULTI_LABEL_SUFFIXES.has(host)) {
    throw invalidHost();
  }
  return host;
}

/** 规范化一组站点域名：去空、去重、限制数量；任一非法值直接抛错。 */
export function normalizeSiteHosts(input) {
  if (input === undefined || input === null || input === "") {
    return [];
  }
  const list = Array.isArray(input) ? input : [input];
  const result = [];
  for (const item of list) {
    const host = normalizeSiteHost(item);
    if (host && !result.includes(host)) {
      result.push(host);
    }
    if (result.length > MAX_SITE_HOSTS) {
      throw invalidHost();
    }
  }
  return result;
}

/** 取可注册域名（eTLD+1 的近似实现）；IP 与单标签 host 原样返回。 */
export function registrableDomain(host) {
  const value = String(host ?? "")
    .trim()
    .toLowerCase()
    .replace(/\.+$/, "");
  if (!value) {
    return "";
  }
  if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(value) || value.includes(":")) {
    return value;
  }
  const labels = value.split(".");
  if (labels.length <= 2) {
    return value;
  }
  if (MULTI_LABEL_SUFFIXES.has(labels.slice(-2).join("."))) {
    return labels.slice(-3).join(".");
  }
  return labels.slice(-2).join(".");
}

/**
 * 判断账户记录的某个站点域名是否命中当前页面的站点。
 * 两侧都先推导可注册域名，再比较是否同一站点；只会命中同一注册域名下的 host。
 */
export function isSameSite(storedHost, currentHost) {
  let stored;
  let current;
  try {
    stored = normalizeSiteHost(storedHost);
    current = normalizeSiteHost(currentHost);
  } catch {
    return false;
  }
  if (!stored || !current) {
    return false;
  }
  const storedBase = registrableDomain(stored);
  const currentBase = registrableDomain(current);
  if (!storedBase || !currentBase) {
    return false;
  }
  return storedBase === currentBase;
}

/** 账户是否在当前站点上（只读取 siteHosts 展示字段）。 */
export function accountMatchesSite(account, currentHost) {
  const hosts = Array.isArray(account?.siteHosts) ? account.siteHosts : [];
  return hosts.some((host) => isSameSite(host, currentHost));
}

/**
 * 按「本站点」优先排序，保持各自原有相对顺序。
 * 返回 { site, rest, all, hasMatches }，供弹窗渲染与切换按钮使用。
 */
export function orderAccountsBySite(accounts, currentHost) {
  const list = Array.isArray(accounts) ? accounts : [];
  const site = [];
  const rest = [];
  for (const account of list) {
    if (accountMatchesSite(account, currentHost)) {
      site.push(account);
    } else {
      rest.push(account);
    }
  }
  return { site, rest, all: [...site, ...rest], hasMatches: site.length > 0 };
}
