/* The well: a railed round opening in the platform and three brass tubes down to the floors below; each tube is a rail the renderer's capsule runs on. */
import { WELL, STEP } from "../../ceo/plan.js";
import { mul, tone, glow } from "../props.js";
import { arc, STONE, BRASS, BRONZE, BOTTLE } from "./parts.js";

const TAU = Math.PI * 2, DEEP = -STEP - 0.24, TOP = 1.2;

/* One tube at (x, z): three thin rods held by collars under a bell mouth, open so the capsule shows. */
function tube(ctx, x, z) {
  const B = ctx.B;
  for (let k = 0; k < 3; k++) { const a = (k / 3) * TAU + 0.5; B.cyl(x + 0.075 * Math.sin(a), DEEP, z + 0.075 * Math.cos(a), 0.011, 0.011, TOP - DEEP, BRASS, { seg: 5 }); }
  for (const y of [0.3, 0.75]) B.ring(x, y, z, 0.06, 0.1, 0, TAU, 10, 1, BRONZE);
  arc(B, x, z, 0.095, TOP - 0.05, TOP + 0.03, 0, TAU, 10, BRASS); B.ring(x, TOP + 0.03, z, 0.06, 0.12, 0, TAU, 10, 1, BRASS);
  const a = B.at(x, TOP - 0.1, z), b = B.at(x, DEEP + 0.05, z);
  ctx.rails.push({ a: [a.x, a.y, a.z], b: [b.x, b.y, b.z] });
}

/* The stone collar, the shaft, its faint light from below, the rail and the three tubes. */
export function well(ctx) {
  const { B } = ctx, { x, z, r } = WELL;
  B.ring(x, 0.012, z, r, r + 0.42, 0, TAU, 28, 2, (i, j) => (j ? tone(mul(STONE, 0.7), i >> 1, 0, 0.1) : BRONZE));
  arc(B, x, z, r, DEEP, 0.012, 0, TAU, 24, (i) => tone(mul(STONE, 0.3), i, 1, 0.15), { inward: true });
  B.ring(x, DEEP, z, 0, r, 0, TAU, 16, 1, BOTTLE, glow(ctx, [...mul(BOTTLE, 0.7), 0.8]));
  for (let k = 0; k < 10; k++) { const a = (k / 10) * TAU; B.cyl(x + (r + 0.34) * Math.sin(a), 0.012, z + (r + 0.34) * Math.cos(a), 0.016, 0.016, 0.44, BRASS, { seg: 6 }); }
  B.ring(x, 0.452, z, r + 0.31, r + 0.37, 0, TAU, 30, 1, BRASS);
  for (let k = 0; k < 3; k++) { const a = (k / 3) * TAU; tube(ctx, x + 0.27 * Math.sin(a), z + 0.27 * Math.cos(a)); }
}
