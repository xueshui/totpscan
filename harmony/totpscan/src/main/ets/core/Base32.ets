import { TotpError, TotpErrorCode } from './TotpError';

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/**
 * RFC 4648 Base32。
 *
 * - decodeStrict：仅接受 A-Z2-7，禁止填充与空白，校验尾部剩余位（绑定二维码 `sec` 用）。
 * - decodeLoose：接受小写、空格、`-` 与末尾 `=`（otpauth URI / 手动输入用）。
 */
export class Base32 {
  static decodeStrict(text: string): Uint8Array {
    if (text.length === 0) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'EMPTY_BASE32');
    }
    for (let i = 0; i < text.length; i += 1) {
      if (ALPHABET.indexOf(text.charAt(i)) < 0) {
        throw new TotpError(TotpErrorCode.INVALID_QR, 'INVALID_BASE32_ALPHABET');
      }
    }
    return Base32.decodeInternal(text);
  }

  static decodeLoose(input: string): Uint8Array {
    let text = input.trim().replace(new RegExp('[\\s-]', 'g'), '').toUpperCase();
    while (text.endsWith('=')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.length === 0) {
      throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'EMPTY_BASE32');
    }
    for (let i = 0; i < text.length; i += 1) {
      if (ALPHABET.indexOf(text.charAt(i)) < 0) {
        throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'INVALID_BASE32_ALPHABET');
      }
    }
    return Base32.decodeInternal(text);
  }

  static encode(bytes: Uint8Array): string {
    let bits = 0;
    let value = 0;
    let out = '';
    for (let i = 0; i < bytes.length; i += 1) {
      value = (value << 8) | bytes[i];
      bits += 8;
      while (bits >= 5) {
        out += ALPHABET.charAt((value >>> (bits - 5)) & 0x1f);
        bits -= 5;
      }
    }
    if (bits > 0) {
      out += ALPHABET.charAt((value << (5 - bits)) & 0x1f);
    }
    return out;
  }

  private static decodeInternal(text: string): Uint8Array {
    let bits = 0;
    let value = 0;
    const out: number[] = [];
    for (let i = 0; i < text.length; i += 1) {
      const index = ALPHABET.indexOf(text.charAt(i));
      value = (value << 5) | index;
      bits += 5;
      if (bits >= 8) {
        out.push((value >>> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    if (bits >= 5) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BASE32_TRAILING_BITS');
    }
    if (bits > 0 && (value & ((1 << bits) - 1)) !== 0) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BASE32_NON_ZERO_PADDING');
    }
    return new Uint8Array(out);
  }
}
