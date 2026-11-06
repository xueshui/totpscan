import { createHmac, timingSafeEqual } from "node:crypto";

/** RFC 6238 支持的算法。 */
export type TotpAlgorithm = "SHA1" | "SHA256" | "SHA512";

export interface TotpOptions {
  algorithm: TotpAlgorithm;
  digits: 6 | 8;
  period: 30 | 60;
}

export const DEFAULT_TOTP_OPTIONS: TotpOptions = {
  algorithm: "SHA1",
  digits: 6,
  period: 30,
};

function hashName(algorithm: TotpAlgorithm): string {
  switch (algorithm) {
    case "SHA1":
      return "sha1";
    case "SHA256":
      return "sha256";
    case "SHA512":
      return "sha512";
  }
}

/** 当前 Unix 毫秒对应的时间步。 */
export function timeStepAt(epochMs: number, period: number): number {
  return Math.floor(epochMs / 1000 / period);
}

/** 8 字节大端计数器。 */
function counterBuffer(timeStep: number): Buffer {
  const buffer = Buffer.alloc(8);
  buffer.writeBigUInt64BE(BigInt(timeStep));
  return buffer;
}

/** 按 RFC 4226 动态截断生成动态码。 */
export function generateTotp(secret: Buffer, timeStep: number, options: TotpOptions = DEFAULT_TOTP_OPTIONS): string {
  const digest = createHmac(hashName(options.algorithm), secret).update(counterBuffer(timeStep)).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const binary =
    ((digest[offset] & 0x7f) << 24) |
    ((digest[offset + 1] & 0xff) << 16) |
    ((digest[offset + 2] & 0xff) << 8) |
    (digest[offset + 3] & 0xff);
  const otp = binary % 10 ** options.digits;
  return otp.toString().padStart(options.digits, "0");
}

export interface TotpVerificationResult {
  matched: boolean;
  /** 命中的时间步；未命中为 null。 */
  timeStep: number | null;
  /** 命中的时间窗偏移（-1 / 0 / 1）；未命中为 null。 */
  windowOffset: number | null;
}

/**
 * 校验动态码：只接受 `t-1 / t / t+1` 三个时间窗（规范 §8.3 第 8 条）。
 * 比较使用常量时间，避免逐位比较泄露信息。
 */
export function verifyTotp(
  secret: Buffer,
  code: string,
  epochMs: number,
  options: TotpOptions = DEFAULT_TOTP_OPTIONS,
  window = 1,
): TotpVerificationResult {
  if (!/^[0-9]+$/.test(code) || code.length !== options.digits) {
    return { matched: false, timeStep: null, windowOffset: null };
  }
  const current = timeStepAt(epochMs, options.period);
  const offsets: number[] = [0];
  for (let i = 1; i <= window; i += 1) {
    offsets.push(-i, i);
  }
  for (const offset of offsets) {
    const step = current + offset;
    if (step < 0) {
      continue;
    }
    const expected = Buffer.from(generateTotp(secret, step, options), "ascii");
    const provided = Buffer.from(code, "ascii");
    if (expected.length === provided.length && timingSafeEqual(expected, provided)) {
      return { matched: true, timeStep: step, windowOffset: offset };
    }
  }
  return { matched: false, timeStep: null, windowOffset: null };
}
