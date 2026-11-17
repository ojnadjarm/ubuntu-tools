/* The Switchboard's shell, the top of the building: a stone wall behind the patch wall and at the door side, full-height glass on the two outer walls under a bronze head beam; no ceiling, the camera lives above. */
import { hash } from "../../../familiars/genome.js";
import { wall } from "../hall.js";
import { tone, mul, lamp, quad, WINDOW } from "../props.js";
import { STONE, BRONZE, MOON } from "./parts.js";

/* A glass wall from a to b, inner face as in wall(): sill, mullions, head beam, one sky pane and one cool light per bay. */
function glazed(ctx, ax, az, bx, bz, h) {
  const B = ctx.B, dx = bx - ax, dz = bz - az, len = Math.hypot(dx, dz), n = Math.round(len / 1.2), bw = len / n, sill = 0.1, top = h - 0.12;
  B.push({ x: ax, z: az, r: Math.atan2(-dz, dx) });
  B.box(len / 2, 0, 0.05, len, sill, 0.12, mul(STONE, 0.8)); B.box(len / 2, top, 0.05, len, 0.12, 0.12, BRONZE);
  for (let k = 0; k <= n; k++) B.box(k * bw, sill, 0.04, 0.05, top - sill, 0.08, BRONZE);
  for (let k = 0; k < n; k++) {
    quad(ctx, WINDOW, [k * bw + 0.025, sill, 0.014], [bw - 0.05, 0, 0], [0, top - sill, 0], { k: [hash("g" + ctx.quads.length) % 97, 1.05, 1] });
    lamp(ctx, (k + 0.5) * bw, 0.7, 0.9, ctx.night ? 0.5 : 0.34, 1.5, { col: MOON });
  }
  B.pop();
}

/* The whole shell for the plan; the office and the pit are other chunks and bring their own floors. */
export function shell(ctx, plan) {
  const { B } = ctx, { w: W, d: D, h: H } = plan.hall, col = (i, j) => tone(mul(STONE, 0.62), i, j, 0.1), opt = { cell: 0.34, stagger: true };
  wall(B, 0, 0, W, 0, H, col, opt);
  glazed(ctx, W, 0, W, D, H);
  wall(B, W, D, 0, D, H, col, opt);
  glazed(ctx, 0, D, 0, 0, H);
}
