/**
 * 提交地址规范化（规范 §7.2 C1–C7）。
 *
 * 设计取舍：
 * - 只实现规范要求的、无语义变化的处理；任何歧义输入一律失败（fail-closed）。
 * - 反斜杠、内部空白、非法百分号编码等 WHATWG 会“修正”的输入，这里直接拒绝，
 *   以免与另一实现产生不同的“规范形式”。
 * - 该文件是全 SDK 唯一的地址规范化实现，比对与提交都复用它。
 */

export class UrlCanonicalizationError extends Error {
  readonly reason: string;

  constructor(reason: string) {
    super(reason);
    this.reason = reason;
    this.name = 'UrlCanonicalizationError';
  }
}

export interface CanonicalUrlParts {
  scheme: string;
  /** 已小写；IPv6 含方括号。 */
  host: string;
  /** 空串表示使用协议默认端口。 */
  port: string;
  path: string;
}

const MAX_URL_LENGTH = 2048;

function fail(reason: string): void {
  throw new UrlCanonicalizationError(reason);
}

export class CanonicalUrl {
  /** 规范化并返回拆分结果；失败抛出 UrlCanonicalizationError。 */
  static normalize(raw: string): CanonicalUrlParts {
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

    const schemeEnd = raw.indexOf('://');
    if (schemeEnd <= 0) {
      fail('NOT_ABSOLUTE_URL');
    }
    const scheme = raw.substring(0, schemeEnd).toLowerCase();
    if (scheme !== 'https' && scheme !== 'http') {
      fail('UNSUPPORTED_SCHEME');
    }

    const rest = raw.substring(schemeEnd + 3);
    if (rest.indexOf('#') >= 0) {
      fail('QUERY_OR_FRAGMENT_PRESENT');
    }
    if (rest.indexOf('?') >= 0) {
      fail('QUERY_OR_FRAGMENT_PRESENT');
    }
    if (rest.length === 0) {
      fail('EMPTY_HOST');
    }

    const pathStart = rest.indexOf('/');
    const authority = pathStart >= 0 ? rest.substring(0, pathStart) : rest;
    const rawPath = pathStart >= 0 ? rest.substring(pathStart) : '/';
    if (authority.length === 0) {
      fail('EMPTY_HOST');
    }
    if (authority.indexOf('@') >= 0) {
      fail('USERINFO_PRESENT');
    }

    let hostRaw = '';
    let portRaw = '';
    if (authority.startsWith('[')) {
      const close = authority.indexOf(']');
      if (close < 0) {
        fail('INVALID_IPV6');
      }
      hostRaw = authority.substring(0, close + 1);
      const tail = authority.substring(close + 1);
      if (tail.length > 0) {
        if (!tail.startsWith(':')) {
          fail('INVALID_AUTHORITY');
        }
        portRaw = tail.substring(1);
      }
    } else {
      const firstColon = authority.indexOf(':');
      if (firstColon >= 0) {
        if (authority.indexOf(':', firstColon + 1) >= 0) {
          fail('IPV6_REQUIRES_BRACKETS');
        }
        hostRaw = authority.substring(0, firstColon);
        portRaw = authority.substring(firstColon + 1);
      } else {
        hostRaw = authority;
      }
    }

    const host = CanonicalUrl.normalizeHost(hostRaw);
    if (scheme === 'http') {
      const lowerHost = host.toLowerCase();
      if (lowerHost !== 'localhost' && lowerHost !== '127.0.0.1' && lowerHost !== '[::1]') {
        fail('INSECURE_HTTP');
      }
    }

    let port = '';
    if (portRaw.length > 0) {
      if (!new RegExp('^[0-9]+$').test(portRaw)) {
        fail('INVALID_PORT');
      }
      const portNumber = Number.parseInt(portRaw, 10);
      if (!Number.isInteger(portNumber) || portNumber < 1 || portNumber > 65535) {
        fail('INVALID_PORT');
      }
      const isDefault = (scheme === 'https' && portNumber === 443) || (scheme === 'http' && portNumber === 80);
      port = isDefault ? '' : String(portNumber);
    }

    const path = CanonicalUrl.normalizePath(rawPath);
    const parts: CanonicalUrlParts = {
      scheme: scheme,
      host: host,
      port: port,
      path: path
    };
    return parts;
  }

  static canonicalize(raw: string): string {
    const parts = CanonicalUrl.normalize(raw);
    return CanonicalUrl.format(parts);
  }

  static format(parts: CanonicalUrlParts): string {
    const portPart = parts.port.length > 0 ? `:${parts.port}` : '';
    return `${parts.scheme}://${parts.host}${portPart}${parts.path}`;
  }

  /** 从规范形式取源（scheme://host[:port]），用于固定路径的绑定确认接口。 */
  static originOf(parts: CanonicalUrlParts): string {
    const portPart = parts.port.length > 0 ? `:${parts.port}` : '';
    return `${parts.scheme}://${parts.host}${portPart}`;
  }

  private static normalizeHost(raw: string): string {
    if (raw.length === 0) {
      fail('EMPTY_HOST');
    }
    if (raw.startsWith('[')) {
      if (!raw.endsWith(']')) {
        fail('INVALID_IPV6');
      }
      return CanonicalUrl.normalizeIpv6(raw.substring(1, raw.length - 1));
    }

    let host = raw.toLowerCase();
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.length === 0) {
      fail('EMPTY_HOST');
    }
    const labels = host.split('.');
    const out: string[] = [];
    for (let i = 0; i < labels.length; i += 1) {
      const label = labels[i];
      if (label.length === 0 || label.length > 63) {
        fail('INVALID_HOST_LABEL');
      }
      if (new RegExp('^[a-z0-9_-]+$').test(label)) {
        out.push(label);
        continue;
      }
      if (CanonicalUrl.isAscii(label)) {
        fail('INVALID_HOST_CHARACTER');
      }
      out.push(CanonicalUrl.punycodeEncode(label));
    }
    const result = out.join('.');
    if (result.length > 253) {
      fail('HOST_TOO_LONG');
    }
    return result;
  }

  private static normalizeIpv6(inner: string): string {
    const text = inner.toLowerCase();
    if (text.length === 0) {
      fail('INVALID_IPV6');
    }
    if (!new RegExp('^[0-9a-f:.]+$').test(text)) {
      fail('INVALID_IPV6');
    }

    let expanded = text;
    if (text.indexOf('.') >= 0) {
      const lastColon = text.lastIndexOf(':');
      if (lastColon < 0) {
        fail('INVALID_IPV6');
      }
      const v4 = text.substring(lastColon + 1);
      const v4parts = v4.split('.');
      if (v4parts.length !== 4) {
        fail('INVALID_IPV6');
      }
      const numbers: number[] = [];
      for (let i = 0; i < 4; i += 1) {
        if (!new RegExp('^[0-9]+$').test(v4parts[i])) {
          fail('INVALID_IPV6');
        }
        const value = Number.parseInt(v4parts[i], 10);
        if (value < 0 || value > 255) {
          fail('INVALID_IPV6');
        }
        numbers.push(value);
      }
      const high = (numbers[0] * 256 + numbers[1]).toString(16);
      const low = (numbers[2] * 256 + numbers[3]).toString(16);
      expanded = text.substring(0, lastColon + 1) + high + ':' + low;
    }

    const doubleColon = expanded.indexOf('::');
    let groups: string[] = [];
    if (doubleColon >= 0) {
      if (expanded.indexOf('::', doubleColon + 2) >= 0) {
        fail('INVALID_IPV6');
      }
      const leftRaw = expanded.substring(0, doubleColon);
      const rightRaw = expanded.substring(doubleColon + 2);
      const left = leftRaw.length > 0 ? leftRaw.split(':') : [];
      const right = rightRaw.length > 0 ? rightRaw.split(':') : [];
      const zeros = 8 - left.length - right.length;
      if (zeros < 1) {
        fail('INVALID_IPV6');
      }
      groups = left.slice();
      for (let i = 0; i < zeros; i += 1) {
        groups.push('0');
      }
      for (let i = 0; i < right.length; i += 1) {
        groups.push(right[i]);
      }
    } else {
      groups = expanded.split(':');
      if (groups.length !== 8) {
        fail('INVALID_IPV6');
      }
    }

    const normalized: string[] = [];
    for (let i = 0; i < groups.length; i += 1) {
      if (!new RegExp('^[0-9a-f]{1,4}$').test(groups[i])) {
        fail('INVALID_IPV6');
      }
      normalized.push(Number.parseInt(groups[i], 16).toString(16));
    }
    return `[${CanonicalUrl.compressIpv6(normalized)}]`;
  }

  /** RFC 5952：压缩最长的连续零组（长度 ≥2，最左优先）。 */
  private static compressIpv6(groups: string[]): string {
    let bestStart = -1;
    let bestLength = 0;
    let i = 0;
    while (i < groups.length) {
      if (groups[i] !== '0') {
        i += 1;
        continue;
      }
      let j = i;
      while (j < groups.length && groups[j] === '0') {
        j += 1;
      }
      if (j - i > bestLength) {
        bestStart = i;
        bestLength = j - i;
      }
      i = j;
    }
    if (bestLength < 2) {
      return groups.join(':');
    }
    const head = groups.slice(0, bestStart).join(':');
    const tail = groups.slice(bestStart + bestLength).join(':');
    return `${head}::${tail}`;
  }

  private static normalizePath(rawPath: string): string {
    if (rawPath.length === 0) {
      return '/';
    }
    if (!rawPath.startsWith('/')) {
      fail('PATH_NOT_ABSOLUTE');
    }

    let decoded = '';
    let i = 0;
    while (i < rawPath.length) {
      const ch = rawPath.charAt(i);
      if (ch === '%') {
        if (i + 2 >= rawPath.length) {
          fail('INVALID_PERCENT_ENCODING');
        }
        const hex = rawPath.substring(i + 1, i + 3);
        if (!new RegExp('^[0-9A-Fa-f]{2}$').test(hex)) {
          fail('INVALID_PERCENT_ENCODING');
        }
        const code = Number.parseInt(hex, 16);
        const decodedChar = String.fromCharCode(code);
        if (new RegExp('^[A-Za-z0-9._~-]$').test(decodedChar)) {
          decoded += decodedChar;
        } else {
          decoded += '%' + hex.toUpperCase();
        }
        i += 3;
      } else {
        decoded += ch;
        i += 1;
      }
    }

    decoded = decoded.replace(new RegExp('/{2,}', 'g'), '/');
    const segments = decoded.split('/');
    const out: string[] = [];
    for (let k = 0; k < segments.length; k += 1) {
      const segment = segments[k];
      if (segment.length === 0 || segment === '.') {
        continue;
      }
      if (segment === '..') {
        if (out.length > 0) {
          out.pop();
        }
        continue;
      }
      out.push(segment);
    }
    if (out.length === 0) {
      return '/';
    }
    return '/' + out.join('/');
  }

  private static isAscii(value: string): boolean {
    for (let i = 0; i < value.length; i += 1) {
      if (value.charCodeAt(i) > 0x7f) {
        return false;
      }
    }
    return true;
  }

  /** RFC 3492 Punycode 编码（仅编码，用于 IDNA ToASCII 的标签部分）。 */
  private static punycodeEncode(label: string): string {
    const input: number[] = [];
    for (let i = 0; i < label.length; i += 1) {
      let cp = label.charCodeAt(i);
      if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < label.length) {
        const low = label.charCodeAt(i + 1);
        if (low >= 0xdc00 && low <= 0xdfff) {
          cp = 0x10000 + ((cp - 0xd800) << 10) + (low - 0xdc00);
          i += 1;
        }
      }
      input.push(cp);
    }

    let n = 128;
    let delta = 0;
    let bias = 72;
    const output: string[] = [];
    for (let i = 0; i < input.length; i += 1) {
      if (input[i] < 128) {
        output.push(String.fromCharCode(input[i]));
      }
    }
    let h = output.length;
    const basic = h;
    if (basic > 0) {
      output.push('-');
    }

    while (h < input.length) {
      let m = 0x7fffffff;
      for (let i = 0; i < input.length; i += 1) {
        if (input[i] >= n && input[i] < m) {
          m = input[i];
        }
      }
      if (m === 0x7fffffff) {
        fail('HOST_PUNYCODE_FAILED');
      }
      delta += (m - n) * (h + 1);
      n = m;

      for (let i = 0; i < input.length; i += 1) {
        const cp = input[i];
        if (cp < n) {
          delta += 1;
        }
        if (cp === n) {
          let q = delta;
          let k = 36;
          while (true) {
            const t = k <= bias ? 1 : (k >= bias + 26 ? 26 : k - bias);
            if (q < t) {
              break;
            }
            output.push(CanonicalUrl.encodeDigit(t + ((q - t) % (36 - t))));
            q = Math.floor((q - t) / (36 - t));
            k += 36;
          }
          output.push(CanonicalUrl.encodeDigit(q));
          bias = CanonicalUrl.adaptBias(delta, h + 1, h === basic);
          delta = 0;
          h += 1;
        }
      }
      delta += 1;
      n += 1;
    }

    const result = 'xn--' + output.join('');
    if (result.length > 63) {
      fail('HOST_LABEL_TOO_LONG');
    }
    return result;
  }

  private static adaptBias(deltaValue: number, numPoints: number, firstTime: boolean): number {
    let delta = firstTime ? Math.floor(deltaValue / 700) : Math.floor(deltaValue / 2);
    delta += Math.floor(delta / numPoints);
    let k = 0;
    while (delta > 455) {
      delta = Math.floor(delta / 35);
      k += 36;
    }
    return k + Math.floor((36 * delta) / (delta + 38));
  }

  private static encodeDigit(digit: number): string {
    if (digit < 26) {
      return String.fromCharCode(0x61 + digit);
    }
    return String.fromCharCode(0x30 + (digit - 26));
  }
}
