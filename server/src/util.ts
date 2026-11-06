import { randomBytes, createHash, timingSafeEqual } from "node:crypto";

const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/** RFC 4648 Base32 编码（大写、无填充），用于 TOTP 共享密钥。 */
export function base32Encode(data: Buffer): string {
  let bits = 0;
  let value = 0;
  let output = "";
  for (const byte of data) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }
  return output;
}

/** RFC 4648 Base32 解码；忽略空格与 `=`，大小写不敏感。非法字符抛错。 */
export function base32Decode(text: string): Buffer {
  const normalized = text.replace(/=+$/g, "").replace(/\s+/g, "").toUpperCase();
  let bits = 0;
  let value = 0;
  const bytes: number[] = [];
  for (const char of normalized) {
    const index = BASE32_ALPHABET.indexOf(char);
    if (index < 0) {
      throw new Error("BASE32_INVALID");
    }
    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

/** base64url（无填充）。 */
export function base64url(data: Buffer): string {
  return data.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

/** 生成密码学安全随机 token（默认 32 字节 → 43 字符 base64url）。 */
export function randomToken(bytes = 32): string {
  return base64url(randomBytes(bytes));
}

/** 生成请求 ID，仅用于日志关联。 */
export function newRequestId(): string {
  return "req_" + randomBytes(12).toString("hex");
}

/** SHA-256 摘要（base64url），用于存储登录 token 而不落明文。 */
export function sha256Token(token: string): string {
  return base64url(createHash("sha256").update(token, "utf8").digest());
}

/** 常量时间比较两个字符串（先各自摘要，避免长度差异泄露）。 */
export function constantTimeEqualString(a: string, b: string): boolean {
  const da = createHash("sha256").update(a, "utf8").digest();
  const db = createHash("sha256").update(b, "utf8").digest();
  return timingSafeEqual(da, db);
}

/** 常量时间比较两段 Buffer；长度不同直接返回 false（动态码定长，不构成有效旁路）。 */
export function constantTimeEqualBuffer(a: Buffer, b: Buffer): boolean {
  if (a.length !== b.length) {
    return false;
  }
  return timingSafeEqual(a, b);
}

/** 是否为合法十进制动态码（长度 6 或 8）。 */
export function isNumericCode(value: unknown, digits?: number): value is string {
  if (typeof value !== "string") {
    return false;
  }
  if (digits !== undefined) {
    return value.length === digits && /^[0-9]+$/.test(value);
  }
  return (value.length === 6 || value.length === 8) && /^[0-9]+$/.test(value);
}
