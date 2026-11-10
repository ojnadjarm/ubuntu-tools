/* Light surfaces of every chunk in one draw: city windows, dot-matrix signs and holo screens; the clock moves only on drawn frames. */
import * as T from "../../../vendor/three.sub.js";

export const WINDOW = 0, DOT = 2, HOLO = 3;
const VS = `attribute vec4 aK; attribute vec3 aCol; varying vec2 vUv; varying vec4 vK; varying vec3 vCol;
void main(){ vUv = uv; vK = aK; vCol = aCol; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`;
const FS = `precision highp float;
uniform float uT, uDim; uniform vec3 uCity, uLit;
varying vec2 vUv; varying vec4 vK; varying vec3 vCol;
float h1(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec4 city(){
  float hh = vK.z, y = vUv.y / hh; vec2 p = vec2(vUv.x + vK.y * 7.3, vUv.y);
  vec3 c = mix(uCity * 0.55, vec3(0.012, 0.02, 0.03), smoothstep(0.0, 0.95, y));
  for (float L = 0.0; L < 2.0; L++) {
    float bw = 0.34 - L * 0.12, bx = floor(p.x / bw + L * 0.37), top = (0.3 + 0.55 * h1(vec2(bx, L + 3.0))) * hh * (1.0 - L * 0.3);
    if (vUv.y < top) {
      vec2 g = vec2(p.x / 0.05, vUv.y / 0.07), f = fract(g);
      float lit = step(0.7 + L * 0.08, h1(floor(g) + L * 17.0)) * step(0.25, f.x) * step(0.3, f.y);
      c = mix(vec3(0.02, 0.03, 0.035) * (1.0 + L), mix(uLit, uCity * 1.6, step(0.6, h1(floor(g) + 5.0))), lit * (0.85 - L * 0.2));
    }
  }
  return vec4(c * uDim, 1.0);
}
vec4 holo(){
  float row = floor(vUv.y * 8.0), len = h1(vec2(row, vK.y + floor(uT * 1.6 + row * 0.37)));
  float bar = step(0.08, vUv.x) * step(vUv.x, 0.14 + 0.76 * len) * step(0.35, fract(vUv.y * 8.0)) * step(fract(vUv.y * 8.0), 0.8);
  vec2 e = abs(vUv - 0.5) * 2.0; float edge = smoothstep(0.9, 1.0, max(e.x, e.y));
  float scan = 0.75 + 0.25 * step(0.5, fract(vUv.y * 22.0 - uT * 0.6));
  return vec4(vCol * (0.16 + bar * 0.75 + edge * 0.7) * scan * vK.z, 0.28 * vK.z);
}
void main(){
  if (vK.x < 0.5) gl_FragColor = city();
  else if (vK.x < 2.5) gl_FragColor = vec4(vCol * (0.8 + 0.2 * smoothstep(0.5, 0.2, abs(vUv.y - 0.5))), 0.9);
  else gl_FragColor = holo();
}`;

/* effects(scene) → {set(id, quads), drop(id), look(theme, night), step(t)}. */
export function effects(scene) {
  const geo = new T.BufferGeometry(), U = { uT: { value: 0 }, uDim: { value: 1 }, uCity: { value: new T.Vector3() }, uLit: { value: new T.Vector3() } }, all = new Map();
  const mesh = new T.Mesh(geo, new T.ShaderMaterial({ uniforms: U, vertexShader: VS, fragmentShader: FS, transparent: true, premultipliedAlpha: true, depthWrite: false }));
  let dirty = false;
  mesh.frustumCulled = false; mesh.renderOrder = 2; scene.add(mesh);
  function merge() {
    const P = [], UV = [], K = [], C = [], I = [];
    for (const quads of all.values()) for (const q of quads) {
      const o = P.length / 3, [w, h] = q.uv, k = q.k || [0, 1, 0], c = q.col || [1, 1, 1];
      for (let i = 0; i < 4; i++) { P.push(...q.p[i]); UV.push(i === 1 || i === 2 ? w : 0, i > 1 ? h : 0); K.push(q.kind, k[0], k[1], k[2]); C.push(c[0], c[1], c[2]); }
      I.push(o, o + 1, o + 2, o, o + 2, o + 3);
      if (q.two) I.push(o, o + 2, o + 1, o, o + 3, o + 2);
    }
    for (const [n, a, s] of [["position", P, 3], ["uv", UV, 2], ["aK", K, 4], ["aCol", C, 3]]) geo.setAttribute(n, new T.BufferAttribute(new Float32Array(a), s));
    geo.setIndex(new T.BufferAttribute(new Uint32Array(I), 1));
    dirty = false;
  }
  return {
    /* quads: [{kind, p: four world corners (counter-clockwise from the lit side), uv: [w, h], k: [a, b, c], col, two}]. */
    set(id, quads) { all.set(id, quads); dirty = true; },
    drop(id) { dirty = all.delete(id) || dirty; },
    look(th, night) { U.uCity.value.set(...th.city); U.uLit.value.set(...th.cityLit); U.uDim.value = night ? 0.8 : 1; },
    step(t) { if (dirty) merge(); U.uT.value = t % 600; },
  };
}
