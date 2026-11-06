import { TotpError, TotpErrorCode } from '../core/TotpError';
import { Base32 } from '../core/Base32';
import { StandardAccountInput } from '../model/Types';
import { normalizeAlgorithm } from './TotpOptions';

const MAX_URI_LENGTH = 4096;

/**
 * 标准 otpauth://totp URI（Key Uri Format）解析与生成。
 *
 * 这是“标准账户”入口，不涉及任何固化地址、签名或网络提交。
 */
export class OtpauthUri {
  static parse(uri: string): StandardAccountInput {
    const raw = uri.trim();
    if (raw.length === 0 || raw.length > MAX_URI_LENGTH) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_LENGTH_INVALID');
    }
    if (!raw.toLowerCase().startsWith('otpauth://')) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_SCHEME_INVALID');
    }

    const rest = raw.substring('otpauth://'.length);
    const queryIndex = rest.indexOf('?');
    const pathPart = queryIndex >= 0 ? rest.substring(0, queryIndex) : rest;
    const queryPart = queryIndex >= 0 ? rest.substring(queryIndex + 1) : '';

    const slashIndex = pathPart.indexOf('/');
    if (slashIndex < 0) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_LABEL_MISSING');
    }
    const type = pathPart.substring(0, slashIndex).toLowerCase();
    if (type !== 'totp') {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_TYPE_UNSUPPORTED');
    }
    const labelRaw = pathPart.substring(slashIndex + 1);
    if (labelRaw.length === 0) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_LABEL_MISSING');
    }
    const label = OtpauthUri.decodeComponent(labelRaw);

    const params = OtpauthUri.parseQuery(queryPart);
    const secretText = params.get('secret');
    if (secretText === undefined || secretText.length === 0) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_SECRET_MISSING');
    }
    const secret = Base32.decodeLoose(secretText);
    if (secret.length < 10 || secret.length > 64) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_SECRET_LENGTH');
    }

    let labelIssuer = '';
    let account = label.trim();
    const colon = label.indexOf(':');
    if (colon >= 0) {
      labelIssuer = label.substring(0, colon).trim();
      account = label.substring(colon + 1).trim();
    }
    if (account.length === 0 || account.length > 255 || OtpauthUri.hasControl(account)) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_ACCOUNT_INVALID');
    }

    let issuer = labelIssuer;
    const issuerParam = params.get('issuer');
    if (issuerParam !== undefined) {
      // U2：label 与 query 同时给出 issuer 时必须完全一致，否则拒绝导入。
      if (labelIssuer.length > 0 && issuerParam.trim() !== labelIssuer) {
        throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_ISSUER_CONFLICT');
      }
      if (issuerParam.trim().length > 0) {
        issuer = issuerParam.trim();
      }
    }
    if (issuer.length > 64 || OtpauthUri.hasControl(issuer)) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_ISSUER_INVALID');
    }

    const algorithmRaw = params.get('algorithm');
    let algorithm = 'SHA1';
    if (algorithmRaw !== undefined && algorithmRaw.length > 0) {
      try {
        algorithm = normalizeAlgorithm(algorithmRaw);
      } catch (error) {
        throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_ALGORITHM_UNSUPPORTED');
      }
    }

    const digitsRaw = params.get('digits');
    let digits = 6;
    if (digitsRaw !== undefined && digitsRaw.length > 0) {
      if (!new RegExp('^[0-9]+$').test(digitsRaw)) {
        throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_DIGITS_UNSUPPORTED');
      }
      digits = Number.parseInt(digitsRaw, 10);
      if (digits !== 6 && digits !== 8) {
        throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_DIGITS_UNSUPPORTED');
      }
    }

    const periodRaw = params.get('period');
    let period = 30;
    if (periodRaw !== undefined && periodRaw.length > 0) {
      if (!new RegExp('^[0-9]+$').test(periodRaw)) {
        throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_PERIOD_INVALID');
      }
      period = Number.parseInt(periodRaw, 10);
      if (!Number.isInteger(period) || period < 1 || period > 3600) {
        throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_PERIOD_INVALID');
      }
    }

    if (params.get('counter') !== undefined) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_COUNTER_UNSUPPORTED');
    }

    const input: StandardAccountInput = {
      issuer: issuer,
      account: account,
      secretBase32: Base32.encode(secret),
      algorithm: algorithm,
      digits: digits,
      period: period
    };
    return input;
  }

  static build(input: StandardAccountInput): string {
    const issuer = input.issuer.trim();
    const account = input.account.trim();
    if (account.length === 0 || account.length > 255) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_ACCOUNT_INVALID');
    }
    if (issuer.length > 64) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_ISSUER_INVALID');
    }
    const label = issuer.length > 0
      ? `${encodeURIComponent(issuer)}:${encodeURIComponent(account)}`
      : encodeURIComponent(account);
    const secret = Base32.encode(Base32.decodeLoose(input.secretBase32));
    const params: string[] = [`secret=${secret}`];
    if (issuer.length > 0) {
      params.push(`issuer=${encodeURIComponent(issuer)}`);
    }
    params.push(`algorithm=${encodeURIComponent(input.algorithm)}`);
    params.push(`digits=${input.digits}`);
    params.push(`period=${input.period}`);
    return `otpauth://totp/${label}?${params.join('&')}`;
  }

  private static parseQuery(query: string): Map<string, string> {
    const result = new Map<string, string>();
    if (query.length === 0) {
      return result;
    }
    const seen = new Set<string>();
    const parts = query.split('&');
    for (let i = 0; i < parts.length; i += 1) {
      const part = parts[i];
      if (part.length === 0) {
        continue;
      }
      const eq = part.indexOf('=');
      const key = eq >= 0 ? part.substring(0, eq) : part;
      const value = eq >= 0 ? part.substring(eq + 1) : '';
      const normalizedKey = OtpauthUri.decodeComponent(key).toLowerCase();
      // U7：同名参数出现多次一律拒绝。
      if (seen.has(normalizedKey)) {
        throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_DUPLICATE_PARAMETER');
      }
      seen.add(normalizedKey);
      result.set(normalizedKey, OtpauthUri.decodeComponent(value));
    }
    return result;
  }

  private static decodeComponent(raw: string): string {
    try {
      return decodeURIComponent(raw);
    } catch (error) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'OTPAUTH_PERCENT_ENCODING_INVALID');
    }
  }

  private static hasControl(value: string): boolean {
    return new RegExp('[\\u0000-\\u001F\\u007F]').test(value);
  }
}
