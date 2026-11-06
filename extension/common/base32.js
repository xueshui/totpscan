/** RFC 4648 Base32 编解码。协议载荷要求大写、无填充；导入场景允许宽松输入。 */

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/**
 * 宽松清洗：去空白与分隔符、转大写、去尾部填充。
 * 仅用于用户手输或第三方备份，不能用于协议载荷校验。
 */
export function normalizeBase32Loose(input) {
  if (typeof input !== "string") {
    throw new Error("BASE32_INVALID");
  }
  const cleaned = input.replace(/[\s\-_.]/g, "").replace(/=+$/g, "").toUpperCase();
  if (cleaned.length === 0 || !/^[A-Z2-7]+$/.test(cleaned)) {
    throw new Error("BASE32_INVALID");
  }
  return cleaned;
}

/** 严格遵守协议：仅大写 A-Z2-7，无填充、无空白。 */
export function isStrictBase32(input) {
  return typeof input === "string" && input.length > 0 && /^[A-Z2-7]+$/.test(input);
}

export function decodeBase32(input, options = {}) {
  const loose = options.loose === true;
  const text = loose ? normalizeBase32Loose(input) : input;
  if (!isStrictBase32(text)) {
    throw new Error("BASE32_INVALID");
  }
  const bytes = [];
  let buffer = 0;
  let bits = 0;
  for (const char of text) {
    const value = ALPHABET.indexOf(char);
    if (value < 0) {
      throw new Error("BASE32_INVALID");
    }
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buffer >>> bits) & 0xff);
      buffer &= (1 << bits) - 1;
    }
  }
  return new Uint8Array(bytes);
}

export function encodeBase32(bytes) {
  let output = "";
  let buffer = 0;
  let bits = 0;
  for (const byte of bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      output += ALPHABET[(buffer >>> bits) & 31];
      buffer &= (1 << bits) - 1;
    }
  }
  if (bits > 0) {
    output += ALPHABET[(buffer << (5 - bits)) & 31];
  }
  return output;
}

/** 判断一个 token 是否可能是 Base32 密钥（用于第三方文本备份的列顺序推断）。 */
export function looksLikeBase32Secret(token) {
  if (typeof token !== "string") {
    return false;
  }
  const cleaned = token.replace(/[\s\-_.]/g, "").replace(/=+$/g, "").toUpperCase();
  return cleaned.length >= 16 && /^[A-Z2-7]+$/.test(cleaned);
}
