/* The office's 3D stage: one WebGL context on a given canvas, free orbit camera, draw on demand, world points to canvas pixels. */
import * as T from "../../../vendor/three.sub.js";

const STEP_MS = 125, SOFT = /swiftshader|llvmpipe|software/i;

/* The canvas's WebGL2 context, or null without one; soft says a software rasteriser draws it. */
function context(canvas, antialias) {
  const gl = canvas.getContext("webgl2", { antialias, alpha: true, depth: true, stencil: false, premultipliedAlpha: true, powerPreference: "low-power" });
  const e = gl && gl.getExtension("WEBGL_debug_renderer_info");
  return { gl, soft: !gl || SOFT.test(e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : "") };
}

/* stage(canvas, {still}) → {scene, cam, invalidate(), ticker(fn), view(home), reset(), zoom(k), project(p), still, stats}; fires "view" on the canvas after a frame that moved the camera. */
export function stage(canvas, { still = false } = {}) {
  const { gl, soft } = context(canvas, !still), frozen = still || soft, calm = matchMedia("(prefers-reduced-motion: reduce)");
  const r = gl ? new T.WebGLRenderer({ canvas, context: gl }) : null;
  if (r) r.outputColorSpace = T.LinearSRGBColorSpace;
  const scene = new T.Scene(), cam = new T.PerspectiveCamera(24, 1, 1, 600), ctl = new T.OrbitControls(cam, canvas), v = new T.Vector3();
  ctl.enableDamping = false; ctl.minPolarAngle = 0.12; ctl.maxPolarAngle = 1.46; ctl.zoomToCursor = true; ctl.screenSpacePanning = false; ctl.enabled = !frozen;
  canvas.style.touchAction = "pan-y";
  let raf = 0, timer = 0, moved = true, prev = 0, ticker = null, dragging = false, pristine = true, home = null, W = 1, H = 1;
  const pts = new Map();
  const S = { scene, cam, still: frozen, stats: { frames: 0, last: 0 } };

  function frame(now) {
    raf = 0;
    const hold = frozen || calm.matches, t = hold ? 1.3 : now / 1000, t0 = performance.now(), active = (ticker ? ticker(t, hold ? 1 : Math.min(0.1, t - prev)) : false) && !hold;
    prev = t;
    if (r) r.render(scene, cam);
    S.stats.frames++; S.stats.last = performance.now() - t0;
    if (moved) { moved = false; canvas.dispatchEvent(new Event("view")); }
    if (active && !document.hidden) { if (dragging) S.invalidate(); else timer = setTimeout(() => { timer = 0; S.invalidate(); }, STEP_MS); }
  }
  S.invalidate = () => { if (document.hidden) return; if (timer) { clearTimeout(timer); timer = 0; } if (!raf) raf = requestAnimationFrame(frame); };
  S.ticker = (fn) => { ticker = fn; };
  S.project = (p) => { v.set(p[0], p[1], p[2]).project(cam); return { x: (v.x * 0.5 + 0.5) * W, y: (0.5 - v.y * 0.5) * H, ok: v.z < 1 && Math.abs(v.x) < 1.1 && Math.abs(v.y) < 1.1 }; };

  /* Puts the camera at the home azimuth and elevation, as close as keeps the box lo..hi whole on screen. */
  function fit() {
    const { el } = home, tall = W < H, k = tall ? 1 : home.shrink || 1, c = [0, 1, 2].map((i) => (home.lo[i] + home.hi[i]) / 2), a = tall && home.azTall !== undefined ? home.azTall : home.az;
    const lo = [0, 1, 2].map((i) => c[i] + (home.lo[i] - c[i]) * (i === 1 ? 1 : k)), hi = [0, 1, 2].map((i) => (i === 1 ? Math.min(home.hi[1], home.top || 1.1) : c[i] + (home.hi[i] - c[i]) * k));
    const dir = [Math.sin(a) * Math.cos(el), Math.sin(el), Math.cos(a) * Math.cos(el)], pad = home.pad || [0.96, 0.9];
    const inside = (d) => {
      cam.position.set(c[0] + dir[0] * d, c[1] + dir[1] * d, c[2] + dir[2] * d); cam.lookAt(c[0], c[1], c[2]); cam.updateMatrixWorld();
      for (let i = 0; i < 8; i++) { v.set(i & 1 ? hi[0] : lo[0], i & 2 ? hi[1] : lo[1], i & 4 ? hi[2] : lo[2]).project(cam); if (Math.abs(v.x) > pad[0] || Math.abs(v.y) > pad[1] || v.z > 1) return false; }
      return true;
    };
    let d0 = 2, d1 = 400;
    for (let i = 0; i < 22; i++) { const m = (d0 + d1) / 2; if (inside(m)) d1 = m; else d0 = m; }
    inside(d1);
    ctl.target.set(c[0], c[1], c[2]); ctl.minDistance = d1 * 0.15; ctl.maxDistance = d1 * 1.6; ctl.update(); moved = true;
  }
  /* home = {lo, hi, az, el, azTall?, top?, shrink?, pad?}. */
  S.view = (h) => { home = h; S.reset(); };
  S.reset = () => { if (!home) return; pristine = true; fit(); S.invalidate(); };
  S.zoom = (k) => { pristine = false; cam.position.sub(ctl.target).multiplyScalar(k).add(ctl.target); ctl.update(); moved = true; S.invalidate(); };

  /* Turns by dAz, tilts by dPol (radians) and scales the distance by k, about the orbit target. */
  function orbit(dAz, dPol, k) {
    const d = v.copy(cam.position).sub(ctl.target).length(), az = Math.atan2(v.x, v.z) + dAz, po = Math.min(ctl.maxPolarAngle, Math.max(ctl.minPolarAngle, Math.acos(v.y / d) + dPol));
    cam.position.set(Math.sin(az) * Math.sin(po), Math.cos(po), Math.cos(az) * Math.sin(po)).multiplyScalar(d * k).add(ctl.target);
    ctl.update();
  }
  /* Touch: one finger sideways turns, two fingers turn, tilt and pinch; one finger up or down is the page's scroll (touch-action pan-y cancels it here). */
  function finger(e) {
    if (e.pointerType !== "touch") return;
    const was = pts.get(e.pointerId), k = 2 * Math.PI / H;
    if (e.type === "pointerdown" || (was && e.type === "pointermove")) pts.set(e.pointerId, [e.clientX, e.clientY]); else pts.delete(e.pointerId);
    dragging = pts.size > 0;
    if (!was || e.type !== "pointermove" || pts.size > 2) return;
    pristine = false;
    if (pts.size === 1) return orbit((was[0] - e.clientX) * k, 0, 1);
    const o = [...pts.values()].find((q) => q !== pts.get(e.pointerId));
    orbit((was[0] - e.clientX) * k / 2, (was[1] - e.clientY) * k / 2, Math.hypot(was[0] - o[0], was[1] - o[1]) / Math.max(1, Math.hypot(e.clientX - o[0], e.clientY - o[1])));
  }
  if (!frozen) {
    ctl.touches = { ONE: null, TWO: null };
    for (const t of ["pointerdown", "pointermove", "pointerup", "pointercancel"]) canvas.addEventListener(t, finger);
    canvas.addEventListener("touchstart", (e) => { if (e.targetTouches.length > 1 && e.cancelable) e.preventDefault(); }, { passive: false });
  }

  ctl.addEventListener("change", () => { moved = true; S.invalidate(); });
  ctl.addEventListener("start", () => { dragging = true; pristine = false; });
  ctl.addEventListener("end", () => { dragging = false; });
  new ResizeObserver(() => {
    if (!canvas.clientWidth || !canvas.clientHeight || (canvas.clientWidth === W && canvas.clientHeight === H)) return;
    W = canvas.clientWidth; H = canvas.clientHeight;
    if (r) { r.setPixelRatio(frozen ? 1 : Math.min(devicePixelRatio, 2)); r.setSize(W, H, false); }
    cam.aspect = W / H; cam.updateProjectionMatrix(); moved = true;
    if (home && pristine) fit();
    if (home) S.invalidate();
  }).observe(canvas);
  document.addEventListener("visibilitychange", () => S.invalidate());
  return S;
}
