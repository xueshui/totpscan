/**
 * 校验打包产物（仅依赖 Node.js 内置模块）：
 *   node tools/verify-pack.mjs
 *   node tools/verify-pack.mjs dist/totpscan-extension-v1.0.0-dev.zip
 *   node tools/verify-pack.mjs dist/totpscan-extension-v1.0.0-store.zip --store
 *
 * 校验内容：
 * - zip 条目路径使用正斜杠、无重复、无越界路径；
 * - manifest 声明的图标 / popup / options / background 均存在；
 * - content、vendor 运行时文件存在；
 * - popup / options 的 HTML 本地引用均存在；
 * - 四个 PNG 图标的 PNG 签名与尺寸正确；
 * - 所有条目可解压且 CRC 一致；
 * - 未混入 tests/tools/package.json 等非运行时文件。
 */

import { inflateRawSync } from "node:zlib";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const manifest = JSON.parse(readFileSync(path.join(root, "manifest.json"), "utf8"));
const defaultZip = path.join(root, "dist", `totpscan-extension-v${manifest.version}-dev.zip`);
const storeMode = process.argv.includes("--store");
const zipArg = process.argv.slice(2).find((arg) => arg !== "--store");
const zipPath = path.resolve(zipArg ?? (storeMode ? defaultZip.replace("-dev", "-store") : defaultZip));

if (!existsSync(zipPath)) {
  console.error(`找不到打包产物：${zipPath}`);
  process.exit(1);
}

/* -------------------------------- ZIP 读取 -------------------------------- */

const buffer = readFileSync(zipPath);

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
})();

function findEndOfCentralDirectory() {
  for (let offset = buffer.length - 22; offset >= Math.max(0, buffer.length - 22 - 0xffff); offset -= 1) {
    if (buffer.readUInt32LE(offset) === 0x06054b50) {
      return offset;
    }
  }
  throw new Error("不是合法的 zip：找不到中央目录结束标记");
}

const eocd = findEndOfCentralDirectory();
const entryCount = buffer.readUInt16LE(eocd + 10);
const centralOffset = buffer.readUInt32LE(eocd + 16);

function readEntries() {
  const entries = [];
  let cursor = centralOffset;
  for (let i = 0; i < entryCount; i += 1) {
    if (buffer.readUInt32LE(cursor) !== 0x02014b50) {
      throw new Error(`中央目录第 ${i + 1} 项签名不正确`);
    }
    const method = buffer.readUInt16LE(cursor + 10);
    const crc = buffer.readUInt32LE(cursor + 16);
    const compressedSize = buffer.readUInt32LE(cursor + 20);
    const uncompressedSize = buffer.readUInt32LE(cursor + 24);
    const nameLength = buffer.readUInt16LE(cursor + 28);
    const extraLength = buffer.readUInt16LE(cursor + 30);
    const commentLength = buffer.readUInt16LE(cursor + 32);
    const localOffset = buffer.readUInt32LE(cursor + 42);
    const name = buffer.subarray(cursor + 46, cursor + 46 + nameLength).toString("utf8");

    if (buffer.readUInt32LE(localOffset) !== 0x04034b50) {
      throw new Error(`条目 ${name} 的本地文件头签名不正确`);
    }
    const localNameLength = buffer.readUInt16LE(localOffset + 26);
    const localExtraLength = buffer.readUInt16LE(localOffset + 28);
    const dataOffset = localOffset + 30 + localNameLength + localExtraLength;
    const compressed = buffer.subarray(dataOffset, dataOffset + compressedSize);
    let data;
    if (method === 0) {
      data = compressed;
    } else if (method === 8) {
      data = inflateRawSync(compressed);
    } else {
      throw new Error(`条目 ${name} 使用了不支持的压缩方法 ${method}`);
    }

    entries.push({
      name,
      method,
      crc,
      compressedSize,
      uncompressedSize,
      data,
    });

    cursor += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

let entries;
try {
  entries = readEntries();
} catch (error) {
  console.error(`读取 zip 失败：${error.message}`);
  process.exit(1);
}

/* --------------------------------- 校验 ---------------------------------- */

const checks = [];
const warnings = [];
function check(label, ok, detail = "") {
  checks.push({ label, ok, detail });
}

const names = entries.map((entry) => entry.name);
const entryMap = new Map(entries.map((entry) => [entry.name, entry]));

function lookup(name) {
  return entryMap.get(name) ?? null;
}

function caseHint(name) {
  const lower = name.toLowerCase();
  const hit = names.find((candidate) => candidate.toLowerCase() === lower);
  return hit && hit !== name ? `大小写不一致，zip 中为 ${hit}` : "";
}

function requireFile(name, label = name) {
  const entry = lookup(name);
  const hint = caseHint(name);
  check(`${label} 存在`, Boolean(entry), entry ? name : hint || "缺失");
  return entry;
}

// 1. 路径规范
const badSeparators = names.filter((name) => name.includes("\\"));
check("zip 条目使用正斜杠路径", badSeparators.length === 0, badSeparators.join(", ") || `${names.length} 个条目`);
const unsafePaths = names.filter(
  (name) => name.startsWith("/") || /^[A-Za-z]:/.test(name) || name.split("/").includes(".."),
);
check("zip 条目无绝对路径或越界路径", unsafePaths.length === 0, unsafePaths.join(", ") || "通过");
const duplicates = names.filter((name, index) => names.indexOf(name) !== index);
check("zip 条目无重复", duplicates.length === 0, [...new Set(duplicates)].join(", ") || "通过");

// 2. manifest 声明
requireFile("manifest.json");
const zippedManifest = lookup("manifest.json");
if (storeMode) {
  let parsed = null;
  try {
    parsed = JSON.parse(zippedManifest.data.toString("utf8"));
  } catch {
    parsed = null;
  }
  check("商店包 manifest 可解析", Boolean(parsed), parsed ? "通过" : "解析失败");
  check("商店包已移除 key", Boolean(parsed) && !("key" in parsed), parsed && "key" in parsed ? "仍包含 key" : "通过");
  const expected = { ...manifest };
  delete expected.key;
  check(
    "商店包 manifest 其余字段与源码一致",
    Boolean(parsed) && JSON.stringify(parsed) === JSON.stringify(expected),
    parsed ? "通过" : "无法比较",
  );
} else {
  let parsed = null;
  try {
    parsed = JSON.parse(zippedManifest.data.toString("utf8"));
  } catch {
    parsed = null;
  }
  check("自用包 manifest 可解析", Boolean(parsed), parsed ? "通过" : "解析失败");
  check("自用包 manifest 含本地注入的 key", Boolean(parsed) && typeof parsed.key === "string" && parsed.key.length > 0, parsed?.key ? "通过" : "缺少 key");
  check("源码 manifest 不含 key", !("key" in manifest), "key" in manifest ? "源码仍包含 key" : "通过");
  const expected = { ...manifest };
  delete expected.key;
  const withoutKey = parsed ? { ...parsed } : null;
  if (withoutKey) delete withoutKey.key;
  check(
    "自用包 manifest 除 key 外与源码一致",
    Boolean(withoutKey) && JSON.stringify(withoutKey) === JSON.stringify(expected),
    withoutKey ? "通过" : "无法比较",
  );
}
check("未打包 keys/ 私钥目录", !names.some((name) => name.startsWith("keys/")), "通过");

// 2.1 清单多语言：默认语种存在，且所有语种覆盖清单中的 __MSG_* 占位符
if (manifest.default_locale) {
  requireFile(`_locales/${manifest.default_locale}/messages.json`, "默认语种 messages.json");
  const locales = [
    ...new Set(
      names.map((name) => name.match(/^_locales\/([^/]+)\/messages\.json$/)?.[1]).filter(Boolean),
    ),
  ].sort();
  check("zip 内包含 _locales", locales.length > 0, locales.join(", ") || "缺失");
  const placeholders = new Set(
    [manifest.name, manifest.description, manifest.action?.default_title]
      .filter((value) => typeof value === "string")
      .flatMap((value) => [...value.matchAll(/__MSG_([A-Za-z0-9_@]+)__/g)].map((match) => match[1])),
  );
  check("清单名称与描述使用 __MSG_ 引用", placeholders.size > 0, [...placeholders].join(", ") || "未使用");
  const localeMessages = new Map();
  for (const locale of locales) {
    const entry = lookup(`_locales/${locale}/messages.json`);
    let messages = null;
    try {
      messages = JSON.parse(entry.data.toString("utf8"));
    } catch {
      messages = null;
    }
    check(`_locales/${locale}/messages.json 可解析`, Boolean(messages), messages ? "通过" : "解析失败");
    if (!messages) {
      continue;
    }
    localeMessages.set(locale, messages);
    const missingKeys = [...placeholders].filter((key) => typeof messages[key]?.message !== "string");
    check(`_locales/${locale} 覆盖全部占位符`, missingKeys.length === 0, missingKeys.join(", ") || "通过");
    const nameLength = [...(messages.extName?.message ?? "")].length;
    const descLength = [...(messages.extDesc?.message ?? "")].length;
    check(`_locales/${locale} 名称 1–45 字符`, nameLength > 0 && nameLength <= 45, `${nameLength} 字符`);
    check(`_locales/${locale} 描述 1–132 字符`, descLength > 0 && descLength <= 132, `${descLength} 字符`);
  }

  const expectedLocales = ["zh_CN", "en", "zh_TW", "ja"];
  check(
    "zip 内仅包含四种受支持语言",
    locales.length === expectedLocales.length && expectedLocales.every((locale) => locales.includes(locale)),
    locales.join(", ") || "缺失",
  );

  const base = localeMessages.get(manifest.default_locale);
  if (base) {
    const baseKeys = Object.keys(base).sort();
    for (const locale of expectedLocales) {
      const messages = localeMessages.get(locale);
      if (!messages) {
        check(`_locales/${locale} 存在`, false, "缺失");
        continue;
      }
      const keys = Object.keys(messages).sort();
      const missing = baseKeys.filter((key) => !keys.includes(key));
      const extra = keys.filter((key) => !baseKeys.includes(key));
      check(`_locales/${locale} key 集合与默认语种一致`, missing.length === 0 && extra.length === 0, [
        missing.length ? `缺少 ${missing.slice(0, 6).join(", ")}` : "",
        extra.length ? `多出 ${extra.slice(0, 6).join(", ")}` : "",
      ]
        .filter(Boolean)
        .join("；") || `${keys.length} 个 key`);

      const empty = keys.filter((key) => typeof messages[key]?.message !== "string" || messages[key].message.trim() === "");
      check(`_locales/${locale} 无空值`, empty.length === 0, empty.slice(0, 6).join(", ") || "通过");

      const placeholderMismatch = baseKeys.filter((key) => {
        if (!messages[key] || typeof messages[key].message !== "string") {
          return false;
        }
        const names = (text) => [...String(text).matchAll(/\{([A-Za-z0-9_]+)\}/g)].map((match) => match[1]).sort().join(",");
        return names(base[key].message) !== names(messages[key].message);
      });
      check(
        `_locales/${locale} 占位符与默认语种一致`,
        placeholderMismatch.length === 0,
        placeholderMismatch.slice(0, 6).join(", ") || "通过",
      );
    }
  }
}

const iconSizes = { ...(manifest.icons ?? {}) };
for (const [size, relative] of Object.entries(iconSizes)) {
  const entry = requireFile(relative, `图标 ${size}px`);
  if (!entry) {
    continue;
  }
  const isPng =
    entry.data.length > 24 &&
    entry.data.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const width = isPng ? entry.data.readUInt32BE(16) : 0;
  const height = isPng ? entry.data.readUInt32BE(20) : 0;
  check(
    `图标 ${size}px 为正确尺寸的 PNG`,
    isPng && width === Number(size) && height === Number(size),
    isPng ? `${width}×${height}` : "PNG 签名或 IHDR 无效",
  );
}
requireFile("icons/icon.svg", "SVG 图标源文件");

requireFile(manifest.action?.default_popup, "popup 页面");
requireFile(manifest.options_ui?.page, "options 页面");
requireFile(manifest.background?.service_worker, "background service worker");
requireFile("content/content.js", "content script");
requireFile("vendor/jsQR.js", "jsQR 本地依赖");
requireFile("vendor/qr-encode.js", "本地二维码编码器");

// 2.2 签名与信任根已移除：包内不得残留预置公钥或验签代码
check("包内不含预置信任根文件", !lookup("common/trusted-keys.js"), lookup("common/trusted-keys.js") ? "不应包含" : "通过");
check(
  "包内不含 demo 信任根文件",
  !lookup("common/trusted-keys.demo.js"),
  lookup("common/trusted-keys.demo.js") ? "不应包含" : "通过",
);
const trustResidue = entries
  .filter((entry) =>
    entry.name.endsWith(".js") || entry.name.endsWith(".mjs") || entry.name.endsWith(".json"),
  )
  .filter((entry) =>
    /TRUSTED_BINDING_KEYS|BUILTIN_BINDING_KEY_COUNT|totpscan-keys\.json|bindingSignatureInput/.test(
      entry.data.toString("utf8"),
    ),
  )
  .map((entry) => entry.name);
check("包内不含信任根/验签代码残留", trustResidue.length === 0, trustResidue.join(", ") || "通过");
const legacyPublicKey = "f99_Ur3P8Us4VTHa7G0sX7Q1lIqDYdui3n8f1wgJP4s";
const legacyHits = entries
  .filter((entry) => entry.data.includes(legacyPublicKey))
  .map((entry) => entry.name);
check("包内不含已废弃的 bk-dev-1 公钥", legacyHits.length === 0, legacyHits.join(", ") || "通过");

// 二维码相关脚本必须完全本地，不得引用远程资源
for (const name of ["vendor/qr-encode.js", "common/qr-export.js"]) {
  const entry = lookup(name);
  if (!entry) {
    continue;
  }
  const source = entry.data.toString("utf8");
  const remote = /(?:https?:)?\/\/[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
  const hits = [...source.matchAll(remote)].map((match) => match[0]);
  check(`${name} 不引用远程资源`, hits.length === 0, hits.slice(0, 3).join(", ") || "通过");
}

// 3. HTML 本地资源引用
function verifyHtmlAssets(pagePath) {
  const page = lookup(pagePath);
  if (!page) {
    return;
  }
  const html = page.data.toString("utf8");
  for (const match of html.matchAll(/(?:src|href)\s*=\s*["']([^"']+)["']/g)) {
    const reference = match[1];
    if (/^(?:[a-z]+:|\/\/|#)/i.test(reference)) {
      continue;
    }
    const clean = reference.split("?")[0].split("#")[0];
    if (!clean) {
      continue;
    }
    const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(pagePath), clean));
    const entry = lookup(resolved);
    check(
      `${pagePath} 引用 ${clean}`,
      Boolean(entry),
      entry ? resolved : caseHint(resolved) || "缺失",
    );
  }
}

verifyHtmlAssets(manifest.action?.default_popup);
verifyHtmlAssets(manifest.options_ui?.page);

// 4. 全量解压与 CRC
const crcFailures = entries.filter((entry) => {
  let crc = 0xffffffff;
  const table = CRC_TABLE;
  for (const byte of entry.data) {
    crc = table[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  const actual = (crc ^ 0xffffffff) >>> 0;
  return actual !== entry.crc || entry.data.length !== entry.uncompressedSize;
});
check("所有条目解压成功且 CRC 一致", crcFailures.length === 0, crcFailures.map((entry) => entry.name).join(", ") || `${entries.length} 个条目`);

// 5. 排除非运行时文件
for (const forbidden of ["package.json", "package-lock.json", "EDGE.md"]) {
  check(`未打包 ${forbidden}`, !lookup(forbidden), lookup(forbidden) ? "不应包含" : "通过");
}
for (const prefix of ["tests/", "tools/", "dist/", "store/", "store-v2/"]) {
  const hit = names.find((name) => name.startsWith(prefix));
  check(`未打包 ${prefix}`, !hit, hit || "通过");
}

/* --------------------------------- 输出 ---------------------------------- */

console.log(`校验产物：${zipPath}`);
console.log(`条目数量：${entries.length}\n`);

let failed = 0;
for (const item of checks) {
  if (!item.ok) {
    failed += 1;
  }
  const status = item.ok ? "通过" : "失败";
  console.log(`[${status}] ${item.label}${item.detail ? `：${item.detail}` : ""}`);
}

console.log("\n条目清单：");
for (const name of [...names].sort()) {
  console.log(`  ${name}`);
}

if (warnings.length > 0) {
  console.log("");
  for (const warning of warnings) {
    console.log(`[警告] ${warning}`);
  }
}

console.log(`\n结果：${failed === 0 ? "全部通过" : `${failed} 项失败`}（${checks.length} 项检查）`);
if (failed > 0) {
  process.exit(1);
}
