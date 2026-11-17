/* The workers' pit, one step below the office: the desk pool on arcs round the table, every desk turned toward it; the step's edge lights while the pit works. */
import { ROOM, EDGE, DAIS, TABLE, SLOTS, ROWS, desk } from "../../ceo/plan.js";
import { mul, tone, glow, lamp } from "../props.js";
import { station, SCALE } from "../room.js";
import { board } from "../sign.js";
import { arc, TIMBER } from "./parts.js";

/* The pit for pool room R: timber floor, the step light, a desk per place of the first arc (the second arc once it is needed), people past the desks standing in front, the pool's name board. */
export function pit(ctx, R) {
  const { B, th } = ctx, { w: W, d: D } = ROOM, cool = { ...ctx, th: { ...th, warm: false } }, tint = mul(th.tints[1], 0.85), n = R.people.length > ROWS[0].n ? SLOTS : ROWS[0].n;
  B.cells([0, 0, EDGE - 0.02], [0, 0, D - EDGE + 0.02], [W, 0, 0], Math.round((D - EDGE) / 0.2), Math.round(W / 0.8), (i, j) => tone(TIMBER, i, j, 0.14), { stagger: true, sub: 6 });
  const col = R.busy ? th.accent : th.second, k = R.busy ? 1 : R.awake ? 0.3 : 0.1, g = glow(ctx, [...mul(col, k), 1]), half = Math.acos((EDGE - TABLE.z) / DAIS), hw = DAIS * Math.sin(half);
  arc(B, TABLE.x, TABLE.z, DAIS + 0.012, 0.02, 0.05, -half, half, 28, col, { glow: g });
  for (const [a, b] of [[0, TABLE.x - hw], [TABLE.x + hw, W]]) B.cells([a, 0.02, EDGE + 0.012], [b - a, 0, 0], [0, 0.03, 0], 1, 1, col, { glow: g });
  if (R.busy) for (const s of [-1, 0, 1]) lamp(ctx, TABLE.x + s * 1.5, 0.15, TABLE.z + DAIS + 0.2 - Math.abs(s) * 0.5, 0.3, 1.2, { col });
  for (let i = 0; i < n; i++) {
    const wk = R.people[i];
    B.push(desk(i));
    if (wk) { const p = station(cool, wk, tint, false); ctx.labels.push({ id: wk.id, pos: [p.x, p.y + 0.6, p.z], near: 78 }); }
    else B.model("desk", { z: 0.37, r: Math.PI });
    B.pop();
  }
  R.people.slice(SLOTS).forEach((wk, i) => {
    const p = B.at(TABLE.x + ((i % 9) - 4) * 0.5, 0, D - 0.75 + Math.floor(i / 9) * 0.4);
    ctx.actors.push({ id: wk.id, role: wk.role, pose: wk.pose, x: p.x, y: p.y, z: p.z, yaw: Math.PI, scale: SCALE });
  });
  B.push({ x: 1.0, z: D - 1.1, r: 0.75 }); board(ctx, R, { id: R.sign, name: R.info.name, w: 1.5, sh: 0.7, y: 0.4, h: 1.2 }); B.pop();
}
