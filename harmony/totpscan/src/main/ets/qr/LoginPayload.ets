import { JsonObject } from '../core/JsonObject';
import { TotpError, TotpErrorCode } from '../core/TotpError';
import { CanonicalUrl } from '../security/CanonicalUrl';
import { RegisteredDomain } from '../security/RegisteredDomain';

export interface ParsedLogin {
  /** 登录域名（不带 scheme 与路径，已规范化为小写 host）。 */
  domain: string;
  /** PSL 级注册域名。 */
  registeredDomain: string;
  /** 16 或 24 位会话标识，仅保存在内存，禁止落盘/日志。 */
  token: string;
  expiresAt: number;
  rawPayload: string;
}

/**
 * `totp-login` 载荷解析。
 *
 * 登录二维码只包含三段：
 * - `url`：域名，不带 scheme 与路径（例如 `auth.example.com`）；
 * - `token`：16 或 24 位会话标识；
 * - `exp`：过期时间（Unix 秒）。
 *
 * 路径不来自登录二维码，提交时只使用绑定时固定的 `path`。
 */
export class LoginPayload {
  static parse(text: string, nowSeconds: number = Math.floor(Date.now() / 1000)): ParsedLogin {
    const json = JsonObject.parse(text);

    const type = json.requiredString('t');
    if (type !== 'totp-login') {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'LOGIN_TYPE_INVALID');
    }
    const version = json.requiredInt('v');
    if (version !== 1) {
      throw new TotpError(TotpErrorCode.UNSUPPORTED_VERSION, 'LOGIN_VERSION_UNSUPPORTED');
    }

    const domainRaw = json.requiredString('url');
    if (domainRaw.length < 1 || domainRaw.length > 253) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'LOGIN_DOMAIN_LENGTH');
    }
    const domain = LoginPayload.normalizeDomain(domainRaw);

    const token = json.requiredString('token');
    if (!new RegExp('^([A-Za-z0-9_-]{16}|[A-Za-z0-9_-]{24})$').test(token)) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'LOGIN_TOKEN_FORMAT');
    }

    const expiresAt = json.requiredInt('exp');
    if (expiresAt < 0) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'LOGIN_EXP_INVALID');
    }
    if (nowSeconds > expiresAt) {
      throw new TotpError(TotpErrorCode.LOGIN_EXPIRED, 'LOGIN_QR_EXPIRED');
    }
    if (expiresAt - nowSeconds > 60) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'LOGIN_QR_TTL_EXCEEDED');
    }

    return {
      domain: domain,
      registeredDomain: RegisteredDomain.of(domain),
      token: token,
      expiresAt: expiresAt,
      rawPayload: text
    };
  }

  /** 校验并规范化「不带 scheme 与路径」的域名。 */
  static normalizeDomain(raw: string): string {
    const trimmed = raw.trim();
    if (trimmed.length === 0 ||
      trimmed.indexOf('://') >= 0 ||
      trimmed.indexOf('/') >= 0 ||
      trimmed.indexOf('\\') >= 0 ||
      trimmed.indexOf('@') >= 0 ||
      trimmed.indexOf('?') >= 0 ||
      trimmed.indexOf('#') >= 0 ||
      trimmed.indexOf(':') >= 0 ||
      new RegExp('[\\u0000-\\u0020\\u007F]').test(trimmed)) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'LOGIN_DOMAIN_INVALID');
    }
    try {
      return CanonicalUrl.normalize(`https://${trimmed}/`).host;
    } catch (error) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'LOGIN_DOMAIN_INVALID');
    }
  }
}
