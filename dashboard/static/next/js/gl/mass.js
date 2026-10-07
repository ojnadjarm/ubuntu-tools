/* The glyph mass: one Points cloud of katakana that morphs between screen shapes, through the eye's pupil when the screen changes, directly when only the data moves. */
const VS = `
attribute vec3 aTo; attribute vec2 aS; attribute vec4 aK; attribute float aG;
uniform float uPx, uTime, uMix, uVia, uSide, uPulse, uPulseR, uFocus;
uniform vec3 uPupil, uAxis;
varying float vG, vT, vC, vF, vB, vA;
vec3 turn(vec3 p, vec3 n, float a){ float c = cos(a), s = sin(a); return p * c + cross(n, p) * s + n * dot(n, p) * (1.0 - c); }
void main(){
  vec3 a = position, b = aTo;
  float dl = fract(aG * 0.618) * 0.35, ph = clamp((uMix - dl) / 0.65, 0.0, 1.0);
  vec3 p; float sz;
  float via = uVia;
  if (via > 0.5) {
    float h = ph < 0.5 ? ph * 2.0 : (ph - 0.5) * 2.0;
    if (ph < 0.5) { float f = h * h * h; p = mix(a, uPupil, f); sz = aS.x * (1.0 - 0.9 * f); }
    else { float f = 1.0 - pow(1.0 - h, 3.0); p = mix(uPupil, b, f); sz = aS.y * (0.1 + 0.9 * f); }
    p = uPupil + turn(p - uPupil, uAxis, (1.0 - abs(ph * 2.0 - 1.0)) * (1.8 + fract(aG * 0.37) * 2.2));
  } else {
    float e = 1.0 - pow(1.0 - ph, 3.0), lift = sin(e * 3.14159) * 0.35;
    p = mix(a, b, e) + normalize(mix(a, b, e) + vec3(0.001)) * lift;
    sz = mix(aS.x, aS.y, e);
  }
  float transit = via * step(0.002, ph) * step(ph, 0.998);
  vA = uSide > 0.5 ? transit : 1.0 - transit;
  vec4 mv = modelViewMatrix * vec4(p, 1.0);
  gl_Position = projectionMatrix * mv;
  gl_PointSize = vA * sz * uPx / -mv.z;
  vT = ph < 0.5 ? aK.x : aK.y; vC = ph < 0.5 ? aK.z : aK.w;
  vG = mod(aG + floor(uTime * (0.4 + fract(aG * 0.37)) * step(2.5, vT)), 61.0);
  vF = clamp(1.0 - (-mv.z - uFocus) / uFocus * 0.8, 0.3, 1.3) * (1.0 + transit * 2.0);
  vB = uPulse * smoothstep(0.9, 0.0, abs(length(p.xy) - uPulseR));
}`;

const FS = `
uniform sampler2D uAtlas; uniform vec3 uPal[4]; uniform vec3 uPulseC; uniform float uTier[5];
varying float vG, vT, vC, vF, vB, vA;
void main(){
  if (vA < 0.5) discard;
  vec3 base = vC < 0.5 ? uPal[0] : vC < 1.5 ? uPal[1] : vC < 2.5 ? uPal[2] : uPal[3];
  float k = vT < 0.5 ? uTier[0] : vT < 1.5 ? uTier[1] : vT < 2.5 ? uTier[2] : vT < 3.5 ? uTier[3] : uTier[4];
  vec3 col = mix(base, vec3(1.0), vT > 2.5 ? (vT - 2.5) * 0.4 : 0.0) * k + uPulseC * vB * 0.6;
  vec2 q = vec2(1.0 - gl_PointCoord.x, gl_PointCoord.y);
  vec2 g = texture2D(uAtlas, (vec2(mod(vG, 8.0), floor(vG / 8.0)) + 0.1 + q * 0.8) / 8.0).rg;
  gl_FragColor = vec4(col * (g.x + g.y * 0.6) * vF, 1.0);
}`;

const ease = (x) => 1 - Math.pow(1 - x, 3);

/* A Points mass of n glyphs with its own perspective camera; show() sets the next shape, frame() places it. */
export function createMass({ T }, atlasTex, n) {
  const scene = new T.Scene(), cam = new T.PerspectiveCamera(32, 1, 0.1, 200);
  const U = { uAtlas: { value: atlasTex }, uPx: { value: 1 }, uTime: { value: 0 }, uMix: { value: 1 }, uVia: { value: 0 }, uSide: { value: 0 }, uFocus: { value: 20 },
    uPulse: { value: 0 }, uPulseR: { value: 0 }, uPulseC: { value: new T.Vector3(0.074, 1, 0.35) }, uPupil: { value: new T.Vector3() }, uAxis: { value: new T.Vector3(0, 0, 1) },
    uTier: { value: [0.022, 0.06, 0.2, 0.5, 1.4] },
    uPal: { value: [new T.Vector3(0.074, 1.0, 0.35), new T.Vector3(1.0, 0.637, 0.133), new T.Vector3(0.434, 0.074, 1.0), new T.Vector3(0.347, 0.807, 1.0)] } };
  const mat = new T.ShaderMaterial({ vertexShader: VS, fragmentShader: FS, transparent: true, depthWrite: false, depthTest: false, blending: T.AdditiveBlending, uniforms: U });
  const g = new T.BufferGeometry(), A = {};
  [["position", 3], ["aTo", 3], ["aS", 2], ["aK", 4], ["aG", 1]].forEach(([k, m]) => { A[k] = new T.BufferAttribute(new Float32Array(n * m), m); g.setAttribute(k, A[k]); });
  for (let i = 0; i < n; i++) A.aG.array[i] = (Math.imul(i + 1, 2654435761) >>> 0) % 61;
  const pts = new T.Points(g, mat);
  pts.frustumCulled = false;
  scene.add(pts);

  const M = { U, cam, scene, pts, n, morph: 0, dur: 1000, pulse: 0 };

  /* True when list is exactly the shape the mass rests in. */
  const rests = (list) => {
    const To = A.aTo.array, S = A.aS.array, K = A.aK.array, f = Math.fround;
    if (U.uMix.value < 1) return false;
    for (let i = 0; i < n; i++) {
      const p = list[i];
      if (!p) { if (S[i * 2 + 1] !== 0) return false; continue; }
      if (To[i * 3] !== f(p.x) || To[i * 3 + 1] !== f(p.y) || To[i * 3 + 2] !== f(p.z) || S[i * 2 + 1] !== f(p.s) || K[i * 4 + 1] !== f(p.t) || K[i * 4 + 3] !== f(p.c || 0)) return false;
    }
    return true;
  };
  /* Next shape; via = through the pupil. The current in-between becomes the source; false when nothing moves. */
  M.show = (list, { via = false, instant = false, dur = 1000 } = {}) => {
    if (!via && rests(list)) return false;
    const P = A.position.array, To = A.aTo.array, S = A.aS.array, K = A.aK.array, m = U.uMix.value, e = ease(m);
    for (let i = 0; i < n; i++) {
      if (m < 1) for (let j = 0; j < 3; j++) P[i * 3 + j] += (To[i * 3 + j] - P[i * 3 + j]) * e;
      else for (let j = 0; j < 3; j++) P[i * 3 + j] = To[i * 3 + j];
      S[i * 2] = m >= 0.5 ? S[i * 2 + 1] : S[i * 2];
      if (m >= 0.5) { K[i * 4] = K[i * 4 + 1]; K[i * 4 + 2] = K[i * 4 + 3]; }
      const p = list[i];
      if (p) {
        To[i * 3] = p.x; To[i * 3 + 1] = p.y; To[i * 3 + 2] = p.z; S[i * 2 + 1] = p.s; K[i * 4 + 1] = p.t; K[i * 4 + 3] = p.c || 0;
        if (S[i * 2] === 0) { P[i * 3] = p.x; P[i * 3 + 1] = p.y; P[i * 3 + 2] = p.z; K[i * 4] = p.t; K[i * 4 + 2] = p.c || 0; }
      } else { To[i * 3] = P[i * 3]; To[i * 3 + 1] = P[i * 3 + 1]; To[i * 3 + 2] = P[i * 3 + 2]; S[i * 2 + 1] = 0; }
    }
    Object.values(A).forEach((a) => { a.needsUpdate = true; });
    U.uVia.value = via ? 1 : 0;
    M.dur = dur;
    M.morph = instant ? 0 : performance.now();
    U.uMix.value = M.morph ? 0 : 1;
    return !!M.morph;
  };
  /* One wave from the centre outwards in colour c (linear rgb). */
  M.ping = (c) => { U.uPulseC.value.set(...c); M.pulse = performance.now(); };
  /* Advances the morph and the pulse: 2 while the mass flows through the pupil, 1 while a data morph or a pulse runs, else 0. */
  M.step = (now) => {
    let lv = 0;
    if (M.morph) { const f = Math.min(1, (now - M.morph) / M.dur); U.uMix.value = f; if (f >= 1) { M.morph = 0; U.uVia.value = 0; } else lv = U.uVia.value > 0.5 ? 2 : 1; }
    if (M.pulse) { const f = (now - M.pulse) / 1200; U.uPulse.value = f < 1 ? 1 - f : 0; U.uPulseR.value = f * 9; if (f >= 1) M.pulse = 0; else lv = Math.max(lv, 1); }
    return lv;
  };
  M.transit = () => U.uVia.value > 0.5 && U.uMix.value < 1;
  return M;
}
