/* The Conductor, the orchestrator's own Familiar: long coat, ear tufts, spark-halo, ledger and tail lamp; build(g) gives the merged mesh and update(t, w, live) acts out the pose weights and the live state. */
import { G, capsule, cyl, torus, sphere, rig, compose, mul } from "./geo.js";
import { attach, aim, MOTE_BONES } from "./ceo-motes.js";

export const BONES = 24 + MOTE_BONES;
const NAVY = [0.19, 0.24, 0.5], NAVY_D = [0.085, 0.105, 0.23], CORAL = [0.851, 0.467, 0.341], CORAL_D = [0.6, 0.24, 0.2], CREAM = [0.953, 0.914, 0.863], CREAM_D = [0.76, 0.62, 0.6];
const GOLD = [0.886, 0.69, 0.29], GOLD_D = [0.62, 0.4, 0.12], WHITE = [1, 0.98, 0.95], INKC = [0.03, 0.04, 0.09], MINT = [0.3, 1, 0.63];
const HOME = [-0.47, 0.6, 0.34], CENTRE = [0, 2.2, 0], COLLAR = [0, 1.27, 0.3], ALARM = [-1.0, 2.3, 0.2], HAND = [0, -0.44, 0];
const toon = (col, shade, { rim = 1, em = 0, flag = 1 } = {}) => ({ col, shade, rim, em, flag });
const lit = (col, flag = 0) => ({ col, shade: col, rim: 0, em: 0, flag });
const TAU = Math.PI * 2, A0 = new Float32Array(16), A1 = new Float32Array(16), A2 = new Float32Array(16);

/* Point v of the last node's space in root space, down a chain of bones. */
function reach(chain, v) {
  let M = compose(A0, chain[0].p, chain[0].r, chain[0].s), T = A1;
  for (let i = 1; i < chain.length; i++) { mul(T, M, compose(A2, chain[i].p, chain[i].r, chain[i].s)); const o = M; M = T; T = o; }
  return [M[0] * v[0] + M[4] * v[1] + M[8] * v[2] + M[12], M[1] * v[0] + M[5] * v[1] + M[9] * v[2] + M[13], M[2] * v[0] + M[6] * v[1] + M[10] * v[2] + M[14]];
}

export function build(g = {}) {
  const R = rig(BONES), group = R.group, root = group(null), ph = g.phase || 0;
  let nv = 0;
  const add = (parent, geo, m, o) => { nv += geo.P.length / 3; return R.part(parent, geo, m, o); };
  const mNavy = toon(NAVY, NAVY_D), mCoral = toon(CORAL, CORAL_D), mCream = toon(CREAM, CREAM_D), mGold = toon(GOLD, GOLD_D), mWhite = toon(WHITE, [0.8, 0.74, 0.76]);
  const mInk = toon(INKC, INKC, { rim: 0.3, flag: 0 }), mBoot = toon([0.09, 0.1, 0.2], [0.04, 0.045, 0.1]), mGlow = toon(CORAL, CORAL, { rim: 0, em: 0.3 });

  add(root, torus(0.76, 0.022, 4, 40), lit([1, 1, 1], 3), { r: [Math.PI / 2, 0, 0], p: [0, 0.01, 0] });
  add(root, G.lo, lit([0.015, 0.03, 0.045]), { p: [0, 0.012, 0], s: [0.66, 0.01, 0.52] });
  [-1, 1].forEach((d) => add(root, G.lo, mBoot, { p: [d * 0.19, 0.075, 0.42], s: [0.15, 0.085, 0.21], outline: 1 }));

  const hip = group(root, [0, 0.5, 0]), GAP = 0.36;
  add(hip, cyl(0.33, 0.66, 0.86, 20, true, GAP, TAU - 2 * GAP), mNavy, { outline: 1 });
  add(hip, cyl(0.31, 0.63, 0.85, 16, true), mCoral);
  [0.98, -0.98, 1.95, -1.95, Math.PI].forEach((a) => add(hip, G.lo, mNavy, { p: [Math.sin(a) * 0.6, -0.38, Math.cos(a) * 0.6], s: [0.18, 0.1, 0.18], outline: 1 }));
  add(hip, G.sph, mNavy, { p: [0, 0.42, 0], s: [0.38, 0.36, 0.34], outline: 1 });
  [0.4, 0.24].forEach((y, i) => add(hip, G.lo, mGold, { p: [0, y, 0.335 + i * 0.03], s: 0.032 }));
  add(hip, cyl(0.43, 0.26, 0.3, 14, true, 0.5, TAU - 1), mNavy, { p: [0, 0.79, -0.02], outline: 1 });
  add(hip, cyl(0.41, 0.245, 0.29, 14, true, 0.5, TAU - 1), mCoral, { p: [0, 0.79, -0.02] });
  add(hip, sphere(4, 2), mGold, { p: [0, 0.71, 0.3], s: [0.085, 0.085, 0.03], outline: 1 });
  add(hip, sphere(4, 2), toon(WHITE, GOLD), { p: [0, 0.71, 0.315], s: [0.045, 0.045, 0.03], r: [0, 0, Math.PI / 4] });

  add(hip, capsule(0.012, 0.12, 5), mGold, { p: [HOME[0] + 0.02, HOME[1] - 0.5 + 0.17, HOME[2] - 0.03] });
  const lantern = group(hip, [HOME[0], HOME[1] - 0.5, HOME[2]], true);
  add(lantern, G.cone, mGold, { p: [0, 0.115, 0], s: [0.085, 0.07, 0.085], outline: 1 });
  add(lantern, cyl(0.07, 0.085, 0.035, 8), mGold, { p: [0, -0.09, 0], outline: 1 });
  add(lantern, G.lo, toon([0.14, 0.3, 0.3], [0.06, 0.14, 0.17]), { s: [0.075, 0.085, 0.075], outline: 1 });
  const ember = add(lantern, G.lo, toon([0.78, 1, 0.86], MINT, { rim: 0, em: 0.25, flag: 0 }), { s: 0.082, bone: 1 });

  const t1 = group(hip, [0.3, -0.12, -0.3]), t2 = group(t1, [0.4, 0, 0]), t3 = group(t2, [0.4, 0, 0]);
  add(t1, G.lo, mNavy, { p: [0.2, 0, 0], s: [0.29, 0.16, 0.16], outline: 1 });
  add(t2, G.lo, mNavy, { p: [0.2, 0, 0], s: [0.31, 0.21, 0.2], outline: 1 });
  add(t3, G.lo, mCream, { p: [0.15, 0, 0], s: [0.25, 0.17, 0.17], outline: 1 });
  add(t3, torus(0.07, 0.022, 5, 10), mGold, { p: [0.37, 0, 0], r: [0, Math.PI / 2, 0], outline: 1 });
  const lampOk = add(t3, G.lo, mGlow, { p: [0.47, 0, 0], s: 0.125, outline: 1, bone: 1 });
  add(lampOk, G.lo, lit([1, 0.9, 0.8]), { p: [-0.3, 0.35, 0.7], s: 0.3 });
  const lampRed = add(t3, G.lo, toon([1, 0.25, 0.22], [1, 0.25, 0.22], { rim: 0, em: 0.3, flag: 0 }), { p: [0.47, 0, 0], s: 0.14, outline: 1, bone: 1 });

  const armR = group(hip, [-0.37, 0.6, 0.02]), fore = group(armR, [0, -0.29, 0]);
  add(armR, capsule(0.088, 0.2), mNavy, { p: [0, -0.14, 0], outline: 1 });
  add(fore, capsule(0.082, 0.16), mNavy, { p: [0, -0.12, 0], outline: 1 });
  add(fore, cyl(0.1, 0.115, 0.075, 10), mCoral, { p: [0, -0.25, 0], outline: 1 });
  add(fore, G.lo, mCream, { p: [0, -0.33, 0], s: [0.09, 0.08, 0.08], outline: 1 });
  [-1, 0, 1].forEach((i) => add(fore, capsule(0.024, 0.075, 5), mCream, { p: [i * 0.05, -0.41 + Math.abs(i) * 0.012, 0], r: [0, 0, i * 0.3], outline: 1 }));

  const armL = group(hip, [0.37, 0.6, 0.02]), elbow = [0.05, -0.3, 0.07], palm = [-0.2, -0.3, 0.33], fv = palm.map((v, i) => v - elbow[i]);
  add(armL, capsule(0.088, 0.2), mNavy, { p: [0.025, -0.15, 0.03], outline: 1 });
  add(armL, capsule(0.082, 0.2), mNavy, { p: elbow.map((v, i) => v + fv[i] * 0.42), r: aim(fv), outline: 1 });
  add(armL, cyl(0.1, 0.115, 0.075, 10), mCoral, { p: elbow.map((v, i) => v + fv[i] * 0.8), r: aim(fv), outline: 1 });
  add(armL, G.lo, mCream, { p: [palm[0] - 0.02, palm[1], palm[2] + 0.03], s: 0.085, outline: 1 });
  const book = group(armL, [-0.33, -0.17, 0.36], true); book.r = [-0.18, -0.12, 0.16];
  add(book, G.box, mGold, { s: [0.27, 0.33, 0.07], outline: 1 });
  add(book, G.box, mCream, { p: [0.012, 0, 0], s: [0.265, 0.3, 0.05] });
  add(book, G.box, mCoral, { p: [0, 0, 0.037], s: [0.17, 0.2, 0.006] });
  add(book, G.box, toon(MINT, [0.1, 0.6, 0.4], { flag: 0 }), { p: [0.07, -0.19, 0.02], s: [0.035, 0.1, 0.01] });

  const head = group(hip, [0, 0.72, 0]), HC = 0.42, A = 0.5, HT = 0.43, C = 0.45, er = 0.125, ey = 0.01;
  const surf = (x, y) => C * Math.sqrt(Math.max(0.05, 1 - (x / A) ** 2 - (y / HT) ** 2));
  add(head, G.sph, mCream, { p: [0, HC, 0], s: [A, HT, C], outline: 1 });
  add(head, G.dome, mNavy, { p: [0, HC + HT * 0.52, -0.03], s: [A * 0.9, HT * 0.53, C * 0.9], outline: 1 });
  add(head, G.cone4, mNavy, { p: [0, HC + HT * 0.5, surf(0, HT * 0.5) - 0.03], s: [0.12, 0.2, 0.05], r: [Math.PI + 0.5, 0, 0] });
  add(head, G.lo, mWhite, { p: [0, HC - 0.17, surf(0, -0.17) - 0.07], s: [0.2, 0.125, 0.1] });
  add(head, G.lo, mCoral, { p: [0, HC - 0.105, surf(0, -0.1) + 0.012], s: [0.036, 0.026, 0.02] });
  [-1, 1].forEach((d) => add(head, G.lo, mCoral, { p: [d * 0.35, HC - 0.13, surf(0.35, -0.13) - 0.015], s: [0.07, 0.03, 0.03], r: [0, d * 0.8, d * 0.4] }));
  const mz = surf(0, -0.19) + 0.028, smile = group(head, [0, HC - 0.165, mz]), mouth = add(head, G.lo, mInk, { p: [0, HC - 0.2, mz - 0.012], s: [0.05, 0.04, 0.025], bone: 1 });
  [-1, 1].forEach((d) => add(smile, torus(0.038, 0.011, 4, 8, Math.PI), mInk, { p: [d * 0.038, 0, 0], r: [0, 0, Math.PI] }));
  const eyes = [-1, 1].map((d) => {
    const x = d * 0.215, e = group(head, [x, HC + ey, surf(x, ey) - er * 0.25]); e.r[1] = x * 1.3;
    add(e, G.lo, mWhite, { s: [er, er, er * 0.5], outline: 1 });
    const iris = add(e, G.lo, mGold, { p: [0, -er * 0.05, er * 0.3], s: [er * 0.72, er * 0.72, er * 0.3], bone: 1 });
    add(iris, G.lo, mInk, { p: [0, 0, 0.5], s: [0.62, 0.62, 0.7] });
    add(iris, G.lo, lit([1, 1, 1]), { p: [0.32, 0.36, 1.05], s: 0.26 });
    const lid = group(e, [0, er * 1.25, er * 0.06]);
    add(lid, G.lo, mCream, { s: [er * 1.18, er * 0.95, er * 0.5] });
    add(lid, capsule(0.011, er * 1.45, 5), mInk, { p: [0, -er * 0.9, er * 0.36], r: [0, 0, Math.PI / 2] });
    return { e, iris, lid, d };
  });
  const tufts = [-1, 1].map((d) => {
    const e = group(head, [d * 0.3, HC + HT * 0.7, -0.03]); e.d = d;
    add(e, G.cone, mNavy, { p: [d * 0.13, 0.3, -0.06], s: [0.16, 0.74, 0.11], r: [-0.3, 0, -d * 0.5], outline: 1 });
    add(e, G.cone, mCoral, { p: [d * 0.12, 0.27, -0.005], s: [0.085, 0.52, 0.06], r: [-0.3, 0, -d * 0.5] });
    return e;
  });
  const HY = HC + HT + 0.3, halo = group(head, [0, HY, 0]), spokes = group(halo, [0, 0, 0]);
  add(halo, torus(0.3, 0.022, 5, 28), mGlow, { r: [Math.PI / 2, 0, 0], outline: 1 });
  for (let i = 0; i < 8; i++) { const a = (i / 8) * TAU; add(spokes, capsule(0.02, 0.085, 5), mGlow, { p: [-Math.sin(a) * 0.4, 0, Math.cos(a) * 0.4], r: [Math.PI / 2, 0, a], outline: 1 }); }

  const motes = attach({ add, group, root, verts: () => nv }, { centre: CENTRE, home: HOME, collar: COLLAR, alarm: ALARM }), mesh = R.mesh();
  const size = (n, k, b = 1) => { n.vis = k > 0.02; n.s[0] = n.s[1] = n.s[2] = k * b; };
  let last = null;

  /* Acts out pose weights w at time t with live = { motes: [{id, hue}], lamp: ok|talking|needs, failing: id }; returns the dim, the error tint and whether mote colours changed. */
  function update(t, w, live = {}) {
    const dt = last == null ? 0.016 : Math.min(0.1, Math.max(0, t - last)), act = 1 - w.sleep, breathe = Math.sin(t * 1.6 + ph) * 0.016 * act + Math.sin(t * 0.9) * 0.02 * w.sleep;
    last = t;
    const recolor = motes.sync(live.motes || [], mesh), beat = Math.sin(t * 1.7 + ph), env = (0.5 + 0.5 * Math.sin(t * 13 + ph)) * (0.55 + 0.45 * Math.sin(t * 3.1 + ph));
    const peek = w.idle * Math.max(0, Math.sin(t * 0.55 + ph)) ** 10, needs = live.lamp ? +(live.lamp === "needs") : w.error, pulse = live.lamp ? +(live.lamp === "talking") : w.talking;

    hip.p[1] = 0.5 - 0.11 * w.sleep + w.talking * Math.sin(t * 5 + ph) * 0.012 + w.error * Math.abs(Math.sin(t * 9)) * 0.025;
    hip.s[0] = hip.s[2] = 1 + breathe + 0.07 * w.sleep; hip.s[1] = 1 - breathe * 1.3 - 0.12 * w.sleep;
    hip.r[0] = 0.15 * w.talking + 0.1 * w.sleep + 0.04 * w.working; hip.r[1] = w.talking * Math.sin(t * 1.4 + ph) * 0.14 + w.working * beat * 0.07;
    hip.r[2] = w.idle * Math.sin(t * 0.7 + ph) * 0.045 + w.error * Math.sin(t * 33) * 0.03 + w.working * beat * 0.025;
    head.r[0] = -0.12 * act + 0.5 * w.sleep + 0.3 * peek + w.talking * Math.sin(t * 6.5 + ph) * 0.05 - 0.14 * w.error - 0.1 * w.working;
    head.r[1] = w.idle * Math.sin(t * 0.5 + ph) * 0.25 * (1 - peek) + 0.3 * peek + w.talking * Math.sin(t * 2 + ph) * 0.16 - 0.22 * w.error;
    head.r[2] = 0.2 * w.sleep + w.idle * Math.sin(t * 0.8 + ph) * 0.05 - 0.1 * w.error + w.working * beat * 0.05;

    armR.r[2] = -(0.2 + 1.8 * w.working + 0.95 * w.talking + 2.2 * w.error - 0.08 * w.sleep) - w.working * beat * 0.3 + w.error * Math.sin(t * 20) * 0.05;
    armR.r[0] = 0.55 * w.idle - 0.95 * w.talking - 0.25 * w.working * Math.cos(t * 1.7 + ph) - 0.2 * w.error;
    fore.r[2] = 0.95 * w.idle - 0.8 * w.working - 0.3 * w.error + 0.3 * w.sleep - w.working * Math.sin(t * 1.7 + ph + 0.9) * 0.35;
    fore.r[0] = -1.1 * w.talking - w.talking * Math.sin(t * 3.3 + ph) * 0.25;
    armL.r[0] = -0.16 * peek - 0.05 * w.talking; armL.r[2] = 0.05 + 0.03 * Math.sin(t * 1.6 + ph) * act;

    const sway = Math.sin(t * 1.3 + ph) * (0.1 * w.idle + 0.06 * w.working + 0.14 * w.talking) + w.error * Math.sin(t * 15) * 0.07;
    t1.r[2] = 0.25 - 0.3 * w.sleep + sway * 0.5; t2.r[2] = 0.8 - 0.25 * w.sleep + sway; t3.r[2] = 0.85 + 0.35 * w.sleep + sway * 1.3;
    t1.r[1] = 0.25 * w.sleep; t2.r[1] = -0.5 * w.sleep; t3.r[1] = -0.7 * w.sleep;
    size(lampOk, (1 - needs) * (1 - 0.35 * w.sleep) * (1 + pulse * 0.22 * Math.sin(t * 2.4)), 0.125);
    size(lampRed, needs * (Math.sin(t * 7) > -0.2 ? 1.12 : 0.55), 0.125);

    const hand = reach([hip, armR, fore], HAND), m = motes.step(t, dt, w, hand, live.failing), look = m.lead || [0, 1.6, 2];
    const lx = Math.max(-1, Math.min(1, look[0] * 0.9)) * (w.working + w.error) + w.idle * Math.sin(t * 0.5 + ph) * 0.5 * (1 - peek) + 0.5 * peek;
    const ly = Math.max(-1, Math.min(1, (look[1] - 1.65) * 1.4)) * (w.working + w.error) - 0.8 * peek;
    const bt = (t * 0.27 + (g.blink || 0)) % 1, blink = bt > 0.955 ? Math.abs(bt - 0.9775) / 0.0225 : 1, open = Math.max(0.07, blink * act + 0.07 * w.sleep);
    for (const e of eyes) {
      e.e.s[1] = open;
      e.iris.p[0] = lx * er * 0.26; e.iris.p[1] = -er * 0.05 + ly * er * 0.2;
      e.iris.s[0] = e.iris.s[1] = er * 0.72 * (1 - 0.3 * w.error);
      e.lid.p[1] = er * (1.25 + 0.38 * w.error + 0.2 * w.talking + 0.12 * w.working - 0.1 * peek); e.lid.r[2] = -e.d * 0.3 * w.error;
    }
    const talk = w.talking * env;
    mouth.s[0] = 0.04 + talk * 0.025 + w.error * 0.015; mouth.s[1] = 0.006 + talk * 0.06 + w.error * 0.035; mouth.vis = w.talking + w.error > 0.05; smile.vis = !mouth.vis;
    tufts.forEach((e) => { e.r[2] = e.d * (0.28 * w.talking + 0.12 * w.working - 0.42 * w.sleep - 0.25 * w.error + Math.sin(t * 2.1 + ph + e.d) * 0.04 * act); e.r[0] = -0.45 * w.sleep + 0.12 * w.talking; });
    halo.p[1] = HY - 0.27 * w.sleep + Math.sin(t * 1.1 + ph) * 0.02 * act;
    halo.r[0] = 0.26 + 0.5 * w.error - 0.2 * w.sleep; halo.r[1] = t * (0.5 + 0.9 * w.working) * act; halo.r[2] = 0.3 * w.error + w.error * Math.sin(t * 19) * 0.04;
    halo.s[0] = halo.s[1] = halo.s[2] = 1 - 0.3 * w.sleep;
    size(spokes, (1 - 0.75 * w.sleep) * (1 + talk * 0.3 + w.working * 0.06 * Math.sin(t * 3.4)));
    size(ember, 0.55 + 0.6 * Math.max(w.sleep, m.out ? 0 : 1) * (0.9 + 0.1 * Math.sin(t * 2.2)), 0.082);
    return { dim: 1 - 0.42 * w.sleep, tint: 0.22 * w.error * (0.6 + 0.4 * Math.sin(t * 10)), screen: 1, recolor };
  }
  return { mesh, bones: R.bones.length, pose: R.pose, update };
}
