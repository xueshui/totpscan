import { CanonicalUrl } from './CanonicalUrl';
import { RegisteredDomain } from './RegisteredDomain';
import { UrlCanonicalizationError } from './CanonicalUrl';

/**
 * 提交地址解析：保留 path 与查询串原样，只规范化 scheme / host / 端口。
 *
 * 与 `CanonicalUrl` 的区别：
 * - 允许 `?query`（绑定地址可能是 `/dtm/ulr?ma=xxx`）；
 * - 不做百分号解码、不合并斜杠、不消解 `.`/`..` 段；
 * - 用于「钉注册域名 + 提交路径前缀」比对，以及保存完整提交地址。
 */
export interface PinnedUrlParts {
  scheme: string;
  /** 已小写；IPv6 含方括号。 */
  host: string;
  /** 空串表示默认端口。 */
  port: string;
  origin: string;
  /** 原样保留，至少为 `/`。 */
  path: string;
  /** 不含 `?`；无查询串时为空串。 */
  query: string;
  /** path + ('?' + query)（query 非空时）。 */
  pathQuery: string;
  /** origin + pathQuery，作为提交目标与绑定记录。 */
  full: string;
  registeredDomain: string;
}

const MAX_URL_LENGTH = 2048;

function fail(reason: string): void {
  throw new UrlCanonicalizationError(reason);
}

export class PinnedUrl {
  static parse(raw: string): PinnedUrlParts {
    if (typeof raw !== 'string') {
      fail('NOT_A_STRING');
    }
    if (raw.length < 1 || raw.length > MAX_URL_LENGTH) {
      fail('LENGTH_OUT_OF_RANGE');
    }
    if (raw !== raw.trim()) {
      fail('SURROUNDING_WHITESPACE');
    }
    if (new RegExp('[\\u0000-\\u001F\\u007F]').test(raw)) {
      fail('CONTROL_CHARACTER');
    }
    if (new RegExp('\\s').test(raw)) {
      fail('WHITESPACE_PRESENT');
    }
    if (raw.indexOf('\\') >= 0) {
      fail('BACKSLASH_NOT_ALLOWED');
    }
    if (raw.indexOf('#') >= 0) {
      fail('FRAGMENT_NOT_ALLOWED');
    }

    const schemeEnd = raw.indexOf('://');
    if (schemeEnd <= 0) {
      fail('NOT_ABSOLUTE_URL');
    }
    const scheme = raw.substring(0, schemeEnd).toLowerCase();
    if (scheme !== 'https' && scheme !== 'http') {
      fail('UNSUPPORTED_SCHEME');
    }
    const rest = raw.substring(schemeEnd + 3);
    if (rest.length === 0) {
      fail('EMPTY_HOST');
    }

    const slash = rest.indexOf('/');
    const question = rest.indexOf('?');
    let splitAt = -1;
    if (slash >= 0) {
      splitAt = slash;
    }
    if (question >= 0 && (splitAt < 0 || question < splitAt)) {
      splitAt = question;
    }
    const authority = splitAt >= 0 ? rest.substring(0, splitAt) : rest;
    if (authority.length === 0) {
      fail('EMPTY_HOST');
    }
    if (authority.indexOf('@') >= 0) {
      fail('USERINFO_PRESENT');
    }

    // 复用 CanonicalUrl 的主机/端口/IDNA/HTTP 限制校验（只传 origin 部分）。
    const originParts = CanonicalUrl.normalize(`${scheme}://${authority}/`);
    const origin = CanonicalUrl.originOf(originParts);

    let pathQuery = splitAt >= 0 ? rest.substring(splitAt) : '/';
    if (pathQuery.startsWith('?')) {
      pathQuery = '/' + pathQuery;
    }
    if (!pathQuery.startsWith('/')) {
      fail('PATH_NOT_ABSOLUTE');
    }
    const q = pathQuery.indexOf('?');
    const path = q >= 0 ? pathQuery.substring(0, q) : pathQuery;
    const query = q >= 0 ? pathQuery.substring(q + 1) : '';
    if (path.length === 0) {
      fail('PATH_NOT_ABSOLUTE');
    }
    PinnedUrl.validatePercentEncoding(path);
    PinnedUrl.validatePercentEncoding(query);

    return {
      scheme: scheme,
      host: originParts.host,
      port: originParts.port,
      origin: origin,
      path: path,
      query: query,
      pathQuery: query.length > 0 ? `${path}?${query}` : path,
      full: origin + (query.length > 0 ? `${path}?${query}` : path),
      registeredDomain: RegisteredDomain.of(originParts.host)
    };
  }

  /** 判断候选 path+query 是否在钉住前缀之内（按 `/` 段边界，查询串按参数边界）。 */
  static matchesPrefix(pinned: PinnedUrlParts, candidate: PinnedUrlParts): boolean {
    if (pinned.path === '/') {
      // 裸源：路径不限制，但仍要求查询串前缀。
    } else if (candidate.path !== pinned.path && !candidate.path.startsWith(`${pinned.path}/`)) {
      return false;
    }
    if (pinned.query.length > 0) {
      if (candidate.query === pinned.query) {
        return true;
      }
      return candidate.query.startsWith(`${pinned.query}&`);
    }
    return true;
  }

  private static validatePercentEncoding(value: string): void {
    let i = 0;
    while (i < value.length) {
      if (value.charAt(i) === '%') {
        if (i + 2 >= value.length) {
          fail('INVALID_PERCENT_ENCODING');
        }
        const hex = value.substring(i + 1, i + 3);
        if (!new RegExp('^[0-9A-Fa-f]{2}$').test(hex)) {
          fail('INVALID_PERCENT_ENCODING');
        }
        i += 3;
      } else {
        i += 1;
      }
    }
  }
}
