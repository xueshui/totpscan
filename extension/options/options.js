/** 设置页：账户管理、外观、备份导出/导入预览与安全说明。 */

import {
  initTheme,
  saveSettings,
  applyTheme,
  THEME_PRESETS,
  THEME_MODE_KEYS,
  normalizeColor,
  resolveAccent,
} from "../common/settings.js";
import {
  initI18n,
  t,
  hasMessage,
  applyI18n,
  changeLanguage,
  browserUiLanguage,
  resolveLocale,
  formatDate,
  LOCALE_LABELS,
  LANGUAGE_OPTIONS,
} from "../common/i18n.js";
import { parseOtpauthUri } from "../common/otpauth.js";
import { openQrExport } from "../common/qr-export.js";
import { analyzeImportText } from "../common/import.js";
import { normalizeSiteHost } from "../common/site-filter.js";
import {
  icon,
  escapeHtml,
  showToast,
  openModal,
  closeModal,
  confirmDialog,
  openContextMenu,
  attachSortable,
  initialsOf,
  hueFromString,
  formatDomain,
} from "../common/ui.js";

const state = {
  settings: null,
  accounts: [],
  import: {
    rows: [],
    failures: [],
    selected: new Set(),
    meta: null,
    raw: "",
  },
};

/** 后台错误码 → 当前语言；未知错误码不显示可能为中文的原文。 */
function errorText(error, vars) {
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

/* ------------------------------- 标签页切换 ------------------------------- */

const TAB_NAMES = ["accounts", "appearance", "backup", "security"];

function switchTab(name) {
  const target = TAB_NAMES.includes(name) ? name : "accounts";
  for (const tab of document.querySelectorAll(".tab")) {
    const active = tab.dataset.tab === target;
    tab.classList.toggle("is-active", active);
    tab.setAttribute("aria-selected", String(active));
  }
  for (const panel of document.querySelectorAll(".tab-panel")) {
    const active = panel.id === `panel-${target}`;
    panel.classList.toggle("is-active", active);
    panel.hidden = !active;
  }
  if (target === "backup") {
    renderBackupWarning();
  }
}

/* -------------------------------- 账户列表 -------------------------------- */

function avatarStyle(account) {
  const hue = hueFromString(`${account.issuer}|${account.account}`);
  return `background:linear-gradient(140deg, hsl(${hue} 76% 62%), hsl(${hue + 12} 72% 46%))`;
}

function statusBadge(account) {
  if (account.type !== "scan") {
    return `<span class="badge badge-muted">${escapeHtml(t("options_badge_standard"))}</span>`;
  }
  if (account.status === "confirmed") {
    return `<span class="badge badge-accent">${escapeHtml(t("options_badge_scan_confirmed"))}</span>`;
  }
  if (account.status === "failed") {
    return `<span class="badge badge-danger">${escapeHtml(t("options_badge_scan_failed"))}</span>`;
  }
  return `<span class="badge badge-warning">${escapeHtml(t("options_badge_scan_pending"))}</span>`;
}

function renderAccounts() {
  const container = document.getElementById("accountsContainer");
  if (state.accounts.length === 0) {
    container.innerHTML = `
      <div class="empty-accounts">
        <strong>${escapeHtml(t("options_empty_title"))}</strong>
        <span>${escapeHtml(t("options_empty_text"))}</span>
      </div>
    `;
    return;
  }
  const rows = state.accounts.map((account) => {
    const labelLine = account.label
      ? `<div class="account-row-label">${escapeHtml(t("options_label_prefix", { label: account.label }))}</div>`
      : "";
    const sites = Array.isArray(account.siteHosts) ? account.siteHosts : [];
    const sitesLine = sites.length
      ? `<div class="account-row-sites">${sites
          .map((host) => `<span class="meta-chip">${escapeHtml(host)}</span>`)
          .join("")}</div>`
      : "";
    const weakBadge = account.weak
      ? `<span class="badge badge-warning">${escapeHtml(t("options_badge_short_secret"))}</span>`
      : "";
    const pinBadge = account.pinned
      ? `<span class="badge badge-accent">${escapeHtml(t("options_badge_pinned"))}</span>`
      : "";
    const urlLine =
      account.type === "scan"
        ? `<div class="account-row-url" title="${escapeHtml(account.submitUrl ?? "")}">${escapeHtml(
            account.submitUrl ?? "",
          )}</div>`
        : "";
    const retryButton =
      account.type === "scan"
        ? `<button class="action-link" data-action="confirm" data-id="${account.id}" type="button">${escapeHtml(
            t("options_retry_confirm"),
          )}</button>`
        : "";
    return `
      <div class="account-row" data-id="${account.id}">
        <button class="drag-handle" type="button" data-drag-handle title="${escapeHtml(
          t("options_drag_title"),
        )}" aria-label="${escapeHtml(
          t("options_drag_aria", { name: account.label || `${account.issuer} ${account.account}` }),
        )}">${icon("grip", 16)}</button>
        <div class="avatar" style="${avatarStyle(account)}">${escapeHtml(
          initialsOf(account.label || account.issuer || account.account),
        )}</div>
        <div class="account-row-main">
          <div class="account-row-title">
            <span class="issuer">${escapeHtml(account.issuer)}</span>
            <span class="account">${escapeHtml(account.account)}</span>
            ${statusBadge(account)}
            ${pinBadge}
            ${weakBadge}
          </div>
          ${labelLine}
          ${sitesLine}
          <div class="account-row-meta">
            <span class="meta-chip">${escapeHtml(account.algorithm)}</span>
            <span class="meta-chip">${escapeHtml(t("options_digits_chip", { digits: account.digits }))}</span>
            <span class="meta-chip">${escapeHtml(t("options_period_chip", { period: account.period }))}</span>
            <span>${escapeHtml(t("options_added_at", { date: formatDate(account.createdAt) }))}</span>
          </div>
          ${urlLine}
        </div>
        <div class="account-row-actions">
          ${retryButton}
          <button class="action-link" data-action="qrcode" data-id="${account.id}" type="button">${escapeHtml(
            t("qr_export_menu"),
          )}</button>
          <button class="action-link" data-action="pin" data-id="${account.id}" type="button">${escapeHtml(
            t(account.pinned ? "popup_unpin" : "popup_pin"),
          )}</button>
          <button class="action-link" data-action="sites" data-id="${account.id}" type="button">${escapeHtml(
            t("options_edit_sites"),
          )}</button>
          <button class="action-link" data-action="label" data-id="${account.id}" type="button">${escapeHtml(
            t("options_edit_note"),
          )}</button>
          <button class="action-link danger" data-action="delete" data-id="${account.id}" type="button">${escapeHtml(
            t("options_delete"),
          )}</button>
          <button class="icon-button subtle row-more" data-action="menu" data-id="${account.id}" type="button" title="${escapeHtml(
            t("common_more_actions"),
          )}" aria-label="${escapeHtml(
            t("popup_more_for", { name: account.label || `${account.issuer} ${account.account}` }),
          )}">${icon("more", 15)}</button>
        </div>
      </div>
    `;
  });
  container.innerHTML = rows.join("");
}

async function reloadAccounts() {
  try {
    state.accounts = await send("accounts:list");
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
    state.accounts = [];
  }
  renderAccounts();
  renderBackupWarning();
}

async function editLabel(account) {
  const body = document.createElement("div");
  body.innerHTML = `
    <div class="field">
      <label for="labelInput">${escapeHtml(t("popup_local_note"))} <span class="optional">${escapeHtml(
        t("common_optional_local"),
      )}</span></label>
      <input class="input" id="labelInput" maxlength="64" value="${escapeHtml(account.label ?? "")}" autocomplete="off" />
      <div class="field-error" id="labelError"></div>
    </div>
    <div class="hint">${escapeHtml(t("options_label_hint"))}</div>
  `;
  openModal({
    title: t("options_edit_label_title"),
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
            await send("account:update-label", { id: account.id, label: body.querySelector("#labelInput").value });
            close();
            await reloadAccounts();
            showToast(t("options_note_saved"), { kind: "success" });
          } catch (error) {
            body.querySelector("#labelError").textContent = errorText(error);
          }
          return false;
        },
      },
    ],
  });
}

/** 把输入框里的域名列表拆开并逐个规范化；非法值抛 BAD_SITE_HOST。 */
function parseSiteHostsInput(value) {
  const parts = String(value ?? "")
    .split(/[\s,;，；]+/)
    .filter(Boolean);
  const hosts = [];
  for (const part of parts) {
    const host = normalizeSiteHost(part);
    if (host && !hosts.includes(host)) {
      hosts.push(host);
    }
  }
  return hosts;
}

/** 编辑账户的站点域名：可增可删，保存后仅影响弹窗展示排序。 */
function editSiteHosts(account) {
  const body = document.createElement("div");
  body.innerHTML = `
    <div class="field">
      <label for="siteHostInput">${escapeHtml(t("options_field_sites"))}</label>
      <div class="site-tag-input">
        <input class="input" id="siteHostInput" maxlength="253" placeholder="${escapeHtml(
          t("options_field_sites_placeholder"),
        )}" autocomplete="off" spellcheck="false" />
        <button class="btn btn-secondary btn-sm" id="siteHostAdd" type="button">${escapeHtml(
          t("options_sites_add"),
        )}</button>
      </div>
      <div class="site-tag-list" id="siteTagList"></div>
      <div class="field-error" id="siteError"></div>
      <div class="hint">${escapeHtml(t("options_sites_hint"))}</div>
    </div>
  `;
  const input = body.querySelector("#siteHostInput");
  const tagList = body.querySelector("#siteTagList");
  const errorEl = body.querySelector("#siteError");
  const hosts = Array.isArray(account.siteHosts) ? [...account.siteHosts] : [];

  const renderTags = () => {
    if (hosts.length === 0) {
      tagList.innerHTML = `<span class="site-tag-empty">${escapeHtml(t("options_sites_empty"))}</span>`;
      return;
    }
    tagList.innerHTML = hosts
      .map(
        (host) => `<span class="site-tag">${escapeHtml(host)}<button class="site-tag-remove" type="button" data-host="${escapeHtml(
          host,
        )}" aria-label="${escapeHtml(t("options_sites_remove", { host }))}" title="${escapeHtml(
          t("options_sites_remove", { host }),
        )}">${icon("close", 12)}</button></span>`,
      )
      .join("");
  };

  const addHost = () => {
    errorEl.textContent = "";
    try {
      const parsed = parseSiteHostsInput(input.value);
      for (const host of parsed) {
        if (!hosts.includes(host)) {
          hosts.push(host);
        }
      }
      input.value = "";
      renderTags();
    } catch (error) {
      errorEl.textContent = errorText(error);
    }
  };

  body.querySelector("#siteHostAdd").addEventListener("click", addHost);
  input.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      addHost();
    }
  });
  tagList.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-host]");
    if (!button) {
      return;
    }
    const index = hosts.indexOf(button.dataset.host);
    if (index >= 0) {
      hosts.splice(index, 1);
      renderTags();
    }
  });
  renderTags();

  openModal({
    title: t("options_edit_sites_title"),
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
            await send("account:update-sites", { id: account.id, siteHosts: hosts });
            close();
            await reloadAccounts();
            showToast(t("options_sites_saved"), { kind: "success" });
          } catch (error) {
            errorEl.textContent = errorText(error);
          }
          return false;
        },
      },
    ],
  });
}

async function deleteAccountRow(account) {
  const name = account.label
    ? t("options_name_with_label", { label: account.label, issuer: account.issuer, account: account.account })
    : `${account.issuer} · ${account.account}`;
  const message = [
    t("options_delete_message", { name }),
    account.type === "scan" ? t("options_delete_scan_note") : "",
  ]
    .filter(Boolean)
    .join("\n");
  const ok = await confirmDialog({
    title: t("options_delete_title"),
    message,
    confirmText: t("options_confirm_delete"),
    cancelText: t("common_cancel"),
    danger: true,
  });
  if (!ok) {
    return;
  }
  try {
    await send("account:delete", { id: account.id });
    await reloadAccounts();
    showToast(t("options_deleted"), { kind: "success" });
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
  }
}

async function togglePin(account) {
  try {
    await send("account:pin", { id: account.id, pinned: !account.pinned });
    await reloadAccounts();
    showToast(t(account.pinned ? "options_unpinned" : "options_pinned"), { duration: 1600 });
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
  }
}

async function applyOrder(ids) {
  const byId = new Map(state.accounts.map((account) => [account.id, account]));
  state.accounts = ids.map((id) => byId.get(id)).filter(Boolean);
  try {
    await send("account:reorder", { ids });
    showToast(t("options_order_saved"), { duration: 1400 });
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
    await reloadAccounts();
  }
}

function openAccountMenu(account, x, y) {
  openContextMenu({
    x,
    y,
    label: t("common_account_actions", { name: `${account.issuer} · ${account.account}` }),
    items: [
      { label: t("options_edit_note"), icon: "page", onSelect: () => editLabel(account) },
      { label: t("options_edit_sites"), icon: "page", onSelect: () => editSiteHosts(account) },
      {
        label: t(account.pinned ? "popup_unpin" : "popup_pin"),
        icon: account.pinned ? "pinOff" : "pin",
        onSelect: () => togglePin(account),
      },
      account.type === "scan"
        ? { label: t("options_retry_binding"), icon: "refresh", onSelect: () => retryConfirm(account) }
        : null,
      { label: t("qr_export_menu"), icon: "qr", onSelect: () => exportAccountQr(account) },
      { label: t("popup_delete_account"), icon: "trash", danger: true, onSelect: () => deleteAccountRow(account) },
    ].filter(Boolean),
  });
}

async function retryConfirm(account) {
  try {
    const result = await send("account:confirm", { id: account.id });
    await reloadAccounts();
    showToast(
      result.ok
        ? t("popup_binding_confirmed")
        : errorText({ code: result.code }, { status: result.status ?? 0 }),
      {
        kind: result.ok ? "success" : "error",
        duration: result.ok ? 2600 : 4400,
      },
    );
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
  }
}

/* ---------------------------- 单账户二维码导出 ---------------------------- */

function exportAccountQr(account) {
  return openQrExport({
    account,
    getUri: async () => (await send("account:otpauth-uri", { id: account.id })).uri,
    errorText,
  });
}

/* ------------------------- 扫码型账户动态码显示开关 ------------------------- */

const scanCodesToggle = document.getElementById("showScanCodesToggle");

function renderShowScanCodes() {
  if (!scanCodesToggle) {
    return;
  }
  const enabled = state.settings?.showScanCodes === true;
  scanCodesToggle.setAttribute("aria-checked", String(enabled));
  scanCodesToggle.setAttribute("aria-label", t("options_show_scan_codes_toggle"));
  scanCodesToggle.title = t("options_show_scan_codes_toggle");
}

function confirmEnableScanCodes() {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (!settled) {
        settled = true;
        resolve(value);
      }
    };

    const body = document.createElement("div");
    body.innerHTML = `
      <p class="modal-text">${escapeHtml(t("options_scan_codes_confirm_message"))}</p>
      <label class="risk-check">
        <input type="checkbox" data-scan-risk-ack />
        <span>${escapeHtml(t("options_scan_codes_ack"))}</span>
      </label>
      <p class="field-error" data-scan-risk-error hidden></p>
    `;
    const checkbox = body.querySelector("[data-scan-risk-ack]");
    const errorEl = body.querySelector("[data-scan-risk-error]");

    openModal({
      title: t("options_scan_codes_confirm_title"),
      content: body,
      actions: [
        { label: t("common_cancel"), onClick: () => finish(false) },
        {
          label: t("common_confirm"),
          variant: "danger",
          keepOpen: true,
          onClick: (close) => {
            if (!checkbox.checked) {
              errorEl.textContent = t("options_scan_codes_risk_unchecked");
              errorEl.hidden = false;
              return false;
            }
            finish(true);
            close();
            return false;
          },
        },
      ],
      onClose: () => finish(false),
    });
  });
}

async function toggleShowScanCodes() {
  if (state.settings?.showScanCodes === true) {
    state.settings = await saveSettings({ showScanCodes: false });
    renderShowScanCodes();
    showToast(t("options_scan_codes_disabled"), { duration: 2200 });
    return;
  }
  const allowed = await confirmEnableScanCodes();
  if (!allowed) {
    return;
  }
  state.settings = await saveSettings({ showScanCodes: true });
  renderShowScanCodes();
  showToast(t("options_scan_codes_enabled"), { kind: "success", duration: 2600 });
}

/* -------------------------------- 添加账户 -------------------------------- */

function openManualModal() {
  const body = document.createElement("div");
  body.innerHTML = `
    <div class="manual-grid">
      <div class="field">
        <label for="manualIssuer">${escapeHtml(t("options_field_issuer"))} <span class="optional">${escapeHtml(
          t("common_optional"),
        )}</span></label>
        <input class="input" id="manualIssuer" maxlength="64" placeholder="${escapeHtml(
          t("options_field_issuer_placeholder"),
        )}" autocomplete="off" />
      </div>
      <div class="field">
        <label for="manualAccount">${escapeHtml(t("options_field_account"))} <span class="optional">${escapeHtml(
          t("common_optional"),
        )}</span></label>
        <input class="input" id="manualAccount" maxlength="255" placeholder="${escapeHtml(
          t("options_field_account_placeholder"),
        )}" autocomplete="off" />
      </div>
      <div class="field full">
        <label for="manualSecret">${escapeHtml(t("options_field_secret"))}</label>
        <input class="input secret-input" id="manualSecret" placeholder="${escapeHtml(
          t("options_field_secret_placeholder"),
        )}" autocomplete="off" spellcheck="false" />
        <div class="hint">${escapeHtml(t("options_secret_hint"))}</div>
      </div>
      <div class="field">
        <label for="manualAlgorithm">${escapeHtml(t("options_field_algorithm"))}</label>
        <select class="select" id="manualAlgorithm">
          <option value="SHA1">SHA1</option>
          <option value="SHA256">SHA256</option>
          <option value="SHA512">SHA512</option>
        </select>
      </div>
      <div class="field">
        <label for="manualDigits">${escapeHtml(t("options_field_digits"))}</label>
        <select class="select" id="manualDigits">
          <option value="6">${escapeHtml(t("options_digits_chip", { digits: 6 }))}</option>
          <option value="8">${escapeHtml(t("options_digits_chip", { digits: 8 }))}</option>
        </select>
      </div>
      <div class="field">
        <label for="manualPeriod">${escapeHtml(t("options_field_period"))}</label>
        <input class="input" id="manualPeriod" type="number" min="1" max="3600" value="30" />
      </div>
      <div class="field">
        <label for="manualLabel">${escapeHtml(t("options_field_note"))} <span class="optional">${escapeHtml(
          t("common_optional"),
        )}</span></label>
        <input class="input" id="manualLabel" maxlength="64" placeholder="${escapeHtml(
          t("options_note_placeholder"),
        )}" autocomplete="off" />
      </div>
      <div class="field full">
        <label for="manualSites">${escapeHtml(t("options_field_sites"))} <span class="optional">${escapeHtml(
          t("common_optional"),
        )}</span></label>
        <input class="input" id="manualSites" maxlength="512" placeholder="${escapeHtml(
          t("options_field_sites_placeholder"),
        )}" autocomplete="off" spellcheck="false" />
        <div class="hint">${escapeHtml(t("options_sites_hint"))}</div>
      </div>
      <div class="field-error full" id="manualError"></div>
    </div>
    <div class="notice">${icon("lock", 16)}<span>${escapeHtml(t("options_manual_notice"))}</span></div>
  `;
  openModal({
    title: t("options_manual_title"),
    subtitle: t("options_manual_sub"),
    content: body,
    size: "wide",
    actions: [
      { label: t("common_cancel") },
      {
        label: t("popup_add_account"),
        variant: "primary",
        keepOpen: true,
        onClick: async (close) => {
          const errorEl = body.querySelector("#manualError");
          errorEl.textContent = "";
          try {
            await send("account:add-standard", {
              input: {
                issuer: body.querySelector("#manualIssuer").value,
                account: body.querySelector("#manualAccount").value,
                secret: body.querySelector("#manualSecret").value,
                algorithm: body.querySelector("#manualAlgorithm").value,
                digits: Number(body.querySelector("#manualDigits").value),
                period: Number(body.querySelector("#manualPeriod").value),
                label: body.querySelector("#manualLabel").value,
                siteHosts: parseSiteHostsInput(body.querySelector("#manualSites").value),
              },
            });
            close();
            await reloadAccounts();
            showToast(t("popup_account_added"), { kind: "success" });
          } catch (error) {
            errorEl.textContent = errorText(error);
          }
          return false;
        },
      },
    ],
  });
}

function openUriModal() {
  const body = document.createElement("div");
  body.innerHTML = `
    <div class="field">
      <label for="uriInput">${escapeHtml(t("options_add_uri"))}</label>
      <textarea class="textarea secret-input" id="uriInput" placeholder="otpauth://totp/Example:alice@example.com?secret=...&issuer=Example" spellcheck="false"></textarea>
      <div class="hint">${escapeHtml(t("options_uri_hint"))}</div>
    </div>
    <div class="field-error" id="uriError"></div>
  `;
  openModal({
    title: t("options_uri_title"),
    subtitle: t("options_uri_sub"),
    content: body,
    actions: [
      { label: t("common_cancel") },
      {
        label: t("options_parse_preview"),
        variant: "primary",
        keepOpen: true,
        onClick: async (close) => {
          const uri = body.querySelector("#uriInput").value.trim();
          const errorEl = body.querySelector("#uriError");
          errorEl.textContent = "";
          if (!uri) {
            errorEl.textContent = t("options_uri_required");
            return false;
          }
          try {
            const parsed = parseOtpauthUri(uri);
            close();
            showOtpauthPreview(parsed);
          } catch (error) {
            errorEl.textContent = error.code ? errorText(error) : t("error_UNKNOWN");
          }
          return false;
        },
      },
    ],
  });
}

function showOtpauthPreview(parsed) {
  openModal({
    title: t("options_preview_title"),
    content: `
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
    `,
    actions: [
      { label: t("common_cancel") },
      {
        label: t("common_add"),
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
              },
            });
            await reloadAccounts();
            showToast(t("popup_account_added"), { kind: "success" });
          } catch (error) {
            showToast(errorText(error), { kind: "error" });
          }
        },
      },
    ],
  });
}

/* --------------------------------- 外观 --------------------------------- */

function renderSwatches() {
  const container = document.getElementById("swatches");
  container.innerHTML = "";
  for (const preset of THEME_PRESETS) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "swatch";
    button.style.background = preset.color;
    button.style.setProperty("--swatch-color", preset.color);
    const name = t(preset.nameKey);
    button.title = name;
    button.setAttribute("aria-label", t("options_use_preset", { name }));
    if (state.settings.themeId === preset.id) {
      button.classList.add("is-selected");
      button.innerHTML = `<span class="swatch-check">${icon("check", 14)}</span>`;
    }
    button.addEventListener("click", async () => {
      state.settings = await saveSettings({ themeId: preset.id });
      applyTheme(state.settings);
      renderAppearance();
      showToast(t("options_preset_applied", { name }), { duration: 1600 });
    });
    container.appendChild(button);
  }
}

function renderLanguageOptions() {
  const select = document.getElementById("languageSelect");
  const uiLanguage = browserUiLanguage();
  const effective = resolveLocale("auto", uiLanguage);
  select.innerHTML = LANGUAGE_OPTIONS.map((option) => {
    if (option === "auto") {
      return `<option value="auto">${escapeHtml(
        t("options_language_auto", { language: LOCALE_LABELS[effective] }),
      )}</option>`;
    }
    return `<option value="${option}">${escapeHtml(LOCALE_LABELS[option])}</option>`;
  }).join("");
  select.value = state.settings.language;
  document.getElementById("languageHint").textContent = t("options_language_current", {
    language: LOCALE_LABELS[resolveLocale(state.settings.language, uiLanguage)],
  });
}

function renderAppearance() {
  renderSwatches();
  const color = resolveAccent(state.settings);
  const colorInput = document.getElementById("customColor");
  const hexInput = document.getElementById("customHex");
  colorInput.value = color.toLowerCase();
  hexInput.value = color.toUpperCase();
  for (const button of document.querySelectorAll("#modeSegmented button")) {
    const active = button.dataset.mode === state.settings.themeMode;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-checked", String(active));
  }
  const preset = THEME_PRESETS.find((item) => item.id === state.settings.themeId);
  document.getElementById("themeHint").textContent = preset
    ? t("options_theme_hint_preset", { name: t(preset.nameKey) })
    : t("options_theme_hint_custom", { color: color.toUpperCase() });
  document.getElementById("modeHint").textContent =
    state.settings.themeMode === "auto"
      ? t("options_mode_hint_auto")
      : t("options_mode_hint_fixed", { mode: t(THEME_MODE_KEYS[state.settings.themeMode]) });
  renderLanguageOptions();
}

async function applyCustomColor(value) {
  const color = normalizeColor(value, "");
  if (!color) {
    showToast(t("options_invalid_color"), { kind: "error" });
    return;
  }
  state.settings = await saveSettings({ themeId: "custom", customColor: color });
  applyTheme(state.settings);
  renderAppearance();
  showToast(t("options_custom_applied"), { duration: 1800 });
}

async function applyLanguage(setting) {
  state.settings = await saveSettings({ language: setting });
  await changeLanguage(setting);
  renderAppearance();
}

/* -------------------------------- 备份导出 -------------------------------- */

function downloadFile(filename, content, mime) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 15000);
}

function renderBackupWarning() {
  const element = document.getElementById("backupScanWarning");
  if (!element) {
    return;
  }
  const scanCount = state.accounts.filter((account) => account.type === "scan").length;
  element.textContent =
    scanCount > 0
      ? t("options_backup_warning_scan", { count: scanCount })
      : t("options_backup_warning_plain");
}

/** 口令强度：仅用于界面提示，不做强制策略。 */
function passwordStrength(password) {
  if (!password) {
    return { label: t("options_strength_none"), tone: "muted" };
  }
  let score = 0;
  if (password.length >= 8) score += 1;
  if (password.length >= 12) score += 1;
  if (password.length >= 16) score += 1;
  if (/[a-z]/.test(password) && /[A-Z]/.test(password)) score += 1;
  if (/\d/.test(password)) score += 1;
  if (/[^A-Za-z0-9]/.test(password)) score += 1;
  if (score <= 2) return { label: t("options_strength_weak"), tone: "weak" };
  if (score <= 4) return { label: t("options_strength_medium"), tone: "medium" };
  return { label: t("options_strength_strong"), tone: "strong" };
}

/** 明文 JSON 导出确认：文件含密钥但不需要口令，文案不再提「口令」。 */
function confirmPlaintextExport(scanCount) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (!settled) {
        settled = true;
        resolve(value);
      }
    };
    const body = document.createElement("div");
    body.innerHTML = `
      <div class="notice notice-danger">${icon("warning", 18)}<span>${escapeHtml(
        t("options_plain_export_notice"),
      )}</span></div>
      <p class="modal-text">${escapeHtml(
        [
          t("options_plain_export_count", { count: state.accounts.length }),
          scanCount > 0 ? t("options_plain_export_scan_note", { count: scanCount }) : "",
        ]
          .filter(Boolean)
          .join(" "),
      )}</p>
      <label class="risk-check"><input type="checkbox" id="riskAck" /> ${escapeHtml(t("options_risk_ack_plain"))}</label>
      <div class="field-error" id="riskError"></div>
    `;
    openModal({
      title: t("options_plain_export_title"),
      subtitle: t("options_plain_export_sub"),
      content: body,
      dismissible: false,
      actions: [
        { label: t("common_cancel"), onClick: () => finish(false) },
        {
          label: t("options_export_plain_action"),
          variant: "danger",
          keepOpen: true,
          onClick: (close) => {
            if (!body.querySelector("#riskAck").checked) {
              body.querySelector("#riskError").textContent = t("options_risk_unchecked");
              return false;
            }
            finish(true);
            close();
            return false;
          },
        },
      ],
      onClose: () => finish(false),
    });
  });
}

/** 加密导出：同一个弹窗内完成风险确认 + 设置口令 + 二次确认，选中即可输入。 */
function promptExportPassword(scanCount) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (!settled) {
        settled = true;
        resolve(value);
      }
    };
    const body = document.createElement("div");
    body.innerHTML = `
      <div class="notice notice-danger">${icon("warning", 18)}<span><strong>${escapeHtml(
        t("options_backup_warning_plain"),
      )}</strong>${
        scanCount > 0 ? escapeHtml(t("options_plain_export_scan_note", { count: scanCount })) : ""
      }</span></div>
      <label class="risk-check"><input type="checkbox" id="riskAck" /> ${escapeHtml(
        t("options_risk_ack_encrypted"),
      )}</label>
      <div class="field password-field">
        <label for="backupPassword">${escapeHtml(t("options_set_password"))}</label>
        <div class="password-input-row">
          <input class="input" id="backupPassword" type="password" autocomplete="new-password" placeholder="${escapeHtml(
            t("options_password_placeholder"),
          )}" />
          <button type="button" class="btn btn-secondary btn-sm password-toggle" id="toggleBackupPassword" aria-pressed="false">${escapeHtml(
            t("common_show"),
          )}</button>
        </div>
        <div class="hint password-strength" id="passwordStrength" data-tone="muted">${escapeHtml(
          t("options_password_strength_none"),
        )}</div>
      </div>
      <div class="field">
        <label for="backupPassword2">${escapeHtml(t("options_password_again"))}</label>
        <input class="input" id="backupPassword2" type="password" autocomplete="new-password" placeholder="${escapeHtml(
          t("options_password_again_placeholder"),
        )}" />
      </div>
      <div class="notice">${icon("lock", 16)}<span>${escapeHtml(t("options_password_notice"))}</span></div>
      <div class="field-error" id="passwordError"></div>
    `;
    const passwordInput = body.querySelector("#backupPassword");
    const againInput = body.querySelector("#backupPassword2");
    const strengthEl = body.querySelector("#passwordStrength");
    const toggle = body.querySelector("#toggleBackupPassword");
    const errorEl = body.querySelector("#passwordError");

    passwordInput.addEventListener("input", () => {
      const info = passwordStrength(passwordInput.value);
      strengthEl.dataset.tone = info.tone;
      strengthEl.textContent = t("options_password_strength", {
        label: info.label,
        count: Array.from(passwordInput.value).length,
      });
      if (errorEl.textContent) {
        errorEl.textContent = "";
      }
    });
    toggle.addEventListener("click", () => {
      const show = passwordInput.type === "password";
      passwordInput.type = show ? "text" : "password";
      againInput.type = show ? "text" : "password";
      toggle.textContent = t(show ? "common_hide" : "common_show");
      toggle.setAttribute("aria-pressed", String(show));
    });

    openModal({
      title: t("options_encrypted_export_title"),
      subtitle: t("options_encrypted_export_sub"),
      content: body,
      dismissible: false,
      actions: [
        { label: t("common_cancel"), onClick: () => finish(null) },
        {
          label: t("options_encrypted_export_action"),
          variant: "primary",
          keepOpen: true,
          onClick: (close) => {
            const password = passwordInput.value;
            const again = againInput.value;
            if (!body.querySelector("#riskAck").checked) {
              errorEl.textContent = t("options_password_missing");
              return false;
            }
            if (Array.from(password).length < 8) {
              errorEl.textContent = t("options_password_too_short");
              passwordInput.focus();
              return false;
            }
            if (password !== again) {
              errorEl.textContent = t("options_password_mismatch");
              againInput.focus();
              return false;
            }
            finish(password);
            close();
            return false;
          },
        },
      ],
      onClose: () => finish(null),
    });
  });
}

async function exportJson() {
  if (state.accounts.length === 0) {
    showToast(t("options_no_accounts"), { kind: "error" });
    return;
  }
  const scanCount = state.accounts.filter((account) => account.type === "scan").length;
  const confirmed = await confirmPlaintextExport(scanCount);
  if (!confirmed) {
    return;
  }
  try {
    const result = await send("backup:export", { password: "" });
    downloadFile(result.filename, result.content, "application/json");
    showToast(t("options_exported_accounts", { count: result.accountCount }), { kind: "success" });
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
  }
}

async function exportEncrypted() {
  if (state.accounts.length === 0) {
    showToast(t("options_no_accounts"), { kind: "error" });
    return;
  }
  const scanCount = state.accounts.filter((account) => account.type === "scan").length;
  const password = await promptExportPassword(scanCount);
  if (!password) {
    return;
  }
  try {
    const result = await send("backup:export", { password });
    downloadFile(result.filename, result.content, "application/json");
    showToast(t("options_exported_encrypted"), { kind: "success", duration: 4200 });
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
  }
}

async function exportText() {
  const standardCount = state.accounts.filter((account) => account.type === "standard").length;
  const scanCount = state.accounts.filter((account) => account.type === "scan").length;
  if (standardCount === 0) {
    showToast(t("options_no_standard_accounts"), { kind: "error" });
    return;
  }
  const ok = await confirmDialog({
    title: t("options_text_export_title"),
    message: [
      t("options_text_export_message", { count: standardCount }),
      scanCount > 0 ? t("options_text_export_scan_note") : "",
    ]
      .filter(Boolean)
      .join("\n"),
    confirmText: t("options_continue_export"),
    cancelText: t("common_cancel"),
    danger: true,
  });
  if (!ok) {
    return;
  }
  try {
    const result = await send("backup:export-text");
    downloadFile(result.filename, result.content, "text/plain;charset=utf-8");
    showToast(t("options_exported_standard", { count: result.accountCount }), { kind: "success" });
  } catch (error) {
    showToast(errorText(error), { kind: "error" });
  }
}

/* -------------------------------- 备份导入 -------------------------------- */

function duplicateKey(type, issuer, account) {
  return `${type}\u0000${issuer}\u0000${account}`;
}

function sourceLabel(source) {
  return (
    {
      json: t("options_source_json"),
      text: t("options_source_text"),
      uri: t("options_source_uri"),
      migration: t("options_source_migration"),
    }[source] ?? t("options_source_unknown")
  );
}

function readFile(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result ?? ""));
    reader.onerror = () => reject(new Error("read failed"));
    reader.readAsText(file, "utf-8");
  });
}

/**
 * 输入备份口令：validate 返回 null 表示解密成功，返回字符串表示错误文案。
 * 口令错误时弹窗保持打开、输入框保留，可直接重试。
 */
function promptImportPassword(validate) {
  return new Promise((resolve) => {
    let settled = false;
    let busy = false;
    const finish = (value) => {
      if (!settled) {
        settled = true;
        resolve(value);
      }
    };
    const body = document.createElement("div");
    body.innerHTML = `
      <div class="field">
        <label for="importPassword">${escapeHtml(t("options_import_password_label"))}</label>
        <div class="password-input-row">
          <input class="input" id="importPassword" type="password" autocomplete="current-password" placeholder="${escapeHtml(
            t("options_import_password_placeholder"),
          )}" />
          <button type="button" class="btn btn-secondary btn-sm password-toggle" id="toggleImportPassword" aria-pressed="false">${escapeHtml(
            t("common_show"),
          )}</button>
        </div>
        <div class="field-error" id="importPasswordError"></div>
      </div>
      <div class="notice">${icon("lock", 16)}<span>${escapeHtml(t("options_import_password_notice"))}</span></div>
    `;
    const input = body.querySelector("#importPassword");
    const errorEl = body.querySelector("#importPasswordError");
    const toggle = body.querySelector("#toggleImportPassword");

    toggle.addEventListener("click", () => {
      const show = input.type === "password";
      input.type = show ? "text" : "password";
      toggle.textContent = t(show ? "common_hide" : "common_show");
      toggle.setAttribute("aria-pressed", String(show));
    });
    input.addEventListener("input", () => {
      if (errorEl.textContent) {
        errorEl.textContent = "";
      }
    });

    openModal({
      title: t("options_import_password_title"),
      subtitle: t("options_import_password_sub"),
      content: body,
      dismissible: false,
      actions: [
        { label: t("common_cancel"), onClick: () => finish(null) },
        {
          label: t("options_decrypt_action"),
          variant: "primary",
          keepOpen: true,
          onClick: async (close) => {
            if (busy) {
              return false;
            }
            const password = input.value;
            if (!password) {
              errorEl.textContent = t("options_import_password_empty");
              input.focus();
              return false;
            }
            busy = true;
            errorEl.textContent = t("options_decrypting");
            try {
              const message = await validate(password);
              if (message) {
                errorEl.textContent = message;
                input.select();
                input.focus();
                return false;
              }
            } finally {
              busy = false;
            }
            finish(password);
            close();
            return false;
          },
        },
      ],
      onClose: () => finish(null),
    });
  });
}

async function analyzeImportWithPassword(text) {
  try {
    return await analyzeImportText(text);
  } catch (error) {
    if (error.code !== "PASSWORD_REQUIRED") {
      throw error;
    }
    let analyzed = null;
    const password = await promptImportPassword(async (candidate) => {
      try {
        analyzed = await analyzeImportText(text, { password: candidate });
        return null;
      } catch (innerError) {
        return errorText(innerError);
      }
    });
    if (!password || !analyzed) {
      return null;
    }
    return analyzed;
  }
}

async function previewImport() {
  const text = document.getElementById("importText").value.trim();
  if (!text) {
    showToast(t("options_import_empty_input"), { kind: "error" });
    return;
  }
  let analyzed;
  try {
    analyzed = await analyzeImportWithPassword(text);
  } catch (error) {
    showToast(error.code ? errorText(error) : t("error_UNKNOWN"), { kind: "error", duration: 4200 });
    return;
  }
  if (!analyzed) {
    return;
  }

  const existing = new Map(
    state.accounts.map((account) => [duplicateKey(account.type, account.issuer, account.account), account]),
  );
  const rows = analyzed.rows.map((row) => ({
    ...row,
    duplicate: existing.has(duplicateKey(row.type, row.issuer, row.account)),
  }));
  state.import = {
    rows,
    failures: analyzed.failures,
    selected: new Set(rows.map((_row, index) => index)),
    meta: analyzed.meta,
    raw: text,
  };
  renderImportPreview();
}

function renderImportPreview() {
  const preview = document.getElementById("importPreview");
  preview.hidden = false;
  const { rows, failures, meta, selected } = state.import;
  const duplicateCount = rows.filter((row) => row.duplicate).length;
  document.getElementById("importSummary").textContent = [
    t(meta.format === "json" ? "options_import_summary_json" : "options_import_summary_text"),
    t("options_import_summary_count", { count: rows.length }),
    duplicateCount > 0 ? t("options_import_summary_dup", { count: duplicateCount }) : "",
    meta.encrypted ? t("options_import_summary_decrypted") : "",
  ]
    .filter(Boolean)
    .join(" · ");

  const tbody = document.getElementById("importTableBody");
  tbody.innerHTML = rows
    .map((row, index) => {
      const checked = selected.has(index);
      return `<tr data-index="${index}" class="${row.duplicate ? "is-duplicate" : ""} ${
        checked ? "" : "is-unchecked"
      }">
        <td class="col-check"><input type="checkbox" class="row-check" data-index="${index}" ${
          checked ? "checked" : ""
        } aria-label="${escapeHtml(t("options_row_select", { index: index + 1 }))}" /></td>
        <td class="name" title="${escapeHtml(row.issuer)}">${escapeHtml(row.issuer)}</td>
        <td class="account" title="${escapeHtml(row.account)}">${escapeHtml(row.account)}</td>
        <td>${escapeHtml(t("popup_algorithm_summary", { algorithm: row.algorithm, digits: row.digits, period: row.period }))}</td>
        <td>${escapeHtml(sourceLabel(row.source))}${row.type === "scan" ? ` · ${escapeHtml(t("popup_scan_account_title"))}` : ""}</td>
        <td>${
          row.duplicate
            ? `<span class="badge badge-warning">${escapeHtml(t("options_badge_duplicate"))}</span>`
            : `<span class="badge badge-success">${escapeHtml(t("options_badge_new"))}</span>`
        }${row.weak ? ` <span class="badge badge-warning">${escapeHtml(t("options_badge_short"))}</span>` : ""}</td>
      </tr>`;
    })
    .join("");

  const failuresEl = document.getElementById("importFailures");
  const failureList = document.getElementById("importFailureList");
  if (failures.length > 0) {
    failuresEl.hidden = false;
    failureList.innerHTML = failures
      .map((failure) => {
        const where =
          failure.line > 0
            ? t("options_failure_line", { line: failure.line })
            : failure.label || t("options_failure_unknown");
        const reason = failure.code ? errorText({ code: failure.code }) : t("options_failure_parse");
        const preview =
          failure.line > 0 && failure.label
            ? t("options_failure_preview", { label: failure.label })
            : "";
        const entry = preview
          ? t("options_failure_entry_preview", { where, reason, preview })
          : t("options_failure_entry", { where, reason });
        return `<li>${escapeHtml(entry)}</li>`;
      })
      .join("");
  } else {
    failuresEl.hidden = true;
  }
  updateSelectedCount();
}

function updateSelectedCount() {
  const count = state.import.selected.size;
  document.getElementById("selectedCount").textContent = t("options_selected_count", {
    selected: count,
    total: state.import.rows.length - count,
  });
  document.getElementById("commitImportButton").disabled = count === 0;
}

async function commitImport() {
  const strategy = document.querySelector('input[name="dupStrategy"]:checked')?.value ?? "skip";
  const rows = state.import.rows.filter((_row, index) => state.import.selected.has(index));
  if (rows.length === 0) {
    showToast(t("options_import_at_least_one"), { kind: "error" });
    return;
  }
  const button = document.getElementById("commitImportButton");
  button.disabled = true;
  try {
    const result = await send("backup:import", {
      rows: rows.map(({ duplicate, weak, source, ...row }) => row),
      strategy,
    });
    await reloadAccounts();
    const parts = [
      t("options_import_added", { count: result.added }),
      result.overwritten > 0 ? t("options_import_overwritten", { count: result.overwritten }) : "",
      result.skipped > 0 ? t("options_import_skipped", { count: result.skipped }) : "",
    ].filter(Boolean);
    openModal({
      title: t("options_import_done_title"),
      content: `<p class="modal-text">${escapeHtml(parts.join(" · "))}</p>${
        result.failed.length > 0
          ? `<div class="failures"><h4>${escapeHtml(t("options_import_failed_title"))}</h4><ul>${result.failed
              .map(
                (failure) =>
                  `<li>${escapeHtml(
                    t("options_import_failure_entry", {
                      name: failure.name,
                      reason: failure.code ? errorText({ code: failure.code }) : t("error_UNKNOWN"),
                    }),
                  )}</li>`,
              )
              .join("")}</ul></div>`
          : ""
      }`,
      actions: [{ label: t("common_done"), variant: "primary" }],
    });
    document.getElementById("importPreview").hidden = true;
    document.getElementById("importText").value = "";
    state.import = { rows: [], failures: [], selected: new Set(), meta: null, raw: "" };
  } catch (error) {
    showToast(error.code ? errorText(error) : t("error_UNKNOWN"), { kind: "error", duration: 4200 });
  } finally {
    button.disabled = false;
  }
}

/* -------------------------------- 事件绑定 -------------------------------- */

function bindEvents() {
  for (const tab of document.querySelectorAll(".tab")) {
    tab.addEventListener("click", () => switchTab(tab.dataset.tab));
  }

  document.getElementById("addManualButton").addEventListener("click", openManualModal);
  document.getElementById("addUriButton").addEventListener("click", openUriModal);
  scanCodesToggle?.addEventListener("click", toggleShowScanCodes);

  document.getElementById("accountsContainer").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-action]");
    if (!button) {
      return;
    }
    const account = state.accounts.find((item) => item.id === button.dataset.id);
    if (!account) {
      return;
    }
    if (button.dataset.action === "label") {
      editLabel(account);
    } else if (button.dataset.action === "sites") {
      editSiteHosts(account);
    } else if (button.dataset.action === "delete") {
      deleteAccountRow(account);
    } else if (button.dataset.action === "confirm") {
      retryConfirm(account);
    } else if (button.dataset.action === "pin") {
      togglePin(account);
    } else if (button.dataset.action === "qrcode") {
      exportAccountQr(account);
    } else if (button.dataset.action === "menu") {
      const rect = button.getBoundingClientRect();
      openAccountMenu(account, rect.right - 180, rect.bottom + 4);
    }
  });

  const accountsContainer = document.getElementById("accountsContainer");
  accountsContainer.addEventListener("contextmenu", (event) => {
    const row = event.target.closest(".account-row");
    if (!row) {
      return;
    }
    const account = state.accounts.find((item) => item.id === row.dataset.id);
    if (!account) {
      return;
    }
    event.preventDefault();
    openAccountMenu(account, event.clientX, event.clientY);
  });
  attachSortable({
    container: accountsContainer,
    itemSelector: ".account-row",
    handleSelector: ".drag-handle",
    onReorder: applyOrder,
  });

  const colorInput = document.getElementById("customColor");
  colorInput.addEventListener("change", () => applyCustomColor(colorInput.value));
  document.getElementById("customHex").addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      applyCustomColor(document.getElementById("customHex").value);
    }
  });
  document.getElementById("applyCustomColor").addEventListener("click", () => {
    applyCustomColor(document.getElementById("customHex").value);
  });

  document.getElementById("modeSegmented").addEventListener("click", async (event) => {
    const button = event.target.closest("button[data-mode]");
    if (!button) {
      return;
    }
    state.settings = await saveSettings({ themeMode: button.dataset.mode });
    applyTheme(state.settings);
    renderAppearance();
  });

  document.getElementById("languageSelect").addEventListener("change", async (event) => {
    await applyLanguage(event.target.value);
  });

  document.getElementById("exportJsonButton").addEventListener("click", exportJson);
  document.getElementById("exportEncryptedButton").addEventListener("click", exportEncrypted);
  document.getElementById("exportTextButton").addEventListener("click", exportText);

  const fileInput = document.getElementById("fileInput");
  document.getElementById("chooseFileButton").addEventListener("click", () => fileInput.click());
  fileInput.addEventListener("change", async () => {
    const file = fileInput.files?.[0];
    if (!file) {
      return;
    }
    try {
      document.getElementById("importText").value = await readFile(file);
      await previewImport();
    } catch (error) {
      showToast(t("options_read_failed"), { kind: "error" });
    } finally {
      fileInput.value = "";
    }
  });

  const dropzone = document.getElementById("dropzone");
  dropzone.addEventListener("click", (event) => {
    if (event.target.closest("button")) {
      return;
    }
    fileInput.click();
  });
  dropzone.addEventListener("dragover", (event) => {
    event.preventDefault();
    dropzone.classList.add("is-dragover");
  });
  dropzone.addEventListener("dragleave", () => dropzone.classList.remove("is-dragover"));
  dropzone.addEventListener("drop", async (event) => {
    event.preventDefault();
    dropzone.classList.remove("is-dragover");
    const file = event.dataTransfer?.files?.[0];
    if (!file) {
      return;
    }
    try {
      document.getElementById("importText").value = await readFile(file);
      await previewImport();
    } catch (error) {
      showToast(t("options_read_failed"), { kind: "error" });
    }
  });

  document.getElementById("previewImportButton").addEventListener("click", previewImport);
  document.getElementById("clearImportButton").addEventListener("click", () => {
    document.getElementById("importText").value = "";
    document.getElementById("importPreview").hidden = true;
    state.import = { rows: [], failures: [], selected: new Set(), meta: null, raw: "" };
  });
  document.getElementById("closePreviewButton").addEventListener("click", () => {
    document.getElementById("importPreview").hidden = true;
  });
  document.getElementById("selectAllRows").addEventListener("change", (event) => {
    const checked = event.target.checked;
    state.import.selected = new Set(checked ? state.import.rows.map((_row, index) => index) : []);
    renderImportPreview();
  });
  document.getElementById("importTableBody").addEventListener("change", (event) => {
    const checkbox = event.target.closest(".row-check");
    if (!checkbox) {
      return;
    }
    const index = Number(checkbox.dataset.index);
    if (checkbox.checked) {
      state.import.selected.add(index);
    } else {
      state.import.selected.delete(index);
    }
    checkbox.closest("tr").classList.toggle("is-unchecked", !checkbox.checked);
    updateSelectedCount();
  });
  document.getElementById("commitImportButton").addEventListener("click", commitImport);

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && changes["totpscan.accounts"]) {
      reloadAccounts();
    }
  });
}

async function init() {
  await initI18n();
  applyI18n(document);
  state.settings = await initTheme();
  updateFooterVersion();
  renderAppearance();
  renderShowScanCodes();
  bindEvents();
  await reloadAccounts();

  window.addEventListener("i18n:changed", () => {
    updateFooterVersion();
    renderAccounts();
    renderAppearance();
    renderShowScanCodes();
    renderBackupWarning();
    if (!document.getElementById("importPreview").hidden) {
      renderImportPreview();
    }
  });

  const hash = location.hash.replace("#", "");
  if (hash === "add") {
    openManualModal();
  } else if (hash === "import") {
    switchTab("backup");
    document.getElementById("dropzone").scrollIntoView({ behavior: "smooth", block: "center" });
  }
}

function updateFooterVersion() {
  let version = "";
  try {
    version = chrome.runtime.getManifest().version;
  } catch {
    version = "—";
  }
  document.getElementById("footerVersion").textContent = t("options_footer_version", { version });
}

init().catch((error) => {
  showToast(t("common_init_failed", { message: errorText(error) }), { kind: "error", duration: 5200 });
});
