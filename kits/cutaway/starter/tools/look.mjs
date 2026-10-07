// Look gate on a still: node tools/look.mjs <png> [x0,y0,x1,y1 px] — primary-colour coverage and bare cells (1/32 of the rect wide; no ink or colour, only paper or hatching) inside the rect (the casing).
// Budgets (skill /cutaway-style), calibrated on the T71 neuron plate at 1920 (primary 5.7 %, bare 21-26 %, largest 3-4) against the
// first gradient plate (primary 0.6 %, bare 48 %, largest 6): primaryPct >= 4, bareCellsPct <= 30, largestBareSquare <= 4.
// tools/shot.mjs runs it on every still over the plate's `__casingPx()` rect and prints LOOK FAIL when a budget is missed.
import { chromium } from 'playwright-core';
import { readFileSync } from 'node:fs';

export const BUDGET = { primaryPct: 4, bareCellsPct: 30, largestBareSquare: 4 };

/** Metrics of a PNG buffer inside rect "x0,y0,x1,y1" (whole image when omitted), computed in a page. */
export async function look(page, buf, rect) {
  return page.evaluate(async ({ data, rect }) => {
    const img = new Image(); img.src = 'data:image/png;base64,' + data; await img.decode();
    const [x0, y0, x1, y1] = rect ? rect.split(',').map(Number) : [0, 0, img.width, img.height], W = x1 - x0, H = y1 - y0;
    const c = new OffscreenCanvas(W, H), g = c.getContext('2d'); g.drawImage(img, -x0, -y0);
    const d = g.getImageData(0, 0, W, H).data;
    const P = { blue: [29, 95, 176], red: [204, 58, 43], yellow: [233, 174, 44] }, hits = { blue: 0, red: 0, yellow: 0 };
    const near = (i, [r, gg, bb]) => Math.hypot(d[i] - r, d[i + 1] - gg, d[i + 2] - bb) < 70;
    for (let i = 0; i < d.length; i += 4) for (const k in P) if (near(i, P[k])) { hits[k]++; break; }
    const C = Math.max(8, Math.round(W / 32)), cols = Math.floor(W / C), rows = Math.floor(H / C), empty = [];
    for (let r = 0; r < rows; r++) for (let q = 0; q < cols; q++) {
      const lum = [];
      for (let y = r * C; y < (r + 1) * C; y++) for (let x = q * C; x < (q + 1) * C; x++) { const i = (y * W + x) * 4; lum.push(0.3 * d[i] + 0.59 * d[i + 1] + 0.11 * d[i + 2]); }
      empty.push(!lum.some((v) => v < 120));
    }
    let best = 0, at = [0, 0];
    const dp = new Array(cols * rows).fill(0);
    for (let r = 0; r < rows; r++) for (let q = 0; q < cols; q++) {
      const i = r * cols + q; if (!empty[i]) continue;
      dp[i] = r && q ? 1 + Math.min(dp[i - cols], dp[i - 1], dp[i - cols - 1]) : 1;
      if (dp[i] > best) { best = dp[i]; at = [x0 + (q + 1 - best) * C, y0 + (r + 1 - best) * C]; }
    }
    const n = W * H, pct = (v) => +((100 * v) / n).toFixed(2);
    return { rect: [x0, y0, x1, y1], primaryPct: pct(hits.blue + hits.red + hits.yellow), bluePct: pct(hits.blue), redPct: pct(hits.red), yellowPct: pct(hits.yellow),
      bareCellsPct: +((100 * empty.filter(Boolean).length) / empty.length).toFixed(1), largestBareSquare: best, bareAt: at };
  }, { data: buf.toString('base64'), rect });
}

/** Budget misses of a metrics object, as text. */
export const misses = (m) => [m.primaryPct < BUDGET.primaryPct && `primary ${m.primaryPct} % < ${BUDGET.primaryPct}`,
  m.bareCellsPct > BUDGET.bareCellsPct && `bare ${m.bareCellsPct} % > ${BUDGET.bareCellsPct}`,
  m.largestBareSquare > BUDGET.largestBareSquare && `bare square ${m.largestBareSquare} > ${BUDGET.largestBareSquare}`].filter(Boolean);

if (import.meta.url === `file://${process.argv[1]}`) {
  const [png, rect] = process.argv.slice(2);
  const b = await chromium.launch({ headless: true });
  const m = await look(await b.newPage(), readFileSync(png), rect);
  console.log(JSON.stringify(m), misses(m).length ? 'LOOK FAIL: ' + misses(m).join('; ') : 'LOOK OK');
  await b.close();
}
