/** 弹窗与选项页共用的轻量 DOM 工具：图标、Toast、模态框、头像配色。 */

import { t } from "./i18n.js";

export function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

const ICONS = {
  qr: '<path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4z"/><path d="M14 14h2v2h-2zM18 14h2v2h-2zM14 18h2v2h-2zM18 18h2v2h-2z"/>',
  settings:
    '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.9.3H10a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9V10a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  moon: '<path d="M21 12.8A8.5 8.5 0 1 1 11.2 3a6.5 6.5 0 0 0 9.8 9.8z"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  close: '<path d="M18 6 6 18M6 6l12 12"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
  warning: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
  trash: '<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v5M14 11v5"/>',
  edit: '<path d="M11 4H4v16h16v-7"/><path d="M18.5 2.5a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4z"/>',
  download: '<path d="M12 3v12M7 10l5 5 5-5M5 21h14"/>',
  upload: '<path d="M12 21V9M7 14l5-5 5 5M5 3h14"/>',
  lock: '<rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M17 4l3 3M14 7l2 2"/>',
  external: '<path d="M14 3h7v7M10 14 21 3M21 14v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5"/>',
  refresh: '<path d="M21 12a9 9 0 1 1-3-6.7M21 3v6h-6"/>',
  page: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M9 13h6M9 17h6"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
  scanLine: '<path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2M3 12h18"/>',
  more: '<circle cx="12" cy="5" r="1.6" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="12" cy="19" r="1.6" fill="currentColor" stroke="none"/>',
  grip: '<circle cx="9" cy="6" r="1.5" fill="currentColor" stroke="none"/><circle cx="15" cy="6" r="1.5" fill="currentColor" stroke="none"/><circle cx="9" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="9" cy="18" r="1.5" fill="currentColor" stroke="none"/><circle cx="15" cy="18" r="1.5" fill="currentColor" stroke="none"/>',
  pin: '<path d="M9 3h6l-1.2 6.2L18 13v2h-5v5l-1 1-1-1v-5H6v-2l4.2-3.8z"/>',
  pinOff: '<path d="M9 3h6l-1.2 6.2L18 13v2h-5v5l-1 1-1-1v-5H6v-2l4.2-3.8z"/><path d="m3 3 18 18"/>',
};

export function icon(name, size = 18) {
  const body = ICONS[name] ?? ICONS.info;
  return `<svg class="icon" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
}

let toastTimer = null;

export function hideToast() {
  const host = document.querySelector(".toast-host");
  if (!host) {
    return;
  }
  if (toastTimer) {
    clearTimeout(toastTimer);
    toastTimer = null;
  }
  host.classList.remove("toast-visible");
  host.hidden = true;
}

export function showToast(message, options = {}) {
  let host = document.querySelector(".toast-host");
  if (!host) {
    host = document.createElement("div");
    host.className = "toast-host";
    document.body.appendChild(host);
  }
  host.textContent = message;
  host.dataset.kind = options.kind ?? "info";
  host.hidden = false;
  host.classList.add("toast-visible");
  if (toastTimer) {
    clearTimeout(toastTimer);
  }
  toastTimer = setTimeout(() => {
    host.classList.remove("toast-visible");
    setTimeout(() => {
      host.hidden = true;
    }, 200);
  }, options.duration ?? 3200);
}

export function getModalRoot() {
  let root = document.getElementById("modalRoot");
  if (!root) {
    root = document.createElement("div");
    root.id = "modalRoot";
    document.body.appendChild(root);
  }
  return root;
}

let activeModalState = null;

export function closeModal() {
  const state = activeModalState;
  if (!state) {
    return;
  }
  activeModalState = null;
  state.onClose?.();
  state.backdrop.remove();
  document.removeEventListener("keydown", state.onKeydown);
  state.previousFocus?.focus?.();
}

/**
 * 打开模态框。
 * content 可以是 HTML 字符串或 DOM 节点；actions 提供按钮。
 */
export function openModal(options) {
  closeModal();
  const previousFocus = document.activeElement;
  const backdrop = document.createElement("div");
  backdrop.className = "modal-backdrop";

  const modal = document.createElement("div");
  modal.className = `modal ${options.size === "wide" ? "modal-wide" : ""}`;
  modal.setAttribute("role", "dialog");
  modal.setAttribute("aria-modal", "true");
  if (options.title) {
    modal.setAttribute("aria-label", options.title);
  }

  const header = document.createElement("div");
  header.className = "modal-header";
  header.innerHTML = `<div class="modal-heading"><h2>${escapeHtml(options.title ?? "")}</h2>${
    options.subtitle ? `<p>${escapeHtml(options.subtitle)}</p>` : ""
  }</div>`;
  const closeButton = document.createElement("button");
  closeButton.className = "icon-button modal-close";
  closeButton.type = "button";
  closeButton.setAttribute("aria-label", t("common_close"));
  closeButton.innerHTML = icon("close", 18);
  closeButton.addEventListener("click", () => closeModal());
  header.appendChild(closeButton);

  const body = document.createElement("div");
  body.className = "modal-body";
  if (typeof options.content === "string") {
    body.innerHTML = options.content;
  } else if (options.content instanceof Node) {
    body.appendChild(options.content);
  }

  const footer = document.createElement("div");
  footer.className = "modal-actions";
  let confirmButton = null;
  for (const action of options.actions ?? []) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `btn ${action.variant === "primary" ? "btn-primary" : action.variant === "danger" ? "btn-danger" : "btn-secondary"}`;
    button.textContent = action.label;
    if (action.disabled) {
      button.disabled = true;
    }
    if (action.variant === "primary" || action.variant === "danger") {
      confirmButton = button;
    }
    button.addEventListener("click", async () => {
      const result = await action.onClick?.(closeModal);
      if (result !== false && action.keepOpen !== true) {
        closeModal();
      }
    });
    footer.appendChild(button);
  }
  if (footer.childElementCount === 0) {
    footer.remove();
  }

  modal.append(header, body);
  if (footer.childElementCount > 0) {
    modal.appendChild(footer);
  }
  backdrop.appendChild(modal);
  getModalRoot().appendChild(backdrop);

  backdrop.addEventListener("mousedown", (event) => {
    if (event.target === backdrop && options.dismissible !== false) {
      closeModal();
    }
  });

  const onKeydown = (event) => {
    if (event.key === "Escape" && options.dismissible !== false) {
      event.stopPropagation();
      closeModal();
      return;
    }
    if (event.key !== "Enter" || !options.enterConfirm || !confirmButton) {
      return;
    }
    const tag = event.target?.tagName;
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    confirmButton.click();
  };
  document.addEventListener("keydown", onKeydown);

  activeModalState = { backdrop, onClose: options.onClose, onKeydown, previousFocus };
  const focusTarget = modal.querySelector("input, textarea, select, button.btn-primary, button");
  focusTarget?.focus?.();
  return { close: closeModal, modal, body };
}

export function confirmDialog(options) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (!settled) {
        settled = true;
        resolve(value);
      }
    };
    openModal({
      title: options.title,
      subtitle: options.subtitle,
      content: `<p class="modal-text">${escapeHtml(options.message)}</p>${
        options.extraHtml ?? ""
      }`,
      actions: [
        { label: options.cancelText ?? t("common_cancel"), onClick: () => finish(false) },
        {
          label: options.confirmText ?? t("common_confirm"),
          variant: options.danger ? "danger" : "primary",
          onClick: () => finish(true),
        },
      ],
      enterConfirm: true,
      onClose: () => finish(false),
    });
  });
}

export async function copyToClipboard(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    try {
      const area = document.createElement("textarea");
      area.value = text;
      area.style.position = "fixed";
      area.style.opacity = "0";
      document.body.appendChild(area);
      area.select();
      const ok = document.execCommand("copy");
      area.remove();
      return ok;
    } catch {
      return false;
    }
  }
}

let activeContextMenu = null;

/** 关闭右键菜单。 */
export function closeContextMenu() {
  if (!activeContextMenu) {
    return;
  }
  const { element, cleanup } = activeContextMenu;
  activeContextMenu = null;
  cleanup();
  element.remove();
}

/**
 * 打开轻量右键菜单。items: [{ label, icon, danger, onSelect }]。
 * 坐标超出视口时会自动向内收。
 */
export function openContextMenu({ x, y, items, label = t("common_more_actions") }) {
  closeContextMenu();
  const menu = document.createElement("div");
  menu.className = "context-menu";
  menu.setAttribute("role", "menu");
  menu.setAttribute("aria-label", label);
  for (const item of items) {
    if (!item) {
      continue;
    }
    const button = document.createElement("button");
    button.type = "button";
    button.className = `context-menu-item${item.danger ? " is-danger" : ""}`;
    button.setAttribute("role", "menuitem");
    button.innerHTML = `${item.icon ? icon(item.icon, 15) : '<span class="context-menu-spacer"></span>'}<span>${escapeHtml(item.label)}</span>`;
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      closeContextMenu();
      item.onSelect?.();
    });
    menu.appendChild(button);
  }
  document.body.appendChild(menu);

  const rect = menu.getBoundingClientRect();
  const left = Math.min(Math.max(6, x), Math.max(6, window.innerWidth - rect.width - 6));
  const top = Math.min(Math.max(6, y), Math.max(6, window.innerHeight - rect.height - 6));
  menu.style.left = `${left}px`;
  menu.style.top = `${top}px`;

  const onPointerDown = (event) => {
    if (!menu.contains(event.target)) {
      closeContextMenu();
    }
  };
  const onKeyDown = (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      closeContextMenu();
    }
  };
  const onViewportChange = () => closeContextMenu();
  document.addEventListener("pointerdown", onPointerDown, true);
  document.addEventListener("keydown", onKeyDown, true);
  window.addEventListener("scroll", onViewportChange, true);
  window.addEventListener("resize", onViewportChange);
  activeContextMenu = {
    element: menu,
    cleanup() {
      document.removeEventListener("pointerdown", onPointerDown, true);
      document.removeEventListener("keydown", onKeyDown, true);
      window.removeEventListener("scroll", onViewportChange, true);
      window.removeEventListener("resize", onViewportChange);
    },
  };
  menu.querySelector("button")?.focus?.();
  return menu;
}

/**
 * 为列表容器接入指针拖拽排序（鼠标 / 触控）与键盘排序。
 * handleSelector 为空时整行可拖；提供时仅手柄可拖。排序结果通过 onReorder(ids) 回传。
 */
export function attachSortable({
  container,
  itemSelector,
  handleSelector = null,
  canStart = () => true,
  onReorder,
}) {
  let dragging = null;
  let pointerId = null;
  let startOrder = [];

  const readIds = () =>
    Array.from(container.querySelectorAll(itemSelector))
      .map((item) => item.dataset.id)
      .filter(Boolean);

  const finish = (event) => {
    if (!dragging) {
      return;
    }
    if (event && pointerId !== null && event.pointerId !== pointerId) {
      return;
    }
    dragging.classList.remove("is-dragging");
    container.classList.remove("is-sorting");
    dragging = null;
    pointerId = null;
    const next = readIds();
    if (next.join("|") !== startOrder.join("|")) {
      onReorder?.(next);
    }
  };

  container.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || !canStart()) {
      return;
    }
    const item = event.target.closest(itemSelector);
    if (!item || !container.contains(item)) {
      return;
    }
    if (handleSelector) {
      if (!event.target.closest(handleSelector)) {
        return;
      }
    } else if (event.target.closest("button, a, input, textarea, select")) {
      return;
    }
    dragging = item;
    pointerId = event.pointerId;
    startOrder = readIds();
    item.classList.add("is-dragging");
    container.classList.add("is-sorting");
    try {
      item.setPointerCapture(event.pointerId);
    } catch {
      // 某些环境不支持指针捕获，仍可通过冒泡事件排序
    }
    event.preventDefault();
  });

  container.addEventListener(
    "pointermove",
    (event) => {
      if (!dragging || event.pointerId !== pointerId) {
        return;
      }
      event.preventDefault();
      const target = document.elementFromPoint(event.clientX, event.clientY)?.closest(itemSelector);
      if (!target || target === dragging || !container.contains(target)) {
        return;
      }
      const rect = target.getBoundingClientRect();
      const after = event.clientY > rect.top + rect.height / 2;
      container.insertBefore(dragging, after ? target.nextElementSibling : target);
    },
    { passive: false },
  );

  container.addEventListener("pointerup", finish);
  container.addEventListener("pointercancel", finish);

  container.addEventListener("keydown", (event) => {
    if (!handleSelector || (event.key !== "ArrowUp" && event.key !== "ArrowDown")) {
      return;
    }
    const handle = event.target.closest(handleSelector);
    const item = handle?.closest(itemSelector);
    if (!item) {
      return;
    }
    const sibling = event.key === "ArrowUp" ? item.previousElementSibling : item.nextElementSibling;
    if (!sibling || !sibling.matches(itemSelector)) {
      return;
    }
    event.preventDefault();
    if (event.key === "ArrowUp") {
      container.insertBefore(item, sibling);
    } else {
      container.insertBefore(item, sibling.nextElementSibling);
    }
    handle.focus();
    onReorder?.(readIds());
  });
}

export function initialsOf(text) {
  const value = String(text ?? "").trim();
  if (!value) {
    return "?";
  }
  const chars = Array.from(value);
  return chars[0].toUpperCase();
}

export function hueFromString(text) {
  let hash = 0;
  for (let i = 0; i < text.length; i += 1) {
    hash = (hash * 31 + text.charCodeAt(i)) >>> 0;
  }
  return hash % 360;
}

export function formatDomain(url) {
  try {
    const parsed = new URL(url);
    return parsed.host;
  } catch {
    return url;
  }
}

export function formatPath(url) {
  try {
    const parsed = new URL(url);
    return parsed.pathname;
  } catch {
    return "";
  }
}

export function relativeSeconds(value) {
  return t("options_period_chip", { period: Math.max(0, Math.round(value)) });
}

export function nowStamp() {
  const date = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-${pad(date.getHours())}${pad(
    date.getMinutes(),
  )}`;
}

// 语言切换后，已经渲染的临时界面无法逐字重译，统一安全关闭。
if (typeof window !== "undefined") {
  window.addEventListener("i18n:changed", () => {
    hideToast();
    closeContextMenu();
    closeModal();
  });
}
