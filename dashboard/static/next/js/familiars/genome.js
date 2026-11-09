/* Familiars genome: the same id always gives the same creature; the role sets the gear. The SVG and the 3D body both read it. */
import { rng } from "../shapes.js";

export const ROLES = ["ceo", "po", "worker", "crew"], POSES = ["working", "idle", "talking", "error", "sleep"];
const KATA = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎ";
const HUES = [152, 172, 192, 118, 44, 238, 268, 318, 206, 88];
const TOPPER = { ears: 0, none: 1, sprout: 2, horns: 3, ant: 4 }, MOUTH = { smile: 0, cat: 1, o: 2, fang: 3 };

export function hash(s) { let h = 2166136261; for (const ch of s) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; }
const pick = (r, a) => a[(r() * a.length) | 0];

/* The pose a panel state acts out: done, stale, off and unknown states rest. */
export const pose = (state) => (POSES.includes(state) ? state : "sleep");

export function genome(id, role = "worker") {
  const r = rng(hash(id)), hue = pick(r, HUES), wide = 0.9 + r() * 0.25, tall = 0.85 + r() * 0.25;
  r(); r(); const phase = r() * 6.28; r();
  const eyes = pick(r, [1, 2, 2, 2, 3]), glyph = KATA[hash(id + "g") % KATA.length], top = pick(r, ["ant", "ant", "ears", "horns", "sprout", "none"]), mouth = MOUTH[pick(r, ["smile", "cat", "o", "fang"])];
  const spots = r() < 0.55;
  if (top === "ant") { r(); r(); r(); r(); }
  if (spots) for (let i = 0; i < 12; i++) r();
  return { id, role: ROLES.includes(role) ? role : "worker", hue, wide, tall, eyes, topper: TOPPER[top], mouth, spots, phase, glyph,
    tail: (r() * 3) | 0, blink: r(), uid: "f" + hash(id).toString(36) };
}

/* HSL (h in degrees, s and l 0..1) to a display-space [r, g, b]. */
export function hsl(h, s, l) {
  const f = (n) => { const k = (n + (((h % 360) + 360) % 360) / 30) % 12; return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1)); };
  return [f(0), f(8), f(4)];
}
export const css = (h, s, l) => `hsl(${(((h % 360) + 360) % 360).toFixed(0)} ${s}% ${l}%)`;
