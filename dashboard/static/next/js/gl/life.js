/* The eye's life: fixation with micro-saccades, pursuit of the pointer, glances at events, blinks, sleep, a pupil driven by load, flashes and squints. */
const mulberry = (a) => () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const RAD = Math.PI / 180, YAW = 30 * RAD, PITCH = 22 * RAD;
const ease = (x) => x * x * (3 - 2 * x);

export const COLORS = { done: [1.0, 0.637, 0.133], needs: [1.0, 0.637, 0.133], stray: [0.434, 0.074, 1.0], info: [0.074, 1.0, 0.35], poke: [0.6, 1.0, 0.86] };

export function createLife({ seed = 7, still = () => false } = {}) {
  const rnd = mulberry(seed), R = (a, b) => a + (b - a) * rnd();
  const L = {
    yaw: 0, pitch: 0, fix: [0, 0], micro: [0, 0], sac: null,
    blink: 0, blinkT0: -1, nextBlink: R(1.6, 3.2), double: false,
    nextMicro: R(0.5, 1.4), nextGlance: R(6, 10), glance: null,
    pupil: 0.3, pupilGoal: 0.3, load: 0.25, act: 0, burst: 0,
    flash: [0, 0, 0, 0], squint: 0, squintGoal: 0, squintT: 0,
    sleep: 0, sleepGoal: 0, pointer: null, pointerT: -99, cam: [0, 0], camGoal: [0, 0], nextAt: 0, t: 0,
  };

  const aim = (ux, uy) => {
    const z = 3.2;
    return [Math.max(-YAW, Math.min(YAW, Math.atan2(ux, z))), Math.max(-PITCH, Math.min(PITCH, Math.atan2(uy, z)))];
  };
  const saccade = (to, t) => {
    const amp = Math.hypot(to[0] - L.yaw, to[1] - L.pitch) / RAD;
    if (amp < 0.15) return;
    L.sac = { t0: t, dur: 0.022 + 0.0024 * amp, from: [L.yaw, L.pitch], to };
    if (amp > 12 && rnd() < 0.35 && L.blinkT0 < 0) L.nextBlink = t + 0.01;
  };

  /* Pointer in eye-radius units from the eye centre (y up), or null when it leaves. */
  L.setPointer = (ux, uy, t) => { L.pointer = ux == null ? null : [ux, uy]; L.pointerT = t; };
  /* A look at (ux, uy) for dur seconds, no flash. */
  L.look = (ux, uy, t, dur = 1.2) => { if (!still()) L.glance = { to: aim(ux, uy), until: t + dur }; };
  /* One event: a glance towards (ux, uy), an iris flash in the kind's colour, a pupil kick; ignored under reduced motion. */
  L.event = (kind, ux, uy, t) => {
    if (still()) return;
    if (ux != null) L.glance = { to: aim(ux, uy), until: t + 1.4 };
    const c = COLORS[kind] || COLORS.info;
    L.flash = [c[0], c[1], c[2], 1];
    L.burst = kind === "needs" ? -0.05 : 0.07;
    if (kind === "needs") { L.squintGoal = 0.45; L.squintT = t + 2.2; }
    if (kind === "poke") { L.nextBlink = t; L.squintGoal = 0.6; L.squintT = t + 0.35; L.burst = -0.08; }
  };
  L.setData = ({ load, act, sleep }) => {
    if (load != null) L.load = Math.max(0, Math.min(1, load));
    if (act != null) L.act = Math.max(0, Math.min(1, act));
    if (sleep != null) L.sleepGoal = typeof sleep === "number" ? Math.max(0, Math.min(1, sleep)) : sleep ? 1 : 0;
  };

  /* Advances to t seconds (amb = the ambient clock for hippus and sway, slowed to a stop at idle); returns 3 while the pointer or a wake-up needs full-rate frames, 2 while a flash fades, 1 while idle life (blink, saccade, squint) moves, else 0. */
  L.step = (t, dt, amb = t) => {
    L.t = t;
    const calm = still();
    let busy = false, hot = false, warm = false;
    const pointerLive = L.pointer && t - L.pointerT < 2.5;
    if (L.glance && t > L.glance.until) L.glance = null;
    if (!calm && !pointerLive && !L.glance && t > L.nextGlance && L.sleep < 0.5) {
      L.glance = { to: [R(-0.3, 0.3), R(-0.16, 0.12)], until: t + R(0.7, 1.5) };
      L.nextGlance = t + R(5, 11);
    }
    const goal = pointerLive ? aim(L.pointer[0], L.pointer[1]) : L.glance ? L.glance.to : [0, 0];
    if (Math.hypot(goal[0] - L.fix[0], goal[1] - L.fix[1]) > 0.035) { L.fix = goal; L.micro = [0, 0]; if (!calm) saccade(goal, t - dt); }
    else if (pointerLive) L.fix = goal;
    if (!calm && t > L.nextMicro && L.sleep < 0.5) {
      const a = R(0, Math.PI * 2), m = R(0.25, 0.7) * RAD;
      L.micro = [Math.cos(a) * m, Math.sin(a) * m];
      saccade([L.fix[0] + L.micro[0], L.fix[1] + L.micro[1]], t - dt);
      L.nextMicro = t + R(1.2, 3.2);
    }
    if (L.sac) {
      const f = Math.min(1, (t - L.sac.t0) / L.sac.dur), e = ease(f);
      L.yaw = L.sac.from[0] + (L.sac.to[0] - L.sac.from[0]) * e;
      L.pitch = L.sac.from[1] + (L.sac.to[1] - L.sac.from[1]) * e;
      if (f >= 1) L.sac = null; else busy = true;
    } else {
      const ty = L.fix[0] + L.micro[0], tp = L.fix[1] + L.micro[1], k = calm ? 1 : Math.min(1, dt * (pointerLive ? 14 : 3));
      L.yaw += (ty - L.yaw) * k; L.pitch += (tp - L.pitch) * k;
      if (pointerLive && Math.hypot(ty - L.yaw, tp - L.pitch) > 0.0015) hot = true;
    }

    if (!calm && L.blinkT0 < 0 && t >= L.nextBlink && L.sleep < 0.5) L.blinkT0 = t - Math.min(dt, 0.05);
    if (L.blinkT0 >= 0) {
      const b = t - L.blinkT0;
      L.blink = b < 0.085 ? ease(b / 0.085) : b < 0.12 ? 1 : b < 0.33 ? 1 - ease((b - 0.12) / 0.21) : 0;
      if (b >= 0.33) {
        L.blinkT0 = -1; L.blink = 0;
        L.nextBlink = !L.double && rnd() < 0.18 ? (L.double = true, t + 0.16) : (L.double = false, t + R(2.8, 7.5));
      } else busy = true;
    }

    const ds = L.sleepGoal - L.sleep;
    L.sleep = calm ? L.sleepGoal : L.sleep + ds * Math.min(1, dt * (ds > 0 ? 1.6 : 4));
    if (Math.abs(L.sleepGoal - L.sleep) > 0.004) hot = true;

    if (t > L.squintT) L.squintGoal = 0;
    L.squint = calm ? L.squintGoal : L.squint + (L.squintGoal - L.squint) * Math.min(1, dt * 7);
    if (Math.abs(L.squintGoal - L.squint) > 0.004) busy = true;

    L.burst *= Math.exp(-dt / 1.2);
    L.pupilGoal = 0.24 + 0.2 * L.load + 0.05 * L.act + L.burst - 0.06 * L.sleep;
    const hippus = calm ? 0 : 0.006 * Math.sin(amb * 1.3) + 0.004 * Math.sin(amb * 2.9 + 1.1);
    const tau = L.pupilGoal < L.pupil ? 0.22 : 0.8;
    L.pupil = calm ? L.pupilGoal : L.pupil + (L.pupilGoal - L.pupil) * Math.min(1, dt / tau);
    L.pupilOut = L.pupil + hippus;

    L.flash[3] *= Math.exp(-dt / 0.55);
    if (L.flash[3] > 0.03) warm = true; else L.flash[3] = 0;

    L.camGoal = pointerLive ? [L.pointer[0] * 0.025, L.pointer[1] * 0.02] : calm ? [0, 0] : [0.012 * Math.sin(amb * 0.21), 0.008 * Math.sin(amb * 0.17 + 2)];
    const kc = calm ? 1 : Math.min(1, dt * 3);
    L.cam[0] += (L.camGoal[0] - L.cam[0]) * kc; L.cam[1] += (L.camGoal[1] - L.cam[1]) * kc;
    if (pointerLive && Math.hypot(L.camGoal[0] - L.cam[0], L.camGoal[1] - L.cam[1]) > 0.001) hot = true;

    L.nextAt = calm ? Infinity : L.sleep > 0.5 ? t + 0.5 : Math.min(L.nextBlink, L.nextMicro, L.glance ? L.glance.until : L.nextGlance, L.nextGlance);
    return hot ? 3 : warm ? 2 : busy ? 1 : 0;
  };

  /* Uniform-ready view of the state. */
  L.view = () => {
    const cp = Math.cos(L.pitch), s = L.sleep, breath = s * 0.03 * Math.sin(L.t * 0.9);
    const blink = Math.max(L.blink, s * (0.9 + breath));
    const g = [Math.sin(L.yaw) * cp, Math.sin(L.pitch) - 0.12 * s, Math.cos(L.yaw) * cp], n = Math.hypot(...g);
    return {
      gaze: g.map((v) => v / n),
      lid: [0.4 + L.pitch * 0.55 - L.squint * 0.08, 0.3 - L.pitch * 0.3 - L.squint * 0.16, blink, L.squint],
      pupil: Math.max(0.14, Math.min(0.62, L.pupilOut ?? L.pupil)),
      flash: L.flash, cam: L.cam, act: L.act, load: L.load, sleep: s,
    };
  };
  return L;
}
