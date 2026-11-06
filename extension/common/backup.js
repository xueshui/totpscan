/**
 * 备份文件格式与口令加密（WebCrypto：PBKDF2-SHA256 + AES-256-GCM）。
 * 加密信封严格按 spec/totp-scan-v1.md §14.3 与 schemas/backup.schema.json 生成。
 * 明文导出仅供用户自行保管；加密导出时文件名会显式包含 encrypted。
 */

import { base64urlToBytes, bytesToBase64url } from "./base64.js";
import { buildOtpauthUri } from "./otpauth.js";

export const BACKUP_FORMAT = "totpscan-backup";
export const BACKUP_VERSION = 1;
export const PBKDF2_ITERATIONS = 600000;
export const AAD_PREFIX = "TOTPSCAN-BACKUP-V1";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

/** 给用户可见的错误附上稳定的错误码，UI 侧按码翻译，避免中文冒泡。 */
function fail(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

export function buildBackupPayload(rows, exportedAt = Math.floor(Date.now() / 1000)) {
  return {
    format: BACKUP_FORMAT,
    version: BACKUP_VERSION,
    encrypted: false,
    exportedAt,
    accounts: rows,
  };
}

/** §14.3：AAD 为 UTF-8 字符串，按固定顺序以单个 LF 拼接、末尾无换行。 */
export function buildBackupAad({ kdfName, salt, iv }) {
  return [`${AAD_PREFIX}`, `version=${BACKUP_VERSION}`, `kdf=${kdfName}`, `salt=${salt}`, `iv=${iv}`].join("\n");
}

/** 口令加密：口令只用于本次派生，不写入文件。 */
export async function encryptBackup(plainText, password) {
  if (typeof password !== "string" || password.length < 1) {
    throw fail("PASSWORD_EMPTY", "备份口令不能为空");
  }
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const saltText = bytesToBase64url(salt);
  const ivText = bytesToBase64url(iv);
  const kdfName = "PBKDF2";
  const baseKey = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, [
    "deriveKey",
  ]);
  const key = await crypto.subtle.deriveKey(
    { name: "PBKDF2", salt, iterations: PBKDF2_ITERATIONS, hash: "SHA-256" },
    baseKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt"],
  );
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv, additionalData: encoder.encode(buildBackupAad({ kdfName, salt: saltText, iv: ivText })) },
      key,
      encoder.encode(plainText),
    ),
  );
  const ciphertext = sealed.slice(0, sealed.length - 16);
  const tag = sealed.slice(sealed.length - 16);
  return {
    format: BACKUP_FORMAT,
    version: BACKUP_VERSION,
    encrypted: true,
    kdf: {
      name: kdfName,
      salt: saltText,
      hash: "SHA-256",
      iterations: PBKDF2_ITERATIONS,
    },
    cipher: {
      name: "AES-256-GCM",
      iv: ivText,
      tag: bytesToBase64url(tag),
    },
    ciphertext: bytesToBase64url(ciphertext),
  };
}

/** 解密备份，返回明文 payload 对象。失败一律使用同一文案，不区分口令错误与数据损坏。 */
export async function decryptBackup(envelope, password) {
  if (!isEncryptedBackup(envelope)) {
    throw fail("NOT_ENCRYPTED", "不是口令加密的备份文件");
  }
  if (typeof password !== "string" || password.length < 1) {
    throw fail("PASSWORD_EMPTY", "请输入备份口令");
  }
  const iterations = Number(envelope.kdf?.iterations);
  if (
    envelope.kdf?.name !== "PBKDF2" ||
    envelope.kdf?.hash !== "SHA-256" ||
    !Number.isInteger(iterations) ||
    iterations < PBKDF2_ITERATIONS ||
    iterations > 5000000
  ) {
    throw fail("DECRYPT_FAILED", "备份无法解密或已损坏");
  }
  let salt;
  let iv;
  let tag;
  let ciphertext;
  try {
    salt = base64urlToBytes(envelope.kdf.salt);
    iv = base64urlToBytes(envelope.cipher.iv);
    tag = base64urlToBytes(envelope.cipher.tag);
    ciphertext = base64urlToBytes(envelope.ciphertext);
  } catch {
    throw fail("DECRYPT_FAILED", "备份无法解密或已损坏");
  }
  if (salt.length < 16 || iv.length !== 12 || tag.length !== 16 || ciphertext.length === 0) {
    throw fail("DECRYPT_FAILED", "备份无法解密或已损坏");
  }
  const sealed = new Uint8Array(ciphertext.length + tag.length);
  sealed.set(ciphertext, 0);
  sealed.set(tag, ciphertext.length);

  let plaintext;
  try {
    const baseKey = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, [
      "deriveKey",
    ]);
    const key = await crypto.subtle.deriveKey(
      { name: "PBKDF2", salt, iterations, hash: "SHA-256" },
      baseKey,
      { name: "AES-GCM", length: 256 },
      false,
      ["decrypt"],
    );
    plaintext = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv,
        additionalData: encoder.encode(
          buildBackupAad({ kdfName: envelope.kdf.name, salt: envelope.kdf.salt, iv: envelope.cipher.iv }),
        ),
      },
      key,
      sealed,
    );
  } catch {
    throw fail("DECRYPT_FAILED", "备份无法解密或已损坏");
  }
  try {
    return JSON.parse(decoder.decode(plaintext));
  } catch {
    throw fail("DECRYPT_FAILED", "备份无法解密或已损坏");
  }
}

export function isEncryptedBackup(value) {
  return (
    !!value &&
    typeof value === "object" &&
    value.format === BACKUP_FORMAT &&
    value.encrypted === true &&
    typeof value.kdf?.salt === "string" &&
    typeof value.cipher?.iv === "string" &&
    typeof value.cipher?.tag === "string" &&
    typeof value.ciphertext === "string"
  );
}

export function isBackupPayload(value) {
  return !!value && typeof value === "object" && value.format === BACKUP_FORMAT && Array.isArray(value.accounts);
}

/**
 * 纯文本导出：每行一个 otpauth://totp 链接。
 * 增强型账户无法用 otpauth 表达固化地址，因此只出现在 JSON 备份中。
 */
export function buildTextExport(standardRows) {
  const lines = standardRows.map((row) =>
    buildOtpauthUri({
      issuer: row.issuer,
      account: row.account,
      secret: row.secret,
      algorithm: row.algorithm,
      digits: row.digits,
      period: row.period,
    }),
  );
  return `${lines.join("\n")}${lines.length > 0 ? "\n" : ""}`;
}
