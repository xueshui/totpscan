import { TotpError, TotpErrorCode } from './TotpError';

const MAX_JSON_LENGTH = 8192;

/**
 * 严格 JSON 读取器。
 *
 * 只做类型校验，不做业务校验；未知字段按规范 §12.1 忽略。
 * 消息中只出现字段名，不出现字段值，避免把密钥/令牌写进日志。
 */
export class JsonObject {
  private readonly values: Record<string, Object>;

  private constructor(values: Record<string, Object>) {
    this.values = values;
  }

  static parse(text: string): JsonObject {
    if (typeof text !== 'string' || text.length === 0 || text.length > MAX_JSON_LENGTH) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'QR_PAYLOAD_LENGTH_INVALID');
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(text);
    } catch (error) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'QR_PAYLOAD_NOT_JSON');
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'QR_PAYLOAD_NOT_OBJECT');
    }
    return new JsonObject(parsed as Record<string, Object>);
  }

  has(key: string): boolean {
    const value: Object | undefined = this.values[key];
    return value !== undefined;
  }

  requiredString(key: string): string {
    const value: Object | undefined = this.values[key];
    if (value === undefined || typeof value !== 'string') {
      throw new TotpError(TotpErrorCode.INVALID_QR, `QR_FIELD_INVALID:${key}`);
    }
    return value as string;
  }

  optionalString(key: string): string {
    const value: Object | undefined = this.values[key];
    if (value === undefined) {
      return '';
    }
    if (typeof value !== 'string') {
      throw new TotpError(TotpErrorCode.INVALID_QR, `QR_FIELD_INVALID:${key}`);
    }
    return value as string;
  }

  requiredInt(key: string): number {
    const value: Object | undefined = this.values[key];
    if (value === undefined || typeof value !== 'number' || !Number.isInteger(value)) {
      throw new TotpError(TotpErrorCode.INVALID_QR, `QR_FIELD_INVALID:${key}`);
    }
    return value as number;
  }

  optionalInt(key: string): number {
    return this.has(key) ? this.requiredInt(key) : -1;
  }
}
