/** 扩展弹窗：账户卡片、倒计时、自动填入、页面扫码与协议流程。 */

import {
  initTheme,
  saveSettings,
  applyTheme,
  nextThemeMode,
  THEME_MODE_KEYS,
} from "../common/settings.js";
import { initI18n, t, hasMessage } from "../common/i18n.js";
import { timeStepAt, secondsRemainingAt, formatCodeForDisplay } from "../common/totp.js";
import { findScanCandidates, detectQrKind } from "../common/protocol.js";
import { parseOtpauthUri } from "../common/otpauth.js";
import { orderAccountsBySite } from "../common/site-filter.js";
import { openQrExport } from "../common/qr-export.js";
import {
  icon,
  escapeHtml,
  showToast,
  openModal,
  closeModal,
  confirmDialog,
  openContextMenu,
  attachSortable,
  copyToClipboard,
  initialsOf,
  hueFromString,
  formatDomain,
} from "../common/ui.js";

const state = {
  settings: null,
  accounts: [],
  codes: new Map(),
  loading: true,
  refreshing: false,
  refreshQueued: false,
  lastRefreshAt: 0,
  scanBusy: false,
  editMode: false,
  searchQuery: "",
  siteHost: "",
  siteOnly: true,
  siteMatchIds: new Set(),
  siteNarrowed: false,
  siteFallbackNotified: false,
};

const listEl = document.getElementById("accountList");
const emptyEl = document.getElementById("emptyState");
const loadingEl = document.getElementById("listLoading");
const headerSub = document.getElementById("headerSub");
const editHint = document.getElementById("editHint");
const themeToggle = document.getElementById("themeToggle");
const editListButton = document.getElementById("editList");
const openOptionsButton = document.getElementById("openOptions");
const emptyAddButton = document.getElementById("emptyAdd");
const scanFab = document.getElementById("scanFab");
const searchBar = document.getElementById("searchBar");
const searchInput = document.getElementById("searchInput");
const searchClear = document.getElementById("searchClear");
const searchEmptyEl = document.getElementById("searchEmpty");
const searchEmptyClear = document.getElementById("searchEmptyClear");
const siteFilter = document.getElementById("siteFilter");
const siteOnlyBtn = document.getElementById("siteOnlyBtn");
const siteAllBtn = document.getElementById("siteAllBtn");

const RING_RADIUS = 15.5;
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS;

/** 把后台错误码翻译成当前语言；未知错误码不直接显示可能为中文的原文。 */
export function errorText(error, vars) {
  const key = `error_${error?.code ?? "UNKNOWN"}`;
  return hasMessage(key) ? t(key, vars) : t("error_UNKNOWN");
}

async function send(type, payload = {}) {
  let response;
  try {
    response = await chrome.runtime.sendMessage({ ...payload, type });
  } catch {
    const error = new Error("backend unavailable");
    error.code = "NO_BACKGROUND";
    throw error;
  }
  if (!response) {
    const error = new Error("backend unavailable");
    error.code = "NO_BACKGROUND";
    throw error;
  }
  if (!response.ok) {
    const error = new Error(response.error?.message ?? "operation failed");
    error.code = response.error?.code ?? "UNKNOWN";
    throw error;
  }
  return response.data;
}

function updateThemeButton() {
  if (!state.settings) {
    return;
  }
  const mode = state.settings.themeMode;
  const name = mode === "dark" ? "moon" : mode === "light" ? "sun" : "clock";
  themeToggle.innerHTML = icon(name, 17);
  themeToggle.title = t("popup_theme_toggle", { mode: t(THEME_MODE_KEYS[mode]) });
  themeToggle.setAttribute("aria-label", themeToggle.title);
}

async function cycleTheme() {
  const mode = nextThemeMode(state.settings.themeMode);
  state.settings = await saveSettings({ themeMode: mode });
  applyTheme(state.settings);
  updateThemeButton();
  showToast(t("popup_theme_switched", { mode: t(THEME_MODE_KEYS[mode]) }), { duration: 1800 });
}

function updateEditButton() {
  editListButton.innerHTML = icon("grip", 17);
  const active = state.editMode;
  editListButton.classList.toggle("is-active", active);
  editListButton.setAttribute("aria-pressed", String(active));
  editListButton.disabled =
    state.accounts.length === 0 || state.searchQuery.trim().length > 0 || state.siteNarrowed;
  const label = t(active ? "popup_edit_list_done" : "popup_edit_list");
  editListButton.title = label;
  editListButton.setAttribute("aria-label", label);
  editHint.hidden = !active || state.accounts.length === 0;
}

function isRestrictedPage(url) {
  return (
    !url ||
    /^(chrome|edge|about|devtools|view-source|chrome-extension|moz-extension):/i.test(url) ||
    /^https:\/\/chromewebstore\.google\.com\//i.test(url)
  );
}

async function getActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab ?? null;
}

/** 只提取 http/https 页面的 host，用于弹窗内的展示筛选。 */
function tabHostOf(tab) {
  try {
    const url = new URL(tab?.url ?? "");
    return url.protocol === "http:" || url.protocol === "https:" ? url.hostname : "";
  } catch {
    return "";
  }
}

function accountInitial(account) {
  return initialsOf(account.label || account.issuer || account.account);
}

function avatarStyle(account) {
  const hue = hueFromString(`${account.issuer}|${account.account}`);
  return `background:linear-gradient(140deg, hsl(${hue} 76% 62%), hsl(${hue + 12} 72% 46%))`;
}

function accountDisplayName(account) {
  return account.label || `${account.issuer} · ${account.account}`;
}

/** 搜索范围：本地备注、发行方、账户名；英文不区分大小写，中文按包含匹配。 */
function matchesSearch(account, query) {
  if (!query) {
    return true;
  }
  return [account.label, account.issuer, account.account].some(
    (value) => typeof value === "string" && value.toLocaleLowerCase().includes(query),
  );
}

function visibleAccounts(accounts) {
  const query = state.searchQuery.trim().toLocaleLowerCase();
  return query ? accounts.filter((account) => matchesSearch(account, query)) : accounts;
}

function clearSearch({ focus = false } = {}) {
  state.searchQuery = "";
  searchInput.value = "";
  render();
  if (focus) {
    searchInput.focus();
  }
}

/** 标准型始终显示动态码；扫码型仅在用户显式开启设置后显示。 */
function showsCode(account) {
  return (
    account.type === "standard" ||
    (account.type === "scan" && state.settings?.showScanCodes === true)
  );
}

function createCard(account) {
  const card = document.createElement("div");
  card.className = `account-card${account.type === "scan" ? " is-scan" : ""}${
    state.editMode ? " is-editing" : ""
  }`;
  card.setAttribute("role", "button");
  card.setAttribute("aria-label", `${account.issuer} ${account.account}`);
  card.tabIndex = 0;
  card.dataset.id = account.id;
  const onSite = state.siteMatchIds.has(account.id);
  card.dataset.site = onSite ? "1" : "0";
  const label = account.label ? `<span class="badge-label">${escapeHtml(account.label)}</span>` : "";
  const pinBadge = account.pinned ? `<span class="badge-label badge-pin">${escapeHtml(t("popup_pinned"))}</span>` : "";
  const siteBadge = onSite
    ? `<span class="badge-label badge-site">${escapeHtml(t("popup_site_badge"))}</span>`
    : "";
  const handle = state.editMode
    ? `<button class="drag-handle" type="button" data-drag-handle title="${escapeHtml(
        t("options_drag_title"),
      )}" aria-label="${escapeHtml(
        t("popup_drag_aria", { name: accountDisplayName(account) }),
      )}">${icon("grip", 15)}</button>`
    : "";
  const moreButton = `<button class="icon-button subtle card-more" type="button" data-more aria-label="${escapeHtml(
    t("popup_more_for", { name: accountDisplayName(account) }),
  )}" title="${escapeHtml(t("common_more_actions"))}">${icon("more", 14)}</button>`;

  if (account.type === "standard") {
    const code = state.codes.get(account.id);
    const display = code ? formatCodeForDisplay(code.code) : "••• •••";
    card.innerHTML = `
      ${handle}
      <div class="avatar" style="${avatarStyle(account)}">${escapeHtml(accountInitial(account))}</div>
      <div class="account-main">
        <div class="account-meta">
          <span class="name">${escapeHtml(account.issuer)}</span>
          <span class="divider-dot"></span>
          <span class="account-name">${escapeHtml(account.account)}</span>
          ${siteBadge}
          ${pinBadge}
          ${label}
        </div>
        <div class="account-code" data-code="${escapeHtml(code?.code ?? "")}">${escapeHtml(display)}</div>
        <div class="account-foot">
          <span class="foot-text">${escapeHtml(t("popup_click_to_fill"))}</span>
          <button class="icon-button subtle copy-button" type="button" title="${escapeHtml(
            t("popup_copy_code"),
          )}" aria-label="${escapeHtml(t("popup_copy_code"))}">${icon("copy", 13)}</button>
          ${moreButton}
        </div>
      </div>
      <div class="ring" aria-hidden="true">
        <svg width="38" height="38" viewBox="0 0 38 38">
          <circle class="ring-track" cx="19" cy="19" r="${RING_RADIUS}" fill="none" stroke-width="2.6" />
          <circle class="ring-progress" cx="19" cy="19" r="${RING_RADIUS}" fill="none" stroke-width="2.6"
            stroke-linecap="round" stroke-dasharray="${RING_CIRCUMFERENCE.toFixed(2)}"
            stroke-dashoffset="0" />
        </svg>
        <span class="ring-label">${account.period}</span>
      </div>
    `;
    const copyButton = card.querySelector(".copy-button");
    copyButton.addEventListener("click", async (event) => {
      event.stopPropagation();
      const current = state.codes.get(account.id);
      if (!current) {
        showToast(t("popup_code_not_ready"), { kind: "error" });
        return;
      }
      const ok = await copyToClipboard(current.code);
      showToast(ok ? t("popup_code_copied") : t("popup_copy_failed"), { kind: ok ? "success" : "error" });
    });
    card.addEventListener("click", () => {
      if (!state.editMode) {
        fillToPage(account);
      }
    });
    card.addEventListener("keydown", (event) => {
      if (state.editMode) {
        return;
      }
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        fillToPage(account);
      }
    });
  } else {
    const statusBadge =
      account.status === "confirmed"
        ? `<span class="badge badge-accent">${escapeHtml(t("popup_scan_only_badge"))}</span>`
        : `<span class="badge badge-warning">${escapeHtml(t("popup_pending_badge"))}</span>`;
    const withCode = showsCode(account);
    const current = state.codes.get(account.id);
    const codeBlock = withCode
      ? `<div class="account-code" data-code="${escapeHtml(current?.code ?? "")}">${escapeHtml(
          current ? formatCodeForDisplay(current.code) : "••• •••",
        )}</div>`
      : `<div class="account-code is-scan">${escapeHtml(t("popup_scan_account_code"))}</div>`;
    const copyButton = withCode
      ? `<button class="icon-button subtle copy-button" type="button" title="${escapeHtml(
          t("popup_copy_code"),
        )}" aria-label="${escapeHtml(t("popup_copy_code"))}">${icon("copy", 13)}</button>`
      : "";
    const trailing = withCode
      ? `<div class="ring" aria-hidden="true">
          <svg width="38" height="38" viewBox="0 0 38 38">
            <circle class="ring-track" cx="19" cy="19" r="${RING_RADIUS}" fill="none" stroke-width="2.6" />
            <circle class="ring-progress" cx="19" cy="19" r="${RING_RADIUS}" fill="none" stroke-width="2.6"
              stroke-linecap="round" stroke-dasharray="${RING_CIRCUMFERENCE.toFixed(2)}"
              stroke-dashoffset="0" />
          </svg>
          <span class="ring-label">${account.period}</span>
        </div>`
      : `<div class="scan-mode-icon" aria-hidden="true">${icon("scanLine", 20)}</div>`;
    card.innerHTML = `
      ${handle}
      <div class="avatar" style="${avatarStyle(account)}">${escapeHtml(accountInitial(account))}</div>
      <div class="account-main">
        <div class="account-meta">
          <span class="name">${escapeHtml(account.issuer)}</span>
          <span class="divider-dot"></span>
          <span class="account-name">${escapeHtml(account.account)}</span>
          ${siteBadge}
          ${pinBadge}
          ${label}
        </div>
        ${codeBlock}
        <div class="account-foot">
          ${statusBadge}
          <span class="domain">${escapeHtml(formatDomain(account.submitUrl ?? ""))}</span>
          ${copyButton}
          ${moreButton}
        </div>
      </div>
      ${trailing}
    `;
    if (withCode) {
      card.querySelector(".copy-button").addEventListener("click", async (event) => {
        event.stopPropagation();
        const latest = state.codes.get(account.id);
        if (!latest) {
          showToast(t("popup_code_not_ready"), { kind: "error" });
          return;
        }
        const ok = await copyToClipboard(latest.code);
        showToast(ok ? t("popup_code_copied") : t("popup_copy_failed"), {
          kind: ok ? "success" : "error",
        });
      });
    }
    card.addEventListener("click", () => {
      if (state.editMode) {
        return;
      }
      if (account.status === "confirmed") {
        startScan();
      } else {
        showScanAccountDetail(account);
      }
    });
    card.addEventListener("keydown", (event) => {
      if (state.editMode) {
        return;
      }
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        card.click();
      }
    });
  }

  card.querySelector("[data-more]").addEventListener("click", (event) => {
    event.stopPropagation();
    const rect = event.currentTarget.getBoundingClientRect();
    openAccountMenu(account, rect.left - 150, rect.bottom + 4);
  });
  card.addEventListener("contextmenu", (event) => {
    event.preventDefault();
    event.stopPropagation();
    openAccountMenu(account, event.clientX, event.clientY);
  });
  return card;
}

function openAccountMenu(account, x, y) {
  openContextMenu({
    x,
    y,
    label: t("common_account_actions", { name: accountDisplayName(account) }),
    items: [
      { label: t("popup_rename"), icon: "edit", onSelect: () => openLabelEditor(account, "rename") },
      { label: t("popup_edit_note"), icon: "page", onSelect: () => openLabelEditor(account, "note") },
      {
        label: t(account.pinned ? "popup_unpin" : "popup_pin"),
        icon: account.pinned ? "pinOff" : "pin",
        onSelect: () => togglePinned(account),
      },
      { label: t("qr_export_menu"), icon: "qr", onSelect: () => exportAccountQr(account) },
      { label: t("popup_delete_account"), icon: "trash", danger: true, onSelect: () => deleteAccount(account) },
    ],
  });
}

function exportAccountQr(account) {
  return openQrExport({
    account,
    getUri: async () => (await send("account:otpauth-uri", { id: account.id })).uri,
    errorText,
  });
}

function openLabelEditor(account, mode = "note") {
  const isRename = mode === "rename";
  const body = document.createElement("div");
  body.innerHTML = `
    <div class="field">
      <label for="popupLabelInput">${escapeHtml(
        t(isRename ? "popup_display_name" : "popup_local_note"),
      )} <span class="optional">${escapeHtml(t("common_optional_local"))}</span></label>
      <input class="input" id="popupLabelInput" maxlength="64" value="${escapeHtml(account.label ?? "")}" autocomplete="off" />
      <div class="field-error" id="popupLabelError"></div>
    </div>
    <div class="hint">${escapeHtml(t("popup_label_hint"))}</div>
  `;
  openModal({
    title: t(isRename ? "popup_rename_title" : "popup_note_title"),
    subtitle: `${account.issuer} · ${account.account}`,
    content: body,
    actions: [
      { label: t("common_cancel") },
      {
        label: t("common_save"),
        variant: "primary",
        keepOpen: true,
        onClick: async (close) => {
          try {
            await send("account:update-label", {
              id: account.id,
              label: body.querySelector("#popupLabelInput").value,
            });
            close();
            await refreshAccounts();
            showToast(t(isRename ? "popup_name_saved" : "popup_note_saved"), { kind: "success" });
          } catch (error) {
            body.querySelector("#popupLabelError").textContent = errorText(error);
          }
          return false;
        },
      },
    ],
  });
}

async function togglePinned(account) {
  try {
    await send("account:pin", { id: account.id, pinned: !account.pinned });
    await refreshAccounts();
    showToast(t(account.pinned ? "popup_unpinned" : "popup_pinned_toast"), { duration: 1600 });
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
  }
}

async function deleteAccount(account) {
  const name = accountDisplayName(account);
  const message = [
    t("popup_delete_message", { name }),
    account.type === "scan" ? t("popup_delete_scan_note") : "",
  ]
    .filter(Boolean)
    .join("\n");
  const ok = await confirmDialog({
    title: t("popup_delete_title"),
    message,
    confirmText: t("popup_confirm_delete"),
    cancelText: t("common_cancel"),
    danger: true,
  });
  if (!ok) {
    return;
  }
  try {
    await send("account:delete", { id: account.id });
    await refreshAccounts();
    showToast(t("popup_account_deleted"), { kind: "success" });
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
  }
}

async function applyOrder(ids) {
  const byId = new Map(state.accounts.map((account) => [account.id, account]));
  state.accounts = ids.map((id) => byId.get(id)).filter(Boolean);
  try {
    await send("account:reorder", { ids });
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
    await refreshAccounts();
  }
}

function render() {
  loadingEl.hidden = true;
  if (state.accounts.length === 0) {
    state.editMode = false;
    state.searchQuery = "";
    searchInput.value = "";
  }
  const query = state.searchQuery.trim();
  const siteView = orderAccountsBySite(state.accounts, state.siteHost);
  state.siteMatchIds = new Set(siteView.site.map((account) => account.id));
  const siteAvailable =
    Boolean(state.siteHost) &&
    state.accounts.some((account) => (account.siteHosts?.length ?? 0) > 0);
  const effectiveSiteOnly = state.siteOnly && siteAvailable && siteView.hasMatches;
  // 站点筛选隐藏了部分账户时禁止排序，避免把未显示的账户挤到列表末尾。
  state.siteNarrowed = effectiveSiteOnly && siteView.site.length < state.accounts.length;
  const visible = visibleAccounts(effectiveSiteOnly ? siteView.site : siteView.all);
  const cards = visible.map(createCard);
  listEl.replaceChildren(...cards);
  const hasAccounts = state.accounts.length > 0;
  searchBar.hidden = !hasAccounts;
  searchClear.hidden = query.length === 0;
  emptyEl.hidden = hasAccounts;
  if (!hasAccounts) {
    listEl.appendChild(emptyEl);
  }
  siteFilter.hidden = !siteAvailable;
  siteOnlyBtn.classList.toggle("is-active", effectiveSiteOnly);
  siteAllBtn.classList.toggle("is-active", !effectiveSiteOnly);
  siteOnlyBtn.setAttribute("aria-pressed", String(effectiveSiteOnly));
  siteAllBtn.setAttribute("aria-pressed", String(!effectiveSiteOnly));
  if (siteAvailable && state.siteOnly && !siteView.hasMatches) {
    if (!state.siteFallbackNotified) {
      state.siteFallbackNotified = true;
      showToast(t("popup_site_fallback"), { duration: 2400 });
    }
  } else if (siteView.hasMatches) {
    state.siteFallbackNotified = false;
  }
  const noResults = hasAccounts && query.length > 0 && visible.length === 0;
  searchEmptyEl.hidden = !noResults;
  if (noResults) {
    listEl.appendChild(searchEmptyEl);
  }
  headerSub.textContent = hasAccounts
    ? t("popup_header_sub_count", { count: state.accounts.length })
    : t("popup_header_sub_default");
  updateEditButton();
  tick();
}

async function refreshAccounts() {
  try {
    state.accounts = await send("accounts:list");
    render();
    await refreshCodes();
  } catch (error) {
    loadingEl.innerHTML = `<span>${escapeHtml(errorText(error))}</span>`;
  }
}

async function refreshCodes() {
  if (state.refreshing) {
    state.refreshQueued = true;
    return;
  }
  state.refreshing = true;
  state.lastRefreshAt = Date.now();
  try {
    const codes = await send("codes:list");
    state.codes = new Map(codes.map((item) => [item.id, item]));
    for (const account of state.accounts) {
      if (!showsCode(account)) {
        continue;
      }
      const card = listEl.querySelector(`[data-id="${account.id}"]`);
      if (!card) {
        continue;
      }
      const current = state.codes.get(account.id);
      const codeEl = card.querySelector(".account-code");
      if (codeEl && current) {
        codeEl.textContent = formatCodeForDisplay(current.code);
        codeEl.dataset.code = current.code;
      }
    }
    tick();
  } catch {
    // 动态码刷新失败时保留上一次的值
  } finally {
    state.refreshing = false;
    if (state.refreshQueued) {
      state.refreshQueued = false;
      refreshCodes();
    }
  }
}

function tick() {
  const now = Date.now();
  let needsRefresh = false;
  for (const account of state.accounts) {
    if (!showsCode(account)) {
      continue;
    }
    const card = listEl.querySelector(`[data-id="${account.id}"]`);
    if (!card) {
      continue;
    }
    const current = state.codes.get(account.id);
    const remaining = secondsRemainingAt(now, account.period);
    const progress = Math.max(0, Math.min(1, remaining / account.period));
    const ring = card.querySelector(".ring-progress");
    if (ring) {
      ring.setAttribute("stroke-dashoffset", String(RING_CIRCUMFERENCE * (1 - progress)));
    }
    const ringLabel = card.querySelector(".ring-label");
    if (ringLabel) {
      ringLabel.textContent = String(Math.ceil(remaining));
      ringLabel.classList.toggle("is-low", remaining <= 5);
    }
    if (current && timeStepAt(now, account.period) !== current.step) {
      needsRefresh = true;
    }
    if (!current) {
      needsRefresh = true;
    }
  }
  if (needsRefresh && now - state.lastRefreshAt >= 1000) {
    refreshCodes();
  }
}

async function ensureContentScript(tabId, allFrames = false) {
  await chrome.scripting.executeScript({
    target: { tabId, allFrames },
    files: ["vendor/jsQR.js", "content/content.js"],
  });
}

function flashCardCopied(id) {
  const card = listEl.querySelector(`[data-id="${id}"]`);
  const footText = card?.querySelector(".foot-text");
  if (!card || !footText) {
    return;
  }
  const original = footText.textContent;
  footText.textContent = t("popup_copied_short");
  card.classList.add("is-copied");
  clearTimeout(card.copyFeedbackTimer);
  card.copyFeedbackTimer = setTimeout(() => {
    footText.textContent = original;
    card.classList.remove("is-copied");
  }, 1600);
}

/** 找不到可填写输入框时静默复制；只有复制本身失败才提示。 */
async function copyCodeSilently(account, code) {
  const ok = await copyToClipboard(code);
  if (ok) {
    flashCardCopied(account.id);
  } else {
    showToast(t("popup_copy_permission_failed"), { kind: "error" });
  }
  return ok;
}

async function fillToPage(account) {
  let code;
  try {
    code = await send("code:get", { id: account.id });
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
    return;
  }
  const tab = await getActiveTab();
  if (!tab?.id || isRestrictedPage(tab.url)) {
    await copyCodeSilently(account, code.code);
    return;
  }
  try {
    await ensureContentScript(tab.id, false);
    const result = await chrome.tabs.sendMessage(
      tab.id,
      { type: "TOTPSCAN_FILL_CODE", code: code.code },
      { frameId: 0 },
    );
    if (result?.ok) {
      showToast(t("popup_filled"), { kind: "success" });
      return;
    }
    if (result?.reason === "NO_FOCUSED_FIELD") {
      await copyCodeSilently(account, code.code);
      return;
    }
    showToast(result?.reason ? errorText({ code: result.reason }) : t("popup_fill_failed"), {
      kind: "error",
      duration: 4200,
    });
  } catch {
    await copyCodeSilently(account, code.code);
  }
}

function setScanBusy(busy) {
  state.scanBusy = busy;
  scanFab.classList.toggle("is-busy", busy);
}

function showScanningModal() {
  openModal({
    title: t("popup_scanning_title"),
    subtitle: t("popup_scanning_sub"),
    content: `<div class="scanning"><div class="spinner"></div><span>${escapeHtml(
      t("popup_scanning_text"),
    )}</span></div>`,
    dismissible: false,
  });
}

async function collectPageQrCodes(tab) {
  try {
    await ensureContentScript(tab.id, true);
  } catch {
    await ensureContentScript(tab.id, false);
  }
  let frames;
  try {
    frames = await chrome.scripting.executeScript({
      target: { tabId: tab.id, allFrames: true },
      func: () =>
        typeof globalThis.__TOTPSCAN_SCAN_PAGE__ === "function"
          ? globalThis.__TOTPSCAN_SCAN_PAGE__()
          : [],
    });
  } catch {
    frames = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () =>
        typeof globalThis.__TOTPSCAN_SCAN_PAGE__ === "function"
          ? globalThis.__TOTPSCAN_SCAN_PAGE__()
          : [],
    });
  }
  const items = [];
  const seen = new Set();
  for (const frame of frames) {
    if (!Array.isArray(frame.result)) {
      continue;
    }
    for (const item of frame.result) {
      if (!item || typeof item.text !== "string" || seen.has(item.text)) {
        continue;
      }
      seen.add(item.text);
      items.push({ ...item, frameId: frame.frameId ?? 0 });
    }
  }
  return items;
}

async function startScan() {
  if (state.scanBusy) {
    return;
  }
  const tab = await getActiveTab();
  if (!tab?.id || isRestrictedPage(tab.url)) {
    showToast(t("popup_scan_unsupported"), { kind: "error" });
    return;
  }
  setScanBusy(true);
  showScanningModal();
  try {
    const items = await collectPageQrCodes(tab);
    closeModal();
    if (items.length === 0) {
      openModal({
        title: t("popup_no_qr_title"),
        content: `<p class="modal-text">${escapeHtml(t("popup_no_qr_text"))}</p>
          <div class="notice">${icon("info", 16)}<span>${escapeHtml(t("popup_no_qr_notice"))}</span></div>`,
        actions: [
          { label: t("popup_rescan"), onClick: () => startScan() },
          { label: t("common_close") },
        ],
      });
      return;
    }
    if (items.length === 1) {
      await handleQrItem(items[0], tab);
      return;
    }
    openCandidatePicker(items, tab);
  } catch (error) {
    closeModal();
    openModal({
      title: t("popup_scan_failed_title"),
      content: `<p class="modal-text">${escapeHtml(error?.code ? errorText(error) : t("popup_scan_failed_fallback"))}</p>
        <div class="notice">${icon("warning", 16)}<span>${escapeHtml(t("popup_scan_failed_notice"))}</span></div>`,
      actions: [{ label: t("common_close") }],
    });
  } finally {
    setScanBusy(false);
  }
}

function describeQrItem(item) {
  const kind = detectQrKind(item.text);
  const labelKeys = {
    binding: ["popup_qr_binding_title", "popup_qr_binding_sub"],
    login: ["popup_qr_login_title", "popup_qr_login_sub"],
    otpauth: ["popup_qr_otpauth_title", "popup_qr_otpauth_sub"],
    migration: ["popup_qr_migration_title", "popup_qr_migration_sub"],
    unknown: ["popup_qr_unknown_title", "popup_qr_unknown_sub"],
  };
  const [titleKey, subtitleKey] = labelKeys[kind] ?? labelKeys.unknown;
  const title = t(titleKey);
  const subtitle = t(subtitleKey);
  let detail = "";
  try {
    if (kind === "binding") {
      const payload = JSON.parse(item.text);
      detail = `${String(payload.iss ?? t("popup_qr_unknown_issuer"))} · ${String(
        payload.acc ?? t("popup_qr_unknown_account"),
      )}`;
    } else if (kind === "login") {
      const payload = JSON.parse(item.text);
      const host = String(payload.url ?? "");
      detail = host ? t("popup_qr_target_site", { host }) : "";
    } else if (kind === "otpauth") {
      detail = t("popup_qr_otpauth_detail");
    } else if (kind === "migration") {
      detail = t("popup_qr_migration_detail");
    }
  } catch {
    detail = "";
  }
  return { kind, title, subtitle, detail };
}

function openCandidatePicker(items, tab) {
  const body = document.createElement("div");
  body.innerHTML = `<p class="sheet-lead">${escapeHtml(
    t("popup_choose_qr_lead", { count: items.length }),
  )}</p>
    <div class="candidate-list"></div>`;
  const list = body.querySelector(".candidate-list");
  items.forEach((item, index) => {
    const meta = describeQrItem(item);
    const button = document.createElement("button");
    button.type = "button";
    button.className = "candidate-item";
    button.innerHTML = `
      <div class="avatar" style="background:hsl(${(index * 47) % 360} 62% 52%)">${icon("qr", 16)}</div>
      <div class="candidate-main">
        <div class="candidate-title">${escapeHtml(meta.title)}</div>
        <div class="candidate-sub">${escapeHtml(meta.detail || meta.subtitle)}</div>
      </div>
      <span class="candidate-arrow">${icon("external", 14)}</span>
    `;
    button.addEventListener("click", async () => {
      closeModal();
      await handleQrItem(item, tab);
    });
    list.appendChild(button);
  });
  openModal({
    title: t("popup_choose_qr_title"),
    content: body,
    size: "wide",
    actions: [{ label: t("common_cancel") }],
  });
}

async function handleQrItem(item, tab) {
  const kind = detectQrKind(item.text);
  if (kind === "binding") {
    await handleBindingQr(item, tab);
    return;
  }
  if (kind === "login") {
    await handleLoginQr(item, tab);
    return;
  }
  if (kind === "otpauth") {
    handleOtpauthQr(item, tab);
    return;
  }
  if (kind === "migration") {
    openModal({
      title: t("popup_migration_title"),
      content: `<p class="modal-text">${escapeHtml(t("popup_migration_text"))}</p>`,
      actions: [
        { label: t("popup_open_options_page"), variant: "primary", onClick: () => chrome.runtime.openOptionsPage() },
        { label: t("common_cancel") },
      ],
    });
    return;
  }
  openModal({
    title: t("popup_unknown_qr_title"),
    content: `<p class="modal-text">${escapeHtml(t("popup_unknown_qr_text"))}</p>
      <div class="notice">${icon("info", 16)}<span>${escapeHtml(t("popup_unknown_qr_notice"))}</span></div>`,
    actions: [{ label: t("common_close") }],
  });
}

function protocolErrorMessage(error) {
  return errorText(error);
}

async function handleBindingQr(item, tab) {
  let parsed;
  try {
    parsed = await send("protocol:parse-binding", { rawText: item.text });
  } catch (error) {
    openModal({
      title: t("popup_binding_failed_title"),
      content: `<p class="modal-text">${escapeHtml(protocolErrorMessage(error))}</p>
        <div class="notice notice-warning">${icon("warning", 16)}<span>${escapeHtml(
          t("popup_no_data_written"),
        )}</span></div>`,
      actions: [{ label: t("common_close") }],
    });
    return;
  }
  const summary = parsed.summary;
  const siteHost = tabHostOf(tab) || state.siteHost;
  const body = document.createElement("div");
  body.innerHTML = `
    <div class="notice notice-accent">${icon("shield", 16)}<span>${escapeHtml(
      t("popup_binding_verified_notice"),
    )}</span></div>
    <div class="kv-list">
      <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_kv_issuer"))}</span><span class="kv-value">${escapeHtml(
        summary.issuer,
      )}</span></div>
      <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_kv_account"))}</span><span class="kv-value">${escapeHtml(
        summary.account,
      )}</span></div>
      <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_kv_submit_url"))}</span><span class="kv-value mono">${escapeHtml(
        summary.submitUrl,
      )}</span></div>
      <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_kv_algorithm"))}</span><span class="kv-value">${escapeHtml(
        t("popup_algorithm_summary", {
          algorithm: summary.algorithm,
          digits: summary.digits,
          period: summary.period,
        }),
      )}</span></div>
    </div>
    <div class="field">
      <label for="bindLabel">${escapeHtml(t("popup_local_note"))} <span class="optional">${escapeHtml(
        t("common_optional_local"),
      )}</span></label>
      <input class="input" id="bindLabel" maxlength="64" placeholder="${escapeHtml(
        t("popup_bind_note_placeholder"),
      )}" autocomplete="off" />
      <div class="field-error" id="bindError"></div>
    </div>
    <div class="field">
      <label for="bindSite">${escapeHtml(t("popup_bind_site_label"))} <span class="optional">${escapeHtml(
        t("common_optional"),
      )}</span></label>
      <input class="input" id="bindSite" maxlength="253" value="${escapeHtml(
        siteHost,
      )}" placeholder="${escapeHtml(t("popup_bind_site_placeholder"))}" autocomplete="off" spellcheck="false" />
      <div class="hint">${escapeHtml(t("popup_bind_site_hint"))}</div>
    </div>
  `;
  let saving = false;
  openModal({
    title: t("popup_confirm_bind_title"),
    subtitle: t("popup_confirm_bind_sub"),
    content: body,
    actions: [
      { label: t("common_cancel") },
      {
        label: t("popup_confirm_bind_action"),
        variant: "primary",
        keepOpen: true,
        onClick: async (close) => {
          if (saving) {
            return false;
          }
          saving = true;
          const label = body.querySelector("#bindLabel").value;
          try {
            const result = await send("account:add-scan", {
              rawText: item.text,
              label,
              siteHosts: [body.querySelector("#bindSite").value],
            });
            close();
            await refreshAccounts();
            if (result.confirm?.ok) {
              showToast(t("popup_bind_success"), { kind: "success" });
            } else {
              showToast(
                t("popup_bind_saved_confirm_failed", {
                  reason: result.confirm?.code
                    ? errorText({ code: result.confirm.code }, { status: result.confirm.status ?? 0 })
                    : t("common_unknown_reason"),
                }),
                {
                  kind: "error",
                  duration: 5200,
                },
              );
            }
          } catch (error) {
            const errorEl = body.querySelector("#bindError");
            if (errorEl) {
              errorEl.textContent = errorText(error);
            } else {
              showToast(errorText(error), { kind: "error" });
            }
          } finally {
            saving = false;
          }
          return false;
        },
      },
    ],
  });
}

async function handleLoginQr(item, tab) {
  let parsed;
  try {
    parsed = await send("protocol:parse-login", { rawText: item.text });
  } catch (error) {
    openModal({
      title: t("popup_login_unavailable_title"),
      content: `<p class="modal-text">${escapeHtml(protocolErrorMessage(error))}</p>
        <div class="notice">${icon("info", 16)}<span>${escapeHtml(t("popup_no_request_sent"))}</span></div>`,
      actions: [{ label: t("common_close") }],
    });
    return;
  }
  const payload = parsed.payload;
  const candidates = findScanCandidates(payload, state.accounts);
  if (candidates.length === 0) {
    openModal({
      title: t("popup_no_candidate_title"),
      content: `<p class="modal-text">${escapeHtml(t("popup_qr_submit_url_lead"))}</p>
        <div class="kv-list"><div class="kv-row"><span class="kv-key">${escapeHtml(
          t("popup_address"),
        )}</span><span class="kv-value mono">${escapeHtml(payload.url)}</span></div></div>
        <div class="notice notice-warning">${icon("shield", 16)}<span>${escapeHtml(
          t("popup_no_candidate_notice"),
        )}</span></div>`,
      actions: [{ label: t("common_close") }],
    });
    return;
  }
  if (candidates.length === 1) {
    await submitCandidate(candidates[0], payload, tab, item.frameId);
    return;
  }
  const body = document.createElement("div");
  body.innerHTML = `<p class="sheet-lead">${escapeHtml(
    t("popup_choose_login_lead", { count: candidates.length }),
  )}</p>
    <div class="candidate-list"></div>`;
  const list = body.querySelector(".candidate-list");
  for (const candidate of candidates) {
    const account = candidate.account;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "candidate-item";
    button.innerHTML = `
      <div class="avatar" style="${avatarStyle(account)}">${escapeHtml(accountInitial(account))}</div>
      <div class="candidate-main">
        <div class="candidate-title">${escapeHtml(account.issuer)} · ${escapeHtml(account.account)}</div>
        <div class="candidate-sub">${escapeHtml(formatDomain(account.submitUrl))}</div>
      </div>
      ${candidate.loose ? `<span class="badge badge-warning">${escapeHtml(t("popup_loose_match"))}</span>` : ""}
    `;
    button.addEventListener("click", async () => {
      closeModal();
      await submitCandidate(candidate, payload, tab, item.frameId);
    });
    list.appendChild(button);
  }
  openModal({
    title: t("popup_choose_login_title"),
    content: body,
    size: "wide",
    actions: [{ label: t("common_cancel") }],
  });
}

async function submitCandidate(candidate, payload, tab, frameId) {
  openModal({
    title: t("popup_submitting_title"),
    subtitle: t("popup_submitting_sub"),
    content: `<div class="scanning"><div class="spinner"></div><span>${escapeHtml(
      t("popup_submitting_text"),
    )}</span></div>`,
    dismissible: false,
  });
  try {
    const result = await send("scan:submit", {
      accountId: candidate.account.id,
      token: payload.token,
      tabId: tab?.id ?? null,
      frameId: Number.isInteger(frameId) ? frameId : 0,
    });
    if (result.ok) {
      openModal({
        title: t("popup_auth_success_title"),
        content: `<div class="scanning" style="padding-top:14px">
            <div style="width:46px;height:46px;border-radius:50%;display:grid;place-items:center;background:var(--success-soft);color:var(--success)">${icon(
              "check",
              24,
            )}</div>
            <span>${escapeHtml(
              t("popup_auth_success_text", { message: t("popup_auth_success_default") }),
            )}</span>
          </div>`,
        actions: [{ label: t("common_done"), variant: "primary" }],
      });
    } else {
      openModal({
        title: t("popup_auth_failed_title"),
        content: `<p class="modal-text">${escapeHtml(errorText({ code: result.code }, { status: result.status ?? 0 }))}</p>
          <div class="notice">${icon("info", 16)}<span>${escapeHtml(t("popup_auth_failed_notice"))}</span></div>`,
        actions: [{ label: t("common_close") }],
      });
    }
  } catch (error) {
    openModal({
      title: t("popup_submit_failed_title"),
      content: `<p class="modal-text">${escapeHtml(errorText(error))}</p>
        <div class="notice notice-warning">${icon("warning", 16)}<span>${escapeHtml(
          t("popup_submit_failed_notice"),
        )}</span></div>`,
      actions: [{ label: t("common_close") }],
    });
  }
}

function handleOtpauthQr(item, tab) {
  let parsed;
  try {
    parsed = parseOtpauthUri(item.text);
  } catch (error) {
    openModal({
      title: t("popup_otpauth_failed_title"),
      content: `<p class="modal-text">${escapeHtml(error?.code ? errorText(error) : t("error_UNKNOWN"))}</p>
        <div class="notice notice-warning">${icon("warning", 16)}<span>${escapeHtml(
          t("popup_secret_hidden_notice"),
        )}</span></div>`,
      actions: [{ label: t("common_close") }],
    });
    return;
  }
  const siteHost = tabHostOf(tab) || state.siteHost;
  const body = document.createElement("div");
  body.innerHTML = `
      <div class="kv-list">
        <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_kv_issuer"))}</span><span class="kv-value">${escapeHtml(
          parsed.issuer,
        )}</span></div>
        <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_kv_account"))}</span><span class="kv-value">${escapeHtml(
          parsed.account,
        )}</span></div>
        <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_kv_algorithm"))}</span><span class="kv-value">${escapeHtml(
          t("popup_algorithm_summary", {
            algorithm: parsed.algorithm,
            digits: parsed.digits,
            period: parsed.period,
          }),
        )}</span></div>
      </div>
      ${
        parsed.weak
          ? `<div class="notice notice-warning">${icon("warning", 16)}<span>${escapeHtml(
              t("popup_weak_secret"),
            )}</span></div>`
          : ""
      }
      <div class="notice">${icon("info", 16)}<span>${escapeHtml(t("popup_standard_notice"))}</span></div>
      <div class="field">
        <label for="otpauthSite">${escapeHtml(t("popup_bind_site_label"))} <span class="optional">${escapeHtml(
          t("common_optional"),
        )}</span></label>
        <input class="input" id="otpauthSite" maxlength="253" value="${escapeHtml(
          siteHost,
        )}" placeholder="${escapeHtml(t("popup_bind_site_placeholder"))}" autocomplete="off" spellcheck="false" />
        <div class="hint">${escapeHtml(t("popup_bind_site_hint"))}</div>
      </div>
    `;
  openModal({
    title: t("popup_add_standard_title"),
    subtitle: t("popup_add_standard_sub"),
    content: body,
    actions: [
      { label: t("common_cancel") },
      {
        label: t("popup_add_account"),
        variant: "primary",
        onClick: async () => {
          try {
            await send("account:add-standard", {
              input: {
                issuer: parsed.issuer,
                account: parsed.account,
                secret: parsed.secret,
                algorithm: parsed.algorithm,
                digits: parsed.digits,
                period: parsed.period,
                label: "",
                siteHosts: [body.querySelector("#otpauthSite").value],
              },
            });
            await refreshAccounts();
            showToast(t("popup_account_added"), { kind: "success" });
          } catch (error) {
            showToast(errorText(error), { kind: "error" });
          }
        },
      },
    ],
  });
}

function showScanAccountDetail(account) {
  openModal({
    title: t("popup_scan_account_title"),
    subtitle: t("popup_scan_account_sub"),
    content: `
      <div class="kv-list">
        <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_kv_issuer"))}</span><span class="kv-value">${escapeHtml(
          account.issuer,
        )}</span></div>
        <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_kv_account"))}</span><span class="kv-value">${escapeHtml(
          account.account,
        )}</span></div>
        <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_kv_submit_url"))}</span><span class="kv-value mono">${escapeHtml(
          account.submitUrl ?? "",
        )}</span></div>
        <div class="kv-row"><span class="kv-key">${escapeHtml(t("popup_binding_status"))}</span><span class="kv-value">${escapeHtml(
          t(account.status === "confirmed" ? "popup_confirmed" : "popup_unconfirmed"),
        )}</span></div>
      </div>
      <div class="notice notice-warning">${icon("warning", 16)}<span>${escapeHtml(
        t("popup_scan_binding_notice"),
      )}</span></div>
    `,
    actions: [
      {
        label: t("popup_reconfirm"),
        variant: "primary",
        keepOpen: true,
        onClick: async (close) => {
          try {
            const result = await send("account:confirm", { id: account.id });
            if (result.ok) {
              close();
              await refreshAccounts();
              showToast(t("popup_binding_confirmed"), { kind: "success" });
            } else {
              showToast(errorText({ code: result.code }), { kind: "error", duration: 4200 });
            }
          } catch (error) {
            showToast(errorText(error), { kind: "error" });
          }
          return false;
        },
      },
      { label: t("common_close") },
    ],
  });
}

function openOptions(hash = "") {
  const url = chrome.runtime.getURL(`options/options.html${hash}`);
  chrome.tabs.create({ url });
}

function bindEvents() {
  themeToggle.addEventListener("click", cycleTheme);
  openOptionsButton.addEventListener("click", () => openOptions());
  emptyAddButton.addEventListener("click", () => openOptions("#add"));
  scanFab.addEventListener("click", startScan);
  searchInput.addEventListener("input", () => {
    state.searchQuery = searchInput.value;
    render();
  });
  searchInput.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.preventDefault();
      clearSearch({ focus: true });
    }
  });
  searchClear.addEventListener("click", () => clearSearch({ focus: true }));
  searchEmptyClear.addEventListener("click", () => clearSearch({ focus: true }));
  siteOnlyBtn.addEventListener("click", () => {
    state.siteOnly = true;
    render();
  });
  siteAllBtn.addEventListener("click", () => {
    state.siteOnly = false;
    render();
  });
  editListButton.addEventListener("click", () => {
    if (state.accounts.length === 0) {
      return;
    }
    if (state.searchQuery) {
      clearSearch();
    }
    state.editMode = !state.editMode;
    render();
  });
  attachSortable({
    container: listEl,
    itemSelector: ".account-card",
    handleSelector: ".drag-handle",
    canStart: () => state.editMode,
    onReorder: applyOrder,
  });
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") {
      return;
    }
    if (changes["totpscan.accounts"]) {
      refreshAccounts();
    }
    const nextSettings = changes["totpscan.settings"]?.newValue;
    if (!nextSettings) {
      return;
    }
    const wasEnabled = state.settings?.showScanCodes === true;
    const nowEnabled = nextSettings.showScanCodes === true;
    state.settings = { ...state.settings, ...nextSettings };
    if (wasEnabled === nowEnabled) {
      return;
    }
    if (!nowEnabled) {
      for (const account of state.accounts) {
        if (account.type === "scan") {
          state.codes.delete(account.id);
        }
      }
    }
    // 关闭时立即重建卡片，码与已渲染的 DOM 一并移除。
    render();
    if (nowEnabled) {
      refreshCodes();
    }
  });
}

async function init() {
  await initI18n();
  state.settings = await initTheme();
  updateThemeButton();
  openOptionsButton.innerHTML = icon("settings", 17);
  searchClear.innerHTML = icon("close", 13);
  try {
    state.siteHost = tabHostOf(await getActiveTab());
  } catch {
    state.siteHost = "";
  }
  bindEvents();
  window.addEventListener("i18n:changed", () => {
    updateEditButton();
    render();
  });
  await refreshAccounts();
  setInterval(tick, 250);
}

init().catch((error) => {
  loadingEl.innerHTML = `<span>${escapeHtml(t("common_init_failed", { message: errorText(error) }))}</span>`;
});
