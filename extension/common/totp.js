/**
 * RFC 6238 / RFC 4226 TOTP 核心。
 * 所有计算只在本扩展内部完成，不产生任何网络请求。
 */

export const TOTP_ALGORITHMS = ["SHA1", "SHA256", "SHA512"];

const HASH_NAMES = {
  SHA1: "SHA-1",
  SHA256: "SHA-256",
  SHA512: "SHA-512",
};

export function isSupportedAlgorithm(value) {
  return TOTP_ALGORITHMS.includes(value);
}

export function timeStepAt(timestampMs, periodSeconds) {
  return Math.floor(timestampMs / 1000 / periodSeconds);
}

export function secondsRemainingAt(timestampMs, periodSeconds) {
  const elapsed = (Math.floor(timestampMs / 1000) % periodSeconds + periodSeconds) % periodSeconds;
  return periodSeconds - elapsed;
}

/** 用 WebCrypto 计算 HMAC，再按 RFC 4226 动态截断。 */
export async function generateTotp(secretBytes, options = {}) {
  const algorithm = options.algorithm ?? "SHA1";
  const digits = options.digits ?? 6;
  const period = options.period ?? 30;
  const timestampMs = options.timestampMs ?? Date.now();

  if (!HASH_NAMES[algorithm]) {
    throw new Error("TOTP_ALGORITHM_UNSUPPORTED");
  }
  if (digits !== 6 && digits !== 8) {
    throw new Error("TOTP_DIGITS_INVALID");
  }
  if (!Number.isInteger(period) || period <= 0 || period > 3600) {
    throw new Error("TOTP_PERIOD_INVALID");
  }
  if (!(secretBytes instanceof Uint8Array) || secretBytes.length === 0) {
    throw new Error("TOTP_SECRET_INVALID");
  }

  const counter = timeStepAt(timestampMs, period);
  const counterBytes = new Uint8Array(8);
  let remaining = counter;
  for (let i = 7; i >= 0; i -= 1) {
    counterBytes[i] = remaining & 0xff;
    remaining = Math.floor(remaining / 256);
  }

  const key = await crypto.subtle.importKey(
    "raw",
    secretBytes,
    { name: "HMAC", hash: HASH_NAMES[algorithm] },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, counterBytes));
  const offset = signature[signature.length - 1] & 0x0f;
  const binary =
    ((signature[offset] & 0x7f) << 24) |
    (signature[offset + 1] << 16) |
    (signature[offset + 2] << 8) |
    signature[offset + 3];
  const code = String(binary % 10 ** digits).padStart(digits, "0");
  return { code, step: counter, remaining: secondsRemainingAt(timestampMs, period) };
}

/** 展示用分组：6 位 → "123 456"，8 位 → "1234 5678"。 */
export function formatCodeForDisplay(code) {
  if (code.length === 6) {
    return `${code.slice(0, 3)} ${code.slice(3)}`;
  }
  if (code.length === 8) {
    return `${code.slice(0, 4)} ${code.slice(4)}`;
  }
  return code;
}
