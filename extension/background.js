/**
 * MV3 background service worker：唯一的密钥与网络编排入口。
 * 弹窗/选项页只能通过消息接口访问账户数据；增强型账户的动态码默认不会返回给 UI，
 * 仅在用户于设置里显式开启 showScanCodes 后随列表返回。
 */

import {
  addScanAccount,
  addStandardAccount,
  confirmScanAccount,
  deleteAccount,
  exportBackup,
  exportTextBackup,
  getStandardCode,
  getAccountOtpauthUri,
  importRows,
  listPublicAccounts,
  listStandardCodes,
  reorderAccounts,
  setAccountPinned,
  submitScanLogin,
  updateLabel,
  updateSiteHosts,
} from "./common/accounts.js";
import { validateBindingPayload, validateLoginPayload } from "./common/protocol.js";
import { DEFAULT_SETTINGS } from "./common/settings.js";
import { getMasterKey } from "./common/vault.js";

const SETTINGS_KEY = "totpscan.settings";
const ACCOUNTS_KEY = "totpscan.accounts";

/** 用户是否显式允许在列表里显示扫码型账户的动态码（默认否）。 */
async function isScanCodesVisible() {
  try {
    const stored = await chrome.storage.local.get(SETTINGS_KEY);
    return stored[SETTINGS_KEY]?.showScanCodes === true;
  } catch {
    return false;
  }
}

const handlers = {
  "accounts:list": () => listPublicAccounts(),
  "account:add-standard": (message) => addStandardAccount(message.input),
  "account:add-scan": (message) =>
    addScanAccount({
      rawText: message.rawText,
      label: message.label,
      siteHosts: message.siteHosts,
    }),
  "account:confirm": (message) => confirmScanAccount(message.id),
  "account:update-label": (message) => updateLabel(message.id, message.label),
  "account:update-sites": (message) => updateSiteHosts(message.id, message.siteHosts),
  "account:delete": (message) => deleteAccount(message.id),
  "account:reorder": (message) => reorderAccounts(message.ids),
  "account:pin": (message) => setAccountPinned(message.id, message.pinned),
  "codes:list": async () =>
    listStandardCodes(Date.now(), { includeScan: await isScanCodesVisible() }),
  "code:get": (message) => getStandardCode(message.id),
  "account:otpauth-uri": (message) => getAccountOtpauthUri(message.id),
  "scan:submit": (message) =>
    submitScanLogin({
      accountId: message.accountId,
      token: message.token,
      tabId: message.tabId,
      frameId: message.frameId,
    }),
  "protocol:parse-binding": (message) => {
    const result = validateBindingPayload(message.rawText);
    return { summary: result.summary };
  },
  "protocol:parse-login": (message) => {
    const result = validateLoginPayload(message.rawText);
    return { summary: result.summary, payload: result.payload };
  },
  "backup:export": (message) => exportBackup({ password: message.password }),
  "backup:export-text": () => exportTextBackup(),
  "backup:import": (message) => importRows(message.rows, message.strategy),
  "vault:ready": async () => {
    await getMasterKey();
    return { ok: true };
  },
};

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (sender?.id && sender.id !== chrome.runtime.id) {
    return false;
  }
  const handler = handlers[message?.type];
  if (!handler) {
    sendResponse({ ok: false, error: { code: "UNKNOWN_MESSAGE", message: "不支持的操作" } });
    return false;
  }
  Promise.resolve()
    .then(() => handler(message, sender))
    .then((data) => sendResponse({ ok: true, data }))
    .catch((error) => {
      sendResponse({
        ok: false,
        error: {
          code: error?.code ?? "INTERNAL_ERROR",
          message: error?.message ?? "操作失败，请稍后重试",
        },
      });
    });
  return true;
});

chrome.runtime.onInstalled.addListener(async () => {
  try {
    await getMasterKey();
    const stored = await chrome.storage.local.get([SETTINGS_KEY, ACCOUNTS_KEY]);
    const patch = {};
    if (!stored[SETTINGS_KEY]) {
      patch[SETTINGS_KEY] = { ...DEFAULT_SETTINGS };
    }
    if (!stored[ACCOUNTS_KEY]) {
      patch[ACCOUNTS_KEY] = { version: 1, accounts: [] };
    }
    if (Object.keys(patch).length > 0) {
      await chrome.storage.local.set(patch);
    }
  } catch {
    // 初始化失败时保留状态，下一次保存操作会再次尝试创建密钥。
  }
});
