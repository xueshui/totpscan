/**
 * 运行时 i18n。
 *
 * 设计说明：
 * - 清单里的 name/description 由浏览器按浏览器界面语言读取 `_locales/*`，运行期无法切换；
 * - 界面文案改为读取同一套 `_locales/<locale>/messages.json`（fetch 扩展内文件），
 *   语言由设置项 `language` 决定，默认 `auto` 时用 `chrome.i18n.getUILanguage()` 判定；
 * - 因此清单与界面共用一份消息表，只存在「浏览器语言」与「用户选择」两个输入源，
 *   二者都用同一套 normalizeLocale/resolveLocale 规则，避免判定不一致。
 */

import { loadSettings } from "./settings.js";
import { setLabels } from "./labels.js";

export const SUPPORTED_LOCALES = ["zh_CN", "en", "zh_TW", "ja"];
export const DEFAULT_LOCALE = "zh_CN";
export const LANGUAGE_OPTIONS = ["auto", ...SUPPORTED_LOCALES];

/** 语言名称一律用该语言自身书写，避免在中文界面里出现英文语言名。 */
export const LOCALE_LABELS = {
  zh_CN: "简体中文",
  en: "English",
  zh_TW: "繁體中文",
  ja: "日本語",
};

const catalogs = new Map();
let current = {
  setting: "auto",
  uiLanguage: "",
  locale: DEFAULT_LOCALE,
  messages: {},
  fallback: {},
};

/** 把 BCP 47 语言标签映射到扩展支持的四个语种。 */
export function normalizeLocale(tag) {
  const value = String(tag ?? "")
    .trim()
    .toLowerCase()
    .replace(/_/g, "-");
  if (!value) {
    return DEFAULT_LOCALE;
  }
  if (value === "zh-tw" || value === "zh-hk" || value.startsWith("zh-hant")) {
    return "zh_TW";
  }
  if (value.startsWith("zh")) {
    return "zh_CN";
  }
  if (value.startsWith("ja")) {
    return "ja";
  }
  if (value.startsWith("en")) {
    return "en";
  }
  return DEFAULT_LOCALE;
}

/** setting 为具体语种时直接使用；为 auto 或非法值时回退到浏览器语言。 */
export function resolveLocale(setting, uiLanguage) {
  if (SUPPORTED_LOCALES.includes(setting)) {
    return setting;
  }
  return normalizeLocale(uiLanguage);
}

export function currentLocale() {
  return current.locale;
}

/** Intl 使用 BCP 47（zh-CN 而不是 zh_CN）。 */
export function intlLocale(locale = current.locale) {
  return locale.replace("_", "-");
}

export function browserUiLanguage() {
  try {
    if (typeof chrome !== "undefined" && chrome.i18n?.getUILanguage) {
      return chrome.i18n.getUILanguage();
    }
  } catch {
    // 非扩展环境（自测脚本）回退到 navigator
  }
  return typeof navigator !== "undefined" ? navigator.language : DEFAULT_LOCALE;
}

async function loadCatalog(locale) {
  if (catalogs.has(locale)) {
    return catalogs.get(locale);
  }
  const response = await fetch(chrome.runtime.getURL(`_locales/${locale}/messages.json`), { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`LOCALE_LOAD_FAILED:${locale}`);
  }
  const raw = await response.json();
  const flat = {};
  for (const [key, value] of Object.entries(raw)) {
    if (value && typeof value.message === "string") {
      flat[key] = value.message;
    }
  }
  catalogs.set(locale, flat);
  return flat;
}

function interpolate(text, vars) {
  if (!vars) {
    return text;
  }
  return text.replace(/\{(\w+)\}/g, (match, name) =>
    Object.prototype.hasOwnProperty.call(vars, name) ? String(vars[name]) : match,
  );
}

/** 取文案。缺失时回退到 zh_CN，再缺失则返回 key 本身，方便发现遗漏。 */
export function t(key, vars) {
  const text = current.messages[key] ?? current.fallback[key] ?? key;
  return interpolate(text, vars);
}

export function hasMessage(key) {
  return Object.prototype.hasOwnProperty.call(current.messages, key);
}

export function formatNumber(value, options) {
  try {
    return new Intl.NumberFormat(intlLocale(), options).format(value);
  } catch {
    return String(value);
  }
}

export function formatDate(timestamp, options = { year: "numeric", month: "2-digit", day: "2-digit" }) {
  try {
    return new Intl.DateTimeFormat(intlLocale(), options).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toLocaleDateString();
  }
}

/** 供背景页 / 内容脚本复用：返回某语种的扁平消息表。 */
export async function getCatalog(locale) {
  return loadCatalog(locale);
}

async function applyLocale(locale) {
  current.locale = locale;
  current.messages = await loadCatalog(locale);
  current.fallback = locale === DEFAULT_LOCALE ? current.messages : await loadCatalog(DEFAULT_LOCALE);
  setLabels({
    importIssuer: t("common_import_default_issuer"),
    unnamedAccount: t("common_unnamed_account"),
    unnamedIssuer: t("common_unnamed_issuer"),
  });
  if (typeof document !== "undefined") {
    document.documentElement.lang = intlLocale(locale);
    applyI18n(document);
  }
  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent("i18n:changed", { detail: { locale } }));
  }
}

/** 静态结构用 data-i18n* 标注；动态 DOM 由页面监听 i18n:changed 后重绘。 */
export function applyI18n(root = document) {
  for (const node of root.querySelectorAll("[data-i18n]")) {
    node.textContent = t(node.dataset.i18n);
  }
  for (const node of root.querySelectorAll("[data-i18n-title]")) {
    node.title = t(node.dataset.i18nTitle);
  }
  for (const node of root.querySelectorAll("[data-i18n-aria-label]")) {
    node.setAttribute("aria-label", t(node.dataset.i18nAriaLabel));
  }
  for (const node of root.querySelectorAll("[data-i18n-placeholder]")) {
    node.placeholder = t(node.dataset.i18nPlaceholder);
  }
}

let storageBound = false;

function bindStorage() {
  if (storageBound || typeof chrome === "undefined" || !chrome.storage?.onChanged) {
    return;
  }
  storageBound = true;
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") {
      return;
    }
    const next = changes["totpscan.settings"]?.newValue;
    if (!next || next.language === current.setting) {
      return;
    }
    current.setting = next.language ?? "auto";
    current.locale = resolveLocale(current.setting, current.uiLanguage);
    applyLocale(current.locale).catch(() => undefined);
  });
}

/** 初始化：读取设置与浏览器语言，加载消息表，绑定设置变更。 */
export async function initI18n() {
  const settings = await loadSettings();
  const uiLanguage = browserUiLanguage();
  const setting = LANGUAGE_OPTIONS.includes(settings.language) ? settings.language : "auto";
  current = {
    setting,
    uiLanguage,
    locale: resolveLocale(setting, uiLanguage),
    messages: {},
    fallback: {},
  };
  bindStorage();
  await applyLocale(current.locale);
  return { ...current };
}

/** 设置页修改语言后立即生效（storage 监听也会触发，这里用于同页即时反馈）。 */
export async function changeLanguage(setting) {
  const next = LANGUAGE_OPTIONS.includes(setting) ? setting : "auto";
  current.setting = next;
  current.locale = resolveLocale(next, current.uiLanguage);
  await applyLocale(current.locale);
  return current.locale;
}

export function currentSetting() {
  return current.setting;
}

export function currentUiLanguage() {
  return current.uiLanguage;
}
