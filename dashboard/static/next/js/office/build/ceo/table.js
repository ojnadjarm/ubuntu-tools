/* The round standing table on its stone dais: the open briefs lie on it as sheets, the newest on top, and the Conductor stands at its side with the model's motes, lamp and failing agent. */
import { genome } from "../../../familiars/genome.js";
import { sheets } from "../../ceo/desk.js";
import { TABLE, DAIS } from "../../ceo/plan.js";
import { mul, tone, glow, lamp } from "../props.js";
import { TIMBER, STONE, BRASS, BRONZE, BOTTLE, PAPER } from "./parts.js";

const TAU = Math.PI * 2, GOLDEN = 2.4, INK = [0.3, 0.3, 0.28];

/* One brief on the table at height y: paper, three ruled lines and a lit edge in its ticket's colour. */
function sheet(ctx, t, i, n, y) {
  const { B, th } = ctx, top = i === n - 1, a = i * GOLDEN, r = top ? 0.1 : 0.3, col = t.state === "failing" ? th.state.error : th.accent, k = t.state === "waiting" ? 0.4 : 1;
  B.push({ x: TABLE.x + r * Math.sin(a), y, z: TABLE.z + r * Math.cos(a), r: a * 1.7 });
  B.cells([-0.1, 0, 0.14], [0.2, 0, 0], [0, 0, -0.28], 1, 1, PAPER);
  for (let l = 0; l < 3; l++) B.cells([-0.07, 0.001, -0.06 + l * 0.05], [0.11 - l * 0.02, 0, 0], [0, 0, -0.012], 1, 1, INK);
  B.cells([-0.1, 0.001, 0.14], [0.2, 0, 0], [0, 0, -0.022], 1, 1, col, { glow: glow(ctx, [...mul(col, k), 1]) });
  B.pop();
}

/* The dais, the table, a sheet per running ticket and the Conductor of room R. */
export function table(ctx, R) {
  const { B, th } = ctx, { x, z, r, h } = TABLE, S = sheets(R.desk), on = R.pose === "working" || R.pose === "talking", col = th.state[R.pose];
  B.ring(x, 0.012, z, 0, DAIS, 0, TAU, 48, 8, (i, j) => (j === 7 ? BRONZE : j === 3 ? mul(BRASS, 0.5) : tone(mul(STONE, 0.72), i >> 1, j, 0.1)));
  B.cyl(x, 0.012, z, 0.27, 0.23, 0.035, BRONZE, { seg: 18, foot: true }); B.cyl(x, 0.04, z, 0.17, 0.09, h - 0.09, TIMBER, { seg: 14 });
  B.cyl(x, h - 0.05, z, r, r, 0.05, mul(TIMBER, 1.5), { seg: 30 });
  B.ring(x, h + 0.002, z, r - 0.04, r, 0, TAU, 30, 1, BRASS); B.ring(x, h + 0.002, z, 0, r - 0.06, 0, TAU, 24, 3, (i, j) => tone(mul(BOTTLE, 0.9), i >> 2, j, 0.12));
  S.forEach((t, i) => sheet(ctx, t, i, S.length, h + 0.006 + i * 0.004));
  if (S.length) lamp(ctx, x, h + 0.4, z, 0.26, 0.9, { col: th.accent });
  const p = B.at(x + 0.98, 0.012, z + 0.05), L = R.live || { motes: [], lamp: "ok", failing: null };
  ctx.actors.push({ id: R.id, role: "ceo", pose: R.pose, x: p.x, y: p.y, z: p.z, yaw: p.r - 0.93, scale: 0.4, live: { motes: L.motes.map((id) => ({ id, hue: genome(id).hue })), lamp: L.lamp, failing: L.failing } });
  ctx.labels.push({ id: R.id, pos: [p.x, p.y + 1.12, p.z] });
  if (col) lamp(ctx, x + 0.75, 0.7, z + 0.35, on ? 0.5 : 0.22, 0.9, { col, halo: on ? 0.3 : 0.12 });
}
