/* The Conductor's motes: one glowing sphere per running agent on two tilted rings, a mint thread from the hand to each, a red one for the failing agent and the flash of a hand-back. */
import { G, cyl, sphere } from "./geo.js";
import { hsl } from "../../familiars/genome.js";

export const SLOTS = 12, MOTE_BONES = SLOTS * 2 + 2;
const TAU = Math.PI * 2, MINT = [0.3, 1, 0.63], ORDER = [0, 3, 1, 4, 2, 5];
const RINGS = [{ r: 1.3, tilt: 0.24, dir: 1 }, { r: 1.02, tilt: -0.32, dir: -1 }];
const glow = (col, em = 0) => ({ col, shade: col, rim: 0, em, flag: 0 });
const mix = (a, b, k) => a + (b - a) * k;

/* Euler angles that turn the Y axis along v. */
export const aim = (v) => { const l = Math.hypot(...v) || 1; return [Math.atan2(v[2], v[1]), 0, -Math.asin(v[0] / l)]; };

/* Adds the mote parts to a rig under root; at = { centre, home, collar, alarm } in root space. sync() maps agents to slots, step() moves them. */
export function attach({ add, group, root, verts }, at) {
  const slots = [];
  for (let i = 0; i < SLOTS; i++) {
    const b = group(root, at.home), v0 = verts();
    add(b, G.lo, glow(hsl(152, 0.9, 0.62), 0.25), { s: 0.085, outline: 1 });
    const v1 = verts();
    add(b, G.lo, glow([1, 1, 1]), { p: [-0.026, 0.03, 0.064], s: 0.03 });
    const th = group(root, at.home);
    add(th, cyl(1, 1, 1, 4, true), glow(MINT, 0.15), { p: [0, 0.5, 0], s: [0.009, 1, 0.009] });
    slots.push({ b, th, v0, v1, id: null, hue: null, k: 0, was: 0, pos: [...at.home], ring: RINGS[i % 2], a: (ORDER[i >> 1] / 6) * TAU + (i % 2) * 0.5 });
  }
  const red = group(root, at.alarm), flash = group(root, at.collar);
  add(red, G.lo, glow([1, 0.27, 0.24], 0.3), { s: 0.11, outline: 1 });
  add(red, G.lo, glow([1, 0.85, 0.8]), { p: [-0.033, 0.04, 0.085], s: 0.036 });
  add(flash, sphere(4, 2), glow([1, 0.95, 0.75], 0.3), { s: [1, 1, 0.3] });
  add(flash, sphere(4, 2), glow([1, 1, 1]), { s: [0.55, 0.55, 0.36], r: [0, 0, Math.PI / 4] });
  let spin = 0, burst = 0;

  /* Gives each agent {id, hue} a slot and repaints it in the mesh buffers; true when colours changed. */
  function sync(list, mesh) {
    const want = list.slice(0, SLOTS);
    let dirty = false;
    for (const s of slots) if (s.id != null && !want.some((m) => m.id === s.id)) s.id = null;
    for (const m of want) {
      if (slots.some((s) => s.id === m.id)) continue;
      const s = slots.find((x) => x.id == null && x.k < 0.02);
      if (!s) continue;
      s.id = m.id;
      if (s.hue !== m.hue) {
        const c = hsl(m.hue, 0.9, 0.62);
        for (let v = s.v0; v < s.v1; v++) { mesh.aCol.set(c, v * 3); mesh.aShade.set(c, v * 3); }
        s.hue = m.hue; dirty = true;
      }
    }
    return dirty;
  }

  /* Moves motes, threads, the red mote and the flash; hand is the conducting hand in root space. Returns the lead mote's place and how many are out. */
  function step(t, dt, w, hand, failing) {
    const ease = 1 - Math.exp(-dt * 3.2), home = w.sleep, threads = w.working;
    spin += dt * (0.3 + 0.75 * w.working + 0.25 * w.talking + 1.2 * w.error);
    let bad = slots.find((s) => s.id != null && s.id === failing) || slots.find((s) => s.id != null), lead = null, out = 0;
    const shake = [Math.sin(t * 31) * 0.02, Math.sin(t * 27) * 0.02, 0], alarm = at.alarm.map((v, i) => v + shake[i]);
    for (const [i, s] of slots.entries()) {
      s.k += ((s.id != null ? 1 : 0) - s.k) * ease;
      if (s.id == null && s.was > 0.12 && s.k <= 0.12) burst = 1;
      s.was = s.k;
      s.b.vis = s.th.vis = false;
      if (s.k < 0.02) { s.k = s.id != null ? 0.02 : 0; continue; }
      const th = spin * s.ring.dir + s.a, x = Math.cos(th) * s.ring.r, z = Math.sin(th) * s.ring.r * 0.55, ct = Math.cos(s.ring.tilt), sn = Math.sin(s.ring.tilt);
      const orb = [at.centre[0] + x * ct, at.centre[1] + x * sn + z * 0.3 + Math.sin(t * 1.7 + i * 2.1) * 0.05, at.centre[2] + z];
      const nest = [at.home[0] + Math.cos(i * 2.4) * 0.07, at.home[1] + 0.02 + (i % 3) * 0.035, at.home[2] + Math.sin(i * 2.4) * 0.07];
      const k = Math.min(1, s.k), e = s === bad ? w.error : 0;
      for (let a = 0; a < 3; a++) s.pos[a] = mix(at.collar[a], mix(mix(orb[a], nest[a], home), alarm[a], e), k);
      const size = k * (1 - 0.55 * home) * (1 + 0.12 * Math.sin(t * 3.1 + i));
      s.b.p[0] = s.pos[0]; s.b.p[1] = s.pos[1]; s.b.p[2] = s.pos[2]; s.b.s[0] = s.b.s[1] = s.b.s[2] = size; s.b.vis = size > 0.03;
      if (s.id != null) { out++; if (!lead) lead = s.pos; }
      const tk = threads * k * (1 - e);
      if (tk > 0.04) {
        const d = [s.pos[0] - hand[0], s.pos[1] - hand[1], s.pos[2] - hand[2]], r = aim(d);
        s.th.vis = true; s.th.p[0] = hand[0]; s.th.p[1] = hand[1]; s.th.p[2] = hand[2];
        s.th.r[0] = r[0]; s.th.r[2] = r[2]; s.th.s[0] = s.th.s[2] = tk; s.th.s[1] = Math.hypot(...d);
      }
    }
    const rk = w.error * (bad ? 1.18 : 1) * (1 + 0.14 * Math.sin(t * 12)), rp = bad ? bad.pos : alarm;
    red.vis = rk > 0.03; red.p[0] = rp[0]; red.p[1] = rp[1]; red.p[2] = rp[2] + 0.01; red.s[0] = red.s[1] = red.s[2] = rk;
    burst = Math.max(0, burst - dt * 2.6);
    const fk = Math.sin(Math.PI * (1 - burst)) * 0.26;
    flash.vis = burst > 0.02 && fk > 0.01; flash.s[0] = flash.s[1] = flash.s[2] = fk; flash.r[2] = burst * 3;
    return { lead: w.error > 0.5 ? rp : lead, out };
  }
  return { sync, step };
}
