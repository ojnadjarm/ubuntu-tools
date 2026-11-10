/* The hall round the rooms: floor, brick walls with city windows, the mezzanine over the kitchen, commons and machines in the free bays, aisle shelves and floor lines. */
import { RW, RD, COLS, MW, MD, GAP, AISLE } from "../layout.js";
import { mul, tone, glow, lamp, neon, rack, grow, cable, pane, holo } from "./props.js";

export const DECK = 1.34;

/* The inner face of a wall from a to b (it faces +z when a→b runs along +x); deco(len) draws in the wall's frame. */
export function wall(B, ax, az, bx, bz, h, col, { cell = 0.3, stagger = false } = {}, deco) {
  const dx = bx - ax, dz = bz - az, len = Math.hypot(dx, dz);
  B.push({ x: ax, z: az, r: Math.atan2(-dz, dx) });
  B.cells([0, 0, 0], [len, 0, 0], [0, h, 0], Math.ceil(len / (stagger ? cell * 2.2 : cell)), Math.ceil(h / cell), col, { stagger });
  B.cells([0, h, -0.07], [0, 0, 0.07], [len, 0, 0], 1, 1, mul(col(0, 0), 0.7));
  deco?.(len);
  B.pop();
}


function commons(ctx) {
  const { B, th } = ctx;
  B.model("rugRounded", { s: [1.6, 1, 1.8], tint: { carpet: mul(th.tints[1], 0.9), carpetDarker: mul(th.tints[1], 0.6) } });
  B.model("loungeSofaCorner", { x: -0.5, z: -0.5 }); B.model("loungeSofa", { x: 0.6, z: 0.75, r: Math.PI }); B.model("tableCoffee", { x: 0.2, z: 0.1 });
  B.model("cabinetTelevision", { x: 0, z: -1.4 }); holo(ctx, [-0.45, 0.4, -1.4], [0.9, 0, 0], [0, 0.5, 0], th.second, ctx.night ? 0.3 : 0.8);
  grow(ctx, 1.35, -0.9, -Math.PI / 2, { w: 0.9, on: !ctx.night }); B.model("speaker", { x: -0.75, z: -1.4 });
}
function machines(ctx) {
  const { B, th } = ctx;
  for (let k = 0; k < 4; k++) rack(ctx, -1.05 + k * 0.7, -1.2, 0, { seed: "m" + k, live: true });
  cable(ctx, [[-1.05, -0.95], [-1.05, -0.6], [1.05, -0.6], [1.05, -0.95]]); cable(ctx, [[0, -0.6], [0, 0.2], [-1.6, 0.2]]);
  grow(ctx, 0, 0.9, Math.PI, { w: 1.5, on: !ctx.night });
  B.model("loungeChair", { x: -1.1, z: 0.6, r: 2.2 }); B.model("sideTable", { x: 1.1, z: 0.5, r: -1.2 }); B.model("kitchenCoffeeMachine", { x: 1.1, y: 0.38, z: 0.5 });
  neon(ctx, 0, 1.36, -1.2, 2.5, 0.03, 0.03, th.accent, { i: 0.3, halo: 0.2 });
}
/* The mezzanine deck in the corner, its posts, rails, neon edge and the stairs. */
function deck(ctx) {
  const { B, th } = ctx, k = ctx.night ? 0.4 : 1;
  B.cells([0, DECK, 0], [0, 0, MD], [MW, 0, 0], Math.round(MD / 0.22), 3, (i, j) => tone(th.deck, i, j, 0.08), { stagger: true, sub: 4 });
  B.box(MW / 2, DECK - 0.14, MD - 0.05, MW, 0.14, 0.1, th.frame); B.box(MW - 0.05, DECK - 0.14, MD / 2, 0.1, 0.14, MD, th.frame);
  B.cells([0, DECK - 0.14, MD], [0, 0, -MD], [MW, 0, 0], 4, 4, mul(th.deck, 0.5));
  for (const [x, z] of [[MW - 0.1, MD - 0.1], [0.12, MD - 0.1], [MW / 2, MD - 0.1]]) B.box(x, 0, z, 0.12, DECK - 0.14, 0.12, th.frame, { foot: true });
  for (let x = 0.1; x < MW; x += 0.535) B.box(x, DECK, MD - 0.06, 0.04, 0.36, 0.04, th.frame);
  neon(ctx, MW / 2, DECK + 0.36, MD - 0.06, MW, 0.035, 0.05, th.accent, { i: 0.22, halo: 0.16, k });
  for (let z = 0.1; z < MD - 2; z += 0.5) B.box(MW - 0.06, DECK, z, 0.04, 0.36, 0.04, th.frame);
  neon(ctx, MW - 0.06, DECK + 0.36, (MD - 1.9) / 2, 0.05, 0.035, MD - 1.9, th.accent, { i: 0, k });
  neon(ctx, MW / 2, DECK - 0.17, MD - 0.02, MW - 0.3, 0.03, 0.03, th.second, { i: 0.35, r: 1.4, halo: 0.2, k: ctx.night ? 0.5 : 1 });
  B.model("stairs", { x: MW + 0.45, z: MD - 0.95, r: Math.PI / 2, s: [1, 1, 1.05] });
}
/* The kitchen and the dining table under the mezzanine. */
function kitchen(ctx) {
  const { B, th } = ctx;
  B.push({ x: 0.3, z: 0.4 });
  ["kitchenFridgeSmall", "kitchenCabinet", "kitchenCabinet", "kitchenBar", "kitchenBar"].forEach((m, i) => B.model(m, { x: 0.2 + i * 0.44, z: m === "kitchenBar" ? -0.1 : 0 }));
  B.model("kitchenCoffeeMachine", { x: 0.75, y: 0.45, z: 0 }); B.model("plantSmall1", { x: 1.6, y: 0.42, z: -0.1, s: 1.5 });
  [0, 1, 2].forEach((i) => B.model("stoolBar", { x: 0.9 + i * 0.4, z: 0.7, r: i * 0.4 }));
  neon(ctx, 1.1, 1.0, -0.3, 1.9, 0.03, 0.03, th.second, { i: 0.5, r: 1.1, halo: 0.25, k: ctx.night ? 0.5 : 1 });
  B.model("table", { x: 3, z: 1.2 }); B.model("bench", { x: 2.8, z: 0.75 }); B.model("bench", { x: 3.2, z: 0.75 }); B.model("benchCushion", { x: 3, z: 1.7, r: Math.PI }); B.model("plantSmall2", { x: 3, y: 0.33, z: 1.2, s: 1.6 });
  B.pop();
}
/* Low shelves, racks and grow beds on the lines between bays, and the dim floor lines along the aisles. */
function aisles(ctx, all, X0, WD, DP) {
  const { B, th } = ctx;
  for (let r = 0; r < all; r++) for (let c = 1; c < COLS; c++) {
    const x = X0 + c * RW, z0 = r * (RD + AISLE) + 0.15;
    for (let k = 0; k < 3; k++) {
      const z = z0 + 0.5 + k * 0.82, v = (c + k * 2 + r) % 4;
      if (v === 0) rack(ctx, x, z, Math.PI / 2, { seed: "s" + r + c + k, h: 0.95, live: !ctx.night });
      else if (v === 2 && (c + r) % 2) grow(ctx, x, z, Math.PI / 2, { w: 0.75, on: !ctx.night });
      else { B.model("bookcaseOpenLow", { x, z, r: Math.PI / 2, s: [2, 1.1, 0.7] }); B.model(v === 1 ? "books" : "plantSmall" + (1 + (c + k) % 3), { x, y: 0.45, z, r: 1.2, s: v === 1 ? 1 : 1.6 }); }
    }
  }
  const dim = glow(ctx, [...mul(th.accent, ctx.night ? 0.1 : 0.22), 1]);
  for (let r = 1; r < all; r++) { const z = r * (RD + AISLE) - AISLE / 2 + 0.1; B.cells([X0 - 0.5, 0.006, z + 0.28], [WD - X0 + 0.3, 0, 0], [0, 0, -0.02], 1, 1, th.accent, { glow: dim }); }
  B.cells([X0 - 0.5, 0.006, DP - 0.3], [0.02, 0, 0], [0, 0, -(DP - 0.6)], 1, 1, th.accent, { glow: dim });
  cable(ctx, [[X0 - 0.3, 0.4], [X0 - 0.3, DP - 0.5], [X0 + 2, DP - 0.5]]);
}

/* The whole hall for a plan; the rooms themselves are other chunks. */
export function hall(ctx, plan) {
  const { B, M, th } = ctx, { w: WD, d: DP, h: H } = plan.hall, X0 = MW + GAP, F = th.floor, wc = (i, j) => tone(th.wall.col, i, j, th.wall.k);
  const n = M.rooms.filter((r) => r.kind !== "pool").length, rows = Math.max(2, Math.ceil(n / COLS)), all = rows + Math.ceil(M.staff.length / COLS);
  const cell = (i) => ({ x: X0 + (i % COLS) * RW + RW / 2, z: Math.floor(i / COLS) * (RD + AISLE) + RD / 2 + 0.1 });
  B.cells([0, 0, 0], [0, 0, DP], [WD, 0, 0], Math.round(DP / F.cu), Math.round(WD / F.cv), (i, j) => tone(F.col, i, j, F.k), { stagger: F.stagger, sub: F.sub });
  const bays = (len, x0, x1) => { for (let x = x0 + RW / 2; x < Math.min(x1, len) - 1; x += RW) pane(ctx, x, 0.6, 2.5, 1.55); };
  wall(B, 0, 0, WD, 0, H, wc, th.wall, (len) => bays(len, X0, len));
  wall(B, WD, 0, WD, DP, H, wc, th.wall, (len) => bays(len, 0.5, len));
  wall(B, WD, DP, 0, DP, H, wc, th.wall, (len) => bays(len, 0.2, len));
  wall(B, 0, DP, 0, 0, H, wc, th.wall, (len) => bays(len, 0.5, len - MD));
  for (let i = n; i < rows * COLS; i++) { B.push(cell(i)); commons(ctx); B.pop(); }
  for (let i = rows * COLS + M.staff.length; i < all * COLS; i++) { B.push(cell(i)); machines(ctx); B.pop(); }
  aisles(ctx, all, X0, WD, DP); deck(ctx); kitchen(ctx);
  if (DP - MD > 7.5) { B.push({ x: MW / 2, z: DP - 2.3 }); machines(ctx); B.pop(); }
  B.model("rugDoormat", { x: 0.5, z: DP - 0.5, r: Math.PI / 2, s: 2 });
  lamp(ctx, WD / 2, 3, DP / 2, ctx.night ? 0 : 0.1, 9, { col: [1, 0.8, 0.55] });
}
