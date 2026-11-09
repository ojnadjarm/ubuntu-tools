/* Familiars in 2D for lists and cards: the hue, eyes, topper and role gear of the 3D body, one mark per pose. */
import { css, pose } from "./genome.js";

const INK = "#04140c", f = (n) => n.toFixed(1);

function mark(p) {
  if (p === "error") return `<circle cx="84" cy="16" r="13" fill="#ff5a52" stroke="${INK}" stroke-width="2.5"/><path d="M84 8v9M84 22v1" stroke="#fff" stroke-width="4" stroke-linecap="round"/>`;
  if (p === "talking") return `<rect x="66" y="3" width="32" height="20" rx="9" fill="#f4fff8" stroke="${INK}" stroke-width="2.5"/><circle cx="75" cy="13" r="2.4"/><circle cx="82" cy="13" r="2.4"/><circle cx="89" cy="13" r="2.4"/>`;
  if (p === "working") return `<circle cx="85" cy="15" r="11" fill="${INK}" stroke="#4dffa0" stroke-width="3" stroke-dasharray="10 5"/><circle cx="85" cy="15" r="3" fill="#4dffa0"/>`;
  return "";
}

/* SVG string of genome g in a panel state; done, stale and sleep rest with shut eyes. */
export function svg(g, state) {
  const W = g.wide, p = pose(state), fill = css(g.hue, 72, 60), deep = css(g.hue + 14, 62, 32), lite = css(g.hue - 8, 88, 84), shut = p === "sleep", err = p === "error";
  const er = g.eyes === 1 ? 13 : g.eyes === 2 ? 9.5 : 7.5, xs = g.eyes === 1 ? [50] : g.eyes === 2 ? [50 - 15 * W, 50 + 15 * W] : [50 - 20 * W, 50, 50 + 20 * W];
  let s = `<svg viewBox="0 0 100 100" class="cr ${state}" role="img" aria-hidden="true"><defs><radialGradient id="${g.uid}" cx="36%" cy="28%" r="80%"><stop offset="0" stop-color="${lite}"/><stop offset=".5" stop-color="${fill}"/><stop offset="1" stop-color="${deep}"/></radialGradient></defs>`;
  [-1, 1].forEach((k) => {
    const x = 50 + k * 22 * W;
    if (g.topper === 0) s += `<path d="M${f(x - 9)} 30L${f(x + k * 6)} 6L${f(x + 10)} 30Z" fill="${fill}" stroke="${INK}" stroke-width="2.5" stroke-linejoin="round"/>`;
    if (g.topper === 1) s += `<circle cx="${f(x + k * 4)}" cy="22" r="10" fill="${deep}" stroke="${INK}" stroke-width="2.5"/>`;
    if (g.topper === 2) s += `<rect x="${f(x - 6)}" y="1" width="12" height="32" rx="6" fill="${fill}" stroke="${INK}" stroke-width="2.5"/>`;
    if (g.topper === 3) s += `<path d="M${f(x - 5)} 28q${k * 2} -18 ${k * 12} -22q0 14 ${-k * 2} 24Z" fill="#ffeec0" stroke="${INK}" stroke-width="2.5" stroke-linejoin="round"/>`;
    if (g.topper === 4) s += `<path d="M${f(x - k * 6)} 26L${f(x + k * 4)} 9" stroke="${deep}" stroke-width="3"/><circle cx="${f(x + k * 4)}" cy="8" r="5" fill="${lite}" stroke="${INK}" stroke-width="2"/>`;
  });
  s += `<ellipse cx="50" cy="58" rx="${f(36 * W)}" ry="${f(34 * g.tall)}" fill="url(#${g.uid})" stroke="${INK}" stroke-width="3"/>`;
  xs.forEach((x) => {
    s += shut ? `<path d="M${f(x - er * 0.8)} 56q${f(er * 0.8)} ${f(er * 0.6)} ${f(er * 1.6)} 0" stroke="${INK}" stroke-width="3" fill="none" stroke-linecap="round"/>`
      : `<g class="lid"><circle cx="${f(x)}" cy="56" r="${er}" fill="#f4fff8" stroke="${INK}" stroke-width="2"/><circle cx="${f(x)}" cy="${p === "working" ? 59 : 57}" r="${f(er * (err ? 0.4 : 0.6))}" fill="${INK}"/><circle cx="${f(x + er * 0.25)}" cy="${f(56 - er * 0.25)}" r="${f(er * 0.2)}" fill="#fff"/></g>`;
    if (err) s += `<path d="M${f(x - er)} ${f(56 - er * 1.5)}l${f(er * 2)} ${f(x < 50 ? er * 0.6 : -er * 0.6)}" stroke="${INK}" stroke-width="3" stroke-linecap="round"/>`;
  });
  s += `<ellipse cx="${f(50 - 24 * W)}" cy="70" rx="5" ry="3" fill="#ff9ec4" opacity=".6"/><ellipse cx="${f(50 + 24 * W)}" cy="70" rx="5" ry="3" fill="#ff9ec4" opacity=".6"/>`;
  s += p === "talking" || err ? `<ellipse cx="50" cy="78" rx="6" ry="${err ? 4 : 6}" fill="${INK}"/>` : `<path d="M43 76q7 7 14 0" stroke="${INK}" stroke-width="3" fill="none" stroke-linecap="round"/>`;
  if (g.mouth === 3 && !err && p !== "talking") s += `<path d="M53 78l1.8 4l1.8 -4.6z" fill="#fff"/>`;
  if (g.role === "po") s += `<g class="gear-po"><path d="M${f(50 - 37 * W)} 56a${f(37 * W)} 36 0 0 1 ${f(74 * W)} 0" fill="none" stroke="#2c3a40" stroke-width="5"/><rect x="${f(44 - 37 * W)}" y="48" width="11" height="20" rx="5" fill="#2c3a40" stroke="${INK}" stroke-width="2"/><path d="M${f(50 - 34 * W)} 66q2 14 20 13" fill="none" stroke="#2c3a40" stroke-width="3"/></g>`;
  if (g.role === "manager") s += `<g class="gear-manager"><path d="M50 87L37 80v15zM50 87l13 -7v15z" fill="#8a5cf6" stroke="${INK}" stroke-width="2.5" stroke-linejoin="round"/><circle cx="50" cy="87" r="4" fill="#5b3aa8" stroke="${INK}" stroke-width="2"/></g>`;
  if (g.role === "worker") s += `<g class="gear-worker"><path d="M${f(50 - 30 * W)} 36a${f(30 * W)} 26 0 0 1 ${f(60 * W)} 0Z" fill="#ffcc33" stroke="${INK}" stroke-width="2.5"/><rect x="${f(50 - 36 * W)}" y="34" width="${f(72 * W)}" height="6" rx="3" fill="#ffcc33" stroke="${INK}" stroke-width="2.5"/></g>`;
  if (g.role === "crew") s += `<path d="M26 86q24 12 48 0" stroke="#ff7359" stroke-width="8" fill="none" stroke-linecap="round"/>`;
  return s + mark(p) + "</svg>";
}
