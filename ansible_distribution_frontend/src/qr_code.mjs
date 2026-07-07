import { t } from './web_i18n.mjs';

const VERSION = 8;
const SIZE = VERSION * 4 + 17;
const DATA_CODEWORDS = 194;
const BLOCK_COUNT = 2;
const DATA_CODEWORDS_PER_BLOCK = 97;
const ECC_CODEWORDS_PER_BLOCK = 24;

const ALPHAS = [6, 24, 42];

const GF_EXP = new Array(512).fill(0);
const GF_LOG = new Array(256).fill(0);

let x = 1;
for (let i = 0; i < 255; i += 1) {
  GF_EXP[i] = x;
  GF_LOG[x] = i;
  x <<= 1;
  if (x & 0x100) x ^= 0x11d;
}
for (let i = 255; i < 512; i += 1) {
  GF_EXP[i] = GF_EXP[i - 255];
}

export function renderQrCodeSvg(value, { className = 'qr-code', ariaLabel = t('login.qrAria') } = {}) {
  const payload = new TextEncoder().encode(String(value ?? ''));
  if (!payload.length) return '';
  if (payload.length > 154) {
    throw new RangeError('QR payload is too large for the local login QR encoder');
  }

  const matrix = buildQrMatrix(payload);
  const quiet = 4;
  const viewSize = SIZE + quiet * 2;
  const rects = [];

  for (let y = 0; y < SIZE; y += 1) {
    for (let x = 0; x < SIZE; x += 1) {
      if (matrix[y][x]) {
        rects.push(`<rect x="${x + quiet}" y="${y + quiet}" width="1" height="1"/>`);
      }
    }
  }

  return `
    <svg class="${escapeAttribute(className)}" viewBox="0 0 ${viewSize} ${viewSize}" role="img" aria-label="${escapeAttribute(ariaLabel)}">
      <rect class="qr-code__background" fill="#fff" width="${viewSize}" height="${viewSize}"/>
      <g class="qr-code__modules" fill="#000">${rects.join('')}</g>
    </svg>
  `;
}

function buildQrMatrix(payload) {
  const data = encodeData(payload);
  const codewords = addErrorCorrection(data);
  let best = null;

  for (let mask = 0; mask < 8; mask += 1) {
    const matrix = emptyMatrix();
    const reserved = emptyMatrix(false);
    drawFunctionPatterns(matrix, reserved);
    drawCodewords(matrix, reserved, codewords, mask);
    drawFormatBits(matrix, reserved, mask);
    drawVersionBits(matrix, reserved);
    const penalty = scoreMask(matrix);
    if (!best || penalty < best.penalty) {
      best = { matrix, penalty };
    }
  }

  return best.matrix;
}

function encodeData(payload) {
  const bits = [];
  appendBits(bits, 0b0100, 4);
  appendBits(bits, payload.length, 8);
  for (const byte of payload) appendBits(bits, byte, 8);

  const capacityBits = DATA_CODEWORDS * 8;
  appendBits(bits, 0, Math.min(4, capacityBits - bits.length));
  while (bits.length % 8 !== 0) bits.push(0);

  const data = bitsToBytes(bits);
  for (let pad = 0xec; data.length < DATA_CODEWORDS; pad = pad === 0xec ? 0x11 : 0xec) {
    data.push(pad);
  }

  return data;
}

function addErrorCorrection(data) {
  const generator = reedSolomonGenerator(ECC_CODEWORDS_PER_BLOCK);
  const blocks = [];

  for (let i = 0; i < BLOCK_COUNT; i += 1) {
    const start = i * DATA_CODEWORDS_PER_BLOCK;
    const block = data.slice(start, start + DATA_CODEWORDS_PER_BLOCK);
    blocks.push({ data: block, ecc: reedSolomonRemainder(block, generator) });
  }

  const result = [];
  for (let i = 0; i < DATA_CODEWORDS_PER_BLOCK; i += 1) {
    for (const block of blocks) result.push(block.data[i]);
  }
  for (let i = 0; i < ECC_CODEWORDS_PER_BLOCK; i += 1) {
    for (const block of blocks) result.push(block.ecc[i]);
  }

  return result;
}

function drawFunctionPatterns(matrix, reserved) {
  drawFinder(matrix, reserved, 3, 3);
  drawFinder(matrix, reserved, SIZE - 4, 3);
  drawFinder(matrix, reserved, 3, SIZE - 4);

  for (let i = 8; i < SIZE - 8; i += 1) {
    setFunction(matrix, reserved, 6, i, i % 2 === 0);
    setFunction(matrix, reserved, i, 6, i % 2 === 0);
  }

  for (const y of ALPHAS) {
    for (const x of ALPHAS) {
      if ((x === 6 && y === 6) || (x === 6 && y === SIZE - 7) || (x === SIZE - 7 && y === 6)) {
        continue;
      }
      drawAlignment(matrix, reserved, x, y);
    }
  }

  setFunction(matrix, reserved, 8, SIZE - 8, true);

  for (let i = 0; i < 9; i += 1) {
    if (i !== 6) {
      reserve(reserved, 8, i);
      reserve(reserved, i, 8);
    }
  }
  for (let i = 0; i < 8; i += 1) {
    reserve(reserved, SIZE - 1 - i, 8);
    reserve(reserved, 8, SIZE - 1 - i);
  }

  for (let i = 0; i < 18; i += 1) {
    reserve(reserved, SIZE - 11 + (i % 3), Math.floor(i / 3));
    reserve(reserved, Math.floor(i / 3), SIZE - 11 + (i % 3));
  }
}

function drawFinder(matrix, reserved, cx, cy) {
  for (let y = -4; y <= 4; y += 1) {
    for (let x = -4; x <= 4; x += 1) {
      const xx = cx + x;
      const yy = cy + y;
      if (!inBounds(xx, yy)) continue;
      const module = Math.max(Math.abs(x), Math.abs(y));
      setFunction(matrix, reserved, xx, yy, module !== 2 && module !== 4);
    }
  }
}

function drawAlignment(matrix, reserved, cx, cy) {
  for (let y = -2; y <= 2; y += 1) {
    for (let x = -2; x <= 2; x += 1) {
      const module = Math.max(Math.abs(x), Math.abs(y));
      setFunction(matrix, reserved, cx + x, cy + y, module !== 1);
    }
  }
}

function drawCodewords(matrix, reserved, codewords, mask) {
  const bits = [];
  for (const codeword of codewords) appendBits(bits, codeword, 8);

  let index = 0;
  let upward = true;
  for (let right = SIZE - 1; right >= 1; right -= 2) {
    if (right === 6) right -= 1;
    for (let vert = 0; vert < SIZE; vert += 1) {
      const y = upward ? SIZE - 1 - vert : vert;
      for (let dx = 0; dx < 2; dx += 1) {
        const x = right - dx;
        if (reserved[y][x]) continue;
        const bit = index < bits.length ? bits[index] === 1 : false;
        matrix[y][x] = bit !== maskApplies(mask, x, y);
        index += 1;
      }
    }
    upward = !upward;
  }
}

function drawFormatBits(matrix, reserved, mask) {
  const bits = formatBits(mask);

  for (let i = 0; i <= 5; i += 1) setFunction(matrix, reserved, 8, i, bitAt(bits, i));
  setFunction(matrix, reserved, 8, 7, bitAt(bits, 6));
  setFunction(matrix, reserved, 8, 8, bitAt(bits, 7));
  setFunction(matrix, reserved, 7, 8, bitAt(bits, 8));
  for (let i = 9; i < 15; i += 1) setFunction(matrix, reserved, 14 - i, 8, bitAt(bits, i));

  for (let i = 0; i < 8; i += 1) setFunction(matrix, reserved, SIZE - 1 - i, 8, bitAt(bits, i));
  for (let i = 8; i < 15; i += 1) setFunction(matrix, reserved, 8, SIZE - 15 + i, bitAt(bits, i));
}

function drawVersionBits(matrix, reserved) {
  const bits = versionBits(VERSION);
  for (let i = 0; i < 18; i += 1) {
    const bit = bitAt(bits, i);
    const a = SIZE - 11 + (i % 3);
    const b = Math.floor(i / 3);
    setFunction(matrix, reserved, a, b, bit);
    setFunction(matrix, reserved, b, a, bit);
  }
}

function scoreMask(matrix) {
  let score = 0;

  for (let y = 0; y < SIZE; y += 1) {
    score += linePenalty(matrix[y]);
  }
  for (let x = 0; x < SIZE; x += 1) {
    score += linePenalty(matrix.map((row) => row[x]));
  }

  for (let y = 0; y < SIZE - 1; y += 1) {
    for (let x = 0; x < SIZE - 1; x += 1) {
      const color = matrix[y][x];
      if (matrix[y][x + 1] === color && matrix[y + 1][x] === color && matrix[y + 1][x + 1] === color) {
        score += 3;
      }
    }
  }

  const pattern = [true, false, true, true, true, false, true, false, false, false, false];
  const inverse = pattern.map((value) => !value);
  for (let y = 0; y < SIZE; y += 1) {
    score += patternPenalty(matrix[y], pattern, inverse);
  }
  for (let x = 0; x < SIZE; x += 1) {
    score += patternPenalty(matrix.map((row) => row[x]), pattern, inverse);
  }

  const dark = matrix.flat().filter(Boolean).length;
  score += Math.floor(Math.abs((dark * 20) / (SIZE * SIZE) - 10)) * 10;
  return score;
}

function linePenalty(line) {
  let penalty = 0;
  let runColor = line[0];
  let runLength = 1;
  for (let i = 1; i < line.length; i += 1) {
    if (line[i] === runColor) {
      runLength += 1;
      if (runLength === 5) penalty += 3;
      else if (runLength > 5) penalty += 1;
    } else {
      runColor = line[i];
      runLength = 1;
    }
  }
  return penalty;
}

function patternPenalty(line, pattern, inverse) {
  let penalty = 0;
  for (let i = 0; i <= line.length - pattern.length; i += 1) {
    const window = line.slice(i, i + pattern.length);
    if (samePattern(window, pattern) || samePattern(window, inverse)) penalty += 40;
  }
  return penalty;
}

function samePattern(a, b) {
  return a.every((value, index) => value === b[index]);
}

function formatBits(mask) {
  const data = (0b01 << 3) | mask;
  let rem = data;
  for (let i = 0; i < 10; i += 1) rem <<= 1;
  for (let i = 14; i >= 10; i -= 1) {
    if (((rem >> i) & 1) !== 0) rem ^= 0x537 << (i - 10);
  }
  return ((data << 10) | rem) ^ 0x5412;
}

function versionBits(version) {
  let rem = version;
  for (let i = 0; i < 12; i += 1) rem <<= 1;
  for (let i = 17; i >= 12; i -= 1) {
    if (((rem >> i) & 1) !== 0) rem ^= 0x1f25 << (i - 12);
  }
  return (version << 12) | rem;
}

function reedSolomonGenerator(degree) {
  const result = new Array(degree).fill(0);
  result[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i += 1) {
    for (let j = 0; j < degree; j += 1) {
      result[j] = multiply(result[j], root);
      if (j + 1 < degree) result[j] ^= result[j + 1];
    }
    root = multiply(root, 0x02);
  }
  return result;
}

function reedSolomonRemainder(data, generator) {
  const result = new Array(generator.length).fill(0);
  for (const byte of data) {
    const factor = byte ^ result.shift();
    result.push(0);
    for (let i = 0; i < generator.length; i += 1) {
      result[i] ^= multiply(generator[i], factor);
    }
  }
  return result;
}

function multiply(a, b) {
  if (a === 0 || b === 0) return 0;
  return GF_EXP[GF_LOG[a] + GF_LOG[b]];
}

function maskApplies(mask, x, y) {
  switch (mask) {
    case 0:
      return (x + y) % 2 === 0;
    case 1:
      return y % 2 === 0;
    case 2:
      return x % 3 === 0;
    case 3:
      return (x + y) % 3 === 0;
    case 4:
      return (Math.floor(y / 2) + Math.floor(x / 3)) % 2 === 0;
    case 5:
      return ((x * y) % 2) + ((x * y) % 3) === 0;
    case 6:
      return (((x * y) % 2) + ((x * y) % 3)) % 2 === 0;
    case 7:
      return (((x + y) % 2) + ((x * y) % 3)) % 2 === 0;
    default:
      return false;
  }
}

function appendBits(bits, value, length) {
  for (let i = length - 1; i >= 0; i -= 1) bits.push((value >>> i) & 1);
}

function bitsToBytes(bits) {
  const result = [];
  for (let i = 0; i < bits.length; i += 8) {
    result.push(bits.slice(i, i + 8).reduce((acc, bit) => (acc << 1) | bit, 0));
  }
  return result;
}

function emptyMatrix(fill = false) {
  return Array.from({ length: SIZE }, () => new Array(SIZE).fill(fill));
}

function setFunction(matrix, reserved, x, y, value) {
  matrix[y][x] = value;
  reserved[y][x] = true;
}

function reserve(reserved, x, y) {
  reserved[y][x] = true;
}

function inBounds(x, y) {
  return x >= 0 && y >= 0 && x < SIZE && y < SIZE;
}

function bitAt(value, index) {
  return ((value >>> index) & 1) !== 0;
}

function escapeAttribute(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
    .replaceAll('`', '&#96;');
}
