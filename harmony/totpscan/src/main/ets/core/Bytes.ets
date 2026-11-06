import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { TotpError, TotpErrorCode } from './TotpError';

/** 字符串按 UTF-8 编码；孤立代理项替换为 U+FFFD。 */
export function utf8Encode(text: string): Uint8Array {
  const out: number[] = [];
  let i = 0;
  while (i < text.length) {
    let cp = text.charCodeAt(i);
    i += 1;
    if (cp >= 0xd800 && cp <= 0xdbff) {
      if (i < text.length) {
        const low = text.charCodeAt(i);
        if (low >= 0xdc00 && low <= 0xdfff) {
          cp = 0x10000 + ((cp - 0xd800) << 10) + (low - 0xdc00);
          i += 1;
        } else {
          cp = 0xfffd;
        }
      } else {
        cp = 0xfffd;
      }
    } else if (cp >= 0xdc00 && cp <= 0xdfff) {
      cp = 0xfffd;
    }

    if (cp < 0x80) {
      out.push(cp);
    } else if (cp < 0x800) {
      out.push(0xc0 | (cp >> 6));
      out.push(0x80 | (cp & 0x3f));
    } else if (cp < 0x10000) {
      out.push(0xe0 | (cp >> 12));
      out.push(0x80 | ((cp >> 6) & 0x3f));
      out.push(0x80 | (cp & 0x3f));
    } else {
      out.push(0xf0 | (cp >> 18));
      out.push(0x80 | ((cp >> 12) & 0x3f));
      out.push(0x80 | ((cp >> 6) & 0x3f));
      out.push(0x80 | (cp & 0x3f));
    }
  }
  return new Uint8Array(out);
}

/** 严格 UTF-8 解码；非法序列抛出异常。仅用于本地存储的 JSON。 */
export function utf8Decode(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b0 = bytes[i];
    i += 1;
    let cp = 0;
    let need = 0;
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      continue;
    } else if ((b0 & 0xe0) === 0xc0) {
      cp = b0 & 0x1f;
      need = 1;
    } else if ((b0 & 0xf0) === 0xe0) {
      cp = b0 & 0x0f;
      need = 2;
    } else if ((b0 & 0xf8) === 0xf0) {
      cp = b0 & 0x07;
      need = 3;
    } else {
      throw new Error('INVALID_UTF8');
    }
    if (i + need > bytes.length) {
      throw new Error('INVALID_UTF8');
    }
    for (let k = 0; k < need; k += 1) {
      const bk = bytes[i];
      if ((bk & 0xc0) !== 0x80) {
        throw new Error('INVALID_UTF8');
      }
      cp = (cp << 6) | (bk & 0x3f);
      i += 1;
    }
    if (cp > 0x10ffff) {
      throw new Error('INVALID_UTF8');
    }
    if (cp >= 0x10000) {
      cp -= 0x10000;
      out += String.fromCharCode(0xd800 + (cp >> 10));
      out += String.fromCharCode(0xdc00 + (cp & 0x3ff));
    } else {
      out += String.fromCharCode(cp);
    }
  }
  return out;
}

/** ASCII 字节序列转字符串（仅用于签名原文与消息，不做 UTF-8 解释）。 */
export function bytesToAscii(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i += 1) {
    out += String.fromCharCode(bytes[i]);
  }
  return out;
}

export function concatBytes(parts: Uint8Array[]): Uint8Array {
  let total = 0;
  for (let i = 0; i < parts.length; i += 1) {
    total += parts[i].length;
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (let i = 0; i < parts.length; i += 1) {
    out.set(parts[i], offset);
    offset += parts[i].length;
  }
  return out;
}

/** 常量时间比较，避免逐字节短路。 */
export function constantTimeEquals(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a[i] ^ b[i];
  }
  return diff === 0;
}

export function bytesToHex(bytes: Uint8Array): string {
  const digits = '0123456789abcdef';
  let out = '';
  for (let i = 0; i < bytes.length; i += 1) {
    out += digits.charAt((bytes[i] >> 4) & 0x0f);
    out += digits.charAt(bytes[i] & 0x0f);
  }
  return out;
}

/** 系统 CSPRNG（Crypto Architecture Kit）。 */
export function randomBytes(length: number): Uint8Array {
  if (length <= 0) {
    throw new TotpError(TotpErrorCode.INVALID_ARGUMENT, 'INVALID_RANDOM_LENGTH');
  }
  try {
    const random = cryptoFramework.createRandom();
    return random.generateRandomSync(length).data;
  } catch (error) {
    throw new TotpError(TotpErrorCode.INTERNAL, 'CSPRNG_UNAVAILABLE');
  }
}
