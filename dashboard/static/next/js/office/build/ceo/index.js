/* The Switchboard, the CEO floor's own room: its shell as the hall chunk, the office (platform, patch wall, table, the owner's chair, the well) as the CEO's chunk, the pit as the desk pool's. */
import { ROOM, EDGE, DAIS, TABLE, WELL, STEP } from "../../ceo/plan.js";
import { mul, tone } from "../props.js";
import { shell } from "./shell.js";
import { patchWall } from "./wall.js";
import { table } from "./table.js";
import { nook } from "./nook.js";
import { well } from "./well.js";
import { pit } from "./pit.js";
import { arc, STONE, BRONZE } from "./parts.js";

const ROW = 0.23, SLAB = 0.3;

/* The stone platform: slabs in rows, cut open round the well, its riser and bronze nosing along the straight edge and round the dais. */
function platform(ctx) {
  const B = ctx.B, W = ROOM.w, half = Math.acos((EDGE - TABLE.z) / DAIS), hw = DAIS * Math.sin(half), col = (j) => (i) => tone(STONE, (i + (j >> 1)) >> 1, j >> 1, 0.09);
  for (let j = 0; j * ROW < EDGE - 1e-6; j++) {
    const z0 = j * ROW, z1 = Math.min(EDGE, z0 + ROW), dz = Math.max(0, z0 - WELL.z, WELL.z - z1), cut = dz < WELL.r ? Math.sqrt(WELL.r ** 2 - dz ** 2) : 0;
    for (const [a, b] of cut ? [[0, WELL.x - cut], [WELL.x + cut, W]] : [[0, W]]) B.cells([a, 0, z0], [0, 0, z1 - z0], [b - a, 0, 0], 1, Math.round((b - a) / SLAB), (_, i) => col(j)(i));
  }
  for (const [a, b] of [[0, TABLE.x - hw], [TABLE.x + hw, W]]) { B.cells([a, -STEP, EDGE], [b - a, 0, 0], [0, STEP, 0], 8, 1, mul(STONE, 0.55)); B.cells([a, 0.002, EDGE], [b - a, 0, 0], [0, 0, -0.04], 1, 1, BRONZE); }
  arc(B, TABLE.x, TABLE.z, DAIS, -STEP, 0.012, -half, half, 28, mul(STONE, 0.55));
}

/* The office for CEO room R, on the platform. */
function office(ctx, R) {
  platform(ctx); patchWall(ctx, R); table(ctx, R); nook(ctx, R); well(ctx);
}

export const SWITCHBOARD = { hall: shell, rooms: { ceo: office, pool: pit }, at: (R, M, c) => ({ x: c.x, y: c.y, z: c.z }) };
