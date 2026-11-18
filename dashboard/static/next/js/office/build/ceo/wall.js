/* The patch wall: a brass switchboard of bottle-green glass on the back wall, one column of jacks per floor, and one lit cable from the table to a jack for every running ticket. */
import { hash } from "../../../familiars/genome.js";
import { columns } from "../../ceo/desk.js";
import { WALL, TABLE, STEP } from "../../ceo/plan.js";
import { mul, tone, glow, lamp, sign } from "../props.js";
import { rod, TIMBER, BRASS, BRONZE, BOTTLE } from "./parts.js";

const FACE = 0.163, DARK = [0.03, 0.035, 0.03], LIT = [0.95, 0.9, 0.72], IVORY = [0.46, 0.43, 0.36], ENAMEL = [0.025, 0.03, 0.028];
/* Ink rows of a capital and from one line to the next, the advance of one monospace letter in ink pixels, the condensed width, the numeral's size against the name's, the plate's margins, a column's least width. */
const CAP = 9, PITCH = 11, ADV = 7.2, NARROW = 0.82, BIG = 1.6, PAD = 0.08, EDGE = 0.24, MINW = 1.0;

/* The head plates for names "<n>F <Name>" (top floor first): a column per name, as wide as its name needs (1 m at least), every name in one size, the largest the wall's width allows, the numeral line over the name line. Each label: {text, x, y, s, w, cx, cw}, s one ink row; top and bot are its capitals' extent in the world. */
export function plates(names) {
  const { x, w, y1 } = WALL, wide = (t, s) => NARROW * (ADV * t.length + 2) * s, sum = (a) => a.reduce((t, v) => t + v, 0);
  const parts = names.map((t) => { const [n, name] = t.split(" "); return [n, name.toUpperCase()]; }), fill = (s) => parts.map(([n, t]) => Math.max(MINW, wide(t, s) + EDGE, wide(n, s * BIG) + EDGE));
  let s = 0, hi = 1;
  for (let i = 0; i < 30; i++) { const m = (s + hi) / 2; if (sum(fill(m)) <= w) s = m; else hi = m; }
  const cws = fill(s), more = (w - sum(cws)) / names.length, big = s * BIG, yn = y1 - PAD - (PITCH * big) / 2, ym = yn - (PITCH * (big + s)) / 2;
  const at = (text, cx, cw, y, k) => ({ text, x: cx, y, s: k, w: wide(text, k), cx, cw, top: [cx, y + (CAP / 2) * k + STEP, FACE], bot: [cx, y - (CAP / 2) * k + STEP, FACE] });
  let left = x - w / 2;
  return parts.flatMap(([n, t], k) => { const cw = cws[k] + more, cx = left + cw / 2; left += cw; return [at(n, cx, cw, yn, big), at(t, cx, cw, ym, s)]; });
}

/* The plates' height on the wall: from the wall top to under the name line. */
const headOf = (L) => WALL.y1 - L[1].y + (PITCH * L[1].s) / 2 + PAD;

/* A ticket's colour and strength: red when failing, the accent when working, the accent low while its session waits. */
const hue = (th, t) => ({ col: t.state === "failing" ? th.state.error : th.accent, k: t.state === "waiting" ? 0.4 : 1 });

/* A square on the wall's face standing on its corner, centred on (x, y). */
const diamond = (B, x, y, z, r, col, g = 0) => B.cells([x - r, y, z], [r, -r, 0], [r, r, 0], 1, 1, col, { glow: g });

/* The cable of ticket t from the table's rim to the jack at j, hanging in a curve, with its plugs and its light. */
function cable(ctx, t, j) {
  const { B, th } = ctx, { col, k } = hue(th, t), g = glow(ctx, [...mul(col, k), 1]), h = hash(t.id);
  const dx = j[0] - TABLE.x, dz = j[2] - TABLE.z, l = Math.hypot(dx, dz), o = ((h % 7) - 3) * 0.035, sag = 0.16 + ((h >>> 3) % 5) * 0.05;
  const s = [TABLE.x + (dx / l) * 0.5 - (dz / l) * o, TABLE.h + 0.03, TABLE.z + (dz / l) * 0.5 + (dx / l) * o], N = 12;
  const at = (i) => { const f = i / N; return [s[0] + (j[0] - s[0]) * f, s[1] + (j[1] - s[1]) * f - 4 * sag * f * (1 - f), s[2] + (j[2] - s[2]) * f]; };
  for (let i = 0; i < N; i++) rod(B, at(i), at(i + 1), 0.024, col, g);
  B.cyl(s[0], TABLE.h, s[2], 0.03, 0.022, 0.03, BRASS, { seg: 8 }); B.box(j[0], j[1] - 0.025, j[2] + 0.03, 0.05, 0.05, 0.06, BRASS);
  const m = at(N / 2);
  lamp(ctx, j[0], j[1], 0.45, 0.32 * k, 0.75, { col, halo: 0.3 * k }); lamp(ctx, m[0], m[1] + 0.1, m[2], 0.2 * k, 0.9, { col });
}

/* The wall for the CEO room R: the body and its plinth, then per floor a name plate (lit while a ticket runs there), the jacks, and a cable per ticket. */
export function patchWall(ctx, R) {
  const { B, th } = ctx, cols = columns(R.desk), { x, w, y0, y1, rows } = WALL, L = plates(cols.map((c) => c.n + "F " + c.name)), HEAD = headOf(L), dy = (y1 - HEAD - 0.2 - y0) / rows;
  B.box(x, 0, 0.18, w + 0.34, y0 - 0.05, 0.36, TIMBER, { foot: true }); B.box(x, y0 - 0.05, 0.2, w + 0.4, 0.05, 0.42, BRONZE);
  B.box(x, y0, 0.08, w + 0.14, y1 - y0 + 0.07, 0.16, BRONZE);
  cols.forEach((c, k) => {
    const { cx, cw } = L[2 * k], per = cw < 1.4 ? 2 : 3, on = c.jacks.length > 0, ink = on ? LIT : IVORY;
    B.cells([cx - cw / 2 + 0.05, y0 + 0.06, FACE], [cw - 0.1, 0, 0], [0, y1 - y0 - HEAD - 0.1, 0], 3, 6, (i, j) => tone(BOTTLE, i + k * 3, j, 0.2));
    B.cells([cx - cw / 2 + 0.05, y1 - HEAD, FACE], [cw - 0.1, 0, 0], [0, HEAD - 0.04, 0], 1, 1, mul(BRASS, 0.45));
    B.cells([cx - cw / 2 + 0.09, y1 - HEAD + 0.04, FACE + 0.004], [cw - 0.18, 0, 0], [0, HEAD - 0.12, 0], 1, 1, ENAMEL);
    for (const l of L.slice(2 * k, 2 * k + 2)) sign(ctx, l.text, [l.x, l.y, FACE + 0.008], [NARROW, 0, 0], [0, 1, 0], ctx.ink(l.text).h * l.s, ink, { i: 0 });
    for (let i = 0; i < rows * per; i++) {
      const jx = cx + ((i % per) - (per - 1) / 2) * 0.4, jy = y1 - HEAD - 0.3 - Math.floor(i / per) * dy, t = c.jacks[i], p = t && hue(th, t);
      diamond(B, jx, jy, FACE + 0.003, 0.065, BRASS); diamond(B, jx, jy, FACE + 0.005, 0.03, DARK);
      diamond(B, jx, jy + 0.12, FACE + 0.003, 0.022, t ? p.col : mul(BOTTLE, 0.5), t ? glow(ctx, [...mul(p.col, p.k), 1]) : 0);
      if (t) cable(ctx, t, [jx, jy, FACE + 0.006]);
    }
  });
  lamp(ctx, x, 2.2, 1.6, ctx.night ? 0.3 : 0.16, w * 0.4, { col: [0.36, 0.7, 0.52] });
}
