/* Numbers that roll and lines that draw: odometer digits, comet-trail sparklines and lens gauges as HTML; roll() and draw() animate them after a render. */
import { esc } from "/static/js/core/fmt.js";

const shown = new Map(), drawn = new Set();
const sty = (d, i) => `--d:${d};--i:${i}`;
/* Forget what was shown, so the next render rolls in from zero and redraws its trails. */
export function fresh() { shown.clear(); drawn.clear(); }

/* Rolling digits for str under key: rendered at the value last shown, roll() moves them on. */
export function odo(key, str, cls = "") {
  str = String(str);
  const zero = str.replace(/\d/g, "0"), prev = shown.get(key);
  const from = prev && prev.length === str.length && [...prev].every((c, i) => /\d/.test(c) === /\d/.test(str[i])) ? prev : zero;
  let h = `<span class="odo${cls ? " " + cls : ""}" data-k="${key}" data-v="${esc(str)}" aria-hidden="true">`;
  [...str].forEach((c, i) => { h += /\d/.test(c) ? `<span class="dg" style="${sty(from[i], str.length - i)}"><span class="st">0123456789</span></span>` : `<span class="sy">${esc(c)}</span>`; });
  return h + `</span><span class="sr-only">${esc(str)}</span>`;
}
/* Moves every odometer under root to its value. */
export function roll(root) {
  root.querySelectorAll(".odo").forEach((o) => {
    const v = o.dataset.v, ch = o.children;
    [...v].forEach((c, i) => { const s = ch[i]; if (s && s.className === "dg") { const w = sty(c, v.length - i); if (s.getAttribute("style") !== w) s.setAttribute("style", w); } });
    shown.set(o.dataset.k, v);
  });
}

/* Comet-trail sparkline of vals: a smooth line fading into a glowing head, a washed area; revealed once per key. */
export function trail(key, vals, label = "") {
  const n = vals.length;
  if (n < 2) return `<div class="trail empty" aria-hidden="true"></div>`;
  const top = Math.max(...vals) * 1.2 || 1, P = vals.map((v, i) => [(i / (n - 1)) * 100, 31 - (v / top) * 28]), f = (x) => x.toFixed(2);
  let d = `M${f(P[0][0])} ${f(P[0][1])}`;
  for (let i = 0; i < n - 1; i++) {
    const a = P[Math.max(0, i - 1)], b = P[i], c = P[i + 1], e = P[Math.min(n - 1, i + 2)];
    d += `C${f(b[0] + (c[0] - a[0]) / 6)} ${f(b[1] + (c[1] - a[1]) / 6)} ${f(c[0] - (e[0] - b[0]) / 6)} ${f(c[1] - (e[1] - b[1]) / 6)} ${f(c[0])} ${f(c[1])}`;
  }
  return `<div class="trail${drawn.has(key) ? " drawn" : ""}" data-t="${key}"${label ? ` role="img" aria-label="${esc(label)}"` : ' aria-hidden="true"'}><svg viewBox="0 0 100 32" preserveAspectRatio="none" aria-hidden="true" focusable="false">` +
    `<path class="area" d="${d}L100 32L0 32Z"/><path class="line" d="${d}"/></svg><i class="tip" style="top:${f((P[n - 1][1] / 32) * 100)}%"></i></div>`;
}
/* Reveals the trails under root that were not drawn yet. */
export function draw(root) {
  const t = root.querySelectorAll(".trail:not(.drawn):not(.empty)");
  if (!t.length) return;
  t.forEach((x) => x.getBoundingClientRect());
  requestAnimationFrame(() => t.forEach((x) => { x.classList.add("drawn"); drawn.add(x.dataset.t); }));
}

/* A glass lens gauge: a conic arc with a hot head over 60 ticks, value text inside, role=meter. */
export function lens(pct, text, label, bad = false) {
  const p = Math.max(0, Math.min(100, pct || 0));
  return `<div class="lens${bad ? " bad" : ""}" role="meter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(p)}" aria-label="${esc(label)}" style="--v:${(p / 100).toFixed(3)}"><i aria-hidden="true"></i><b>${text}</b></div>`;
}
