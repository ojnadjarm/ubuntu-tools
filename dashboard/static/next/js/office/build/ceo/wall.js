/* The patch wall: a brass switchboard of bottle-green glass on the back wall, one column of jacks per floor, and one lit cable from the table to a jack for every running ticket. */
import { hash } from "../../../familiars/genome.js";
import { columns } from "../../ceo/desk.js";
import { WALL, TABLE } from "../../ceo/plan.js";
import { mul, tone, glow, lamp, sign } from "../props.js";
import { fit } from "../sign.js";
import { rod, TIMBER, BRASS, BRONZE, BOTTLE } from "./parts.js";

const FACE = 0.163, HEAD = 0.3, PER = 2, DARK = [0.03, 0.035, 0.03], LIT = [0.86, 0.8, 0.6], DIM = [0.36, 0.28, 0.13];

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
  const { B, th } = ctx, cols = columns(R.desk), n = cols.length, { x, w, y0, y1, rows } = WALL, cw = w / n, dusk = ctx.night ? 0.6 : 1;
  B.box(x, 0, 0.18, w + 0.34, y0 - 0.05, 0.36, TIMBER, { foot: true }); B.box(x, y0 - 0.05, 0.2, w + 0.4, 0.05, 0.42, BRONZE);
  B.box(x, y0, 0.08, w + 0.14, y1 - y0 + 0.07, 0.16, BRONZE);
  cols.forEach((c, k) => {
    const cx = x - w / 2 + (k + 0.5) * cw, on = c.jacks.length > 0, ink = mul(on ? LIT : DIM, dusk);
    B.cells([cx - cw / 2 + 0.05, y0 + 0.06, FACE], [cw - 0.1, 0, 0], [0, y1 - y0 - HEAD - 0.1, 0], 3, 6, (i, j) => tone(BOTTLE, i + k * 3, j, 0.2));
    B.cells([cx - cw / 2 + 0.05, y1 - HEAD, FACE], [cw - 0.1, 0, 0], [0, HEAD - 0.04, 0], 1, 1, mul(BRASS, 0.45));
    const { lines, s } = fit(ctx.ink, c.n + "F " + c.name.split(" ")[0], cw - 0.24, HEAD - 0.1), yc = y1 - HEAD / 2 - 0.02;
    lines.forEach((t, i) => sign(ctx, t, [cx, yc + ((lines.length - 1) / 2 - i) * 11 * s, FACE + 0.008], [0.82, 0, 0], [0, 1, 0], ctx.ink(t).h * s, ink, { i: 0 }));
    for (let i = 0; i < rows * PER; i++) {
      const jx = cx + ((i % PER) - (PER - 1) / 2) * 0.36, jy = y1 - HEAD - 0.3 - Math.floor(i / PER) * 0.27, t = c.jacks[i], p = t && hue(th, t);
      diamond(B, jx, jy, FACE + 0.003, 0.05, BRASS); diamond(B, jx, jy, FACE + 0.005, 0.022, DARK);
      diamond(B, jx, jy + 0.095, FACE + 0.003, 0.018, t ? p.col : mul(BOTTLE, 0.5), t ? glow(ctx, [...mul(p.col, p.k), 1]) : 0);
      if (t) cable(ctx, t, [jx, jy, FACE + 0.006]);
    }
  });
  lamp(ctx, x, 1.6, 1.3, ctx.night ? 0.3 : 0.16, 2.6, { col: [0.36, 0.7, 0.52] });
}
