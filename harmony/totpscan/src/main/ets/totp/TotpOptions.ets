/** RFC 6238 参数。协议绑定二维码只允许 SHA1/SHA256/SHA512、6/8 位、30/60 秒。 */
export interface TotpOptions {
  algorithm: string;
  digits: number;
  period: number;
}

export const DEFAULT_TOTP_OPTIONS: TotpOptions = {
  algorithm: 'SHA1',
  digits: 6,
  period: 30
};

export function normalizeAlgorithm(raw: string): string {
  const value = raw.toUpperCase();
  if (value === 'SHA1' || value === 'SHA256' || value === 'SHA512') {
    return value;
  }
  throw new Error('UNSUPPORTED_TOTP_ALGORITHM');
}
