/* Decode type: each character flickers through half-width katakana in a 1ch cell, then settles left to right; screen readers get the real text at once. */
import { KANA } from "../gl/glyphs.js";

const still = matchMedia("(prefers-reduced-motion: reduce)");
const live = new Set();
let raf = 0;
const kana = () => KANA[(Math.random() * KANA.length) | 0];

/* Decodes the text of el in place and restores its markup when done; delay in ms. */
export function decode(el, delay = 0) {
  if (!el || still.matches || el.dataset.decoding) return;
  const html = el.innerHTML, text = el.textContent.trim();
  if (!text) return;
  const cells = [], t0 = performance.now() + delay, span = Math.min(900, 180 + text.length * 24);
  const walk = document.createTreeWalker(el, NodeFilter.SHOW_TEXT), nodes = [];
  while (walk.nextNode()) if (walk.currentNode.nodeValue.trim()) nodes.push(walk.currentNode);
  let n = 0;
  nodes.forEach((tn) => {
    const box = document.createElement("span");
    box.className = "dec"; box.setAttribute("aria-hidden", "true");
    tn.nodeValue.split(/(\s+)/).forEach((w) => {
      if (!w) return;
      if (/^\s+$/.test(w)) { box.append(w); return; }
      const wd = document.createElement("span"); wd.className = "wd";
      for (const ch of w) {
        const i = document.createElement("i"); i.className = "kx"; i.textContent = kana();
        wd.append(i); cells.push({ i, ch, at: t0 + (n++ / Math.max(1, text.length - 1)) * span + Math.random() * 120 });
      }
      box.append(wd);
    });
    tn.replaceWith(box);
  });
  const sr = document.createElement("span"); sr.className = "sr-only"; sr.textContent = text;
  el.prepend(sr);
  el.dataset.decoding = "1";
  live.add({ el, html, cells, swap: 0 });
  if (!raf) raf = requestAnimationFrame(tick);
}
function tick(now) {
  raf = 0;
  for (const d of live) {
    if (!d.el.isConnected) { live.delete(d); continue; }
    const flick = now - d.swap > 55;
    if (flick) d.swap = now;
    let left = 0;
    for (const c of d.cells) {
      if (c.done) continue;
      if (now >= c.at) { c.i.className = ""; c.i.textContent = c.ch; c.done = true; continue; }
      left++;
      if (flick && Math.random() < 0.6) c.i.textContent = kana();
    }
    if (!left) { d.el.innerHTML = d.html; delete d.el.dataset.decoding; live.delete(d); }
  }
  if (live.size && !document.hidden) raf = requestAnimationFrame(tick);
  else for (const d of live) { d.el.innerHTML = d.html; delete d.el.dataset.decoding; live.delete(d); }
}
/* Decodes every [data-dec] under root, staggered. */
export function decodeAll(root, sel = "[data-dec]", step = 60) {
  root.querySelectorAll(sel).forEach((el, i) => decode(el, i * step));
}
