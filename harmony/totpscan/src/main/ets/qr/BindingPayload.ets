import { JsonObject } from '../core/JsonObject';
import { Base32 } from '../core/Base32';
import { TotpError, TotpErrorCode } from '../core/TotpError';
import { PinnedUrl, PinnedUrlParts } from '../security/PinnedUrl';

export interface BindingFields {
  bindingId: string;
  issuer: string;
  account: string;
  secretBase32: string;
  algorithm: string;
  digits: number;
  period: number;
  /** 绑定时的完整提交地址（含 path+query）。 */
  submitUrl: string;
  issuedAt: number;
}

export interface ParsedBinding extends BindingFields {
  secret: Uint8Array;
  /** 未提供 exp 时为 -1。 */
  expiresAt: number;
  rawPayload: string;
  /** 钉住的 PSL 级注册域名。 */
  registeredDomain: string;
  /** 钉住的 path+query 前缀。 */
  pathQuery: string;
}

/**
 * `totp-bind` 载荷解析。
 *
 * 绑定只固定两段定位信息：
 * - `dom`：提交域名（例如 `example.com` 或 `dkn.example.com`）；
 * - `path`：提交路径与查询串（例如 `/dtm/ulr?ma=xxx`）。
 *
 * 提交地址固定为 `https://<dom><path>`。载荷不做签名与验签。
 */
export class BindingPayload {
  static parse(text: string, nowSeconds: number = Math.floor(Date.now() / 1000)): ParsedBinding {
    const json = JsonObject.parse(text);
    BindingPayload.requireHeader(json);

    const bindingId = json.requiredString('bid');
    if (!new RegExp('^b_[A-Za-z0-9_-]{16,64}$').test(bindingId)) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_ID_INVALID');
    }

    const issuer = BindingPayload.normalizeNfc(json.requiredString('iss'));
    if (issuer.length < 1 || issuer.length > 64 || BindingPayload.hasControl(issuer)) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_ISSUER_INVALID');
    }
    const account = BindingPayload.normalizeNfc(json.requiredString('acc'));
    if (account.length < 1 || account.length > 255 || BindingPayload.hasControl(account)) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_ACCOUNT_INVALID');
    }

    const secretText = json.requiredString('sec');
    if (secretText.length < 26 || secretText.length > 103) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_SECRET_LENGTH');
    }
    const secret = Base32.decodeStrict(secretText);
    if (secret.length < 16 || secret.length > 64) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_SECRET_LENGTH');
    }
    const secretBase32 = Base32.encode(secret);

    const algorithm = json.requiredString('alg');
    if (algorithm !== 'SHA1' && algorithm !== 'SHA256' && algorithm !== 'SHA512') {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_ALGORITHM_INVALID');
    }
    const digits = json.requiredInt('dig');
    if (digits !== 6 && digits !== 8) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_DIGITS_INVALID');
    }
    const period = json.requiredInt('per');
    if (period !== 30 && period !== 60) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_PERIOD_INVALID');
    }

    const domainRaw = json.requiredString('dom');
    if (domainRaw.length < 1 || domainRaw.length > 253 || BindingPayload.hasInvalidDomainChar(domainRaw)) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_DOMAIN_INVALID');
    }
    const pathRaw = json.requiredString('path');
    if (pathRaw.length < 1 || pathRaw.length > 2048 || pathRaw.charAt(0) !== '/') {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_PATH_INVALID');
    }

    let parts: PinnedUrlParts;
    try {
      parts = PinnedUrl.parse(`https://${domainRaw}${pathRaw}`);
    } catch (error) {
      throw new TotpError(TotpErrorCode.INSECURE_ADDRESS, 'BINDING_SUBMIT_URL_INVALID', '二维码中的服务器地址不安全，已拒绝');
    }

    const issuedAt = json.requiredInt('iat');
    if (issuedAt < 0) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_IAT_INVALID');
    }
    const expiresAt = json.optionalInt('exp');
    if (expiresAt >= 0 && nowSeconds > expiresAt) {
      throw new TotpError(TotpErrorCode.QR_EXPIRED, 'BINDING_QR_EXPIRED');
    }

    return {
      bindingId: bindingId,
      issuer: issuer,
      account: account,
      secretBase32: secretBase32,
      algorithm: algorithm,
      digits: digits,
      period: period,
      submitUrl: parts.full,
      issuedAt: issuedAt,
      secret: secret,
      expiresAt: expiresAt,
      rawPayload: text,
      registeredDomain: parts.registeredDomain,
      pathQuery: parts.pathQuery
    };
  }

  private static requireHeader(json: JsonObject): void {
    const type = json.requiredString('t');
    if (type !== 'totp-bind') {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BINDING_TYPE_INVALID');
    }
    const version = json.requiredInt('v');
    if (version !== 1) {
      throw new TotpError(TotpErrorCode.UNSUPPORTED_VERSION, 'BINDING_VERSION_UNSUPPORTED');
    }
  }

  private static hasInvalidDomainChar(value: string): boolean {
    return value.indexOf('://') >= 0 ||
      value.indexOf('/') >= 0 ||
      value.indexOf('\\') >= 0 ||
      value.indexOf('@') >= 0 ||
      value.indexOf('?') >= 0 ||
      value.indexOf('#') >= 0 ||
      value.indexOf(':') >= 0 ||
      new RegExp('[\\u0000-\\u0020\\u007F]').test(value);
  }

  private static normalizeNfc(value: string): string {
    try {
      return value.normalize('NFC');
    } catch (error) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'NFC_NORMALIZATION_UNAVAILABLE');
    }
  }

  private static hasControl(value: string): boolean {
    return new RegExp('[\\u0000-\\u001F\\u007F]').test(value);
  }
}
