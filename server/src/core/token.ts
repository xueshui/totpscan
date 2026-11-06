import { randomToken, sha256Token } from "../util.ts";

/** 登录 token 长度：16 或 24 个 base64url 字符（规范 §6.4）。 */
export const TOKEN_LENGTH = 24;

/** 生成登录 token（24 个 base64url 字符）。 */
export function generateToken(): string {
  return randomToken(18);
}

/** 存储与检索使用摘要，避免明文落库 / 落日志（规范 §8.2）。 */
export function tokenDigest(token: string): string {
  return sha256Token(token);
}

/** 形态校验：16 或 24 个 base64url 字符，不触达存储层。 */
export function isTokenShaped(value: unknown): value is string {
  return typeof value === "string" && /^(?:[A-Za-z0-9_-]{16}|[A-Za-z0-9_-]{24})$/.test(value);
}
