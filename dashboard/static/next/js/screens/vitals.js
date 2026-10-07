/* Vitals: each usage series is a ribbon of glyph columns under a small sun eye whose rings hold the four "now" values; panes roll the numbers, a probe reads any sample. */
import { esc } from "/static/js/core/fmt.js";
import { terrain, terrainTop, dust } from "../shapes.js";
import { fitEye, FACE } from "../gl/cam.js";
import { odo, trail } from "../ui/num.js";
import { store } from "../store.js";

export const own = true;
const SER = [["cpu", "%"], ["ram", "%"], ["io", "KB/s"], ["net", "kbit/s"]];
const R0 = 1.24, DR = 0.12;
const fmt = (v) => (v >= 100 ? v.toFixed(0) : v.toFixed(1));
const series = (D) => SER.map(([k, u]) => ({ k, u, values: ((D.sparks || {})[k] || {}).values || [] }));
const dims = () => (innerWidth < 820 ? { w: 9, h: 2.2, dz: 2.2 } : { w: 14, h: 2.6, dz: 2.6 });
const flat = () => innerWidth <= 768;
const PX = 52, LANE = 18, STEP = 0.3, TOP = 11, BODY = 9.5, DOT = 0.34;
/* Bucket maxima so a phone ribbon keeps one glyph column per STEP; the newest column stays the newest sample. */
const squeeze = (v, m) => (v.length <= m ? v : Array.from({ length: m }, (_, j) => (j === m - 1 ? v[v.length - 1] : Math.max(...v.slice(Math.floor((j * v.length) / m), Math.floor(((j + 1) * v.length) / m))))));

/* Phone layout: flat ribbons stacked under the eye, each under its own label lane, PX CSS px per world unit whatever the width. */
function stack(S) {
  const box = document.getElementById("scape"), sun = document.getElementById("sun");
  const bw = box ? box.clientWidth : innerWidth, bh = box ? box.clientHeight : 512, top = sun ? sun.offsetHeight : 88;
  const span = bw / PX, w = span - 0.6, cols = Math.max(2, Math.min(Math.max(...S.map((s) => s.values.length)), Math.floor(w / STEP) + 1));
  const lane = LANE / PX, pitch = (bh - top + LANE) / PX / S.length, R = Math.max(2, Math.floor((pitch - lane - DOT - 0.28) / 0.22) + 1), h = R * 0.22;
  const lanes = S.map((_, i) => bh / PX / 2 - (top - LANE) / PX - i * pitch);
  return { w, h, span, R, lanes, cols, lane, sig: [bw, bh, top].join("x") };
}
const now = (s) => s.values[s.values.length - 1];
let probe = -1;

export function render(grid, D) {
  const S = series(D);
  return `<div class="nxs vitals"><section class="scape" id="scape" aria-label="usage, last 30 minutes; move over it to read a sample"><div class="sun" id="sun" aria-hidden="true"></div>` +
    S.map((s) => `<div class="nlbl" data-k="${s.k}" aria-hidden="true">${s.k} <b>${s.values.length ? fmt(now(s)) : "—"}</b> ${s.u}</div>`).join("") +
    `<div class="probe" id="probe" hidden></div></section><div class="stats">` +
    S.map((s) => {
      const v = s.values, n = v.length;
      if (!n) return `<section class="pane"><h2><span data-dec>${s.k}</span><s>30 min</s></h2><p class="sm">netdata not answering</p></section>`;
      const avg = v.reduce((a, b) => a + b, 0) / n;
      return `<section class="pane"><h2><span data-dec>${s.k}</span><s>30 min</s></h2><div class="nbig">${odo("vt." + s.k, fmt(v[n - 1]))} <u>${esc(s.u)} now</u></div>` +
        trail("vt." + s.k, v, `${s.k}, last 30 minutes, now ${fmt(v[n - 1])} ${s.u}`) +
        `<dl class="kv"><dt>min</dt><dd>${fmt(Math.min(...v))}</dd><dt>avg</dt><dd>${fmt(avg)}</dd><dt>max</dt><dd>${fmt(Math.max(...v))}</dd></dl></section>`;
    }).join("") + `</div></div>`;
}

/* Keeps each ribbon's label on its newest column, stacked so none overlap. */
function labels(st, S, d) {
  const box = document.getElementById("scape");
  if (!box || !st.massProject) return;
  const b = box.getBoundingClientRect();
  if (d.lanes) {
    S.forEach((s, i) => {
      const l = box.querySelector(`.nlbl[data-k="${s.k}"]`), p = st.massProject(-d.w / 2 - 0.12, d.lanes[i], 0);
      const tr = `translate3d(${(p.x - b.left).toFixed(1)}px,${(p.y - b.top).toFixed(1)}px,0)`;
      if (l && l.style.transform !== tr) l.style.transform = tr;
    });
    return;
  }
  const L = S.map((s, i) => {
    const l = box.querySelector(`.nlbl[data-k="${s.k}"]`);
    if (!l) return null;
    const n = s.values.length - 1, p = st.massProject(d.w / 2, (n >= 0 ? terrainTop(s, n, d) : 0) + 0.5, (i - 1.5) * -d.dz);
    return { l, x: p.x - b.left, y: p.y - b.top };
  }).filter(Boolean).sort((u, v) => u.y - v.y);
  const gap = L.length ? L[0].l.offsetHeight + 4 : 0;
  L.forEach((o, i) => {
    if (i && o.y - L[i - 1].y < gap) o.y = L[i - 1].y + gap;
    const tr = `translate3d(${o.x.toFixed(1)}px,${o.y.toFixed(1)}px,0) translate(-100%,-100%)`;
    if (o.l.style.transform !== tr) o.l.style.transform = tr;
  });
}

/* Phone scene: the stacked ribbons, the camera square to them. */
function flatScene(S) {
  const d = stack(S), pts = [...dust(700, { rx: 18, ry: 9, z0: -18, z1: -6 })];
  S.forEach((s, i) => {
    const y = d.lanes[i] - d.lane - 0.13 - (d.R - 1) * 0.22 + d.h / 2;
    terrain([{ values: squeeze(s.values, d.cols) }], d).forEach((p) => pts.push({ ...p, y: p.y + y, s: p.s === 13 ? TOP : p.s === 8.5 ? BODY : p.s }));
  });
  return {
    key: JSON.stringify(S.map((s) => s.values)) + d.sig,
    pts, box: document.getElementById("scape"), span: d.span, tilt: 0, ar: 9,
    eyeEl: document.getElementById("sun"), eyeFit: (b) => fitEye(b, { outer: R0 + DR * 3, n: FACE, pad: 0 }),
    rings: S.map((s, i) => { const v = s.values, top = v.length ? Math.max(...v) : 0; return { r: R0 + DR * i, v: top > 0 ? now(s) / top : 0, kind: 0 }; }), ringN: FACE, halo: 0,
    frame: (st) => labels(st, S, d), pulse: false,
  };
}

export function scene(D) {
  const S = series(D), d = dims(), narrow = innerWidth < 820;
  if (flat()) return flatScene(S);
  return {
    key: JSON.stringify(S.map((s) => s.values)),
    pts: [...dust(narrow ? 700 : 1800, { rx: 18, ry: 9, z0: -18, z1: -6 }), ...terrain(S, d)],
    box: document.getElementById("scape"), span: d.w + (narrow ? 1.6 : 3), tilt: 0.62,
    eyeEl: document.getElementById("sun"), eyeFit: (b) => fitEye(b, { outer: R0 + DR * 3, n: FACE, pad: 0 }),
    rings: S.map((s, i) => { const v = s.values, top = v.length ? Math.max(...v) : 0; return { r: R0 + DR * i, v: top > 0 ? now(s) / top : 0, kind: 0 }; }), ringN: FACE, halo: 0,
    frame: (st) => labels(st, S, d), pulse: false,
  };
}

/* Pointer over the skyline: the sample under it, for all four series. */
export function pointer(e) {
  const box = e.target.closest && e.target.closest("#scape"), pr = document.getElementById("probe"), st = store.stage;
  if (!box || !pr || !st || !st.massProject || !store.D) { if (pr) pr.hidden = true; return; }
  const S = series(store.D), d = flat() ? stack(S) : dims(), n = Math.max(...S.map((s) => s.values.length)) - 1;
  if (n < 1) return;
  const a = d.lanes ? st.massProject(-d.w / 2, 0, 0) : st.massProject(-d.w / 2, -d.h / 2, 1.5 * d.dz), z = d.lanes ? st.massProject(d.w / 2, 0, 0) : st.massProject(d.w / 2, -d.h / 2, 1.5 * d.dz);
  const i = Math.max(0, Math.min(n, Math.round(((e.clientX - a.x) / (z.x - a.x)) * n)));
  if (i === probe && !pr.hidden) return;
  probe = i;
  const b = box.getBoundingClientRect();
  pr.hidden = false;
  pr.style.transform = `translate(${Math.min(b.width - 160, Math.max(0, e.clientX - b.left + 12)).toFixed(0)}px, 8px)`;
  pr.innerHTML = `<b>${Math.round(((n - i) * 30) / n)} min ago</b>` + S.map((s) => `<span>${s.k} <i>${s.values[i] != null ? fmt(s.values[i]) : "—"}</i> ${s.u}</span>`).join("");
}
