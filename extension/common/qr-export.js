/** 单账户 otpauth 二维码导出：确认 → 渲染 → 遮挡揭示 → 60 秒后清空关闭。 */

import { t, formatNumber } from "./i18n.js";
import { icon, escapeHtml, openModal, closeModal, confirmDialog, showToast } from "./ui.js";
import { drawQrToCanvas, clearQrCanvas } from "../vendor/qr-encode.js";

const QR_VISIBLE_MS = 60_000;

function accountName(account) {
  return account.label || `${account.issuer} · ${account.account}`;
}

/** 扫码型账户：额外风险说明 + 必须勾选确认。 */
function confirmEnhancedExport(name) {
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
      <p class="modal-text">${escapeHtml(t("qr_export_confirm_message"))}</p>
      <div class="notice notice-warning qr-risk-notice">${icon("warning", 16)}<span>${escapeHtml(
        t("qr_export_scan_warning"),
      )}</span></div>
      <label class="risk-check">
        <input type="checkbox" data-qr-risk-ack />
        <span>${escapeHtml(t("qr_export_scan_ack"))}</span>
      </label>
      <p class="field-error" data-qr-risk-error hidden></p>
    `;
    const checkbox = body.querySelector("[data-qr-risk-ack]");
    const errorEl = body.querySelector("[data-qr-risk-error]");

    openModal({
      title: t("qr_export_confirm_title"),
      subtitle: name,
      content: body,
      actions: [
        { label: t("common_cancel"), onClick: () => finish(false) },
        {
          label: t("qr_export_confirm_action"),
          variant: "danger",
          keepOpen: true,
          onClick: (close) => {
            if (!checkbox.checked) {
              errorEl.textContent = t("qr_export_risk_unchecked");
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

function renderQrModal(uri, name, isEnhanced) {
  const body = document.createElement("div");
  body.className = "qr-export";
  body.innerHTML = `
    <div class="qr-frame is-covered" data-qr-frame>
      <canvas class="qr-canvas" data-qr-canvas aria-label="${escapeHtml(t("qr_export_title"))}"></canvas>
      <button type="button" class="qr-cover" data-qr-cover aria-label="${escapeHtml(
        t("qr_export_reveal_hint"),
      )}">
        ${icon("qr", 26)}
        <span>${escapeHtml(t("qr_export_reveal_hint"))}</span>
      </button>
    </div>
    <div class="qr-countdown" data-qr-countdown></div>
    <div class="notice notice-warning">${icon("warning", 16)}<span>${escapeHtml(
      t(isEnhanced ? "qr_export_scan_display_notice" : "qr_export_display_notice"),
    )}</span></div>
  `;

  const canvas = body.querySelector("[data-qr-canvas]");
  const frame = body.querySelector("[data-qr-frame]");
  const cover = body.querySelector("[data-qr-cover]");
  const countdownEl = body.querySelector("[data-qr-countdown]");

  let timer = null;
  let deadline = Date.now() + QR_VISIBLE_MS;

  const cleanup = () => {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    clearQrCanvas(canvas);
    frame.replaceChildren();
    body.replaceChildren();
  };

  openModal({
    title: t("qr_export_title"),
    subtitle: name,
    content: body,
    actions: [{ label: t("common_close") }],
    onClose: cleanup,
  });

  try {
    drawQrToCanvas(canvas, uri, { pixelSize: 216 });
  } catch (error) {
    closeModal();
    showToast(t(error?.code === "QR_TOO_LONG" ? "qr_export_too_long" : "qr_export_failed"), {
      kind: "error",
    });
    return;
  }

  const updateCountdown = () => {
    const remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
    countdownEl.textContent = t("qr_export_countdown", { seconds: formatNumber(remaining) });
    if (remaining <= 0) {
      closeModal();
    }
  };
  updateCountdown();
  timer = setInterval(updateCountdown, 1000);

  cover.addEventListener("click", () => {
    frame.classList.remove("is-covered");
    cover.remove();
  });
}

/**
 * 打开单账户二维码导出流程。
 * @param {object} options
 * @param {object} options.account 账户公开数据
 * @param {() => Promise<string>} options.getUri 确认后才调用的链接获取函数
 * @param {(error: any) => string} [options.errorText] 后台错误码翻译
 */
export async function openQrExport({ account, getUri, errorText }) {
  const isEnhanced = account.type === "scan";
  const name = accountName(account);

  if (isEnhanced) {
    const allowed = await confirmEnhancedExport(name);
    if (!allowed) {
      return;
    }
  } else {
    const allowed = await confirmDialog({
      title: t("qr_export_confirm_title"),
      subtitle: name,
      message: t("qr_export_confirm_message"),
      confirmText: t("qr_export_confirm_action"),
      cancelText: t("common_cancel"),
      danger: true,
    });
    if (!allowed) {
      return;
    }
  }

  let uri;
  try {
    uri = await getUri();
  } catch (error) {
    showToast(errorText ? errorText(error) : t("qr_export_failed"), { kind: "error" });
    return;
  }
  if (!uri) {
    showToast(t("qr_export_failed"), { kind: "error" });
    return;
  }
  renderQrModal(uri, name, isEnhanced);
}
