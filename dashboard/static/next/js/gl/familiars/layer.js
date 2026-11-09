/* The Familiars on the GPU: each creature is one skinned mesh and its ink hull (2 draws), drawn with depth and 4× MSAA into their own target, then laid over the HDR scene. */
import { build, BONES, PITCH } from "./body.js";
import { compose, mul } from "./geo.js";
import { body, hull, BODY_FS, HULL_FS, COMP } from "./glsl.js";
import { genome, pose, POSES } from "../../familiars/genome.js";

export const PAD = { working: [0.3, 1, 0.63], idle: [0.45, 0.62, 0.55], talking: [0.35, 0.85, 1], error: [1, 0.32, 0.3], sleep: [0.2, 0.3, 0.27] };
/* Body units per pixel of drawn size, and where the feet stand under the centre. */
export const UNIT = 0.7, FEET = 0.58;
const BACK = 1, DOUBLE = 2;

/* draw(list, S, t, dt) with list far to near of {id, role, state, x, y, size, yaw, lift, squash, fade} in HDR pixels; drop(id); busy while a pose still blends. */
export function createFamiliars({ T, r, cam, quad }) {
  const scene = new T.Scene(), all = new Map(), tilt = compose(new Float32Array(16), [0, 0, 0], [PITCH, 0, 0], [1, 1, 1]), m0 = new Float32Array(16), m1 = new Float32Array(16);
  const CU = { uTex: { value: null }, uRes: { value: new T.Vector2() }, uGain: { value: 1 } };
  const comp = quad(COMP, CU, T.CustomBlending, { blendSrc: T.OneFactor, blendDst: T.OneMinusSrcAlphaFactor, transparent: true });
  const res = new T.Vector2();
  let rt = null;

  function make(id, role, state) {
    const b = build(genome(id, role)), geo = new T.BufferGeometry(), p = pose(state);
    for (const [k, n] of [["position", 3], ["normal", 3], ["aCol", 3], ["aShade", 3], ["aP", 4], ["aO", 1]]) geo.setAttribute(k, new T.BufferAttribute(b.mesh[k], n));
    geo.setIndex(new T.BufferAttribute(b.mesh.index, 1));
    const U = { uB: { value: new Float32Array(BONES * 16) }, uRes: { value: res }, uZ: { value: new T.Vector3() }, uTint: { value: new T.Vector4(1, 0.2, 0.2, 0) }, uPad: { value: new T.Vector3() }, uDim: { value: 1 }, uScr: { value: 1 }, uFade: { value: 1 } };
    const mat = (vs, fs, side) => new T.RawShaderMaterial({ glslVersion: T.GLSL3, vertexShader: vs, fragmentShader: fs, uniforms: U, side, blending: T.NoBlending });
    const meshes = [new T.Mesh(geo, mat(body(BONES), BODY_FS, DOUBLE)), new T.Mesh(geo, mat(hull(BONES), HULL_FS, BACK))];
    meshes.forEach((m) => { m.frustumCulled = false; m.matrixAutoUpdate = false; scene.add(m); });
    return { b, geo, U, meshes, role, w: Object.fromEntries(POSES.map((s) => [s, s === p ? 1 : 0])), settled: false };
  }
  function drop(id) {
    const c = all.get(id);
    if (!c) return;
    c.meshes.forEach((m) => { scene.remove(m); m.material.dispose(); });
    c.geo.dispose(); all.delete(id);
  }
  /* Blends the pose weights toward the state's pose; false once they have arrived. */
  function blend(c, state, dt) {
    const to = pose(state), k = 1 - Math.exp(-dt * 7);
    let moving = false;
    for (const s of POSES) { const g = s === to ? 1 : 0; c.w[s] += (g - c.w[s]) * k; if (Math.abs(g - c.w[s]) > 0.003) moving = true; else c.w[s] = g; }
    return moving;
  }

  const F = { busy: false, drop, count: () => all.size };
  F.draw = (list, S, t, dt) => {
    const hdr = S.hdr, w = hdr.width, h = hdr.height;
    if (!rt || rt.width !== w || rt.height !== h) {
      if (rt) rt.dispose();
      rt = new T.WebGLRenderTarget(w, h, { type: T.UnsignedByteType, format: T.RGBAFormat, depthBuffer: true, stencilBuffer: false, samples: 4, minFilter: T.NearestFilter, magFilter: T.NearestFilter });
    }
    res.set(w, h);
    for (const c of all.values()) c.meshes[0].visible = c.meshes[1].visible = false;
    let x0 = w, y0 = h, x1 = 0, y1 = 0, busy = false;
    list.forEach((o, i) => {
      let c = all.get(o.id);
      if (c && c.role !== o.role) { drop(o.id); c = null; }
      if (!c) { c = make(o.id, o.role, o.state); all.set(o.id, c); }
      const moving = blend(c, o.state, dt), awake = c.w.sleep < 1;
      busy = busy || moving;
      if (moving || awake || !c.settled) {
        const a = c.b.update(t, c.w), pad = c.U.uPad.value.set(0, 0, 0);
        for (const s of POSES) { pad.x += PAD[s][0] * c.w[s]; pad.y += PAD[s][1] * c.w[s]; pad.z += PAD[s][2] * c.w[s]; }
        c.U.uDim.value = a.dim; c.U.uTint.value.w = a.tint; c.U.uScr.value = a.screen;
        c.settled = !moving && !awake;
      }
      const u = o.size * UNIT;
      mul(m1, tilt, compose(m0, [0, 0, 0], [0, o.yaw, 0], [u * (1 - 0.5 * o.squash), u * (1 + o.squash), u * (1 - 0.5 * o.squash)]));
      m1[12] = o.x; m1[13] = o.y - o.size * FEET + o.lift;
      c.b.pose(c.U.uB.value, m1);
      c.U.uZ.value.set(0.9 - (1.8 * (i + 0.5)) / list.length, 0.9 / list.length / (2.6 * u), Math.max(0.018 * u, 1.1));
      c.U.uFade.value = o.fade;
      c.meshes[0].visible = c.meshes[1].visible = true;
      x0 = Math.min(x0, o.x - o.size * 1.2); x1 = Math.max(x1, o.x + o.size * 1.2); y0 = Math.min(y0, o.y - o.size * 1.2); y1 = Math.max(y1, o.y + o.size * 1.6);
    });
    F.busy = busy;
    x0 = Math.max(0, Math.floor(x0)); y0 = Math.max(0, Math.floor(y0)); x1 = Math.min(w, Math.ceil(x1)); y1 = Math.min(h, Math.ceil(y1));
    if (!list.length || x1 <= x0 || y1 <= y0) return;
    rt.scissor.set(x0, y0, x1 - x0, y1 - y0); rt.scissorTest = true;
    r.setRenderTarget(rt); r.setClearColor(0x000000, 0); r.clear(true, true, false);
    r.render(scene, cam);
    hdr.scissor.set(x0, y0, x1 - x0, y1 - y0); hdr.scissorTest = true;
    r.setRenderTarget(hdr);
    CU.uTex.value = rt.texture; CU.uRes.value.set(w, h);
    r.render(comp, cam);
    hdr.scissorTest = false; r.setRenderTarget(hdr);
  };
  return F;
}
