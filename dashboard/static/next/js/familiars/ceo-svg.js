/* The Conductor in 2D for lists and chips: ear tufts, spark-halo, coat triangle with coral lining and the tail lamp; motes only when the caller has room for them. */
import { css, pose } from "./genome.js";

const INK = "#04140c", NAVY = "#2a3466", DEEP = "#1d2340", CORAL = "#D97757", CREAM = "#f3e9dc", GOLD = "#e2b04a", MINT = "#4dffa0", RED = "#ff4a42";
const LAMP = { ok: CORAL, talking: "#ffa07a", needs: RED };
const SPOTS = [[9, 30], [91, 22], [20, 12], [80, 8], [5, 52], [95, 62], [30, 4], [70, 2], [12, 70], [90, 78], [3, 14], [97, 40]];

/* SVG string of the Conductor in a panel state; o.motes = agent hues (pass them from 48 px up), o.lamp = ok|talking|needs. */
export function ceoSvg(state, o = {}) {
  const p = pose(state), shut = p === "sleep", err = p === "error", up = p === "working" || p === "talking" || err;
  const lamp = LAMP[o.lamp] || (err ? RED : p === "talking" ? LAMP.talking : CORAL), hand = err ? [13, 31] : [12, 40];
  const out = (d, w, c) => `<path d="${d}" fill="none" stroke="${INK}" stroke-width="${w + 5}" stroke-linecap="round"/><path d="${d}" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round"/>`;
  let s = `<svg viewBox="0 0 100 100" class="cr ceo ${state}" role="img" aria-hidden="true">`;
  s += out("M64 84Q88 84 87 62Q86 52 84 47", 9, NAVY) + `<path d="M86.6 57Q86 51 84 47" fill="none" stroke="${CREAM}" stroke-width="9" stroke-linecap="round"/>`;
  s += `<circle cx="84" cy="40" r="${shut ? 5.5 : 7.5}" fill="${lamp}" stroke="${INK}" stroke-width="2.5" opacity="${shut ? 0.6 : 1}"/>` + (shut ? "" : `<circle cx="82" cy="38" r="2" fill="#fff" opacity=".8"/>`);
  if (!up) s += "";
  s += `<path d="M50 44L17 90q6.6 7 13.2 0q6.6 7 13.2 0q6.6 7 13.2 0q6.6 7 13.2 0q6.6 7 13.2 0Z" fill="${NAVY}" stroke="${INK}" stroke-width="3" stroke-linejoin="round"/>`;
  s += `<path d="M50 62L42.5 93.5h15Z" fill="${CORAL}" stroke="${INK}" stroke-width="2" stroke-linejoin="round"/><ellipse cx="45.5" cy="95" rx="4" ry="2.6" fill="${DEEP}" stroke="${INK}" stroke-width="1.5"/><ellipse cx="54.5" cy="95" rx="4" ry="2.6" fill="${DEEP}" stroke="${INK}" stroke-width="1.5"/>`;
  s += `<g transform="rotate(10 60 70)"><rect x="52" y="60" width="14" height="17" rx="2" fill="${GOLD}" stroke="${INK}" stroke-width="2.5"/><rect x="55" y="64" width="8" height="9" rx="1" fill="${CORAL}"/></g>`;
  s += out("M68 60Q72 70 64 74", 6, NAVY);
  if (up) s += out(`M31 62L${hand[0] + 5} ${hand[1] + 7}`, 7, NAVY) + `<circle cx="${hand[0] + 3.4}" cy="${hand[1] + 4.6}" r="4.6" fill="${CORAL}"/><circle cx="${hand[0]}" cy="${hand[1]}" r="5" fill="${CREAM}" stroke="${INK}" stroke-width="2.5"/>`;
  [-1, 1].forEach((k) => {
    const x = 50 + k * 16, d = shut ? 8 : 0;
    s += `<path d="M${x - k * 9} 24L${x + k * (17 + d)} ${1 + d * 2.2}L${x + k * 7} 31Z" fill="${NAVY}" stroke="${INK}" stroke-width="3" stroke-linejoin="round"/><path d="M${x - k * 3} 23L${x + k * (13 + d)} ${6.5 + d * 2.2}L${x + k * 5} 27Z" fill="${CORAL}"/>`;
  });
  s += `<path d="M36 50L50 60L64 50L60 62H40Z" fill="${DEEP}" stroke="${INK}" stroke-width="2.5" stroke-linejoin="round"/>`;
  s += `<ellipse cx="50" cy="37" rx="22" ry="19" fill="${CREAM}" stroke="${INK}" stroke-width="3"/><path d="M29.5 31A22 19 0 0 1 70.5 31Q58 22 50 31Q42 22 29.5 31Z" fill="${NAVY}" stroke="${INK}" stroke-width="2" stroke-linejoin="round"/>`;
  s += `<path d="M50 54l3 4.5l4.5 1.5l-4.5 1.5l-3 4.5l-3 -4.5l-4.5 -1.5l4.5 -1.5Z" fill="${GOLD}" stroke="${INK}" stroke-width="1.6" stroke-linejoin="round"/>`;
  [41, 59].forEach((x) => {
    s += shut ? `<path d="M${x - 5} 39q5 4 10 0" stroke="${INK}" stroke-width="3" fill="none" stroke-linecap="round"/>`
      : `<g class="lid"><circle cx="${x}" cy="39" r="6" fill="#fffaf2" stroke="${INK}" stroke-width="2"/><circle cx="${x}" cy="${p === "working" ? 39 : 40}" r="${err ? 2.2 : 3.4}" fill="${INK}"/><circle cx="${x + 1.4}" cy="38" r="1.1" fill="#fff"/><path d="M${x - 6.6} ${err ? 34 : 36.4}h13.2v-4.4h-13.2Z" fill="${CREAM}"/><path d="M${x - 6.6} ${err ? 34 : 36.4}h13.2" stroke="${INK}" stroke-width="2.2" stroke-linecap="round"/></g>`;
  });
  s += `<path d="M30.5 43l5 2M69.5 43l-5 2" stroke="${CORAL}" stroke-width="3" stroke-linecap="round"/>`;
  s += p === "talking" || err ? `<ellipse cx="50" cy="49.5" rx="3.6" ry="${err ? 2.4 : 3.6}" fill="${INK}"/>` : `<path d="M45 48q2.5 3.4 5 0q2.5 3.4 5 0" stroke="${INK}" stroke-width="2.2" fill="none" stroke-linecap="round"/>`;
  const hy = shut ? 19 : 8, hc = shut ? "#a8523a" : CORAL;
  s += `<g transform="rotate(${err ? -28 : -12} 50 ${hy})"><ellipse cx="50" cy="${hy}" rx="14" ry="4.6" fill="none" stroke="${INK}" stroke-width="5.5"/><ellipse cx="50" cy="${hy}" rx="14" ry="4.6" fill="none" stroke="${hc}" stroke-width="3"/>`;
  if (!shut) s += `<path d="M50 ${hy - 7}v-3.4M50 ${hy + 7}v3.4M33 ${hy}h-3.6M67 ${hy}h3.6M38 ${hy - 5}l-2.6 -2.4M62 ${hy - 5}l2.6 -2.4M38 ${hy + 5}l-2.6 2.4M62 ${hy + 5}l2.6 2.4" stroke="${hc}" stroke-width="2.4" stroke-linecap="round"/>`;
  s += "</g>";
  (o.motes || []).slice(0, 12).forEach((hue, i) => {
    const [x, y] = shut ? [22 + (i % 4) * 3.4, 72 - ((i / 4) | 0) * 3.4] : SPOTS[i], bad = err && i === 0, at = bad ? [hand[0] - 5, hand[1] - 12] : [x, y];
    if (p === "working") s += `<path d="M${hand[0]} ${hand[1] - 4}L${at[0]} ${at[1]}" stroke="${MINT}" stroke-width=".9" opacity=".75"/>`;
    s += `<circle cx="${at[0]}" cy="${at[1]}" r="${shut ? 1.8 : 3.7}" fill="${bad ? RED : css(hue, 90, 62)}" stroke="${INK}" stroke-width="1.4"/>`;
  });
  if (err && !(o.motes || []).length) s += `<circle cx="${hand[0] - 5}" cy="${hand[1] - 12}" r="4" fill="${RED}" stroke="${INK}" stroke-width="1.4"/>`;
  return s + "</svg>";
}
