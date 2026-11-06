/**
 * 备份导入解析（宽松但可解释）：
 * - 自家 JSON（含口令加密）
 * - 逐行 otpauth://totp 链接
 * - 常见分隔符行：issuer:account:secret / secret  account  issuer / Base32 空格分组
 * - Google Authenticator 的 otpauth-migration://offline?data= 迁移二维码
 *
 * 解析绝不写出密钥；失败项只给出原因与脱敏预览。
 */

import { base64ToBytes, utf8Decode } from "./base64.js";
import { decodeBase32, encodeBase32, looksLikeBase32Secret } from "./base32.js";
import { OtpAuthError, parseOtpauthUri } from "./otpauth.js";
import { labels } from "./labels.js";
import { decryptBackup, isBackupPayload, isEncryptedBackup } from "./backup.js";

export class ImportError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "ImportError";
    this.code = code;
  }
}

function redactPreview(line) {
  return String(line)
    .replace(/([A-Za-z2-7\s]{20,})/g, "***")
    .replace(/(secret=)[^&\s]+/gi, "$1***")
    .slice(0, 80);
}

function rowFromStandard(parsed, source) {
  return {
    type: "standard",
    issuer: parsed.issuer,
    account: parsed.account,
    label: "",
    secret: parsed.secret,
    algorithm: parsed.algorithm,
    digits: parsed.digits,
    period: parsed.period,
    weak: parsed.weak === true,
    source,
  };
}

function parseColonLine(line) {
  const parts = line.split(":").map((part) => part.trim());
  if (parts.length < 2) {
    return null;
  }
  const last = parts[parts.length - 1].replace(/\s+/g, "");
  if (!looksLikeBase32Secret(last)) {
    return null;
  }
  const secret = last;
  const names = parts.slice(0, -1);
  if (names.length === 0) {
    return null;
  }
  const issuer = names.length >= 2 ? names[0] : labels.importIssuer;
  const account = names.length >= 2 ? names.slice(1).join(":") : names[0];
  return { issuer, account, secret };
}

function parseFlexibleLine(line) {
  const colon = parseColonLine(line);
  if (colon) {
    return colon;
  }

  let tokens = line
    .split(/\t+|\s{2,}|,|;/)
    .map((token) => token.trim())
    .filter(Boolean);

  if (tokens.length >= 2) {
    const secretIndex = tokens.findIndex((token) => looksLikeBase32Secret(token));
    if (secretIndex >= 0) {
      const secret = tokens[secretIndex];
      const names = tokens.filter((_token, index) => index !== secretIndex);
      if (names.length === 0) {
        return { issuer: labels.importIssuer, account: labels.unnamedAccount, secret };
      }
      if (names.length === 1) {
        return { issuer: labels.importIssuer, account: names[0], secret };
      }
      return { issuer: names[1], account: names[0], secret };
    }
  }

  const words = line.split(/\s+/).filter(Boolean);
  if (words.length === 0) {
    return null;
  }
  if (words.length === 1) {
    if (looksLikeBase32Secret(words[0])) {
      return { issuer: labels.importIssuer, account: labels.unnamedAccount, secret: words[0] };
    }
    return null;
  }

  // Base32 空格分组：从第一个 Base32 词开始，尽量连续收集。
  let runStart = -1;
  let runEnd = -1;
  for (let i = 0; i < words.length; i += 1) {
    const cleaned = words[i].replace(/=+$/g, "");
    if (/^[A-Z2-7]+$/i.test(cleaned) && cleaned.length >= 2) {
      if (runStart < 0) {
        runStart = i;
      }
      runEnd = i;
    } else if (runStart >= 0) {
      break;
    }
  }
  if (runStart >= 0) {
    const joined = words.slice(runStart, runEnd + 1).join("");
    if (looksLikeBase32Secret(joined)) {
      const before = words.slice(0, runStart);
      const after = words.slice(runEnd + 1);
      if (before.length === 0 && after.length === 0) {
        return { issuer: labels.importIssuer, account: labels.unnamedAccount, secret: joined };
      }
      if (before.length === 0 && after.length === 1) {
        return { issuer: labels.importIssuer, account: after[0], secret: joined };
      }
      if (before.length === 0 && after.length >= 2) {
        return { issuer: after[1], account: after[0], secret: joined };
      }
      if (before.length === 1) {
        return { issuer: labels.importIssuer, account: before[0], secret: joined };
      }
      return { issuer: before[0], account: before.slice(1).join(" "), secret: joined };
    }
  }

  if (looksLikeBase32Secret(words[0])) {
    return { issuer: words[2] ?? labels.importIssuer, account: words[1] ?? labels.unnamedAccount, secret: words[0] };
  }
  if (looksLikeBase32Secret(words[words.length - 1])) {
    const names = words.slice(0, -1);
    return {
      issuer: names.length >= 2 ? names[0] : labels.importIssuer,
      account: names.length >= 2 ? names[1] : names[0],
      secret: words[words.length - 1],
    };
  }
  return null;
}

function buildFlexibleRow(line) {
  const parsed = parseFlexibleLine(line);
  if (!parsed) {
    throw new ImportError("UNRECOGNIZED_LINE", "无法识别的行格式");
  }
  let secret;
  let secretBytes;
  try {
    secret = parsed.secret.replace(/\s+/g, "").replace(/=+$/g, "").toUpperCase();
    secretBytes = decodeBase32(secret);
  } catch {
    throw new ImportError("BAD_SECRET", "密钥不是合法的 Base32");
  }
  if (secretBytes.length < 10) {
    throw new ImportError("SHORT_SECRET", "密钥长度不足 10 字节");
  }
  if (secretBytes.length > 128) {
    throw new ImportError("LONG_SECRET", "密钥长度异常");
  }
  return {
    type: "standard",
    issuer: (parsed.issuer || labels.importIssuer).normalize("NFC").slice(0, 64),
    account: (parsed.account || labels.unnamedAccount).normalize("NFC").slice(0, 255),
    label: "",
    secret: encodeBase32(secretBytes),
    algorithm: "SHA1",
    digits: 6,
    period: 30,
    weak: secretBytes.length < 16,
    source: "text",
  };
}

/* ------------------------- Google Authenticator 迁移 ------------------------- */

function readVarint(bytes, offset) {
  let result = 0;
  let shift = 0;
  let position = offset;
  while (position < bytes.length) {
    const byte = bytes[position];
    position += 1;
    result += (byte & 0x7f) * 2 ** shift;
    if ((byte & 0x80) === 0) {
      return [result, position];
    }
    shift += 7;
    if (shift > 49) {
      throw new ImportError("BAD_MIGRATION", "迁移数据中的变长整数无效");
    }
  }
  throw new ImportError("BAD_MIGRATION", "迁移数据不完整");
}

function readMessage(bytes) {
  const fields = [];
  let offset = 0;
  while (offset < bytes.length) {
    let tag;
    [tag, offset] = readVarint(bytes, offset);
    const fieldNumber = Math.floor(tag / 8);
    const wireType = tag % 8;
    if (wireType === 0) {
      let value;
      [value, offset] = readVarint(bytes, offset);
      fields.push({ fieldNumber, wireType, value });
    } else if (wireType === 2) {
      let length;
      [length, offset] = readVarint(bytes, offset);
      if (offset + length > bytes.length) {
        throw new ImportError("BAD_MIGRATION", "迁移数据长度越界");
      }
      fields.push({ fieldNumber, wireType, value: bytes.subarray(offset, offset + length) });
      offset += length;
    } else if (wireType === 5) {
      offset += 4;
    } else if (wireType === 1) {
      offset += 8;
    } else {
      throw new ImportError("BAD_MIGRATION", "迁移数据包含不支持的字段类型");
    }
  }
  return fields;
}

const MIGRATION_ALGORITHMS = { 0: "SHA1", 1: "SHA1", 2: "SHA256", 3: "SHA512" };
const MIGRATION_DIGITS = { 0: 6, 1: 6, 2: 8 };

function parseMigrationOtp(bytes) {
  const fields = readMessage(bytes);
  let secretBytes = null;
  let name = "";
  let issuer = "";
  let algorithm = 1;
  let digits = 1;
  let type = 2;
  for (const field of fields) {
    if (field.fieldNumber === 1 && field.wireType === 2) {
      secretBytes = field.value;
    } else if (field.fieldNumber === 2 && field.wireType === 2) {
      name = utf8Decode(field.value);
    } else if (field.fieldNumber === 3 && field.wireType === 2) {
      issuer = utf8Decode(field.value);
    } else if (field.fieldNumber === 4 && field.wireType === 0) {
      algorithm = field.value;
    } else if (field.fieldNumber === 5 && field.wireType === 0) {
      digits = field.value;
    } else if (field.fieldNumber === 6 && field.wireType === 0) {
      type = field.value;
    }
  }
  if (type === 1) {
    throw new ImportError("HOTP_UNSUPPORTED", "不支持 HOTP 账户");
  }
  if (!secretBytes || secretBytes.length < 10) {
    throw new ImportError("BAD_SECRET", "密钥缺失或长度不足");
  }
  if (secretBytes.length > 128) {
    throw new ImportError("LONG_SECRET", "密钥长度异常");
  }
  let accountName = name.normalize("NFC");
  let issuerName = issuer.normalize("NFC");
  const colon = accountName.indexOf(":");
  if (colon > 0) {
    const nameIssuer = accountName.slice(0, colon);
    if (!issuerName) {
      issuerName = nameIssuer;
    }
    accountName = accountName.slice(colon + 1);
  }
  return {
    type: "standard",
    issuer: (issuerName || labels.importIssuer).slice(0, 64),
    account: (accountName || labels.unnamedAccount).slice(0, 255),
    label: "",
    secret: encodeBase32(secretBytes),
    algorithm: MIGRATION_ALGORITHMS[algorithm] ?? "SHA1",
    digits: MIGRATION_DIGITS[digits] ?? 6,
    period: 30,
    weak: secretBytes.length < 16,
    source: "migration",
  };
}

/**
 * 解析 otpauth-migration://offline?data=...
 * 返回 {rows, failures}，单条失败不影响其他条目。
 */
export function parseMigrationUri(uri) {
  if (!/^otpauth-migration:\/\//i.test(uri)) {
    throw new ImportError("BAD_MIGRATION", "不是 Google Authenticator 迁移链接");
  }
  const questionIndex = uri.indexOf("?");
  const query = questionIndex >= 0 ? uri.slice(questionIndex + 1) : "";
  let data = "";
  for (const pair of query.split("&")) {
    const index = pair.indexOf("=");
    if (index < 0) {
      continue;
    }
    if (pair.slice(0, index).toLowerCase() === "data") {
      try {
        data = decodeURIComponent(pair.slice(index + 1));
      } catch {
        throw new ImportError("BAD_MIGRATION", "迁移链接编码无效");
      }
      break;
    }
  }
  if (!data) {
    throw new ImportError("BAD_MIGRATION", "迁移链接缺少 data 参数");
  }
  let bytes;
  try {
    bytes = base64ToBytes(data);
  } catch {
    throw new ImportError("BAD_MIGRATION", "迁移数据不是合法的 Base64");
  }
  const fields = readMessage(bytes);
  const rows = [];
  const failures = [];
  let index = 0;
  for (const field of fields) {
    if (field.fieldNumber !== 1 || field.wireType !== 2) {
      continue;
    }
    index += 1;
    try {
      rows.push(parseMigrationOtp(field.value));
    } catch (error) {
      failures.push({
        line: 0,
        label: `迁移条目 ${index}`,
        reason: error?.message ?? "迁移条目解析失败",
        code: error?.code ?? "BAD_ROW",
      });
    }
  }
  if (rows.length === 0 && failures.length === 0) {
    throw new ImportError("BAD_MIGRATION", "迁移数据中没有可导入的账户");
  }
  return { rows, failures };
}

/* --------------------------------- 主入口 --------------------------------- */

function parseBackupAccounts(accounts, existingFailures) {
  const rows = [];
  const failures = existingFailures;
  accounts.forEach((raw, index) => {
    const name = `${raw?.issuer ?? ""} / ${raw?.account ?? ""}`.trim() || `备份第 ${index + 1} 项`;
    try {
      if (!raw || typeof raw !== "object") {
        throw new ImportError("BAD_ROW", "账户条目不是对象");
      }
      const type = raw.type === "scan" ? "scan" : "standard";
      const issuer = String(raw.issuer ?? "").normalize("NFC").trim();
      const account = String(raw.account ?? "").normalize("NFC").trim();
      if (!issuer || issuer.length > 64 || !account || account.length > 255) {
        throw new ImportError("BAD_ROW", "签发方或账户名称无效");
      }
      let secret;
      try {
        secret = encodeBase32(decodeBase32(String(raw.secret ?? ""), { loose: true }));
      } catch {
        throw new ImportError("BAD_SECRET", "密钥不是合法的 Base32");
      }
      const secretBytes = decodeBase32(secret);
      if (secretBytes.length < 10 || secretBytes.length > 128) {
        throw new ImportError("BAD_SECRET", "密钥长度异常");
      }
      if (raw.algorithm !== undefined && !["SHA1", "SHA256", "SHA512"].includes(raw.algorithm)) {
        throw new ImportError("BAD_ALGORITHM", "算法不受支持");
      }
      const algorithm = raw.algorithm ?? "SHA1";
      const digits = raw.digits === 8 ? 8 : raw.digits === 6 || raw.digits === undefined ? 6 : null;
      if (digits === null) {
        throw new ImportError("BAD_DIGITS", "位数只支持 6 或 8");
      }
      const period = raw.period === undefined ? 30 : raw.period;
      if (!Number.isInteger(period) || period < 1 || period > 3600) {
        throw new ImportError("BAD_PERIOD", "周期必须在 1–3600 秒之间");
      }
      const row = {
        type,
        issuer,
        account,
        label: typeof raw.label === "string" ? raw.label.slice(0, 64) : "",
        secret,
        algorithm,
        digits,
        period,
        weak: secretBytes.length < 16,
        source: "json",
      };
      if (type === "scan") {
        Object.assign(row, {
          submitUrl: raw.submitUrl,
          bid: raw.bid,
          iat: raw.iat,
          status: raw.status,
          confirmedAt: raw.confirmedAt,
        });
      }
      rows.push(row);
    } catch (error) {
      failures.push({ line: 0, label: name, reason: error?.message ?? "解析失败", code: error?.code ?? "BAD_ROW" });
    }
  });
  return { rows, failures };
}

/**
 * 分析导入文本。
 * 如果文件需要口令而未提供，抛出 ImportError("PASSWORD_REQUIRED")。
 */
export async function analyzeImportText(text, options = {}) {
  let rawText = String(text ?? "").replace(/^\uFEFF/, "").trim();
  if (!rawText) {
    throw new ImportError("EMPTY", "文件内容为空");
  }
  const failures = [];
  const rows = [];

  if (rawText.startsWith("{") || rawText.startsWith("[")) {
    let parsed;
    try {
      parsed = JSON.parse(rawText);
    } catch {
      throw new ImportError("BAD_JSON", "JSON 文件格式错误");
    }
    let payload = parsed;
    if (Array.isArray(parsed)) {
      payload = { format: "totpscan-backup", version: 1, accounts: parsed };
    } else if (isEncryptedBackup(parsed)) {
      if (!options.password) {
        throw new ImportError("PASSWORD_REQUIRED", "该备份已使用口令加密，请输入口令");
      }
      try {
        payload = await decryptBackup(parsed, options.password);
      } catch (error) {
        throw new ImportError("BAD_PASSWORD", error.message);
      }
    }
    if (!isBackupPayload(payload)) {
      throw new ImportError("BAD_JSON", "无法识别的 JSON 备份格式");
    }
    const parsedRows = parseBackupAccounts(payload.accounts, failures);
    return {
      rows: parsedRows.rows,
      failures: parsedRows.failures,
      meta: {
        format: "json",
        encrypted: isEncryptedBackup(parsed),
        total: payload.accounts.length,
      },
    };
  }

  const lines = rawText.split(/\r?\n/);
  let lineNumber = 0;
  for (const rawLine of lines) {
    lineNumber += 1;
    const line = rawLine.trim();
    if (!line || line.startsWith("#") || line.startsWith("//")) {
      continue;
    }
    try {
      if (/^otpauth-migration:\/\//i.test(line)) {
        const migration = parseMigrationUri(line);
        rows.push(...migration.rows);
        failures.push(...migration.failures);
        continue;
      }
      if (/^otpauth:\/\//i.test(line)) {
        let parsed;
        try {
          parsed = parseOtpauthUri(line);
        } catch (error) {
          if (error instanceof OtpAuthError) {
            throw new ImportError(error.code, error.message);
          }
          throw error;
        }
        rows.push(rowFromStandard(parsed, "uri"));
        continue;
      }
      rows.push(buildFlexibleRow(line));
    } catch (error) {
      failures.push({
        line: lineNumber,
        label: redactPreview(line),
        reason: error?.message ?? "无法解析该行",
        code: error?.code ?? "BAD_ROW",
      });
    }
  }

  if (rows.length === 0 && failures.length === 0) {
    throw new ImportError("EMPTY", "没有找到可导入的账户");
  }
  return {
    rows,
    failures,
    meta: { format: "text", encrypted: false, total: rows.length + failures.length },
  };
}
