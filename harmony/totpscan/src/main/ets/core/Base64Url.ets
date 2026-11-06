import { TotpError, TotpErrorCode } from './TotpError';

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** Base64url（RFC 4648 §5），无填充。 */
export class Base64Url {
  static encode(bytes: Uint8Array): string {
    let out = '';
    let i = 0;
    while (i + 2 < bytes.length) {
      const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      out += ALPHABET.charAt((n >>> 18) & 0x3f);
      out += ALPHABET.charAt((n >>> 12) & 0x3f);
      out += ALPHABET.charAt((n >>> 6) & 0x3f);
      out += ALPHABET.charAt(n & 0x3f);
      i += 3;
    }
    const rest = bytes.length - i;
    if (rest === 1) {
      const n = bytes[i] << 16;
      out += ALPHABET.charAt((n >>> 18) & 0x3f);
      out += ALPHABET.charAt((n >>> 12) & 0x3f);
    } else if (rest === 2) {
      const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
      out += ALPHABET.charAt((n >>> 18) & 0x3f);
      out += ALPHABET.charAt((n >>> 12) & 0x3f);
      out += ALPHABET.charAt((n >>> 6) & 0x3f);
    }
    return out;
  }

  /** 严格解码：禁止 `=` 填充与非法字符，拒绝长度模 4 为 1。 */
  static decode(text: string): Uint8Array {
    if (text.length === 0) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'EMPTY_BASE64URL');
    }
    if (text.indexOf('=') >= 0 || text.length % 4 === 1) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'INVALID_BASE64URL');
    }
    let bits = 0;
    let value = 0;
    const out: number[] = [];
    for (let i = 0; i < text.length; i += 1) {
      const index = ALPHABET.indexOf(text.charAt(i));
      if (index < 0) {
        throw new TotpError(TotpErrorCode.INVALID_QR, 'INVALID_BASE64URL');
      }
      value = (value << 6) | index;
      bits += 6;
      if (bits >= 8) {
        out.push((value >>> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    if (bits > 0 && (value & ((1 << bits) - 1)) !== 0) {
      throw new TotpError(TotpErrorCode.INVALID_QR, 'BASE64URL_NON_ZERO_PADDING');
    }
    return new Uint8Array(out);
  }
}
