/* The Familiar body: a soft toon creature with limbs, a face and its role worn as gear; build(g) gives the merged mesh and update(t, w) acts out the pose weights. */
import { G, capsule, cyl, torus, rig } from "./geo.js";
import { hsl } from "../../familiars/genome.js";

export const BONES = 28, PITCH = 0.4;
const WHITE = [0.96, 1, 0.97], INKC = [0.03, 0.08, 0.06], SLATE = [0.2, 0.25, 0.28], MINT = [0.3, 1, 0.63];
/* Vertex flags: 1 dims and tints with the pose, 2 flickers as a screen, 3 takes the pad colour. */
const toon = (col, { shade = col.map((c, i) => c * [0.42, 0.5, 0.58][i]), rim = 1, em = 0, flag = 0 } = {}) => ({ col, shade, rim, em, flag });
const lit = (col, flag = 0) => ({ col, shade: col, rim: 0, em: 0, flag });

export function build(g) {
  const R = rig(BONES), { group, part: add } = R, root = group(null);
  const base = hsl(g.hue, 0.7, 0.6), dark = hsl(g.hue + 14, 0.6, 0.34), lite = hsl(g.hue - 8, 0.85, 0.82);
  const mBody = toon(base, { shade: dark, flag: 1 }), mLite = toon(lite, { shade: base, flag: 1 }), mDark = toon(dark, { flag: 1 }), mWhite = toon(WHITE, { shade: [0.66, 0.8, 0.86], flag: 1 });
  const mInk = toon(INKC, { rim: 0.35 }), mPink = toon([1, 0.62, 0.77], { shade: [0.85, 0.4, 0.6], rim: 0, flag: 1 }), mSet = toon(SLATE, { shade: [0.07, 0.1, 0.12] });
  const W = g.wide, HT = 0.44 * g.tall;

  add(root, torus(0.62, 0.022, 4, 36), lit([1, 1, 1], 3), { r: [Math.PI / 2, 0, 0], p: [0, 0.01, 0] });
  add(root, G.lo, mDark, { p: [-0.19 * W, 0.07, 0.07], s: [0.15, 0.075, 0.21], outline: 1 });
  add(root, G.lo, mDark, { p: [0.19 * W, 0.07, 0.07], s: [0.15, 0.075, 0.21], outline: 1 });
  const hip = group(root, [0, 0.42, 0]);
  add(hip, G.sph, mBody, { s: [0.4 * W, 0.36, 0.36 * W], outline: 1 });
  add(hip, G.lo, mLite, { p: [0, -0.04, 0.15 * W], s: [0.27 * W, 0.25, 0.24] });
  if (g.tail === 0) add(hip, G.lo, mLite, { p: [0, -0.12, -0.36 * W], s: 0.13, outline: 1 });
  if (g.tail === 1) add(hip, G.cone, mDark, { p: [0, 0, -0.42 * W], s: [0.09, 0.4, 0.09], r: [-0.9, 0, 0], outline: 1 });

  const arms = [-1, 1].map((d) => {
    const a = group(hip, [d * 0.35 * W, 0.14, 0.02]);
    add(a, capsule(0.075, 0.2), mBody, { p: [0, -0.15, 0], outline: 1 });
    add(a, G.lo, mLite, { p: [0, -0.31, 0], s: 0.092, outline: 1 });
    return a;
  });

  const head = group(hip, [0, 0.3, 0]), HC = 0.36, A = 0.5 * W, C = 0.46;
  add(head, G.sph, mBody, { p: [0, HC, 0], s: [A, HT, C], outline: 1 });
  const surf = (x, y) => C * Math.sqrt(Math.max(0.05, 1 - (x / A) ** 2 - (y / HT) ** 2));
  if (g.spots) [[-0.3, 0.2], [0.34, 0.12], [0.12, 0.3]].forEach(([x, y], i) => add(head, G.lo, mLite, { p: [x * W, HC + y * g.tall, -surf(x * W, y * g.tall) * 0.9], s: [0.09 - i * 0.015, 0.09 - i * 0.015, 0.04] }));

  const er = g.eyes === 1 ? 0.16 : g.eyes === 2 ? 0.118 : 0.09, ey = 0.03;
  const exs = g.eyes === 1 ? [0] : g.eyes === 2 ? [-0.2 * W, 0.2 * W] : [-0.27 * W, 0, 0.27 * W];
  const eyes = exs.map((x) => {
    const e = group(head, [x, HC + ey, surf(x, ey) - er * 0.25]); e.r[1] = x * 1.3;
    add(e, G.lo, mWhite, { s: [er, er, er * 0.5], outline: 1 });
    const pupil = add(e, G.lo, mInk, { p: [0, -er * 0.08, er * 0.36], s: [er * 0.62, er * 0.62, er * 0.3], bone: 1 });
    add(pupil, G.lo, toon(WHITE, { rim: 0 }), { p: [0.38, 0.42, 0.9], s: 0.3 });
    const brow = add(head, capsule(0.016, er * 1.3, 5), mInk, { p: [x, HC + ey + er * 1.35, surf(x, ey + er) + 0.01], r: [0, 0, Math.PI / 2], bone: 1 });
    return { e, pupil, brow, x };
  });
  const my = -0.19 * g.tall, mz = surf(0, my);
  const smile = add(head, torus(0.07, 0.014, 4, 10, Math.PI), mInk, { p: [0, HC + my + 0.04, mz + 0.005], r: [0, 0, Math.PI], bone: 1 });
  const mouth = add(head, G.lo, mInk, { p: [0, HC + my, mz - 0.01], s: [0.06, 0.05, 0.03], bone: 1 });
  if (g.mouth === 3) add(head, G.cone4, mWhite, { p: [0.04, HC + my + 0.015, mz + 0.01], s: [0.016, 0.045, 0.016], r: [Math.PI, 0, 0] });
  [-1, 1].forEach((d) => add(head, G.lo, mPink, { p: [d * 0.31 * W, HC - 0.1, surf(0.31 * W, -0.1) - 0.02], s: [0.07, 0.045, 0.03], r: [0, d * 0.6, 0] }));

  const top = HC + HT, ears = [];
  [-1, 1].forEach((d) => {
    const e = group(head, [d * 0.27 * W, top - 0.07, 0]);
    if (g.topper === 0) { add(e, G.cone, mBody, { p: [d * 0.04, 0.12, 0], s: [0.14, 0.3, 0.1], r: [0, 0, -d * 0.3], outline: 1 }); add(e, G.cone, mPink, { p: [d * 0.04, 0.1, 0.035], s: [0.08, 0.2, 0.06], r: [0, 0, -d * 0.3] }); }
    if (g.topper === 1) add(e, G.lo, mDark, { p: [d * 0.08, 0.03, 0], s: [0.15, 0.15, 0.08], outline: 1 });
    if (g.topper === 2) { add(e, capsule(0.07, 0.34), mBody, { p: [0, 0.22, 0], outline: 1 }); add(e, capsule(0.035, 0.28), mPink, { p: [0, 0.22, 0.045] }); }
    if (g.topper === 3) add(e, G.cone, toon([1, 0.93, 0.75], { shade: [0.8, 0.6, 0.4] }), { p: [d * 0.05, 0.1, 0], s: [0.07, 0.3, 0.07], r: [0, 0, -d * 0.5], outline: 1 });
    if (g.topper === 4) { add(e, capsule(0.014, 0.22, 5), mDark, { p: [d * 0.03, 0.13, 0], r: [0, 0, -d * 0.3] }); add(e, G.lo, mLite, { p: [d * 0.075, 0.28, 0], s: 0.055, outline: 1 }); }
    e.d = d; ears.push(e);
  });

  if (g.role === "po") {
    add(head, torus(A + 0.02, 0.028, 5, 16, Math.PI), mSet, { p: [0, HC, 0] });
    [-1, 1].forEach((d) => add(head, G.lo, mSet, { p: [d * (A + 0.01), HC - 0.02, 0], s: [0.05, 0.1, 0.1], outline: 1 }));
    add(head, capsule(0.012, 0.3, 5), mSet, { p: [-A * 0.82, HC - 0.17, 0.2], r: [1.1, 0, -0.35] });
    add(head, G.lo, toon(MINT, { em: 0.4 }), { p: [-A * 0.62, HC - 0.24, 0.35], s: 0.035 });
    const tab = group(arms[1], [0.02, -0.36, 0.06], true);
    add(tab, G.box, mSet, { s: [0.2, 0.27, 0.025], outline: 1 }); add(tab, G.box, lit(MINT), { p: [0, 0, 0.014], s: [0.16, 0.22, 0.004] });
  }
  if (g.role === "worker") {
    const mHat = toon([1, 0.8, 0.2], { shade: [0.8, 0.45, 0.05] });
    add(head, G.dome, mHat, { p: [0, top - 0.07, -0.05], s: [A * 0.56, 0.17, C * 0.56], outline: 1 });
    add(head, cyl(1, 1, 0.03, 14), mHat, { p: [0, top - 0.065, 0.0], s: [A * 0.66, 1, C * 0.68], outline: 1 });
  }
  if (g.role === "crew") add(hip, torus(0.25 * W, 0.06, 6, 14), toon([1, 0.45, 0.35], { shade: [0.6, 0.15, 0.2] }), { p: [0, 0.27, 0], r: [Math.PI / 2, 0, 0], outline: 1 });

  const desk = group(root, [0, 0.3, 0.52 * W + 0.1]);
  add(desk, G.box, toon(SLATE), { s: [0.42, 0.025, 0.26], outline: 1 });
  add(desk, G.box, toon(SLATE), { p: [0, 0.14, 0.15], s: [0.42, 0.28, 0.02], r: [0.3, 0, 0], outline: 1 });
  add(desk, G.box, lit(MINT, 2), { p: [0, 0.14, 0.137], s: [0.36, 0.22, 0.005], r: [0.3, 0, 0] });
  const dots = [0, 1, 2].map((i) => add(root, G.lo, toon(WHITE, { shade: [0.66, 0.8, 0.86] }), { p: [0.42 + i * 0.13, 1.42 * g.tall + 0.1, 0.1], s: 0.045, outline: 1, bone: 1 }));
  const bang = group(root, [0, 1.72 * g.tall + 0.2, 0]), RED = toon([1, 0.35, 0.32], { shade: [0.75, 0.15, 0.2], em: 0.25 });
  add(bang, capsule(0.045, 0.16, 6), RED, { p: [0, 0.07, 0], outline: 1 }); add(bang, G.lo, RED, { p: [0, -0.14, 0], s: 0.05, outline: 1 });
  const zz = group(root, [0.5, 1.25, 0.1]), ZC = lit([0.62, 0.84, 0.75]);
  [[0, 1], [0.17, 0.62]].forEach(([o, k]) => {
    const z = group(zz, [o, o * 1.1, 0], true); z.s = [k, k, k];
    add(z, G.box, ZC, { p: [0, 0.08, 0], s: [0.17, 0.035, 0.03], outline: 1 }); add(z, G.box, ZC, { p: [0, -0.08, 0], s: [0.17, 0.035, 0.03], outline: 1 });
    add(z, G.box, ZC, { s: [0.2, 0.035, 0.03], r: [0, 0, 0.82], outline: 1 });
  });

  const show = (n, k) => { n.vis = k > 0.01; n.s[0] = n.s[1] = n.s[2] = k; };
  /* Acts out pose weights w (working, idle, talking, error, sleep; they sum to 1) at time t; returns the dim, the error tint and the screen flicker. */
  function update(t, w) {
    const ph = g.phase, act = 1 - w.sleep, breathe = Math.sin(t * 2 + ph) * 0.022 * act + w.sleep * 0.01;
    const type = Math.sin(t * 17 + ph), env = (0.5 + 0.5 * Math.sin(t * 13 + ph)) * (0.55 + 0.45 * Math.sin(t * 3.1 + ph));
    hip.p[1] = 0.42 - 0.1 * w.sleep + w.working * Math.abs(type) * 0.012 + w.talking * Math.sin(t * 6 + ph) * 0.018 + w.error * Math.abs(Math.sin(t * 9)) * 0.04;
    hip.s[0] = hip.s[2] = 1 + breathe; hip.s[1] = 1 - breathe * 1.4 - 0.1 * w.sleep;
    hip.r[0] = 0.16 * w.working + 0.22 * w.sleep; hip.r[1] = w.talking * Math.sin(t * 1.7 + ph) * 0.2; hip.r[2] = w.error * Math.sin(t * 36) * 0.06 + w.idle * Math.sin(t * 0.8 + ph) * 0.05;
    head.r[0] = -0.2 * act + w.working * (0.24 + Math.sin(t * 4.4 + ph) * 0.03) + w.sleep * 0.42 + w.talking * Math.sin(t * 7 + ph) * 0.07 - w.error * 0.16;
    head.r[1] = w.idle * Math.sin(t * 0.6 + ph) * 0.4 + w.talking * Math.sin(t * 2.1 + ph) * 0.22 + w.working * Math.sin(t * 1.3 + ph) * 0.12;
    head.r[2] = w.sleep * 0.28 + w.idle * Math.sin(t * 0.9 + ph) * 0.07 + w.error * Math.sin(t * 31) * 0.05;
    const bt = (t * 0.31 + g.blink) % 1, blink = bt > 0.95 ? Math.abs(bt - 0.975) / 0.025 : 1, open = Math.max(0.07, blink * act + 0.07 * w.sleep) * (1 + 0.15 * w.error);
    for (const e of eyes) {
      e.e.s[1] = open;
      e.pupil.s[0] = e.pupil.s[1] = er * 0.62 * (1 - 0.4 * w.error);
      e.pupil.p[0] = (w.idle * Math.sin(t * 0.6 + ph) * 0.25 + w.error * Math.sin(t * 23) * 0.2) * er; e.pupil.p[1] = -er * (0.08 + 0.3 * w.working);
      e.brow.vis = w.error > 0.05; e.brow.r[2] = Math.PI / 2 - Math.sign(e.x || 1) * 0.45 * w.error;
    }
    const talk = w.talking * env;
    mouth.s[0] = 0.045 + talk * 0.03 + w.error * 0.02; mouth.s[1] = 0.006 + talk * 0.075 + w.error * 0.05; mouth.vis = w.talking + w.error > 0.05;
    smile.vis = !mouth.vis;
    arms.forEach((a, i) => {
      const d = i ? 1 : -1;
      a.r[0] = -w.working * (1.15 + (i ? type : -type) * 0.2) - w.talking * (i ? 0.5 + Math.sin(t * 5 + ph) * 0.3 : 0.1) - w.sleep * 0.15;
      a.r[2] = d * (0.22 + w.idle * Math.sin(t * 2 + ph) * 0.05 + w.talking * (i ? 0.9 + Math.sin(t * 3.3 + ph) * 0.4 : 0.1) + w.error * (2.5 + Math.sin(t * 20 + i * 2) * 0.3) - w.working * 0.3);
    });
    ears.forEach((e) => { e.r[2] = -e.d * (Math.sin(t * 2.3 + ph) * 0.06 * act + 0.5 * w.sleep + 0.25 * w.error * Math.sin(t * 30)); e.r[0] = -0.25 * w.sleep; });
    show(desk, w.working);
    dots.forEach((d, i) => { show(d, w.talking > 0.02 ? 0.075 * w.talking * (0.6 + 0.4 * Math.sin(t * 7 - i * 1.1)) : 0); d.p[1] = 1.42 * g.tall + 0.1 + Math.max(0, Math.sin(t * 7 - i * 1.1)) * 0.07; });
    show(bang, w.error * (1 + 0.12 * Math.sin(t * 12))); show(zz, w.sleep);
    return { dim: 1 - 0.45 * w.sleep, tint: 0.3 * w.error * (0.6 + 0.4 * Math.sin(t * 10)), screen: 0.75 + 0.25 * Math.sin(t * 9 + ph) };
  }
  return { mesh: R.mesh(), bones: R.bones.length, pose: R.pose, update };
}
