/**
 * 生成扩展图标：深色底 + 主题色盾牌 + 环形倒计时 + 二维码定位角。
 *
 * 只依赖 Node.js 内置模块（zlib/fs），无需 npm 依赖：
 *   node tools/build-icons.mjs
 *
 * 同时输出：
 *   icons/icon.svg（128×128 可改色源文件，改 --accent 即可）
 *   icons/icon16.png、icon32.png、icon48.png、icon128.png
 */

import { deflateSync } from "node:zlib";
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const DESIGN = 128;
const SS = 6; // 每个像素 6×6 超采样，用于抗锯齿

const C = {
  bgTop: [30, 41, 66],
  bgBottom: [9, 15, 28],
  accent: [47, 111, 237],
  accentLight: [96, 165, 250],
  shieldFill: [14, 26, 46],
  white: [237, 243, 252],
  track: [255, 255, 255],
};

const RING_CENTER = [64, 62];
const RING_RADIUS = 27;
const RING_WIDTH = 4.2;
const FINDERS = [
  [48, 47],
  [80, 47],
  [48, 79],
];

/* ------------------------------- 基础绘制工具 ------------------------------- */

function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function lerpColor(a, b, t) {
  return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
}

function blend(base, over, alpha) {
  return lerpColor(base, over, clamp01(alpha));
}

/** 圆角矩形的有符号距离（<=0 表示在内部）。 */
function sdRoundBox(u, v, cx, cy, halfW, halfH, radius) {
  const qx = Math.abs(u - cx) - (halfW - radius);
  const qy = Math.abs(v - cy) - (halfH - radius);
  const ax = Math.max(qx, 0);
  const ay = Math.max(qy, 0);
  return Math.hypot(ax, ay) + Math.min(Math.max(qx, qy), 0) - radius;
}

/** 盾牌轮廓：与 SVG 中的 path 完全一致。 */
function buildShieldPolygon() {
  const points = [
    [64, 16],
    [100, 28],
    [100, 62],
  ];
  const cubic = (p0, p1, p2, p3) => {
    for (let i = 1; i <= 16; i += 1) {
      const t = i / 16;
      const mt = 1 - t;
      const x =
        mt * mt * mt * p0[0] +
        3 * mt * mt * t * p1[0] +
        3 * mt * t * t * p2[0] +
        t * t * t * p3[0];
      const y =
        mt * mt * mt * p0[1] +
        3 * mt * mt * t * p1[1] +
        3 * mt * t * t * p2[1] +
        t * t * t * p3[1];
      points.push([x, y]);
    }
  };
  cubic([100, 62], [100, 86], [82, 102], [64, 112]);
  cubic([64, 112], [46, 102], [28, 86], [28, 62]);
  points.push([28, 28]);
  return points;
}

const SHIELD = buildShieldPolygon();

function pointInPolygon(x, y, polygon) {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i, i += 1) {
    const [xi, yi] = polygon[i];
    const [xj, yj] = polygon[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

function distanceToSegment(x, y, ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  const lengthSquared = dx * dx + dy * dy;
  const t = lengthSquared === 0 ? 0 : clamp01(((x - ax) * dx + (y - ay) * dy) / lengthSquared);
  return Math.hypot(x - (ax + t * dx), y - (ay + t * dy));
}

function distanceToPolygon(x, y, polygon) {
  let best = Infinity;
  for (let i = 0; i < polygon.length; i += 1) {
    const a = polygon[i];
    const b = polygon[(i + 1) % polygon.length];
    best = Math.min(best, distanceToSegment(x, y, a[0], a[1], b[0], b[1]));
  }
  return best;
}

function angleAlong(u, v) {
  const theta = Math.atan2(v - RING_CENTER[1], u - RING_CENTER[0]);
  const start = -Math.PI / 2;
  return (theta - start + Math.PI * 2) % (Math.PI * 2);
}

function ringPoint(angle) {
  return [
    RING_CENTER[0] + Math.cos(angle) * RING_RADIUS,
    RING_CENTER[1] + Math.sin(angle) * RING_RADIUS,
  ];
}

const ARC_START = ringPoint(-Math.PI / 2);
const ARC_END = ringPoint(Math.PI);
const ARC_SWEEP = Math.PI * 1.5;

function inRingBand(u, v, width) {
  const d = Math.hypot(u - RING_CENTER[0], v - RING_CENTER[1]);
  return Math.abs(d - RING_RADIUS) <= width / 2;
}

function inFinder(u, v, cx, cy, size, border) {
  const dx = Math.abs(u - cx);
  const dy = Math.abs(v - cy);
  const half = size / 2;
  if (dx > half || dy > half) {
    return 0;
  }
  const hole = half - border;
  if (dx > hole && dy > hole) {
    return 0; // 边框外的角
  }
  if (dx <= hole && dy <= hole) {
    return dx <= 1.7 && dy <= 1.7 ? 1 : 0; // 中心小方块
  }
  return 1;
}

/** 返回某个设计坐标点的颜色与不透明度。 */
function sample(u, v, size) {
  const bgDistance = sdRoundBox(u, v, 64, 64, 64, 64, 28);
  if (bgDistance > 0) {
    return null;
  }

  // 深色底 + 左上角主题色微光
  let t = clamp01(v / DESIGN);
  t = t * t * (3 - 2 * t);
  let color = lerpColor(C.bgTop, C.bgBottom, t * 0.92);
  const glowDistance = Math.hypot(u - 46, v - 32);
  if (glowDistance < 76) {
    color = blend(color, C.accent, (1 - glowDistance / 76) ** 2 * 0.12);
  }

  // 顶部内高光，增强立体感
  if (bgDistance > -1.2) {
    color = blend(color, C.accentLight, 0.18);
  }

  const insideShield = pointInPolygon(u, v, SHIELD);
  const shieldEdge = distanceToPolygon(u, v, SHIELD);
  const detailed = size >= 48;

  if (detailed) {
    if (insideShield) {
      color = lerpColor(C.shieldFill, C.accent, clamp01((62 - v) / 120) * 0.12);
    }
    if (insideShield && shieldEdge <= 2.6) {
      color = C.accent;
    }

    if (insideShield) {
      // 倒计时轨道
      if (inRingBand(u, v, RING_WIDTH)) {
        color = blend(color, C.track, 0.14);
      }
      // 剩余 270° 的倒计时弧
      const angle = angleAlong(u, v);
      const onArc =
        inRingBand(u, v, RING_WIDTH) &&
        (angle <= ARC_SWEEP ||
          Math.hypot(u - ARC_START[0], v - ARC_START[1]) <= RING_WIDTH / 2 ||
          Math.hypot(u - ARC_END[0], v - ARC_END[1]) <= RING_WIDTH / 2);
      if (onArc) {
        color = C.white;
      }

      // 二维码三个定位角
      for (const [cx, cy] of FINDERS) {
        if (inFinder(u, v, cx, cy, 10, 2.4)) {
          color = C.white;
        }
      }
    }
  } else if (insideShield) {
    color = C.accent;
    if (shieldEdge <= 2.2) {
      color = blend(C.accent, C.accentLight, 0.6);
    }
    const ringWidth = size <= 20 ? 10 : 8;
    if (inRingBand(u, v, ringWidth)) {
      color = blend(color, C.track, 0.16);
    }
    const angle = angleAlong(u, v);
    const onArc =
      inRingBand(u, v, ringWidth) &&
      (angle <= ARC_SWEEP ||
        Math.hypot(u - ARC_START[0], v - ARC_START[1]) <= ringWidth / 2 ||
        Math.hypot(u - ARC_END[0], v - ARC_END[1]) <= ringWidth / 2);
    if (onArc) {
      color = C.white;
    }
    const dotRadius = size <= 20 ? 6 : 4.5;
    if (Math.hypot(u - RING_CENTER[0], v - RING_CENTER[1]) <= dotRadius) {
      color = C.white;
    }
  }

  return color;
}

/* --------------------------------- PNG 编码 -------------------------------- */

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

function pngChunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typeBytes = Buffer.from(type, "ascii");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBytes, data])));
  return Buffer.concat([length, typeBytes, data, crc]);
}

function render(size) {
  const pixels = Buffer.alloc(size * size * 4);
  const scale = DESIGN / size;
  const samples = SS * SS;

  for (let py = 0; py < size; py += 1) {
    for (let px = 0; px < size; px += 1) {
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      for (let sy = 0; sy < SS; sy += 1) {
        for (let sx = 0; sx < SS; sx += 1) {
          const u = (px + (sx + 0.5) / SS) * scale;
          const v = (py + (sy + 0.5) / SS) * scale;
          const color = sample(u, v, size);
          if (color) {
            r += color[0];
            g += color[1];
            b += color[2];
            a += 1;
          }
        }
      }
      const index = (py * size + px) * 4;
      if (a > 0) {
        pixels[index] = Math.round(r / a);
        pixels[index + 1] = Math.round(g / a);
        pixels[index + 2] = Math.round(b / a);
        pixels[index + 3] = Math.round((a / samples) * 255);
      }
    }
  }

  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8; // bit depth
  header[9] = 6; // RGBA
  header[10] = 0;
  header[11] = 0;
  header[12] = 0;

  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y += 1) {
    raw[y * (size * 4 + 1)] = 0; // filter: none
    pixels.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4);
  }

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", header),
    pngChunk("IDAT", deflateSync(raw, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

/* ---------------------------------- SVG 源 ---------------------------------- */

function svgSource() {
  const hex = ([r, g, b]) =>
    "#" + [r, g, b].map((value) => value.toString(16).padStart(2, "0")).join("").toUpperCase();
  const accentHex = hex(C.accent);
  const accentLightHex = hex(C.accentLight);

  const finders = FINDERS.map(
    ([cx, cy]) => `  <g>
    <rect x="${cx - 5}" y="${cy - 5}" width="10" height="10" fill="none" stroke="#EDF3FC" stroke-width="2.4"/>
    <rect x="${cx - 1.7}" y="${cy - 1.7}" width="3.4" height="3.4" fill="#EDF3FC"/>
  </g>`,
  ).join("\n");

  return `<svg width="128" height="128" viewBox="0 0 128 128" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="扫码增强认证器图标">
  <!-- 改色只需修改下面的 accent（主题色）与 accent-light（高光色）。 -->
  <style>
    :root { --accent: ${accentHex}; --accent-light: ${accentLightHex}; }
  </style>
  <defs>
    <linearGradient id="bg" x1="20" y1="6" x2="108" y2="124" gradientUnits="userSpaceOnUse">
      <stop stop-color="#1E2942"/>
      <stop offset="1" stop-color="#090F1C"/>
    </linearGradient>
    <radialGradient id="glow" cx="0" cy="0" r="1" gradientTransform="translate(46 32) rotate(47) scale(76)" gradientUnits="userSpaceOnUse">
      <stop stop-color="var(--accent)" stop-opacity="0.16"/>
      <stop offset="1" stop-color="var(--accent)" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="shield" x1="64" y1="16" x2="64" y2="112" gradientUnits="userSpaceOnUse">
      <stop stop-color="#1A2A47"/>
      <stop offset="1" stop-color="#0D1A30"/>
    </linearGradient>
  </defs>

  <rect width="128" height="128" rx="28" fill="url(#bg)"/>
  <rect width="128" height="128" rx="28" fill="url(#glow)"/>

  <path d="M64 16 L100 28 L100 62 C100 86 82 102 64 112 C46 102 28 86 28 62 L28 28 Z"
        fill="url(#shield)" stroke="var(--accent)" stroke-width="5" stroke-linejoin="round"/>

  <circle cx="64" cy="62" r="${RING_RADIUS}" stroke="#FFFFFF" stroke-opacity="0.14" stroke-width="${RING_WIDTH}"/>
  <path d="M64 35 A27 27 0 1 1 37 62" stroke="#EDF3FC" stroke-width="${RING_WIDTH}" stroke-linecap="round"/>

${finders}
</svg>
`;
}

/* ---------------------------------- 输出 ---------------------------------- */

const here = path.dirname(fileURLToPath(import.meta.url));
const iconsDir = path.join(here, "..", "icons");
mkdirSync(iconsDir, { recursive: true });

for (const size of [16, 32, 48, 128]) {
  const target = path.join(iconsDir, `icon${size}.png`);
  writeFileSync(target, render(size));
  console.log(`已生成 ${target}`);
}

const svgTarget = path.join(iconsDir, "icon.svg");
writeFileSync(svgTarget, svgSource(), "utf8");
console.log(`已生成 ${svgTarget}`);
