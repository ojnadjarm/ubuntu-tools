/* Eye lab engine: WebGL2 via three.js, an HDR scene pass from the variant, 13-tap bloom, AgX composite, and an on-demand frame scheduler. */
import * as T from "../vendor/three.lab.js";
import { AGX, VS_TRI, NOISE } from "./glsl.js";

export const still = matchMedia("(prefers-reduced-motion: reduce)");
const STILL_T = 7.5;
const phone = () => Math.min(innerWidth, innerHeight) < 600;

const DOWN = `precision highp float;
uniform sampler2D uSrc; uniform vec2 uTexel, uDst; uniform float uFirst, uThresh;
out vec4 o;
vec3 s(vec2 uv){ vec3 c = texture(uSrc, uv).rgb; return any(isnan(c)) || any(isinf(c)) ? vec3(0.0) : c; }
float w(vec3 c){ return 1.0 / (1.0 + dot(c, vec3(0.2126, 0.7152, 0.0722))); }
void main(){
  vec2 uv = gl_FragCoord.xy / uDst, t = uTexel;
  vec3 a = s(uv + t * vec2(-2, 2)), b = s(uv + t * vec2(0, 2)), c = s(uv + t * vec2(2, 2));
  vec3 d = s(uv + t * vec2(-2, 0)), e = s(uv), f = s(uv + t * vec2(2, 0));
  vec3 g = s(uv + t * vec2(-2, -2)), h = s(uv + t * vec2(0, -2)), i = s(uv + t * vec2(2, -2));
  vec3 j = s(uv + t * vec2(-1, 1)), k = s(uv + t * vec2(1, 1)), l = s(uv + t * vec2(-1, -1)), m = s(uv + t * vec2(1, -1));
  vec3 r;
  if (uFirst > 0.5) {
    vec3 q0 = (a + b + d + e) * 0.25, q1 = (b + c + e + f) * 0.25, q2 = (d + e + g + h) * 0.25, q3 = (e + f + h + i) * 0.25, q4 = (j + k + l + m) * 0.25;
    float w0 = w(q0), w1 = w(q1), w2 = w(q2), w3 = w(q3), w4 = w(q4);
    r = (q0 * w0 * 0.125 + q1 * w1 * 0.125 + q2 * w2 * 0.125 + q3 * w3 * 0.125 + q4 * w4 * 0.5) / (w0 * 0.125 + w1 * 0.125 + w2 * 0.125 + w3 * 0.125 + w4 * 0.5);
    float br = max(r.r, max(r.g, r.b)), soft = clamp(br - uThresh * 0.5, 0.0, uThresh);
    soft = soft * soft / (2.0 * uThresh + 1e-4);
    r *= max(soft, br - uThresh) / max(br, 1e-4);
  } else {
    r = e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
  }
  o = vec4(r, 1.0);
}`;

const UP = `precision highp float;
uniform sampler2D uSrc; uniform vec2 uTexel; uniform vec2 uDst; uniform float uRad;
out vec4 o;
void main(){
  vec2 uv = gl_FragCoord.xy / uDst, t = uTexel * uRad;
  vec3 c = texture(uSrc, uv).rgb * 4.0;
  c += (texture(uSrc, uv + vec2(-t.x, 0)).rgb + texture(uSrc, uv + vec2(t.x, 0)).rgb + texture(uSrc, uv + vec2(0, t.y)).rgb + texture(uSrc, uv + vec2(0, -t.y)).rgb) * 2.0;
  c += texture(uSrc, uv + t).rgb + texture(uSrc, uv - t).rgb + texture(uSrc, uv + vec2(t.x, -t.y)).rgb + texture(uSrc, uv + vec2(-t.x, t.y)).rgb;
  o = vec4(c / 16.0, 1.0);
}`;

const COMP = `precision highp float;
uniform sampler2D uHdr, uBloom; uniform vec2 uRes; uniform vec2 uCtr; uniform float uBloomK, uExp, uCA, uGrain, uVig, uPunch, uSeed;
out vec4 o;
${NOISE}
${AGX}
void main(){
  vec2 uv = gl_FragCoord.xy / uRes, d = (gl_FragCoord.xy - uCtr) / max(uRes.x, uRes.y);
  float r2 = dot(d, d);
  vec2 off = d * uCA * (0.4 + 3.0 * r2);
  vec3 c = vec3(texture(uHdr, uv - off).r, texture(uHdr, uv).g, texture(uHdr, uv + off).b);
  vec3 b = vec3(texture(uBloom, uv - off * 2.0).r, texture(uBloom, uv).g, texture(uBloom, uv + off * 2.0).b);
  c = (c + b * uBloomK) * uExp;
  c *= mix(1.0, smoothstep(1.25, 0.1, length(d * vec2(1.0, 1.25))), uVig);
  c = srgb(agx(c, uPunch));
  float n = h12(gl_FragCoord.xy + uSeed * 91.7) + h12(gl_FragCoord.xy * 1.37 + uSeed * 37.1) - 1.0;
  c += n * uGrain * (0.35 + 0.65 * (1.0 - c));
  o = vec4(c, 1.0);
}`;

const TIERS = {
  high: { scale: 1, levels: 5, q: 2 },
  mid: { scale: 0.85, levels: 4, q: 1 },
  low: { scale: 0.7, levels: 3, q: 0 },
};

/* Engine over a full-viewport canvas; variant = { init(ctx), step(state, t, dt) → busy, draw(r, cam) } and a life that animates the eye. */
export function createEngine(canvas, { variant, life, box, capture = false, idleFps = 4, lifeFps = 12, tier: forceTier, post = {} }) {
  const r = new T.WebGLRenderer({ canvas, antialias: false, alpha: false, depth: false, stencil: false, powerPreference: "high-performance", preserveDrawingBuffer: capture });
  r.autoClear = false;
  r.outputColorSpace = T.LinearSRGBColorSpace;
  const gl = r.getContext();
  const cam = new T.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const tri = new T.BufferGeometry();
  tri.setAttribute("position", new T.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3));
  const quad = (fs, uniforms, blend = T.NoBlending) => {
    const m = new T.Mesh(tri, new T.RawShaderMaterial({ glslVersion: T.GLSL3, vertexShader: VS_TRI, fragmentShader: fs, uniforms, depthTest: false, depthWrite: false, blending: blend }));
    m.frustumCulled = false;
    return m;
  };
  const rt = (w, h) => new T.WebGLRenderTarget(w, h, { type: T.HalfFloatType, format: T.RGBAFormat, depthBuffer: false, stencilBuffer: false, minFilter: T.LinearFilter, magFilter: T.LinearFilter, wrapS: T.ClampToEdgeWrapping, wrapT: T.ClampToEdgeWrapping });

  const P = Object.assign({ bloom: 0.9, exp: 1.0, ca: 0.0025, grain: 0.035, vig: 0.85, punch: 0.35, thresh: 0.9, rad: 1.0 }, post);
  const dU = { uSrc: { value: null }, uTexel: { value: new T.Vector2() }, uDst: { value: new T.Vector2() }, uFirst: { value: 0 }, uThresh: { value: P.thresh } };
  const uU = { uSrc: { value: null }, uTexel: { value: new T.Vector2() }, uDst: { value: new T.Vector2() }, uRad: { value: P.rad } };
  const cU = { uHdr: { value: null }, uBloom: { value: null }, uRes: { value: new T.Vector2() }, uCtr: { value: new T.Vector2() }, uBloomK: { value: P.bloom }, uExp: { value: P.exp },
    uCA: { value: P.ca }, uGrain: { value: P.grain }, uVig: { value: P.vig }, uPunch: { value: P.punch }, uSeed: { value: 0 } };
  const down = quad(DOWN, dU), up = quad(UP, uU, T.AdditiveBlending), comp = quad(COMP, cU);

  const S = { W: 0, H: 0, dpr: 1, scale: 1, tier: "high", q: 2, levels: 5, hdr: null, chain: [], eye: { x: 0, y: 0, r: 1 }, frames: 0, draws: 0, ms: [], pointer: null };
  const ctx = { T, r, gl, cam, quad, S };
  variant.init(ctx);

  function alloc() {
    const dpr = Math.min(devicePixelRatio || 1, phone() ? 2 : 1.5);
    const W = Math.max(1, Math.round(innerWidth * dpr)), H = Math.max(1, Math.round(innerHeight * dpr));
    if (W !== S.W || H !== S.H || dpr !== S.dpr) { r.setPixelRatio(1); r.setSize(W, H, false); S.W = W; S.H = H; S.dpr = dpr; S.hdr = null; }
    const w = Math.max(2, Math.round(W * S.scale)), h = Math.max(2, Math.round(H * S.scale));
    if (!S.hdr || S.hdr.width !== w || S.hdr.height !== h || S.chain.length !== S.levels) {
      S.hdr && S.hdr.dispose(); S.chain.forEach((c) => c.dispose());
      S.hdr = rt(w, h); S.chain = [];
      for (let i = 1, cw = w, ch = h; i <= S.levels; i++) { cw = Math.max(1, cw >> 1); ch = Math.max(1, ch >> 1); S.chain.push(rt(cw, ch)); }
    }
    const b = box();
    S.eye = { x: b.x * dpr * S.scale, y: (innerHeight - b.y) * dpr * S.scale, r: b.r * dpr * S.scale };
    S.ctr = { x: b.x * dpr, y: (innerHeight - b.y) * dpr };
  }

  function render() {
    alloc();
    r.setRenderTarget(S.hdr);
    variant.draw(r, cam, S);
    let src = S.hdr;
    S.chain.forEach((dst, i) => {
      dU.uSrc.value = src.texture; dU.uTexel.value.set(1 / src.width, 1 / src.height); dU.uDst.value.set(dst.width, dst.height); dU.uFirst.value = i === 0 ? 1 : 0;
      r.setRenderTarget(dst); r.render(down, cam); src = dst;
    });
    for (let i = S.chain.length - 1; i > 0; i--) {
      const s = S.chain[i], d = S.chain[i - 1];
      uU.uSrc.value = s.texture; uU.uTexel.value.set(1 / s.width, 1 / s.height); uU.uDst.value.set(d.width, d.height);
      r.setRenderTarget(d); r.render(up, cam);
    }
    cU.uHdr.value = S.hdr.texture; cU.uBloom.value = S.chain[0].texture; cU.uRes.value.set(S.W, S.H); cU.uCtr.value.set(S.ctr.x, S.ctr.y);
    cU.uSeed.value = (S.frames % 64) + 1;
    r.setRenderTarget(null); r.render(comp, cam);
    S.frames++;
  }

  let raf = 0, timer = 0, until = 0, last = 0, t0 = performance.now(), visible = true;
  const E = { S, ctx, P: cU, still };

  function frame(tMs) {
    const t = still.matches ? STILL_T : (tMs - t0) / 1000, dt = last ? Math.min(0.1, (tMs - last) / 1000) : 1 / 60;
    last = tMs;
    const busy = life.step(t, dt, S) | variant.step(S, t, dt, life);
    render();
    return busy;
  }
  function track(tMs) {
    S.ms.push(tMs); if (S.ms.length > 90) S.ms.shift();
    if (S.ms.length < 30 || forceTier) return;
    const n = S.ms.length, span = (S.ms[n - 1] - S.ms[n - 21]) / 20;
    if (span > 21 && S.scale > 0.5) { S.scale = Math.max(0.5, S.scale * 0.88); S.ms = []; }
  }
  function loop(tMs) {
    raf = 0;
    if (document.hidden || !visible) return;
    const busy = frame(tMs);
    if (still.matches) return;
    if (busy > 1 || tMs < until) { track(tMs); raf = requestAnimationFrame(loop); return; }
    S.ms = [];
    const next = life.nextAt ? (life.nextAt - (tMs - t0) / 1000) * 1000 : Infinity;
    const wait = busy ? 1000 / lifeFps : idleFps > 0 ? 1000 / idleFps : Math.max(8, next);
    if (wait !== Infinity) timer = setTimeout(kick, wait);
  }
  function kick() { timer = 0; if (!capture && !raf && !document.hidden && visible) raf = requestAnimationFrame(loop); }

  /* Keeps full-rate frames coming for ms; afterwards the idle rhythm or nothing. */
  E.wake = (ms = 0) => {
    until = Math.max(until, performance.now() + ms);
    if (timer) { clearTimeout(timer); timer = 0; }
    kick();
  };
  /* Capture mode: one deterministic frame at t seconds with a fixed step. */
  E.renderAt = (t, dt = 1 / 30) => { life.step(t, dt, S); variant.step(S, t, dt, life); render(); };
  const px = new Uint16Array(4);
  E.probe = () => {
    alloc();
    r.setRenderTarget(S.hdr);
    r.readRenderTargetPixels(S.hdr, 0, 0, 1, 1, px);
    const t = performance.now();
    for (let i = 0; i < 4; i++) { r.setRenderTarget(S.hdr); variant.draw(r, cam, S); }
    r.readRenderTargetPixels(S.hdr, 0, 0, 1, 1, px);
    return (performance.now() - t) / 4;
  };
  E.clock = () => (performance.now() - t0) / 1000;
  E.setTier = (name) => { const k = TIERS[name] || TIERS.high; S.tier = name; S.scale = k.scale; S.levels = k.levels; S.q = k.q; };
  E.dispose = () => { cancelAnimationFrame(raf); clearTimeout(timer); r.dispose(); };

  E.setTier(forceTier || "high");
  if (!forceTier && !capture) {
    E.probe();
    const ms = Math.min(E.probe(), E.probe(), E.probe()), px = S.hdr.width * S.hdr.height;
    const perMp = ms / (px / 1e6);
    E.setTier(perMp < 2.2 ? "high" : perMp < 5 ? "mid" : "low");
    S.probeMs = +ms.toFixed(2);
  }
  document.addEventListener("visibilitychange", () => { if (!document.hidden) E.wake(0); else { cancelAnimationFrame(raf); raf = 0; clearTimeout(timer); timer = 0; } });
  new IntersectionObserver((es) => { visible = es[es.length - 1].isIntersecting; if (visible) E.wake(0); }).observe(canvas);
  addEventListener("resize", () => E.wake(0));
  still.addEventListener("change", () => E.wake(0));
  return E;
}
