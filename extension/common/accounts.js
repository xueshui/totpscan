/**
 * 账户仓储与提交编排（仅在 background service worker 中执行）。
 *
 * 设计约束：
 * - 明文密钥只在后台内存中短暂存在，落盘前由 vault.js 加密；
 * - 增强型账户的动态码绝不出现在返回给 UI 的消息里（S13）；
 * - 扫码登录只向账户自己的固化地址提交（S1）。
 */

import { decodeBase32, encodeBase32 } from "./base32.js";
import { normalizeManualEntry, buildOtpauthExportUri } from "./otpauth.js";
import { decryptSecretBytes, encryptSecretBytes } from "./vault.js";
import { generateTotp, secondsRemainingAt, timeStepAt } from "./totp.js";
import { isTransportAllowed, parseSubmitUrl } from "./canonical-url.js";
// 仅用于站点展示字段的规范化；站点筛选函数不参与提交路径。
import { normalizeSiteHosts } from "./site-filter.js";
import {
  ProtocolError,
  buildBindingConfirmUrl,
  validateBindingPayload,
} from "./protocol.js";

/** 给用户可见的错误附上稳定的错误码，UI 侧按码翻译。 */
function fail(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}
import { buildBackupPayload, buildTextExport, encryptBackup } from "./backup.js";

const STORAGE_KEY = "totpscan.accounts";
const STATE_VERSION = 1;
const SECRET_CACHE = new Map();
const FETCH_TIMEOUT_MS = 12000;

let queue = Promise.resolve();

function withLock(task) {
  const run = queue.then(task, task);
  queue = run.then(
    () => undefined,
    () => undefined,
  );
  return run;
}

function newAccountId() {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  const base64 = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  return `a_${base64}`;
}

async function readState() {
  const stored = await chrome.storage.local.get(STORAGE_KEY);
  const state = stored[STORAGE_KEY];
  if (!state || typeof state !== "object" || !Array.isArray(state.accounts)) {
    return { version: STATE_VERSION, accounts: [] };
  }
  return state;
}

async function writeState(state) {
  await chrome.storage.local.set({ [STORAGE_KEY]: state });
}

export function normalizeLabel(input) {
  if (input === undefined || input === null || input === "") {
    return "";
  }
  if (typeof input !== "string") {
    throw fail("LABEL_INVALID", "本地备注格式无效");
  }
  const value = input.normalize("NFC").trim();
  if (Array.from(value).length > 64) {
    throw fail("LABEL_TOO_LONG", "本地备注不能超过 64 个字符");
  }
  if (/[\u0000-\u001F\u007F]/.test(value)) {
    throw fail("LABEL_CONTROL", "本地备注不能包含换行或控制字符");
  }
  return value;
}

function publicView(account) {
  return {
    id: account.id,
    type: account.type,
    issuer: account.issuer,
    account: account.account,
    label: account.label ?? "",
    siteHosts: Array.isArray(account.siteHosts) ? account.siteHosts : [],
    algorithm: account.algorithm,
    digits: account.digits,
    period: account.period,
    weak: account.weak === true,
    pinned: account.pinned === true,
    submitUrl: account.type === "scan" ? account.submitUrl : null,
    status: account.type === "scan" ? account.status : null,
    confirmedAt: account.confirmedAt ?? null,
    createdAt: account.createdAt,
    updatedAt: account.updatedAt,
  };
}

async function decryptAccountSecret(account) {
  const cached = SECRET_CACHE.get(account.id);
  if (cached) {
    return cached;
  }
  const bytes = await decryptSecretBytes(account.secret);
  SECRET_CACHE.set(account.id, bytes);
  return bytes;
}

function forgetSecret(id) {
  SECRET_CACHE.delete(id);
}

export async function listPublicAccounts() {
  const state = await readState();
  return state.accounts.map(publicView);
}

async function findAccount(id) {
  const state = await readState();
  const account = state.accounts.find((item) => item.id === id);
  if (!account) {
    throw fail("ACCOUNT_NOT_FOUND", "账户不存在");
  }
  return { state, account };
}

export async function addStandardAccount(input) {
  const normalized = input?.secretBytes ? input : normalizeManualEntry(input);
  const label = normalizeLabel(input?.label);
  const secretBytes = normalized.secretBytes ?? decodeBase32(normalized.secret);
  const secretRecord = await encryptSecretBytes(secretBytes);
  const now = Date.now();
  const account = {
    id: newAccountId(),
    type: "standard",
    issuer: normalized.issuer,
    account: normalized.account,
    label,
    siteHosts: normalizeSiteHosts(input?.siteHosts),
    algorithm: normalized.algorithm,
    digits: normalized.digits,
    period: normalized.period,
    weak: secretBytes.length < 16,
    secret: secretRecord,
    createdAt: now,
    updatedAt: now,
  };
  await withLock(async () => {
    const state = await readState();
    state.accounts.push(account);
    await writeState(state);
  });
  return publicView(account);
}

/** 从扫码绑定结果创建增强型账户，并立即尝试确认。 */
export async function addScanAccount({ rawText, label, siteHosts }) {
  const result = validateBindingPayload(rawText);
  const { payload, target } = result;
  let safeLabel = "";
  let labelError = "";
  try {
    safeLabel = normalizeLabel(label);
  } catch (error) {
    labelError = error.message;
  }
  const secretBytes = decodeBase32(payload.sec);
  const secretRecord = await encryptSecretBytes(secretBytes);
  const now = Date.now();
  const account = {
    id: newAccountId(),
    type: "scan",
    issuer: payload.iss,
    account: payload.acc,
    label: safeLabel,
    siteHosts: normalizeSiteHosts(siteHosts),
    algorithm: payload.alg,
    digits: payload.dig,
    period: payload.per,
    weak: secretBytes.length < 16,
    secret: secretRecord,
    submitUrl: target.submitUrl,
    submitPath: target.path,
    siteDomain: target.domain,
    bid: payload.bid,
    iat: payload.iat,
    status: "pending",
    failureCount: 0,
    createdAt: now,
    updatedAt: now,
  };

  await withLock(async () => {
    const state = await readState();
    if (state.accounts.some((item) => item.type === "scan" && item.bid === payload.bid)) {
      throw new ProtocolError("DUPLICATE_BINDING", "该绑定已经存在于本地");
    }
    state.accounts.push(account);
    await writeState(state);
  });

  let confirm = { ok: false, code: "CONFIRM_PENDING" };
  try {
    confirm = await confirmScanAccount(account.id);
  } catch (error) {
    confirm = { ok: false, code: error?.code ?? "CONFIRM_FAILED" };
    await withLock(async () => {
      const { state, account: latest } = await findAccount(account.id);
      latest.status = "failed";
      latest.updatedAt = Date.now();
      await writeState(state);
    }).catch(() => undefined);
  }
  return {
    account: publicView({ ...account, status: confirm.ok ? "confirmed" : "failed" }),
    confirm,
    labelError,
  };
}

/** 用内部计算的动态码确认绑定；目标固定为固化地址同源的确认接口。 */
export async function confirmScanAccount(id) {
  const { account } = await findAccount(id);
  if (account.type !== "scan") {
    throw fail("ONLY_SCAN_CONFIRM", "只有扫码型账户需要确认绑定");
  }
  const target = buildBindingConfirmUrl(account.submitUrl, account.bid);
  if (!isTransportAllowed(new URL(target).origin + "/")) {
    throw fail("INSECURE_TRANSPORT", "提交地址不是 HTTPS 或本地回环地址");
  }
  const secret = await decryptAccountSecret(account);
  const { code } = await generateTotp(secret, {
    algorithm: account.algorithm,
    digits: account.digits,
    period: account.period,
  });

  let response;
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    response = await fetch(target, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code }),
      credentials: "omit",
      cache: "no-store",
      redirect: "manual",
      signal: controller.signal,
    });
    clearTimeout(timer);
  } catch {
    throw fail("CONFIRM_NETWORK", "无法连接提交地址，请检查网络与证书");
  }

  const ok = response.status === 200;
  await withLock(async () => {
    const { state, account: latest } = await findAccount(id);
    latest.status = ok ? "confirmed" : "failed";
    latest.failureCount = ok ? 0 : (latest.failureCount ?? 0) + 1;
    latest.updatedAt = Date.now();
    if (ok) {
      latest.confirmedAt = Date.now();
    }
    await writeState(state);
  });
  if (ok) {
    return { ok: true, status: response.status };
  }
  if (response.status === 401) {
    return { ok: false, status: 401, code: "CONFIRM_REJECTED" };
  }
  return { ok: false, status: response.status, code: "CONFIRM_HTTP" };
}

export async function updateLabel(id, label) {
  const safeLabel = normalizeLabel(label);
  await withLock(async () => {
    const { state, account } = await findAccount(id);
    account.label = safeLabel;
    account.updatedAt = Date.now();
    await writeState(state);
  });
  return { ok: true };
}

/** 更新账户可关联的站点域名（仅用于弹窗展示筛选）。 */
export async function updateSiteHosts(id, siteHosts) {
  const safeHosts = normalizeSiteHosts(siteHosts);
  await withLock(async () => {
    const { state, account } = await findAccount(id);
    account.siteHosts = safeHosts;
    account.updatedAt = Date.now();
    await writeState(state);
  });
  return { ok: true, siteHosts: safeHosts };
}

export async function deleteAccount(id) {
  await withLock(async () => {
    const state = await readState();
    state.accounts = state.accounts.filter((item) => item.id !== id);
    await writeState(state);
  });
  forgetSecret(id);
  return { ok: true };
}

/** 按界面顺序持久化账户列表；未出现在 ids 中的账户按原顺序追加。 */
export async function reorderAccounts(ids) {
  if (!Array.isArray(ids) || ids.some((id) => typeof id !== "string")) {
    throw fail("INVALID_ORDER", "排序参数无效");
  }
  await withLock(async () => {
    const state = await readState();
    const remaining = new Map(state.accounts.map((item) => [item.id, item]));
    const next = [];
    for (const id of ids) {
      const account = remaining.get(id);
      if (account) {
        next.push(account);
        remaining.delete(id);
      }
    }
    for (const account of state.accounts) {
      if (remaining.has(account.id)) {
        next.push(account);
      }
    }
    state.accounts = next;
    await writeState(state);
  });
  return { ok: true };
}

/** 置顶会把账户移到列表首位；取消置顶保持当前位置。 */
export async function setAccountPinned(id, pinned) {
  await withLock(async () => {
    const { state, account } = await findAccount(id);
    account.pinned = pinned === true;
    account.updatedAt = Date.now();
    if (account.pinned) {
      state.accounts = [account, ...state.accounts.filter((item) => item.id !== id)];
    }
    await writeState(state);
  });
  return { ok: true };
}

/** 只对标准型账户返回动态码（UI 可展示/复制）。 */
export async function getStandardCode(id, timestampMs = Date.now()) {
  const { account } = await findAccount(id);
  if (account.type !== "standard") {
    throw new ProtocolError("ENHANCED_CODE_FORBIDDEN", "增强型账户不提供可读动态码");
  }
  const secret = await decryptAccountSecret(account);
  const result = await generateTotp(secret, {
    algorithm: account.algorithm,
    digits: account.digits,
    period: account.period,
    timestampMs,
  });
  return {
    id,
    code: result.code,
    digits: account.digits,
    period: account.period,
    remaining: result.remaining,
    step: result.step,
  };
}

/**
 * 生成单个账户的 otpauth 链接，仅供界面在内存中渲染二维码。
 * 标准型与扫码型都允许；扫码型由界面额外做风险确认。
 * 返回值不写入 storage / 日志 / 备份。
 */
export async function getAccountOtpauthUri(id) {
  const { account } = await findAccount(id);
  const secretBytes = await decryptAccountSecret(account);
  return {
    uri: buildOtpauthExportUri({
      issuer: account.issuer,
      account: account.account,
      secret: encodeBase32(secretBytes),
      algorithm: account.algorithm,
      digits: account.digits,
      period: account.period,
    }),
    type: account.type,
  };
}

export async function listStandardCodes(timestampMs = Date.now(), { includeScan = false } = {}) {
  const state = await readState();
  const codes = [];
  for (const account of state.accounts) {
    if (account.type !== "standard" && !(includeScan && account.type === "scan")) {
      continue;
    }
    const secret = await decryptAccountSecret(account);
    const result = await generateTotp(secret, {
      algorithm: account.algorithm,
      digits: account.digits,
      period: account.period,
      timestampMs,
    });
    codes.push({
      id: account.id,
      code: result.code,
      digits: account.digits,
      period: account.period,
      remaining: result.remaining,
      step: result.step,
    });
  }
  return codes;
}

export async function accountTiming(timestampMs = Date.now()) {
  const state = await readState();
  return state.accounts
    .filter((item) => item.type === "standard")
    .map((item) => ({
      id: item.id,
      period: item.period,
      step: timeStepAt(timestampMs, item.period),
      remaining: secondsRemainingAt(timestampMs, item.period),
    }));
}

function interpretSubmitResponse(status) {
  if (status === 200) {
    return { ok: true, status };
  }
  if (status === 401) {
    return { ok: false, status, code: "AUTH_REJECTED" };
  }
  if (status === 400) {
    return { ok: false, status, code: "AUTH_BAD_REQUEST" };
  }
  if (status === 429) {
    return { ok: false, status, code: "AUTH_RATE_LIMIT" };
  }
  if (status === 0 || (status >= 300 && status < 400)) {
    return { ok: false, status, code: "AUTH_REDIRECT" };
  }
  return { ok: false, status, code: "AUTH_HTTP" };
}

/**
 * 扫码登录提交。动态码只在后台生成并直接发往固化地址，不返回给 UI。
 * 优先由登录页同源的 content script 发起（携带会话 Cookie），失败再回退到后台请求。
 */
export async function submitScanLogin({ accountId, token, tabId, frameId }) {
  const { account } = await findAccount(accountId);
  if (account.type !== "scan") {
    throw new ProtocolError("NOT_SCAN_ACCOUNT", "标准型账户不能用于扫码提交");
  }
  if (account.status !== "confirmed") {
    throw new ProtocolError("NOT_CONFIRMED", "该账户的绑定尚未确认，无法用于登录");
  }
  if (typeof token !== "string" || !/^(?:[A-Za-z0-9_-]{16}|[A-Za-z0-9_-]{24})$/.test(token)) {
    throw new ProtocolError("BAD_TOKEN", "会话标识格式无效");
  }
  if (!isTransportAllowed(account.submitUrl)) {
    throw new ProtocolError("INSECURE_TRANSPORT", "固化地址不是 HTTPS 或本地回环地址");
  }
  const secret = await decryptAccountSecret(account);
  const { code } = await generateTotp(secret, {
    algorithm: account.algorithm,
    digits: account.digits,
    period: account.period,
  });
  const body = { code, token };

  let contentScriptFailure = null;
  if (Number.isInteger(tabId)) {
    try {
      const response = await chrome.tabs.sendMessage(
        tabId,
        { type: "TOTPSCAN_SUBMIT", url: account.submitUrl, body },
        Number.isInteger(frameId) ? { frameId } : undefined,
      );
      if (response?.ok) {
        return interpretSubmitResponse(response.status, response.bodyText);
      }
      contentScriptFailure = response?.reason ?? "UNKNOWN";
    } catch {
      contentScriptFailure = "NO_CONTENT_SCRIPT";
    }
  }

  let response;
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    response = await fetch(account.submitUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      credentials: "include",
      cache: "no-store",
      redirect: "manual",
      signal: controller.signal,
    });
    clearTimeout(timer);
  } catch {
    throw new ProtocolError(
      "SUBMIT_FAILED",
      contentScriptFailure === "CROSS_ORIGIN"
        ? "登录页与固化地址不同源，且后台无法完成提交"
        : "无法连接提交地址，请检查网络与证书",
    );
  }
  return interpretSubmitResponse(response.status, "");
}

function backupRowFromRecord(account, secretBytes) {
  const base = {
    type: account.type,
    issuer: account.issuer,
    account: account.account,
    label: account.label ?? "",
    siteHosts: Array.isArray(account.siteHosts) ? account.siteHosts : [],
    secret: encodeBase32(secretBytes),
    algorithm: account.algorithm,
    digits: account.digits,
    period: account.period,
  };
  if (account.type === "scan") {
    return {
      ...base,
      submitUrl: account.submitUrl,
      bid: account.bid,
      iat: account.iat,
      status: account.status,
      confirmedAt: account.confirmedAt ?? null,
    };
  }
  return base;
}

function stampName() {
  const date = new Date();
  const pad = (value) => String(value).padStart(2, "0");
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-${pad(date.getHours())}${pad(
    date.getMinutes(),
  )}`;
}

export async function exportBackup({ password = "" } = {}) {
  const state = await readState();
  const rows = [];
  for (const account of state.accounts) {
    const secret = await decryptAccountSecret(account);
    rows.push(backupRowFromRecord(account, secret));
  }
  const payload = buildBackupPayload(rows);
  const containsScan = rows.some((row) => row.type === "scan");
  if (password) {
    // §14.3：密文内的明文为紧凑 JSON（无多余空白、encrypted 固定为 false）
    const envelope = await encryptBackup(JSON.stringify(payload), password);
    return {
      filename: `totpscan-backup-encrypted-${stampName()}.json`,
      content: JSON.stringify(envelope, null, 2),
      encrypted: true,
      accountCount: rows.length,
      containsScan,
    };
  }
  return {
    filename: `totpscan-backup-${stampName()}.json`,
    content: JSON.stringify(payload, null, 2),
    encrypted: false,
    accountCount: rows.length,
    containsScan,
  };
}

export async function exportTextBackup() {
  const state = await readState();
  const rows = [];
  for (const account of state.accounts) {
    if (account.type !== "standard") {
      continue;
    }
    const secret = await decryptAccountSecret(account);
    rows.push({ ...account, secret: encodeBase32(secret) });
  }
  return {
    filename: `authenticator-${stampName()}.txt`,
    content: buildTextExport(rows),
    accountCount: rows.length,
    excludedScan: state.accounts.filter((item) => item.type === "scan").length,
  };
}

function normalizeImportText(value, field, maxLength) {
  if (typeof value !== "string") {
    throw fail("BAD_FIELD", `${field}缺失`);
  }
  const text = value.normalize("NFC").trim();
  if (text.length === 0 || text.length > maxLength) {
    throw fail("BAD_FIELD", `${field}长度无效`);
  }
  if (/[\u0000-\u001F\u007F]/.test(text)) {
    throw fail("BAD_FIELD", `${field}含控制字符`);
  }
  return text;
}

function duplicateKey(type, issuer, account) {
  return `${type}\u0000${issuer}\u0000${account}`;
}

/**
 * 落库导入行。支持 skip / overwrite / keep 三种重复策略。
 * 扫码型行会重新解析 submitUrl，并校验传输协议与绑定标识。
 */
export async function importRows(rows, strategy = "skip") {
  if (!["skip", "overwrite", "keep"].includes(strategy)) {
    throw fail("UNKNOWN_STRATEGY", "未知的重复处理策略");
  }
  if (!Array.isArray(rows) || rows.length === 0) {
    return { added: 0, overwritten: 0, skipped: 0, failed: [], total: 0 };
  }
  return withLock(async () => {
    const state = await readState();
    const result = { added: 0, overwritten: 0, skipped: 0, failed: [], total: rows.length };
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      const name = `${row?.issuer ?? ""} / ${row?.account ?? ""}`.trim() || `第 ${index + 1} 项`;
      try {
        const type = row.type === "scan" ? "scan" : "standard";
        const issuer = normalizeImportText(row.issuer, "签发方", 64);
        const accountName = normalizeImportText(row.account, "账户", 255);
        const label = normalizeLabel(row.label ?? "");
        const algorithm =
          row.algorithm === undefined || row.algorithm === ""
            ? "SHA1"
            : String(row.algorithm).toUpperCase();
        if (!["SHA1", "SHA256", "SHA512"].includes(algorithm)) {
          throw fail("BAD_ALGORITHM", "签名算法不受支持");
        }
        const digits = row.digits === undefined ? 6 : Number(row.digits);
        if (digits !== 6 && digits !== 8) {
          throw fail("BAD_DIGITS", "动态码位数不受支持");
        }
        const period = row.period === undefined ? 30 : Number(row.period);
        if (!Number.isInteger(period) || period < 1 || period > 3600) {
          throw fail("BAD_PERIOD", "时间步长无效");
        }
        const secretBytes = decodeBase32(row.secret, { loose: true });
        if (secretBytes.length < 10) {
          throw fail("SHORT_SECRET", "密钥长度不足 10 字节");
        }
        if (secretBytes.length > 128) {
          throw fail("LONG_SECRET", "密钥长度异常");
        }

        const base = {
          type,
          issuer,
          account: accountName,
          label,
          siteHosts: normalizeSiteHosts(row.siteHosts),
          algorithm,
          digits,
          period,
          weak: secretBytes.length < 16,
        };

        if (type === "scan") {
          let target;
          try {
            target = parseSubmitUrl(row.submitUrl);
          } catch {
            throw fail("BAD_SUBMIT_URL", "提交地址无效");
          }
          if (!isTransportAllowed(target.submitUrl)) {
            throw fail("INSECURE_TRANSPORT", "固化地址不是 HTTPS 或本地回环地址");
          }
          if (typeof row.bid !== "string") {
            throw fail("MISSING_BINDING_ID", "缺少绑定标识");
          }
          const iat = Number.isInteger(row.iat) ? row.iat : 0;
          Object.assign(base, {
            submitUrl: target.submitUrl,
            submitPath: target.path,
            siteDomain: target.domain,
            bid: row.bid,
            iat,
            status: ["confirmed", "pending", "failed"].includes(row.status) ? row.status : "pending",
            confirmedAt: Number.isInteger(row.confirmedAt) ? row.confirmedAt : null,
            failureCount: 0,
          });
        }

        const encrypted = await encryptSecretBytes(secretBytes);
        const now = Date.now();
        const key = duplicateKey(type, issuer, accountName);
        const existing = state.accounts.find(
          (item) => duplicateKey(item.type, item.issuer, item.account) === key,
        );

        if (existing && strategy === "skip") {
          result.skipped += 1;
          continue;
        }
        if (existing && strategy === "overwrite") {
          Object.assign(existing, base, {
            secret: encrypted,
            updatedAt: now,
          });
          if (type === "scan" && !existing.confirmedAt) {
            existing.confirmedAt = base.confirmedAt ?? null;
          }
          forgetSecret(existing.id);
          result.overwritten += 1;
          continue;
        }

        state.accounts.push({
          id: newAccountId(),
          ...base,
          secret: encrypted,
          createdAt: now,
          updatedAt: now,
        });
        result.added += 1;
      } catch (error) {
        result.failed.push({
          index,
          name,
          reason: error?.message ?? "导入失败",
          code: error?.code ?? "BAD_ROW",
        });
      }
    }
    await writeState(state);
    return result;
  });
}

export { publicView as toPublicView };
