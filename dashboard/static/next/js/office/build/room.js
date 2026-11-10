/* One room per builder, in its own frame (centre at the origin, back wall at -z): a desk station per person, decor in the empty places, a lounge corner, the room's name board, and the room light. */
import { hash, genome } from "../../familiars/genome.js";
import { mul, glow, lamp, rack, grow, holo } from "./props.js";
import { board } from "./sign.js";

export const SEAT = 0.28, SCALE = 0.36;
const CREAM = [0.6, 0.66, 0.62], OFF = [0.12, 0.14, 0.14], STANDBY = [0.16, 0.32, 0.36];

/* One desk place with its seat at the origin, facing +z: the desk strip, the holo screen and the light pool carry the occupant's state; one asleep but on shows a standby light, one off stays dark. */
export function station(ctx, who, tint, lead) {
  const { B, th } = ctx, col = th.state[who.pose], on = who.pose === "working" || who.pose === "talking", err = who.pose === "error";
  B.cyl(0, 0, 0, 0.2, 0.17, SEAT, th.seat, { foot: true }); B.cyl(0, SEAT - 0.03, 0, 0.19, 0.19, 0.02, mul(tint, 0.9), { seg: 14 });
  B.model("desk", { z: 0.37, r: Math.PI });
  B.box(0, 0.384, 0.545, 0.7, 0.022, 0.03, col || OFF, { glow: glow(ctx, [...(col ? mul(col, on || err ? 1 : 0.55) : OFF), 1]) });
  if (on || err) { holo(ctx, [-0.24, 0.46, 0.5], [0.48, 0, 0], [0, 0.3, 0], col); lamp(ctx, 0, 0.6, 0.42, lead ? 0.95 : 0.8, 0.7, { col, halo: 0.5 }); lamp(ctx, 0, 0.05, 0.75, 0.3, 0.5, { col }); }
  else if (col) { holo(ctx, [-0.13, 0.46, 0.5], [0.26, 0, 0], [0, 0.17, 0], col, 0.45); lamp(ctx, 0, 0.5, 0.45, 0.16, 0.5, { col, halo: 0.1 }); }
  else if (who.on) { B.box(0, 0.4, 0.5, 0.3, 0.17, 0.012, STANDBY, { glow: glow(ctx, [...STANDBY, 1]) }); B.box(0.2, 0.396, 0.53, 0.04, 0.014, 0.04, th.second, { glow: glow(ctx, [...th.second, 1]) }); }
  if (th.warm) { B.model(lead ? "lampRoundTable" : "lampSquareTable", { x: 0.29, y: 0.384, z: 0.42, glow: { lamp: col ? glow(ctx, [1, 0.86, 0.52, 1]) : 0 } }); if (col) lamp(ctx, 0.29, 0.7, 0.42, on ? 0.4 : 0.3, 0.55, { halo: 0.22 }); }
  B.cyl(-0.27, 0.384, 0.42, 0.026, 0.03, 0.055, CREAM, { seg: 8 });
  if (lead) B.model("plantSmall" + (1 + hash(who.id) % 3), { x: -0.14, y: 0.384, z: 0.47, s: 1.3 });
  const p = B.at(0, SEAT, 0);
  ctx.actors.push({ id: who.id, role: who.role, pose: who.pose, x: p.x, y: p.y, z: p.z, yaw: p.r, scale: SCALE });
  return p;
}

const DECOR = [
  (ctx, live) => rack(ctx, 0, -0.05, 0, { seed: "d", live }),
  (ctx) => grow(ctx, 0, 0, 0, { w: 0.7 }),
  ({ B }) => { B.model("loungeChair", { z: 0.05 }); B.model("pillow", { y: 0.2, z: 0.05, s: 0.9 }); },
  ({ B }) => { B.model("cardboardBoxClosed", { x: -0.1, r: 0.3 }); B.model("cardboardBoxOpen", { x: 0.22, z: 0.2, r: -0.4, s: 0.8 }); },
  ({ B }) => { B.model("sideTableDrawers", {}); B.model("radio", { y: 0.3, r: 0.2 }); },
  ({ B }) => { B.model("bookcaseOpenLow", { z: -0.1 }); B.model("plantSmall1", { x: 0.1, y: 0.44, z: -0.1, s: 1.5 }); B.model("books", { x: -0.12, y: 0.44, z: -0.1 }); },
  (ctx, live) => { rack(ctx, -0.1, -0.05, 0, { seed: "e", h: 0.8, live }); ctx.B.model("trashcan", { x: 0.32, z: 0.1 }); },
];
const LOUNGE = [
  (B, t) => { B.model("loungeSofa", { z: 0.25, r: Math.PI, tint: { carpet: t } }); B.model("tableCoffee", { z: -0.4 }); B.model("books", { x: 0.1, y: 0.2, z: -0.4, r: 1 }); },
  (B, t) => { B.model("loungeChair", { x: -0.5, z: 0.1, r: 2.5, tint: { carpet: t } }); B.model("loungeChair", { x: 0.5, z: 0.1, r: -2.5, tint: { carpet: t } }); B.model("tableRound", { z: -0.1, s: 0.7 }); B.model("plantSmall3", { y: 0.27, z: -0.1, s: 1.5 }); },
  (B, t) => { B.model("benchCushion", { z: 0.3, r: Math.PI, tint: { carpet: t } }); B.model("pottedPlant", { x: 0.75, z: 0.3, s: 1.4 }); B.model("bear", { x: -0.2, y: 0.22, z: 0.3, r: Math.PI, s: 1.2 }); },
];

/* The floor trace round a room: bright in the accent while someone works, dim amber while only awake, a hairline when everyone sleeps. */
function trace(ctx, R, w, d) {
  const { B, th } = ctx, col = R.busy ? th.accent : R.awake ? th.second : th.accent, k = (R.busy ? 1 : R.awake ? 0.5 : 0.13) * (R.busy ? 1 : th.trace), g = glow(ctx, [...mul(col, k), 1]), t = 0.035, y = 0.007;
  B.cells([-w / 2, y, d / 2], [w, 0, 0], [0, 0, -t], 1, 1, col, { glow: g }); B.cells([-w / 2, y, -d / 2 + t], [w, 0, 0], [0, 0, -t], 1, 1, col, { glow: g });
  B.cells([-w / 2, y, d / 2], [t, 0, 0], [0, 0, -d], 1, 1, col, { glow: g }); B.cells([w / 2 - t, y, d / 2], [t, 0, 0], [0, 0, -d], 1, 1, col, { glow: g });
  if (R.busy) for (const [x, z] of [[-w / 2, 0], [w / 2, 0], [0, d / 2], [0, -d / 2]]) lamp(ctx, x, 0.15, z, 0.34, 1.2, { col });
}
function rug(ctx, R, tint, h) {
  ctx.B.model(h % 2 ? "rugRounded" : "rugRectangle", { z: 0.45, s: [1.25, 1, 1.7], tint: { carpet: tint, carpetDarker: mul(tint, 0.7), carpetWhite: mul(CREAM, 0.8), carpetBlue: mul(tint, 1.2) } });
}
/* The desks along both side walls: one station per person, decor (or a bare desk) where nobody sits; tags adds a small label per person. */
function places(ctx, R, list, tint, w, d, slots, tags, bare) {
  const B = ctx.B, h = hash(R.id);
  for (let k = 0; k < slots; k++) {
    const side = k % 2 ? 1 : -1, wk = list[k];
    B.push({ x: side * (w / 2 - 0.3), z: -d / 2 + 1.15 + (k >> 1) * 0.82, r: -side * Math.PI / 2 });
    if (wk) { const p = station(ctx, wk, mul(tint, 0.85), false); if (tags) ctx.labels.push({ id: wk.id, pos: [p.x, p.y + 0.6, p.z], near: 78 }); }
    else if (bare) B.model("desk", { z: 0.37, r: Math.PI });
    else DECOR[(h + k * 3) % DECOR.length](ctx, R.busy > 0);
    B.pop();
  }
}
/* The furnished size of a room, its desk count, its tint and its hash, from its cell of the plan. */
function frame(ctx, R, k) {
  const c = ctx.plan.cells[R.id], h = hash(R.id);
  return { w: c.w, d: c.d, slots: c.slots, h, tint: mul(ctx.th.tints[Math.max(0, R.team) % ctx.th.tints.length], k(h)) };
}

/* A seat's room: the seat at the lead desk under the room's name board, its workers at the side desks. */
export function seatRoom(ctx, R) {
  const { B } = ctx, { w, d, slots, h, tint } = frame(ctx, R, (h) => 0.86 + (h % 5) * 0.07), lead = R.people[0];
  trace(ctx, R, w, d); rug(ctx, R, tint, h);
  B.push({ z: -d / 2 + 0.5 });
  const p = station(ctx, lead, tint, true);
  B.pop();
  places(ctx, R, R.people.slice(1), tint, w, d, slots, false);
  B.push({ z: d / 2 - 0.75 }); LOUNGE[h % LOUNGE.length](B, mul(tint, 0.9)); B.pop();
  const lit = R.awake || ctx.night;
  B.model("lampRoundFloor", { x: -0.8, z: -d / 2 + 0.6, glow: { lamp: lit ? glow(ctx, [1, 0.82, 0.5, 1]) : 0 } });
  if (lit) lamp(ctx, -0.8, 0.95, -d / 2 + 0.7, ctx.night ? 0.8 : 0.5, 1.3, { halo: 0.3 });
  B.push({ z: -d / 2 + 0.15 }); board(ctx, R, { id: R.sign, name: R.info.name, y: 0.8, h: 1.85 }); B.pop();
  ctx.labels.push({ id: R.id, pos: [p.x, p.y + 0.82, p.z] });
}

/* A team room of staff: the team's name board at the back, one desk per member. */
export function teamRoom(ctx, R) {
  const { B } = ctx, { w, d, slots, h, tint } = frame(ctx, R, () => 0.9);
  trace(ctx, R, w, d); rug(ctx, R, tint, h);
  B.push({ z: -d / 2 + 0.3 }); board(ctx, R, { id: R.sign, name: R.info.name }); B.pop();
  places(ctx, R, R.people, tint, w, d, slots, true);
  B.push({ z: d / 2 - 0.75 }); LOUNGE[(h + 1) % LOUNGE.length](B, mul(tint, 0.9)); B.pop();
}

/* The desk pool: one desk per agent the CEO runs himself (bare when free), no lead desk, its name board at the back. */
export function pool(ctx, R) {
  const { B } = ctx, { w, d, slots, h, tint } = frame(ctx, R, () => 0.9);
  trace(ctx, R, w, d); rug(ctx, R, tint, h);
  B.push({ z: -d / 2 + 0.3 }); board(ctx, R, { id: R.sign, name: R.info.name }); B.pop();
  places(ctx, R, R.people, tint, w, d, slots, true, true);
}

/* The CEO's place: a neon ring on the deck, a wide desk under three holo screens, the name board and the Conductor standing on the floor with the model's motes, lamp and failing agent. */
export function ceoSpot(ctx, R) {
  const { B, th } = ctx, on = R.pose === "working" || R.pose === "talking", col = th.state[R.pose] || th.accent, k = on ? 1 : R.pose === "sleep" ? 0.15 : 0.5;
  B.model("rugRound", { s: [2.6, 1, 2.6], tint: { carpet: [0.1, 0.13, 0.26], carpetDarker: [0.5, 0.28, 0.2], carpetWhite: mul(CREAM, 0.8) } });
  B.ring(0, 0.012, 0, 1.2, 1.24, 0, Math.PI * 2, 40, 1, col, glow(ctx, [...mul(col, k), 1]));
  B.model("desk", { x: -0.37, z: -0.75 }); B.model("desk", { x: 0.37, z: -0.75 });
  B.model("books", { x: -0.5, y: 0.384, z: -0.75 }); B.model("computerKeyboard", { x: 0, y: 0.384, z: -0.68 });
  for (const s of [-1, 0, 1]) { B.push({ x: s * 0.5, y: 0.46, z: -0.86 + Math.abs(s) * 0.1, r: -s * 0.5 }); holo(ctx, [-0.22, 0, 0], [0.44, 0, 0], [0, 0.34, 0], s ? th.second : col, on ? 1 : 0.35); B.pop(); }
  grow(ctx, 1.25, -0.6, -0.5, { w: 0.6 });
  B.push({ x: -1.35, z: -0.3, r: 0.8 }); board(ctx, { busy: on ? 1 : 0, awake: R.pose !== "sleep" }, { id: "sign-" + R.id, who: R.id, name: R.rank || R.name, w: 0.9, sh: 0.6, y: 0.35, h: 1.05 }); B.pop();
  B.model("lampRoundFloor", { x: -0.9, z: 0.75, glow: { lamp: glow(ctx, [1, 0.82, 0.5, 1]) } }); lamp(ctx, -0.9, 0.95, 0.85, ctx.night ? 0.8 : 0.5, 1.3, { halo: 0.3 });
  lamp(ctx, 0, 0.7, -0.6, on ? 0.8 : 0.3, 0.9, { col, halo: on ? 0.4 : 0.15 });
  const p = B.at(0, 0, 0), L = R.live || { motes: [], lamp: "ok", failing: null };
  ctx.actors.push({ id: R.id, role: "ceo", pose: R.pose, x: p.x, y: p.y, z: p.z, yaw: p.r, scale: 0.4, live: { motes: L.motes.map((id) => ({ id, hue: genome(id).hue })), lamp: L.lamp, failing: L.failing } });
  ctx.labels.push({ id: R.id, pos: [p.x, p.y + 1.12, p.z] });
}
