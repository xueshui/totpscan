/**
 * 打包扩展为 zip（仅依赖 Node.js 内置模块，无 npm 依赖）：
 *   node tools/pack.mjs           # 自用/开发包：从 keys/extension-public-key.der 临时注入 key，扩展 ID 固定
 *   node tools/pack.mjs --store   # 商店提审包：不注入 key，由商店重新分配 ID
 *
 * 源码 manifest.json 不包含 key；本地密钥目录已被 .gitignore 排除。
 *
 * 特点：
 * - zip 内路径统一使用正斜杠 `/`，避免部分解压工具把目录名当文件名；
 * - 固定时间戳，输出可复现；
 * - 打包前先检查 manifest 声明的关键文件是否齐全；
 * - 排除 dist/tests/tools/keys/store/store-v2 等非运行时文件；
 * - 两种产物文件名带 -dev / -store 后缀，并各自打印大小与 SHA256。
 */

import { createHash } from "node:crypto";
import { deflateRawSync } from "node:zlib";
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const manifest = JSON.parse(readFileSync(path.join(root, "manifest.json"), "utf8"));
const version = manifest.version;
const storeMode = process.argv.includes("--store");

const EXCLUDED_TOP_LEVEL = new Set([
  "dist",
  "store",
  "store-v2",
  "tests",
  "tools",
  "keys",
  "package.json",
  "package-lock.json",
  "node_modules",
  "EDGE.md",
  "privacy.zh-CN.html",
  "privacy.zh-TW.html",
  "privacy.en.html",
  "privacy.ja.html",
  ".gitignore",
  ".DS_Store",
]);

function walk(directory, prefix = "") {
  const result = [];
  for (const name of readdirSync(directory)) {
    if (prefix === "" && EXCLUDED_TOP_LEVEL.has(name)) {
      continue;
    }
    const absolute = path.join(directory, name);
    const relative = prefix === "" ? name : `${prefix}/${name}`;
    const stat = statSync(absolute);
    if (stat.isDirectory()) {
      result.push(...walk(absolute, relative));
    } else if (stat.isFile()) {
      result.push({ absolute, relative, size: stat.size });
    }
  }
  return result;
}

/* --------------------------------- 预检 ---------------------------------- */

const required = new Set([
  "manifest.json",
  "background.js",
  "content/content.js",
  "vendor/jsQR.js",
  "vendor/qr-encode.js",
  manifest.action?.default_popup,
  manifest.options_ui?.page,
  manifest.background?.service_worker,
  ...Object.values(manifest.icons ?? {}),
  ...Object.values(manifest.action?.default_icon ?? {}),
  manifest.default_locale ? `_locales/${manifest.default_locale}/messages.json` : null,
].filter(Boolean));

const missing = [...required].filter((relative) => {
  try {
    return !statSync(path.join(root, relative)).isFile();
  } catch {
    return true;
  }
});
if (missing.length > 0) {
  console.error("打包前检查失败，以下文件缺失：");
  for (const relative of missing) {
    console.error(`  - ${relative}`);
  }
  process.exit(1);
}

/* ------------------------------- ZIP 写入 -------------------------------- */

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

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

// 固定为 2020-01-01 00:00，保证同样输入产出同样 zip。
const DOS_TIME = 0;
const DOS_DATE = ((2020 - 1980) << 9) | (1 << 5) | 1;

function buildZip(entries) {
  const localParts = [];
  const centralParts = [];
  let offset = 0;

  for (const entry of entries) {
    const name = Buffer.from(entry.relative, "utf8");
    const raw = entry.content ?? readFileSync(entry.absolute);
    const crc = crc32(raw);
    const compressed = deflateRawSync(raw, { level: 9 });
    const useDeflate = compressed.length < raw.length;
    const payload = useDeflate ? compressed : raw;
    const method = useDeflate ? 8 : 0;

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt16LE(DOS_TIME, 10);
    local.writeUInt16LE(DOS_DATE, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(payload.length, 18);
    local.writeUInt32LE(raw.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    localParts.push(local, name, payload);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt16LE(DOS_TIME, 12);
    central.writeUInt16LE(DOS_DATE, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(payload.length, 20);
    central.writeUInt32LE(raw.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE((0o644 << 16) >>> 0, 38);
    central.writeUInt32LE(offset, 42);
    centralParts.push(central, name);

    offset += local.length + name.length + payload.length;
  }

  const centralSize = centralParts.reduce((total, part) => total + part.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(0, 4);
  end.writeUInt16LE(0, 6);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralSize, 12);
  end.writeUInt32LE(offset, 16);
  end.writeUInt16LE(0, 20);

  return Buffer.concat([...localParts, ...centralParts, end]);
}

/* --------------------------------- 输出 ---------------------------------- */

const files = walk(root).sort((a, b) => a.relative.localeCompare(b.relative, "en"));

// 源码 manifest 不含 key：dev 包从本地公钥文件临时注入，store 包保持无 key。
let manifestKey = null;
if (!storeMode) {
  const localKeyPath = path.join(root, "keys", "extension-public-key.der");
  try {
    manifestKey = readFileSync(localKeyPath).toString("base64");
  } catch {
    console.error("自用包需要本地公钥 keys/extension-public-key.der 才能固定扩展 ID。");
    console.error("该目录已被 .gitignore 排除；商店包可直接使用 --store，无需本地 key。");
    process.exit(1);
  }
}

const manifestIndex = files.findIndex((file) => file.relative === "manifest.json");
if (manifestIndex < 0) {
  console.error("打包内容中缺少 manifest.json。");
  process.exit(1);
}
const zipManifest = { ...manifest };
if (manifestKey) {
  zipManifest.key = manifestKey;
} else {
  delete zipManifest.key;
}
files[manifestIndex] = {
  ...files[manifestIndex],
  content: Buffer.from(`${JSON.stringify(zipManifest, null, 2)}\n`, "utf8"),
};

const zip = buildZip(files);

const dist = path.join(root, "dist");
mkdirSync(dist, { recursive: true });
const suffix = storeMode ? "store" : "dev";
const target = path.join(dist, `totpscan-extension-v${version}-${suffix}.zip`);
writeFileSync(target, zip);

const sha256 = createHash("sha256").update(zip).digest("hex").toUpperCase();

console.log(`模式：${storeMode ? "商店提审包（不含 key）" : "自用包（注入本地 key，ID 固定）"}`);
console.log(`已生成 ${target}`);
console.log(`文件数：${files.length}，大小：${zip.length} 字节`);
console.log(`SHA256：${sha256}`);
if (!storeMode) {
  const id = [...createHash("sha256").update(Buffer.from(manifestKey, "base64")).digest().subarray(0, 16)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .split("")
    .map((nibble) => "abcdefghijklmnop"[parseInt(nibble, 16)])
    .join("");
  console.log(`固定扩展 ID：${id}`);
}
