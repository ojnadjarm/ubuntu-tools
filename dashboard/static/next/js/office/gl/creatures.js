/* The Familiars in world space: the dashboard's skinned toon bodies and ink hulls, drawn by the office camera; only acting creatures ask for frames. */
import * as T from "../../../vendor/three.sub.js";
import { build, BONES } from "../../gl/familiars/body.js";
import * as ceo from "../../gl/familiars/ceo.js";
import { compose } from "../../gl/familiars/geo.js";
import { genome, pose, POSES } from "../../familiars/genome.js";

const PAD = { working: [0.3, 1, 0.63], idle: [0.45, 0.62, 0.55], talking: [0.35, 0.85, 1], error: [1, 0.32, 0.3], sleep: [0.2, 0.3, 0.27] };
const HEAD = `precision highp float;
in vec3 position, normal; in vec4 aP;
uniform mat4 projectionMatrix, viewMatrix;`;
const body = (n) => `${HEAD}
in vec3 aCol, aShade; uniform mat4 uB[${n}];
out vec3 vN, vCol, vShade, vK; out float vZ;
void main(){
  mat4 M = uB[int(aP.x + 0.5)];
  vN = mat3(M) * normal; vZ = normalize(mat3(viewMatrix) * vN).z; vCol = aCol; vShade = aShade; vK = aP.yzw;
  gl_Position = projectionMatrix * viewMatrix * (M * vec4(position, 1.0));
}`;
const BODY_FS = `precision highp float;
in vec3 vN, vCol, vShade, vK; in float vZ;
uniform vec4 uTint; uniform vec3 uPad, uLight; uniform float uDim, uScr;
out vec4 o;
const vec3 L = vec3(0.4472, 0.8305, 0.4898), RIM = vec3(0.55, 1.0, 0.78);
void main(){
  if (vK.z > 2.5) { o = vec4(uPad, 1.0); return; }
  float f = gl_FrontFacing ? 1.0 : -1.0;
  vec3 n = normalize(vN) * f;
  float d = dot(n, L) * 0.5 + 0.5;
  float t = smoothstep(0.43, 0.47, d) * 0.62 + smoothstep(0.76, 0.8, d) * 0.38;
  vec3 c = mix(vShade, vCol, t);
  float r = pow(1.0 - max(vZ * f, 0.0), 3.0) * smoothstep(0.35, 0.75, d + n.y * 0.3);
  c += RIM * vK.x * r * 0.4 + vCol * vK.y;
  if (vK.z > 0.5 && vK.z < 1.5) c = mix(c, uTint.rgb * (0.35 + 0.65 * t), uTint.a) * uDim;
  if (vK.z > 1.5) c *= uScr; else if (vK.y < 0.2) c *= uLight;
  o = vec4(c, 1.0);
}`;
const hull = (n) => `${HEAD}
in float aO; uniform mat4 uB[${n}]; uniform float uInk;
void main(){
  mat4 M = uB[int(aP.x + 0.5)];
  if (aO < 0.5 || dot(M[0].xyz, M[0].xyz) < 1e-8) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
  vec4 v = M * vec4(position, 1.0);
  v.xyz += normalize(mat3(M) * normal) * uInk;
  gl_Position = projectionMatrix * viewMatrix * v;
}`;
const HULL_FS = `precision highp float;
out vec4 o;
void main(){ o = vec4(0.07, 0.05, 0.05, 1.0); }`;

/* creatures(scene) → {set(list), step(t, dt)}, keyed by id; a pose change reuses the body. */
export function creatures(scene) {
  const all = new Map(), root = new Float32Array(16);
  function make(a) {
    const boss = a.role === "ceo", n = boss ? ceo.BONES : BONES, b = (boss ? ceo.build : build)(genome(a.id, a.role)), geo = new T.BufferGeometry(), p = pose(a.pose);
    for (const [k, s] of [["position", 3], ["normal", 3], ["aCol", 3], ["aShade", 3], ["aP", 4], ["aO", 1]]) geo.setAttribute(k, new T.BufferAttribute(b.mesh[k], s));
    geo.setIndex(new T.BufferAttribute(b.mesh.index, 1));
    const U = { uB: { value: new Float32Array(n * 16) }, uTint: { value: new T.Vector4(1, 0.2, 0.2, 0) }, uPad: { value: new T.Vector3() }, uLight: { value: new T.Vector3(1, 1, 1) }, uDim: { value: 1 }, uScr: { value: 1 }, uInk: { value: 0.006 } };
    const mat = (vs, fs, side) => new T.RawShaderMaterial({ glslVersion: T.GLSL3, vertexShader: vs, fragmentShader: fs, uniforms: U, side });
    const meshes = [new T.Mesh(geo, mat(body(n), BODY_FS, T.DoubleSide)), new T.Mesh(geo, mat(hull(n), HULL_FS, T.BackSide))];
    meshes.forEach((m) => { m.frustumCulled = false; m.matrixAutoUpdate = false; scene.add(m); });
    return { b, geo, U, meshes, role: a.role, w: Object.fromEntries(POSES.map((s) => [s, s === p ? 1 : 0])), settled: false };
  }
  function drop(id) { const c = all.get(id); c.meshes.forEach((m) => { scene.remove(m); m.material.dispose(); }); c.geo.dispose(); all.delete(id); }
  const C = {
    /* list of {id, role, pose, x, y, z, yaw, scale, light: [r, g, b], live}. */
    set(list) {
      const keep = new Set(list.map((a) => a.id));
      for (const id of [...all.keys()]) if (!keep.has(id)) drop(id);
      for (const a of list) {
        let c = all.get(a.id);
        if (c && c.role !== a.role) { drop(a.id); c = null; }
        if (!c) { c = make(a); all.set(a.id, c); }
        c.a = a; c.settled = false;
        c.U.uLight.value.set(...(a.light || [1, 1, 1]).map((v) => Math.min(1.15, v))); c.U.uInk.value = 0.018 * a.scale;
      }
    },
    /* The meshes of creature id (body and hull), [] when it is not in the scene. */
    parts: (id) => (all.has(id) ? all.get(id).meshes : []),
    /* Advances every creature that acts or still blends; true while one of them needs another frame. */
    step(t, dt) {
      let busy = false;
      for (const c of all.values()) {
        const to = pose(c.a.pose), k = 1 - Math.exp(-dt * 7), acts = to === "working" || to === "talking" || to === "error";
        let moving = false;
        for (const s of POSES) { const g = s === to ? 1 : 0; c.w[s] += (g - c.w[s]) * k; if (Math.abs(g - c.w[s]) > 0.003) moving = true; else c.w[s] = g; }
        if (!moving && !acts && c.settled) continue;
        const r = c.b.update(acts || moving ? t : 1.3, c.w, c.a.live), pad = c.U.uPad.value.set(0, 0, 0);
        for (const s of POSES) { pad.x += PAD[s][0] * c.w[s]; pad.y += PAD[s][1] * c.w[s]; pad.z += PAD[s][2] * c.w[s]; }
        c.U.uDim.value = r.dim; c.U.uTint.value.w = r.tint; c.U.uScr.value = r.screen;
        if (r.recolor) c.geo.attributes.aCol.needsUpdate = c.geo.attributes.aShade.needsUpdate = true;
        compose(root, [c.a.x, c.a.y, c.a.z], [0, c.a.yaw, 0], [c.a.scale, c.a.scale, c.a.scale]);
        c.b.pose(c.U.uB.value, root);
        c.settled = !moving && !acts;
        busy = busy || moving || acts;
      }
      return busy;
    },
  };
  return C;
}
