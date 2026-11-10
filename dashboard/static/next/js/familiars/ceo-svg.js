/* The Conductor in 2D for lists and chips: ear tufts, spark-halo, coat triangle with coral lining and the tail lamp; motes only when the caller has room for them. */
import { css, pose } from "./genome.js";

const INK = "#04140c", NAVY = "#2a3466", DEEP = "#1d2340", CORAL = "#D97757", CREAM = "#f3e9dc", GOLD = "#e2b04a", MINT = "#4dffa0", RED = "#ff4a42", LID = "#dccbb6";
const LAMP = { ok: CORAL, talking: "#ffa07a", needs: RED };
/* Where the motes sit on the two tilted rings round the coat, clear of the hand, the face and the lamp. */
const SPOTS = [[7, 62], [95, 76], [22, 88], [76, 94], [4, 80], [30, 70], [72, 82], [14, 74], [86, 91], [38, 84], [60, 89], [26, 60]];
/* Whether the segment a-b stays clear of the face. */
const clear = (a, b) => { const dx = b[0] - a[0], dy = b[1] - a[1], u = Math.max(0, Math.min(1, ((50 - a[0]) * dx + (38 - a[1]) * dy) / (dx * dx + dy * dy || 1))); return Math.hypot(a[0] + dx * u - 50, a[1] + dy * u - 38) > 25; };

/* SVG string of the Conductor in a panel state; o.motes = agent hues (pass them from 48 px up), o.lamp = ok|talking|needs. */
export function ceoSvg(state, o = {}) {
  const p = pose(state), shut = p === "sleep", err = p === "error", up = p === "working" || p === "talking" || err;
  const lamp = LAMP[o.lamp] || (err ? RED : p === "talking" ? LAMP.talking : CORAL), hand = err ? [13, 31] : [12, 40];
  const out = (d, w, c) => `<path d="${d}" fill="none" stroke="${INK}" stroke-width="${w + 5}" stroke-linecap="round"/><path d="${d}" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round"/>`;
  let s = `<svg viewBox="0 0 100 100" class="cr ceo ${state}" role="img" aria-hidden="true">`;
  s += out("M66 82Q93 87 93 64Q93 50 87 43", 10, NAVY) + `<path d="M93 60Q92.6 49 87 43" fill="none" stroke="${CREAM}" stroke-width="10" stroke-linecap="round"/><path d="M82.5 44.5l8.5 -4" stroke="${GOLD}" stroke-width="3.2" stroke-linecap="round"/>`;
  if (!shut && lamp === LAMP.talking) s += `<circle class="ring" cx="86" cy="32" r="12.6" fill="none" stroke="${lamp}" stroke-width="1.8"/>`;
  if (!shut && lamp === RED) s += `<path d="M86 17.5v-5M94.8 22.4l3.4 -3.6M77.4 22.4l-2.4 -2.6" stroke="${RED}" stroke-width="3" stroke-linecap="round"/>`;
  s += `<circle cx="86" cy="32" r="${shut ? 8 : 10}" fill="${lamp}" stroke="${INK}" stroke-width="2.5" opacity="${shut ? 0.85 : 1}"/>` + (shut ? "" : lamp === RED ? `<path d="M86 26.5v6.5" stroke="#fff" stroke-width="3" stroke-linecap="round"/><circle cx="86" cy="37.4" r="1.6" fill="#fff"/>` : `<circle cx="83" cy="29" r="2.6" fill="#fff" opacity=".8"/>`);
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
  s += `<ellipse cx="50" cy="48.6" rx="7.4" ry="4.8" fill="#fffaf2"/><ellipse cx="50" cy="45.4" rx="1.9" ry="1.3" fill="${CORAL}"/>`;
  const lid = err ? 36.6 : p === "talking" ? 38.2 : 39.4;
  [41, 59].forEach((x, i) => {
    s += shut ? `<path d="M${x - 5.5} 40q5.5 4.4 11 0" stroke="${INK}" stroke-width="2.8" fill="none" stroke-linecap="round"/>`
      : `<g class="lid"><circle cx="${x}" cy="40" r="6" fill="#fffaf2"/><circle cx="${x}" cy="40.8" r="${err ? 3.8 : 4.8}" fill="${GOLD}"/><circle cx="${x}" cy="40.8" r="${err ? 2 : 2.7}" fill="${INK}"/><circle cx="${x + 1.7}" cy="39.6" r="1.1" fill="#fff"/><path d="M${x - 6.8} ${lid}V37Q${x} 29.5 ${x + 6.8} 37V${lid}Z" fill="${LID}"/><path d="M${x - 6.4} ${lid}h12.8" stroke="${INK}" stroke-width="2.2" stroke-linecap="round"${err ? ` transform="rotate(${i ? -12 : 12} ${x} ${lid})"` : ""}/></g>`;
  });
  s += `<path d="M30 46.5l4.6 1.6M70 46.5l-4.6 1.6" stroke="${CORAL}" stroke-width="3" stroke-linecap="round"/>`;
  s += p === "talking" || err ? `<ellipse class="mouth" cx="50" cy="50" rx="3.2" ry="${err ? 2.2 : 3.2}" fill="${INK}"/>` : `<path d="M45.6 48.2q2.2 3.2 4.4 0q2.2 3.2 4.4 0" stroke="${INK}" stroke-width="2" fill="none" stroke-linecap="round"/>`;
  const hy = shut ? 19 : 8, hc = CORAL;
  s += `<g transform="rotate(${err ? -28 : -12} 50 ${hy})"><ellipse cx="50" cy="${hy}" rx="14" ry="4.6" fill="none" stroke="${INK}" stroke-width="5.5"/><ellipse cx="50" cy="${hy}" rx="14" ry="4.6" fill="none" stroke="${hc}" stroke-width="3"/>`;
  if (!shut) s += `<path d="M50 ${hy - 7}v-3.4M50 ${hy + 7}v3.4M33 ${hy}h-3.6M67 ${hy}h3.6M38 ${hy - 5}l-2.6 -2.4M62 ${hy - 5}l2.6 -2.4M38 ${hy + 5}l-2.6 2.4M62 ${hy + 5}l2.6 2.4" stroke="${hc}" stroke-width="2.4" stroke-linecap="round"/>`;
  s += "</g>";
  (o.motes || []).slice(0, 12).forEach((hue, i) => {
    const bad = err && i === 0, at = bad ? [hand[0] - 5, hand[1] - 12] : shut ? [22 + (i % 4) * 3.4, 72 - ((i / 4) | 0) * 3.4] : SPOTS[i], from = [hand[0], hand[1] - 4];
    if (p === "working" && clear(from, at)) s += `<path d="M${from[0]} ${from[1]}L${at[0]} ${at[1]}" stroke="${MINT}" stroke-width=".9" opacity=".75"/>`;
    s += `<circle cx="${at[0]}" cy="${at[1]}" r="${shut ? 1.8 : 3.7}" fill="${bad ? RED : css(hue, 90, 62)}" stroke="${INK}" stroke-width="1.4"/>`;
  });
  if (err && !(o.motes || []).length) s += `<circle cx="${hand[0] - 5}" cy="${hand[1] - 12}" r="4" fill="${RED}" stroke="${INK}" stroke-width="1.4"/>`;
  return s + "</svg>";
}
