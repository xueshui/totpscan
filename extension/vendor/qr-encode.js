/**
 * 本地最小二维码编码器（不依赖任何远程资源）。
 *
 * 仅用于单个账户 otpauth:// 链接的屏幕展示：
 * - byte 模式（UTF-8）
 * - 纠错级别 ECC M
 * - 版本 1–15（byte 容量 14–412 字节）
 * - 自动挑选 8 种掩码中惩罚分最低的一个
 *
 * 对照实现：ISO/IEC 18004 与 Nayuki QR Code generator 的公开算法说明。
 */

/** ECC M 每块纠错码字数，下标即版本号（0 占位）。 */
const ECC_CODEWORDS_PER_BLOCK = [
  -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24,
];

/** ECC M 分块数，下标即版本号（0 占位）。 */
const NUM_ERROR_CORRECTION_BLOCKS = [
  -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10,
];

const MIN_VERSION = 1;
const MAX_VERSION = 15;
/** ECC M 的格式信息取值。 */
const ECC_FORMAT_BITS = 0;

function getNumRawDataModules(version) {
  let result = (16 * version + 128) * version + 64;
  if (version >= 2) {
    const numAlign = Math.floor(version / 7) + 2;
    result -= (25 * numAlign - 10) * numAlign - 55;
    if (version >= 7) {
      result -= 36;
    }
  }
  return result;
}

function getNumDataCodewords(version) {
  return (
    Math.floor(getNumRawDataModules(version) / 8) -
    ECC_CODEWORDS_PER_BLOCK[version] * NUM_ERROR_CORRECTION_BLOCKS[version]
  );
}

function getBit(value, index) {
  return ((value >>> index) & 1) !== 0;
}

function getAlignmentPatternPositions(version) {
  if (version === 1) {
    return [];
  }
  const numAlign = Math.floor(version / 7) + 2;
  const step = Math.ceil((version * 4 + 4) / (numAlign * 2 - 2)) * 2;
  const result = [6];
  for (let pos = version * 4 + 10; result.length < numAlign; pos -= step) {
    result.splice(1, 0, pos);
  }
  return result;
}

/* --------------------------- GF(256) 与 Reed–Solomon --------------------------- */

function gfMultiply(x, y) {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z & 0xff;
}

function reedSolomonDivisor(degree) {
  const result = new Uint8Array(degree);
  result[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < result.length; j++) {
      result[j] = gfMultiply(result[j], root);
      if (j + 1 < result.length) {
        result[j] ^= result[j + 1];
      }
    }
    root = gfMultiply(root, 0x02);
  }
  return result;
}

function reedSolomonRemainder(data, divisor) {
  const result = new Uint8Array(divisor.length);
  for (const byte of data) {
    const factor = byte ^ result[0];
    result.copyWithin(0, 1);
    result[result.length - 1] = 0;
    for (let i = 0; i < result.length; i++) {
      result[i] ^= gfMultiply(divisor[i], factor);
    }
  }
  return result;
}

/** 把数据码字切块、计算纠错并交织成最终码字序列。 */
function addEccAndInterleave(dataCodewords, version) {
  const numBlocks = NUM_ERROR_CORRECTION_BLOCKS[version];
  const blockEccLen = ECC_CODEWORDS_PER_BLOCK[version];
  const rawCodewords = Math.floor(getNumRawDataModules(version) / 8);
  const numShortBlocks = numBlocks - (rawCodewords % numBlocks);
  const shortBlockLen = Math.floor(rawCodewords / numBlocks);

  const blocks = [];
  const divisor = reedSolomonDivisor(blockEccLen);
  for (let i = 0, offset = 0; i < numBlocks; i++) {
    const dataLen = shortBlockLen - blockEccLen + (i < numShortBlocks ? 0 : 1);
    const dat = Array.from(dataCodewords.slice(offset, offset + dataLen));
    offset += dataLen;
    const ecc = reedSolomonRemainder(dat, divisor);
    if (i < numShortBlocks) {
      dat.push(0);
    }
    blocks.push(dat.concat(Array.from(ecc)));
  }

  const result = [];
  for (let i = 0; i < blocks[0].length; i++) {
    for (let j = 0; j < blocks.length; j++) {
      if (i !== shortBlockLen - blockEccLen || j >= numShortBlocks) {
        result.push(blocks[j][i]);
      }
    }
  }
  return result;
}

/* ------------------------------- 数据码字编码 ------------------------------- */

function encodeDataCodewords(bytes, version) {
  const bits = [];
  const push = (value, length) => {
    for (let i = length - 1; i >= 0; i--) {
      bits.push((value >>> i) & 1);
    }
  };

  push(0b0100, 4); // byte 模式
  push(bytes.length, version <= 9 ? 8 : 16);
  for (const byte of bytes) {
    push(byte, 8);
  }

  const capacityBits = getNumDataCodewords(version) * 8;
  for (let i = 0; i < 4 && bits.length < capacityBits; i++) {
    bits.push(0);
  }
  while (bits.length % 8 !== 0) {
    bits.push(0);
  }

  const data = [];
  for (let i = 0; i < bits.length; i += 8) {
    let byte = 0;
    for (let j = 0; j < 8; j++) {
      byte = (byte << 1) | bits[i + j];
    }
    data.push(byte);
  }
  const capacityBytes = capacityBits / 8;
  for (let pad = 0xec; data.length < capacityBytes; pad ^= 0xec ^ 0x11) {
    data.push(pad);
  }
  return data;
}

function pickVersion(byteLength) {
  for (let version = MIN_VERSION; version <= MAX_VERSION; version++) {
    const capacityBits = getNumDataCodewords(version) * 8;
    const neededBits = 4 + (version <= 9 ? 8 : 16) + byteLength * 8;
    if (neededBits <= capacityBits) {
      return version;
    }
  }
  return null;
}

/* --------------------------------- 矩阵绘制 --------------------------------- */

function createMatrix(version, codewords, mask) {
  const size = version * 4 + 17;
  const modules = new Uint8Array(size * size);
  const isFunction = new Uint8Array(size * size);

  const setFunction = (x, y, dark) => {
    const index = y * size + x;
    modules[index] = dark ? 1 : 0;
    isFunction[index] = 1;
  };

  const drawFinderPattern = (cx, cy) => {
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const x = cx + dx;
        const y = cy + dy;
        if (x >= 0 && x < size && y >= 0 && y < size) {
          const dist = Math.max(Math.abs(dx), Math.abs(dy));
          setFunction(x, y, dist !== 2 && dist !== 4);
        }
      }
    }
  };

  const drawAlignmentPattern = (cx, cy) => {
    for (let dy = -2; dy <= 2; dy++) {
      for (let dx = -2; dx <= 2; dx++) {
        setFunction(cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
      }
    }
  };

  const drawFormatBits = (maskValue) => {
    const data = (ECC_FORMAT_BITS << 3) | maskValue;
    let rem = data;
    for (let i = 0; i < 10; i++) {
      rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    }
    const bits = ((data << 10) | rem) ^ 0x5412;

    for (let i = 0; i <= 5; i++) {
      setFunction(8, i, getBit(bits, i));
    }
    setFunction(8, 7, getBit(bits, 6));
    setFunction(8, 8, getBit(bits, 7));
    setFunction(7, 8, getBit(bits, 8));
    for (let i = 9; i < 15; i++) {
      setFunction(14 - i, 8, getBit(bits, i));
    }

    for (let i = 0; i < 8; i++) {
      setFunction(size - 1 - i, 8, getBit(bits, i));
    }
    for (let i = 8; i < 15; i++) {
      setFunction(8, size - 15 + i, getBit(bits, i));
    }
    setFunction(8, size - 8, true);
  };

  // 定时图形
  for (let i = 0; i < size; i++) {
    setFunction(6, i, i % 2 === 0);
    setFunction(i, 6, i % 2 === 0);
  }
  // 三个定位图形
  drawFinderPattern(3, 3);
  drawFinderPattern(size - 4, 3);
  drawFinderPattern(3, size - 4);

  // 校正图形
  const alignPositions = getAlignmentPatternPositions(version);
  const numAlign = alignPositions.length;
  for (let i = 0; i < numAlign; i++) {
    for (let j = 0; j < numAlign; j++) {
      const skipCorner =
        (i === 0 && j === 0) ||
        (i === 0 && j === numAlign - 1) ||
        (i === numAlign - 1 && j === 0);
      if (!skipCorner) {
        drawAlignmentPattern(alignPositions[i], alignPositions[j]);
      }
    }
  }

  // 先占位格式信息区域
  drawFormatBits(0);

  // 版本信息（版本 7 及以上）
  if (version >= 7) {
    let rem = version;
    for (let i = 0; i < 12; i++) {
      rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
    }
    const bits = (version << 12) | rem;
    for (let i = 0; i < 18; i++) {
      const bit = getBit(bits, i);
      const a = size - 11 + (i % 3);
      const b = Math.floor(i / 3);
      setFunction(a, b, bit);
      setFunction(b, a, bit);
    }
  }

  // 码字填充（从右下角开始之字形）
  let bitIndex = 0;
  const totalBits = codewords.length * 8;
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) {
      right = 5;
    }
    for (let vert = 0; vert < size; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? size - 1 - vert : vert;
        const index = y * size + x;
        if (!isFunction[index] && bitIndex < totalBits) {
          modules[index] = getBit(codewords[bitIndex >>> 3], 7 - (bitIndex & 7)) ? 1 : 0;
          bitIndex++;
        }
      }
    }
  }

  // 掩码
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const index = y * size + x;
      if (isFunction[index]) {
        continue;
      }
      let invert;
      switch (mask) {
        case 0: invert = (x + y) % 2 === 0; break;
        case 1: invert = y % 2 === 0; break;
        case 2: invert = x % 3 === 0; break;
        case 3: invert = (x + y) % 3 === 0; break;
        case 4: invert = (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0; break;
        case 5: invert = ((x * y) % 2) + ((x * y) % 3) === 0; break;
        case 6: invert = (((x * y) % 2) + ((x * y) % 3)) % 2 === 0; break;
        case 7: invert = (((x + y) % 2) + ((x * y) % 3)) % 2 === 0; break;
        default: invert = false;
      }
      if (invert) {
        modules[index] ^= 1;
      }
    }
  }

  drawFormatBits(mask);
  return { size, modules };
}

/* --------------------------------- 掩码评分 --------------------------------- */

function finderPenaltyAddHistory(currentRunLength, runHistory, size) {
  if (runHistory[0] === 0) {
    currentRunLength += size;
  }
  runHistory.pop();
  runHistory.unshift(currentRunLength);
}

function finderPenaltyCountPatterns(runHistory) {
  const n = runHistory[1];
  const core =
    n > 0 &&
    runHistory[2] === n &&
    runHistory[3] === n * 3 &&
    runHistory[4] === n &&
    runHistory[5] === n;
  return (
    (core && runHistory[0] >= n * 4 && runHistory[6] >= n ? 1 : 0) +
    (core && runHistory[6] >= n * 4 && runHistory[0] >= n ? 1 : 0)
  );
}

function finderPenaltyTerminateAndCount(currentRunColor, currentRunLength, runHistory, size) {
  if (currentRunColor) {
    finderPenaltyAddHistory(currentRunLength, runHistory, size);
    currentRunLength = 0;
  }
  currentRunLength += size;
  finderPenaltyAddHistory(currentRunLength, runHistory, size);
  return finderPenaltyCountPatterns(runHistory);
}

function getPenaltyScore({ size, modules }) {
  let result = 0;

  for (let y = 0; y < size; y++) {
    let runColor = false;
    let runLength = 0;
    const runHistory = new Array(7).fill(0);
    for (let x = 0; x < size; x++) {
      const dark = modules[y * size + x] === 1;
      if (dark === runColor) {
        runLength++;
        if (runLength === 5) {
          result += 3;
        } else if (runLength > 5) {
          result++;
        }
      } else {
        finderPenaltyAddHistory(runLength, runHistory, size);
        if (!runColor) {
          result += finderPenaltyCountPatterns(runHistory) * 40;
        }
        runColor = dark;
        runLength = 1;
      }
    }
    result += finderPenaltyTerminateAndCount(runColor, runLength, runHistory, size) * 40;
  }

  for (let x = 0; x < size; x++) {
    let runColor = false;
    let runLength = 0;
    const runHistory = new Array(7).fill(0);
    for (let y = 0; y < size; y++) {
      const dark = modules[y * size + x] === 1;
      if (dark === runColor) {
        runLength++;
        if (runLength === 5) {
          result += 3;
        } else if (runLength > 5) {
          result++;
        }
      } else {
        finderPenaltyAddHistory(runLength, runHistory, size);
        if (!runColor) {
          result += finderPenaltyCountPatterns(runHistory) * 40;
        }
        runColor = dark;
        runLength = 1;
      }
    }
    result += finderPenaltyTerminateAndCount(runColor, runLength, runHistory, size) * 40;
  }

  for (let y = 0; y < size - 1; y++) {
    for (let x = 0; x < size - 1; x++) {
      const color = modules[y * size + x];
      if (
        color === modules[y * size + x + 1] &&
        color === modules[(y + 1) * size + x] &&
        color === modules[(y + 1) * size + x + 1]
      ) {
        result += 3;
      }
    }
  }

  let dark = 0;
  for (let i = 0; i < modules.length; i++) {
    dark += modules[i];
  }
  const total = size * size;
  const k = Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1;
  result += k * 10;
  return result;
}

/* --------------------------------- 对外接口 --------------------------------- */

/**
 * 把文本编码成二维码矩阵。
 * @param {string} text 任意文本（按 UTF-8 编码）
 * @returns {{ size: number, modules: Uint8Array, version: number }}
 */
export function encodeQr(text) {
  const bytes = new TextEncoder().encode(String(text ?? ""));
  const version = pickVersion(bytes.length);
  if (!version) {
    const error = new Error("QR_TOO_LONG");
    error.code = "QR_TOO_LONG";
    throw error;
  }
  const dataCodewords = encodeDataCodewords(bytes, version);
  const codewords = addEccAndInterleave(dataCodewords, version);

  let best = null;
  let bestScore = Infinity;
  for (let mask = 0; mask < 8; mask++) {
    const candidate = createMatrix(version, codewords, mask);
    const score = getPenaltyScore(candidate);
    if (score < bestScore) {
      bestScore = score;
      best = candidate;
    }
  }
  return { ...best, version };
}

/**
 * 把文本直接绘制到 canvas（不使用 dataURL / base64）。
 * @param {HTMLCanvasElement} canvas
 * @param {string} text
 * @param {{ pixelSize?: number, margin?: number, dark?: string, light?: string }} options
 */
export function drawQrToCanvas(canvas, text, options = {}) {
  const pixelSize = options.pixelSize ?? 216;
  const margin = options.margin ?? 4;
  const dark = options.dark ?? "#101828";
  const light = options.light ?? "#ffffff";

  const qr = encodeQr(text);
  const count = qr.size + margin * 2;
  const scale = Math.max(2, Math.floor(pixelSize / count));
  const pixel = count * scale;

  canvas.width = pixel;
  canvas.height = pixel;
  canvas.style.width = `${pixel}px`;
  canvas.style.height = `${pixel}px`;

  const ctx = canvas.getContext("2d");
  ctx.fillStyle = light;
  ctx.fillRect(0, 0, pixel, pixel);
  ctx.fillStyle = dark;
  for (let y = 0; y < qr.size; y++) {
    for (let x = 0; x < qr.size; x++) {
      if (qr.modules[y * qr.size + x]) {
        ctx.fillRect((x + margin) * scale, (y + margin) * scale, scale, scale);
      }
    }
  }
  return qr;
}

/** 清空画布尺寸与内容，避免残留任何图像数据。 */
export function clearQrCanvas(canvas) {
  if (!canvas) {
    return;
  }
  try {
    canvas.width = 0;
    canvas.height = 0;
    canvas.style.width = "0px";
    canvas.style.height = "0px";
    canvas.getContext("2d")?.clearRect(0, 0, 0, 0);
  } catch {
    // 画布已被移除时忽略
  }
}
