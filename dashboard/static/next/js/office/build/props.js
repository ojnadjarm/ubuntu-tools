/* Cyberpunk props built by code on the batch: neon tubes, server racks, grow beds, cables, and the light quads (city windows, dot signs, holo screens). */
import { hash } from "../../familiars/genome.js";
import { GREEN, AMBER } from "../theme.js";

/* The kinds of light quad a chunk may carry. */
export const WINDOW = 0, DOT = 2, HOLO = 3;
export const mul = (c, k) => c.map((v) => v * k);
export const tone = (c, i, j, k = 0.07) => { const h = Math.sin(i * 127.1 + j * 311.7) * 43758.5453, f = 1 - k + 2 * k * (h - Math.floor(h)); return [c[0] * f, c[1] * f, c[2] * f]; };
/* The index of an emissive colour [r, g, b, mix]; equal colours share one. */
export const glow = (ctx, rgba) => (ctx.glowIx[rgba.join()] ??= ctx.glows.push(rgba) - 1);
export function lamp(ctx, x, y, z, i, r, { col = AMBER, halo = 0 } = {}) { const p = ctx.B.at(x, y, z); ctx.lamps.push({ x: p.x, y: p.y, z: p.z, col, i, r, halo }); }

/* A light quad from o along u and v in the current frame. */
export function quad(ctx, kind, o, u, v, { col, k, two = false, uv } = {}) {
  const B = ctx.B, at = (a, b) => { const p = B.at(o[0] + u[0] * a + v[0] * b, o[1] + u[1] * a + v[1] * b, o[2] + u[2] * a + v[2] * b); return [p.x, p.y, p.z]; };
  ctx.quads.push({ kind, p: [at(0, 0), at(1, 0), at(1, 1), at(0, 1)], uv: uv || [Math.hypot(...u), Math.hypot(...v)], k, col, two });
}

/* A neon tube: an emissive box, its halos and the light it throws on the room. */
export function neon(ctx, x, y, z, w, h, d, col, { i = 0.45, r = 1.1, halo = 0.3, rot = 0, k = 1 } = {}) {
  const B = ctx.B, long = Math.max(w, d), n = i > 0 ? Math.max(1, Math.round(long / 1.1)) : 0;
  B.box(x, y, z, w, h, d, col, { r: rot, glow: glow(ctx, [...mul(col, k), 1]) });
  B.push({ x, y, z, r: rot });
  for (let j = 0; j < n; j++) { const f = ((j + 0.5) / n - 0.5) * long; lamp(ctx, w >= d ? f : 0, h / 2, w >= d ? 0 : f, i, r, { col, halo }); }
  B.pop();
}

/* A server rack, front on +z; live racks blink status rows. */
export function rack(ctx, x, z, r, { live = true, seed = "r", h = 1.3 } = {}) {
  const B = ctx.B, rows = Math.round((h - 0.2) / 0.12);
  B.push({ x, z, r });
  B.box(0, 0, 0, 0.5, h, 0.42, [0.2, 0.23, 0.24], { foot: true });
  B.cells([-0.22, 0.08, 0.212], [0.44, 0, 0], [0, h - 0.14, 0], 1, 1, [0.06, 0.07, 0.08]);
  for (let k = 0; k < rows; k++) {
    const q = hash(seed + x.toFixed(1) + z.toFixed(1) + k), col = q % 6 === 0 ? AMBER : GREEN, w = 0.05 + ((q >>> 3) % 4) * 0.05, x0 = -0.19 + ((q >>> 6) % 4) * 0.06, on = live && q % 5 > 0;
    B.cells([x0, 0.13 + k * 0.12, 0.215], [w, 0, 0], [0, 0.03, 0], 1, 1, col, { glow: glow(ctx, [...mul(col, on ? 1 : 0.16), 1]) });
  }
  if (live) lamp(ctx, 0, h * 0.55, 0.5, 0.2, 0.8, { col: GREEN, halo: 0.14 });
  B.pop();
}

/* A planter under a grow light. */
export function grow(ctx, x, z, r, { w = 1, on = true } = {}) {
  const B = ctx.B, th = ctx.th, n = Math.max(2, Math.round(w / 0.3));
  B.push({ x, z, r });
  B.box(0, 0, 0, w, 0.2, 0.3, [0.2, 0.22, 0.23], { foot: true });
  for (let k = 0; k < n; k++) B.model(k % 3 === 1 ? "pottedPlant" : "plantSmall" + (1 + (k % 3)), { x: (k + 0.5) / n * w - w / 2, y: k % 3 === 1 ? 0.12 : 0.2, z: 0, s: k % 3 === 1 ? 1.1 : 2.1, r: k, foot: false });
  for (const s of [-1, 1]) B.box(s * (w / 2 - 0.02), 0.2, -0.13, 0.025, 0.86, 0.025, th.frame);
  neon(ctx, 0, 1.04, -0.03, w, 0.035, 0.07, th.grow, { i: on ? 0.42 : 0.12, r: 0.8, halo: on ? 0.3 : 0.1, k: on ? 1 : 0.4 });
  B.pop();
}

/* A cable lying on the floor through the given [x, z] points. */
export function cable(ctx, pts, col = [0.07, 0.08, 0.09]) {
  for (let k = 1; k < pts.length; k++) {
    const [ax, az] = pts[k - 1], [bx, bz] = pts[k], dx = bx - ax, dz = bz - az;
    ctx.B.box((ax + bx) / 2, 0, (az + bz) / 2, Math.hypot(dx, dz) + 0.03, 0.014, 0.035, col, { r: Math.atan2(-dz, dx) });
  }
}

/* A big city window in the current wall frame, centred on x with its sill at y. */
export function pane(ctx, x, y, w, h) {
  const B = ctx.B, th = ctx.th, t = 0.045, bar = (x0, y0, ww, hh) => B.cells([x0, y0, 0.03], [ww, 0, 0], [0, hh, 0], 1, 1, th.frame);
  quad(ctx, WINDOW, [x - w / 2, y, 0.016], [w, 0, 0], [0, h, 0], { k: [hash("w" + ctx.quads.length) % 97, h, 0] });
  bar(x - w / 2 - t, y - t, w + 2 * t, t); bar(x - w / 2 - t, y + h, w + 2 * t, t); bar(x - w / 2 - t, y, t, h); bar(x + w / 2, y, t, h);
  for (let k = 1, n = Math.round(w / 0.62); k < n; k++) bar(x - w / 2 + (w * k) / n - t / 3, y, t / 1.5, h);
  bar(x - w / 2, y + h * 0.66, w, t / 1.5);
  B.box(x, y - t - 0.04, 0.05, w + 0.2, 0.04, 0.1, th.frame);
  lamp(ctx, x, y + h * 0.35, 0.8, ctx.night ? 0.2 : 0.26, 1.3, { col: mul(th.city, 1.7) });
}

/* A holo screen floating from o along u and v, seen from both sides. */
export function holo(ctx, o, u, v, col, k = 1) { quad(ctx, HOLO, o, u, v, { col, k: [hash("h" + ctx.quads.length) % 53, k, 0], two: true, uv: [1, 1] }); }

/* A dot-matrix neon sign h tall, centred on o, reading along u with its top towards v (unit vectors); ctx.ink(text) gives {w, h, runs: [[x0, x1, y]]}. */
export function sign(ctx, text, o, u, v, h, col, { i = 0.3, halo = 0.22 } = {}) {
  const t = ctx.ink(text), s = h / t.h, w = t.w * s, x0 = -w / 2;
  for (const [a, b, y] of t.runs) {
    const p = [0, 1, 2].map((n) => o[n] + u[n] * (x0 + a * s) + v[n] * (h / 2 - (y + 0.92) * s));
    quad(ctx, DOT, p, mul(u, (b - a) * s), mul(v, s * 0.84), { col, uv: [1, 1] });
  }
  if (i > 0) for (let k = 0, n = Math.max(1, Math.round(w / 0.9)); k < n; k++) { const f = x0 + ((k + 0.5) / n) * w; lamp(ctx, o[0] + u[0] * f + 0.0, o[1] + u[1] * f + 0.12, o[2] + u[2] * f, i, 0.9, { col, halo }); }
  return w;
}
