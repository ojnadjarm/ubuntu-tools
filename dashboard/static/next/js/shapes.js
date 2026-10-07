/* Shapes of the glyph mass: each returns points {x,y,z,t tier,s size,c colour}. */
const TAU = Math.PI * 2;
export const C = { mint: 0, gold: 1, vio: 2, ice: 3 };

function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
let R = rng(52);
/* Every shape draws from one seeded stream, so the same data always gives the same field. */
export const reseed = (s = 52) => { R = rng(s); };

/* Depth dust: a sparse shell of dim glyphs, a few violet. */
export function dust(n, { rx = 16, ry = 10, z0 = -14, z1 = 4 } = {}) {
  const out = [];
  for (let i = 0; i < n; i++) out.push({ x: (R() * 2 - 1) * rx, y: (R() * 2 - 1) * ry, z: z0 + R() * (z1 - z0), t: R() < 0.08 ? 1 : 0, s: 14 + R() * 10, c: R() < 0.05 ? C.vio : C.mint });
  return out;
}

const rows = (v, i, lo, span, h) => Math.max(1, Math.round((0.12 + 0.88 * (v[i] - lo) / span) * h / 0.22));
/* Usage skyline: one ribbon of glyph columns per series; column height = value, the newest top white-hot. */
export function terrain(series, { w = 13, h = 3.2, dz = 1.7 } = {}) {
  const out = [];
  series.forEach((sr, si) => {
    const v = sr.values.length ? sr.values : [0], lo = Math.min(...v), span = Math.max(...v) - lo || 1, z = (si - (series.length - 1) / 2) * -dz, step = w / Math.max(1, v.length - 1);
    v.forEach((_, i) => {
      const x = -w / 2 + i * step, n = rows(v, i, lo, span, h);
      for (let r = 0; r < n; r++) { const top = r === n - 1; out.push({ x, y: -h / 2 + r * 0.22, z, t: top ? (i === v.length - 1 ? 4 : 3) : r > n - 3 ? 1 : 0, s: top ? 13 : 8.5, c: C.mint }); }
      if (i % 2 === 0) out.push({ x, y: -h / 2 - 0.34, z, t: 1, s: 7, c: C.vio });
    });
  });
  return out;
}
export const terrainTop = (sr, i, { h }) => { const v = sr.values.length ? sr.values : [0], lo = Math.min(...v), span = Math.max(...v) - lo || 1; return -h / 2 + (rows(v, i, lo, span, h) - 1) * 0.22; };

/* Orbit ellipse of dim glyphs in the plane tilted by `tilt` around x. */
export function orbit(rad, { n = 120, tilt = 1.05 } = {}) {
  const out = [];
  for (let j = 0; j < n; j++) { const a = (j / n) * TAU, p = orbitPoint(rad, a, { tilt }); out.push({ ...p, t: j % 9 === 0 ? 1 : 0, s: 15, c: C.mint, o: 1 }); }
  return out;
}
export const orbitPoint = (rad, a, { tilt = 1.05 } = {}) => ({ x: Math.cos(a) * rad, y: Math.sin(a) * rad * Math.cos(tilt), z: -Math.sin(a) * rad * Math.sin(tilt) });
/* A bowed glyph stream from the eye to an orbiting agent; it turns with the orbit. */
export function stream(from, to, n = 26, c = C.mint) {
  const out = [];
  for (let j = 1; j < n; j++) { const f = j / n, bow = Math.sin(f * Math.PI) * 0.5; out.push({ x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f + bow, z: from.z + (to.z - from.z) * f, t: j % 6 === 0 ? 4 : j % 2 ? 2 : 1, s: 17, c, o: 1 }); }
  return out;
}

/* Rain: one glyph column per unit, height from its memory; failed units gold, strays violet. */
export function rain(cols, { w = 22, h = 11, z = -6 } = {}) {
  const out = [], n = cols.length || 1, step = w / n;
  cols.forEach((c, i) => {
    const x = -w / 2 + (i + 0.5) * step, len = Math.max(3, Math.round(c.h * h / 0.34)), y0 = h / 2 - R() * 1.5;
    for (let r = 0; r < len; r++) out.push({ x, y: y0 - r * 0.34, z: z - (i % 3) * 1.4, t: r === len - 1 ? (c.c === C.mint ? 3 : 4) : r > len - 4 ? 1 : 0, s: r === len - 1 ? 20 : 15, c: c.c });
  });
  return out;
}

/* Constellation: one star per site on its group's ring, brighter when faster; down = gold, stray = violet. */
export function stars(groups, { r0 = 3.2, dr = 2.1, tilt = 1.1 } = {}) {
  const out = [];
  groups.forEach((g, gi) => {
    const rad = r0 + gi * dr;
    out.push(...orbit(rad, { n: Math.round(rad * 20), tilt }).map((p) => ({ ...p, o: 0 })));
    g.forEach((s, i) => {
      const p = orbitPoint(rad, (i / Math.max(1, g.length)) * TAU + gi * 0.7, { tilt }), t = s.bright > 0.66 ? 3 : s.bright > 0.33 ? 2 : 1;
      out.push({ ...p, t, s: 17, c: s.c });
      for (let k = 0; k < 6; k++) { const a = (k / 6) * TAU; out.push({ x: p.x + Math.cos(a) * 0.3, y: p.y + Math.sin(a) * 0.3, z: p.z, t: t - 1, s: 9, c: s.c }); }
    });
  });
  return out;
}

/* Sheets: one glyph-edged card plane per item, receding in a tilted grid. */
export function sheets(n, { cols = 6, w = 1.9, h = 1.25, gap = 0.5 } = {}) {
  const out = [], m = Math.max(1, Math.min(n, 36)), rowsN = Math.ceil(m / cols), c0 = Math.min(cols, m);
  for (let i = 0; i < m; i++) {
    const cx = ((i % cols) - (c0 - 1) / 2) * (w + gap), cy = ((rowsN - 1) / 2 - Math.floor(i / cols)) * (h + gap), z = -4 - Math.floor(i / cols) * 1.6;
    const per = 2 * (w + h) / 0.26;
    for (let j = 0; j < per; j++) {
      const d = (j / per) * 2 * (w + h), x = d < w ? d : d < w + h ? w : d < 2 * w + h ? 2 * w + h - d : 0, y = d < w ? 0 : d < w + h ? d - w : d < 2 * w + h ? h : 2 * (w + h) - d;
      out.push({ x: cx - w / 2 + x, y: cy - h / 2 + y, z, t: j === 0 ? 3 : j % 5 === 0 ? 1 : 0, s: 14, c: i === 0 && n > 0 ? C.gold : C.mint });
    }
  }
  return out;
}

/* Wave: a glyph ribbon of three harmonics, receding in depth. */
export function wave({ n = 90, w = 20, lines = 5 } = {}) {
  const out = [];
  for (let l = 0; l < lines; l++) for (let i = 0; i < n; i++) {
    const f = i / (n - 1), x = -w / 2 + f * w, y = Math.sin(f * 9 + l * 0.7) * 1.2 + Math.sin(f * 23 + l) * 0.35 - 1 + l * 0.18, peak = Math.abs(Math.sin(f * 9 + l * 0.7)) > 0.97;
    out.push({ x, y, z: -3 - l * 1.3, t: peak ? 3 : l === 0 ? 1 : 0, s: 16, c: l === 2 ? C.vio : C.mint });
  }
  return out;
}

/* Swatch: the palette as four glyph clusters. */
export function swatch() {
  const out = [];
  [C.mint, C.gold, C.vio, C.ice].forEach((c, i) => {
    const cx = (i - 1.5) * 3.2;
    for (let k = 0; k < 90; k++) { const a = R() * TAU, r = Math.sqrt(R()) * 1; out.push({ x: cx + Math.cos(a) * r, y: -3 + Math.sin(a) * r * 0.6, z: -1, t: k < 8 ? 3 : 1, s: 17, c }); }
  });
  return out;
}
