// Icon generator for the Gixbee Admin PWA — pure Node, no dependencies.
// Run from super-admin-web/:   node tools/generate-icons.js
// Writes PNGs into public/icons/. Re-run any time; replace with branded
// icons later if you get proper artwork.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

// ── Minimal PNG encoder (RGBA, no interlace) ────────────────────────────────
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
function encodePNG(width, height, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 6;  // color type RGBA
  // filter type 0 per scanline
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;
    rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ── Drawing (per-pixel with 2x supersampling for smooth edges) ──────────────
const BG = [15, 23, 42];     // slate-900 (matches admin chrome)
const ACCENT = [37, 99, 235]; // blue-600
const WHITE = [255, 255, 255];

// Signed distance helpers, in unit coords (0..1)
function inRoundedRect(x, y, r) {
  const dx = Math.max(Math.abs(x - 0.5) - (0.5 - r), 0);
  const dy = Math.max(Math.abs(y - 0.5) - (0.5 - r), 0);
  return Math.hypot(dx, dy) <= r;
}
// "G" mark: a ring with a gap on the right, plus a bar into the center.
function inGMark(x, y) {
  const cx = 0.5, cy = 0.46;           // slightly above center
  const d = Math.hypot(x - cx, y - cy);
  const R = 0.26, thick = 0.085;
  const onRing = d >= R - thick && d <= R + thick;
  const ang = Math.atan2(y - cy, x - cx); // -PI..PI, 0 = right
  const inGap = ang > -0.55 && ang < 0.10; // opening on the right
  if (onRing && !inGap) return true;
  // horizontal bar of the G: from center-right into the ring opening
  if (
    x >= cx - 0.02 && x <= cx + R + thick - 0.005 &&
    y >= cy - 0.005 && y <= cy + 0.10
  ) {
    return d <= R + thick; // clip to ring outer radius
  }
  return false;
}
function inAccentBar(x, y) {
  const w = 0.62, h = 0.075, cy = 0.845;
  const rx = Math.abs(x - 0.5) - (w / 2 - h / 2);
  const ry = Math.abs(y - cy) - 0;
  if (Math.abs(y - cy) > h / 2) return false;
  if (Math.abs(x - 0.5) <= w / 2 - h / 2) return true;
  return Math.hypot(Math.max(rx, 0), Math.abs(y - cy)) <= h / 2;
}

function render(size, { rounded = true, pad = 0 } = {}) {
  const S = 2; // supersample
  const N = size * S;
  const rgba = Buffer.alloc(size * size * 4);
  const cornerR = rounded ? 0.20 : 0.0001;
  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < S; sy++) {
        for (let sx = 0; sx < S; sx++) {
          // unit coords with optional maskable padding
          let x = (px * S + sx + 0.5) / N;
          let y = (py * S + sy + 0.5) / N;
          if (pad > 0) {
            x = (x - pad) / (1 - 2 * pad);
            y = (y - pad) / (1 - 2 * pad);
          }
          let c = null;
          const inside =
            pad > 0
              ? x >= 0 && x <= 1 && y >= 0 && y <= 1 && inRoundedRect(x, y, cornerR)
              : inRoundedRect(x, y, cornerR);
          if (pad > 0) c = BG; // maskable: full-bleed background
          if (inside) c = BG;
          if (inside && inAccentBar(x, y)) c = ACCENT;
          if (inside && inGMark(x, y)) c = WHITE;
          if (c) { r += c[0]; g += c[1]; b += c[2]; a += 255; }
        }
      }
      const i = (py * size + px) * 4;
      const n = S * S;
      rgba[i] = Math.round(r / n);
      rgba[i + 1] = Math.round(g / n);
      rgba[i + 2] = Math.round(b / n);
      rgba[i + 3] = Math.round(a / n);
    }
  }
  return encodePNG(size, size, rgba);
}

const outDir = path.join(__dirname, '..', 'public', 'icons');
fs.mkdirSync(outDir, { recursive: true });
const files = {
  'icon-192.png': render(192),
  'icon-512.png': render(512),
  'icon-maskable-512.png': render(512, { rounded: false, pad: 0.12 }),
  'apple-touch-icon.png': render(180, { rounded: false }),
};
for (const [name, buf] of Object.entries(files)) {
  const p = path.join(outDir, name);
  fs.writeFileSync(p, buf);
  console.log('wrote', p, buf.length, 'bytes');
}
console.log('Done.');
