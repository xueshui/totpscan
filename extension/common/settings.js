/** 主题色、明暗模式与持久化（弹窗与选项页共用）。 */

export const THEME_PRESETS = [
  { id: "blue", nameKey: "themePreset.blue", color: "#2F6FED" },
  { id: "emerald", nameKey: "themePreset.emerald", color: "#0E9F6E" },
  { id: "violet", nameKey: "themePreset.violet", color: "#7C5CFC" },
  { id: "coral", nameKey: "themePreset.coral", color: "#E8590C" },
  { id: "rose", nameKey: "themePreset.rose", color: "#D6336C" },
  { id: "teal", nameKey: "themePreset.teal", color: "#0E7490" },
  { id: "amber", nameKey: "themePreset.amber", color: "#B45309" },
  { id: "slate", nameKey: "themePreset.slate", color: "#475569" },
];

export const DEFAULT_SETTINGS = {
  themeId: "blue",
  customColor: "#2F6FED",
  themeMode: "auto",
  language: "auto",
  showScanCodes: false,
};

const SETTINGS_KEY = "totpscan.settings";
const MODE_VALUES = new Set(["auto", "light", "dark"]);
const LANGUAGE_VALUES = new Set(["auto", "zh_CN", "en", "zh_TW", "ja"]);
const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;

export function normalizeColor(value, fallback = "#2F6FED") {
  return typeof value === "string" && HEX_COLOR.test(value.trim()) ? value.trim().toUpperCase() : fallback;
}

export function resolveAccent(settings) {
  if (settings?.themeId === "custom") {
    return normalizeColor(settings.customColor);
  }
  const preset = THEME_PRESETS.find((item) => item.id === settings?.themeId);
  return preset ? preset.color : THEME_PRESETS[0].color;
}

export async function loadSettings() {
  try {
    const stored = await chrome.storage.local.get(SETTINGS_KEY);
    const value = stored[SETTINGS_KEY] ?? {};
    return {
      themeId: typeof value.themeId === "string" ? value.themeId : DEFAULT_SETTINGS.themeId,
      customColor: normalizeColor(value.customColor, DEFAULT_SETTINGS.customColor),
      themeMode: MODE_VALUES.has(value.themeMode) ? value.themeMode : DEFAULT_SETTINGS.themeMode,
      language: LANGUAGE_VALUES.has(value.language) ? value.language : DEFAULT_SETTINGS.language,
      showScanCodes: value.showScanCodes === true,
    };
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

export async function saveSettings(patch) {
  const current = await loadSettings();
  const next = { ...current, ...patch };
  await chrome.storage.local.set({ [SETTINGS_KEY]: next });
  return next;
}

export function prefersDark() {
  return typeof matchMedia === "function" && matchMedia("(prefers-color-scheme: dark)").matches;
}

export function isDarkMode(settings) {
  if (settings.themeMode === "dark") {
    return true;
  }
  if (settings.themeMode === "light") {
    return false;
  }
  return prefersDark();
}

export function applyTheme(settings, doc = document) {
  const root = doc.documentElement;
  const dark = isDarkMode(settings);
  root.dataset.theme = dark ? "dark" : "light";
  root.dataset.themeMode = settings.themeMode;
  root.style.setProperty("--accent", resolveAccent(settings));
}

/** 初始化主题并跟随系统；返回当前设置。 */
export async function initTheme() {
  const settings = await loadSettings();
  applyTheme(settings);
  const media = typeof matchMedia === "function" ? matchMedia("(prefers-color-scheme: dark)") : null;
  if (media) {
    const onChange = () => {
      if (document.documentElement.dataset.themeMode === "auto") {
        document.documentElement.dataset.theme = media.matches ? "dark" : "light";
      }
    };
    if (typeof media.addEventListener === "function") {
      media.addEventListener("change", onChange);
    }
  }
  if (chrome?.storage?.onChanged) {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area === "local" && changes[SETTINGS_KEY]?.newValue) {
        applyTheme(changes[SETTINGS_KEY].newValue);
      }
    });
  }
  return settings;
}

/** 弹窗右上角快捷切换：自动 → 浅色 → 深色 → 自动。 */
export function nextThemeMode(current) {
  if (current === "auto") {
    return "light";
  }
  if (current === "light") {
    return "dark";
  }
  return "auto";
}

/** 明暗模式文案的 i18n key。 */
export const THEME_MODE_KEYS = {
  auto: "theme_mode_auto",
  light: "theme_mode_light",
  dark: "theme_mode_dark",
};
