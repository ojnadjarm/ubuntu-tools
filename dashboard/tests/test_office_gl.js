// Office renderer (office/gl): one three.js for eye and office, draw on demand, pick and project, the still renderer, one context per visit; own page, 2 hand-made chunks.
// Run: node tests/test_office_gl.js   (PWC = path to playwright-core; SHOT = a PNG path for the GPU frame)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan"];
const NAMES = ("WebGLRenderer WebGLRenderTarget Scene Mesh Points BufferGeometry BufferAttribute InstancedBufferAttribute InstancedBufferGeometry OrthographicCamera PerspectiveCamera " +
  "ShaderMaterial RawShaderMaterial CanvasTexture DataTexture Texture Color Vector2 Vector3 Vector4 Matrix3 Matrix4 Quaternion Euler MathUtils HalfFloatType FloatType UnsignedByteType " +
  "RGBAFormat RedFormat LinearFilter NearestFilter LinearMipmapLinearFilter ClampToEdgeWrapping RepeatWrapping AdditiveBlending NoBlending NormalBlending CustomBlending OneFactor " +
  "OneMinusSrcAlphaFactor SRGBColorSpace LinearSRGBColorSpace NoColorSpace NoToneMapping GLSL3 OrbitControls MeshBasicMaterial ColorManagement MOUSE TOUCH FrontSide BackSide DoubleSide").split(" ");
const PAGE = `<!doctype html><html><body><div id="host"></div></body></html>`;

/* Runs in the page: mounts the renderer with two hand-made chunks and keeps handles on window. */
async function mount() {
  const { createRenderer } = await import("/static/next/js/office/gl/index.js");
  const flat = (x0, z0, x1, z1, y, c) => ({ position: new Float32Array([x0, y, z0, x0, y, z1, x1, y, z1, x1, y, z0]), color: new Float32Array([...c, ...c, ...c, ...c]), index: new Uint32Array([0, 1, 2, 0, 2, 3]) });
  const chunk = (id, M) => id === "hall"
    ? { id, ...flat(0, 0, 8, 6, 0, [0.5, 0.33, 0.21]), lo: [0, 0, 0], hi: [8, 2.5, 6], actors: [], labels: [],
      lamps: [{ x: 4, y: 2, z: 3, col: [1, 0.8, 0.5], i: 0.3, r: 2, halo: 0.3 }],
      quads: [{ kind: 0, p: [[1, 0.6, 0.02], [3, 0.6, 0.02], [3, 2, 0.02], [1, 2, 0.02]], uv: [2, 1.4], k: [3, 1.4, 0] }] }
    : { id, ...flat(3, 2, 5, 4, 0.01, [0.5, 0.22, 0.16]), lo: [3, 0, 2], hi: [5, 1, 4], lamps: [],
      quads: [{ kind: 3, p: [[3.5, 0.4, 2.2], [4.5, 0.4, 2.2], [4.5, 0.9, 2.2], [3.5, 0.9, 2.2]], uv: [1, 1], k: [5, 1, 0], col: [0.3, 1, 0.63], two: true }],
      actors: [{ id: "a1", role: "worker", pose: M.pose, x: 4, y: 0.01, z: 3, yaw: 0.4, scale: 0.36, light: [1, 1, 1] }],
      labels: [{ id: "a1", pos: [4, 0.83, 3] }] };
  const canvas = document.createElement("canvas");
  canvas.setAttribute("aria-hidden", "true");
  Object.assign(canvas.style, { display: "block", width: "100%", height: "560px" });
  document.getElementById("host").append(canvas);
  const opts = { theme: { city: [0.6, 0.36, 0.14], cityLit: [1, 0.82, 0.4] }, kit: {}, chunk, ink: () => ({ w: 1, h: 1, runs: [] }) };
  const R = createRenderer(canvas, opts);
  Object.assign(window, { R, canvas, opts, createRenderer, plan: { hall: { w: 8, d: 6, h: 2.5 }, cells: { r1: { x: 4, z: 3, w: 2, d: 2, slots: 1 } }, home: { az: 0.5, el: 0.6, azTall: 1.2, top: 1.5, shrink: 0.8 } } });
  window.go = (pose, patch) => R.apply({ night: false, pose }, window.plan, { layout: false, night: false, rooms: [], people: [], panels: [], line: false, ...patch });
  return R.still;
}
const frames = (p) => p.evaluate(() => window.R.stats().frames);
const settle = (p, n) => p.waitForFunction((k) => window.R.stats().frames >= k, n, { timeout: 20000 });

async function open(b, base, ctx = {}) {
  const p = await (await b.newContext({ viewport: { width: 1366, height: 768 }, ...ctx })).newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.addInitScript(() => {
    window.__gl = new Set();
    const get = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (kind, ...a) { const c = get.call(this, kind, ...a); if (c && /webgl/.test(kind)) window.__gl.add(this); return c; };
  });
  await p.goto(base + "/api/blank");
  await p.setContent(PAGE);
  return { p, errs };
}

async function gpu(base) {
  const b = await chromium.launch({ headless: true, args: ["--mute-audio", ...GPU] });
  try {
    const { p, errs } = await open(b, base);
    const got = await p.evaluate(async (names) => { const m = await import("/static/next/vendor/three.sub.js"); return { n: Object.keys(m).length, missing: names.filter((k) => m[k] === undefined) }; }, NAMES);
    assert.deepStrictEqual(got, { n: 54, missing: [] }, "the 54 exports exist");

    assert.strictEqual(await p.evaluate(mount), false, "with the GPU flags the renderer is not still");
    await p.evaluate(() => window.go("idle", { layout: true }));
    await settle(p, 1);
    await p.waitForTimeout(600);
    const rest = await frames(p);
    assert.ok(rest >= 1, "at least 1 frame after apply");
    await p.waitForTimeout(3000);
    assert.strictEqual(await frames(p) - rest, 0, "0 frames in 3 s at rest");

    const hit = await p.evaluate(() => { const q = window.R.project("a1"); return { q, id: window.R.pick(q.x, q.y), miss: window.R.pick(3, 3), none: window.R.project("nobody").ok }; });
    assert.ok(hit.q.ok && hit.q.x > 0 && hit.q.x < 1366 && hit.q.y > 0 && hit.q.y < 560, "project(id) is on the canvas: " + JSON.stringify(hit.q));
    assert.deepStrictEqual([hit.id, hit.miss, hit.none], ["a1", null, false], "pick at the projected point returns the id, a corner and an unknown id return nothing");

    await p.evaluate(() => window.go("idle", {}));
    await p.waitForTimeout(400);
    assert.deepStrictEqual(await p.evaluate(() => [window.R.stats().rebuilt, window.R.stats().chunks]).then((s) => [...s, 0]), [0, 2, await frames(p) - rest], "an empty patch rebuilds nothing and draws nothing");

    await p.evaluate(() => window.go("working", { rooms: ["r1"], people: ["a1"] }));
    await p.waitForTimeout(800);
    const fps = await p.evaluate(() => new Promise((ok) => {
      const f = () => window.R.stats().frames;
      let n = f(), a = null, t0 = performance.now();
      (function poll() {
        const now = performance.now();
        if (f() !== n) { n = f(); if (!a) a = [n, now]; else if (now - a[1] >= 3000) return ok((n - a[0]) / ((now - a[1]) / 1000)); }
        if (!a && now - t0 > 5000) return ok(0);
        requestAnimationFrame(poll);
      })();
    }));
    assert.ok(fps > 0 && fps <= 8, `a working creature draws at most 8 frames a second, drew ${fps.toFixed(2)}`);
    assert.strictEqual(await p.evaluate(() => window.R.stats().rebuilt), 1, "one room in the patch rebuilds one chunk");
    if (process.env.SHOT) await p.screenshot({ path: process.env.SHOT });

    await p.evaluate(() => { Object.defineProperty(document, "hidden", { configurable: true, get: () => true }); document.dispatchEvent(new Event("visibilitychange")); });
    await p.waitForTimeout(500);
    const h0 = await frames(p);
    await p.waitForTimeout(1500);
    assert.strictEqual(await frames(p) - h0, 0, "0 frames while the tab is hidden");
    await p.evaluate(() => { delete document.hidden; document.dispatchEvent(new Event("visibilitychange")); });
    await settle(p, h0 + 1);

    const one = await p.evaluate(() => {
      const same = [];
      for (let i = 0; i < 3; i++) { window.canvas.remove(); document.getElementById("host").append(window.canvas); same.push(window.createRenderer(window.canvas, window.opts) === window.R); }
      return { same, canvases: document.querySelectorAll("canvas").length, contexts: window.__gl.size };
    });
    assert.deepStrictEqual(one, { same: [true, true, true], canvases: 1, contexts: 1 }, "1 canvas and 1 context after 3 mounts");
    assert.deepStrictEqual(errs, [], "no page errors");

    const calm = await open(b, base, { reducedMotion: "reduce" });
    await calm.p.evaluate(mount);
    await calm.p.evaluate(() => window.go("working", { layout: true }));
    await settle(calm.p, 1);
    await calm.p.waitForTimeout(1500);
    assert.strictEqual(await frames(calm.p), 1, "reduced motion: one frame per change, a working creature holds its pose");
    assert.deepStrictEqual(calm.errs, [], "no page errors under reduced motion");
    return fps;
  } finally { await b.close(); }
}

async function soft(base) {
  const b = await chromium.launch({ headless: true, args: ["--mute-audio", "--disable-3d-apis"] });
  try {
    const { p, errs } = await open(b, base);
    assert.strictEqual(await p.evaluate(mount), true, "without 3D the renderer is still");
    await p.evaluate(() => window.go("working", { layout: true }));
    await p.waitForTimeout(1500);
    assert.strictEqual(await frames(p), 1, "software: exactly 1 frame for the first apply");
    await p.evaluate(() => window.go("idle", { rooms: ["r1"], people: ["a1"] }));
    await p.waitForTimeout(1500);
    assert.strictEqual(await frames(p), 2, "software: exactly 1 frame per apply");
    const hit = await p.evaluate(() => { const q = window.R.project("a1"); return [q.ok, window.R.pick(q.x, q.y)]; });
    assert.deepStrictEqual(hit, [true, "a1"], "the still renderer projects and picks like the WebGL one");
    assert.deepStrictEqual(errs, [], "no page errors without 3D");
  } finally { await b.close(); }
}

const srv = serveStatic(() => undefined);
(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  try {
    const fps = await gpu(base);
    await soft(base);
    console.log(`ok office gl: 54 exports, 0 frames at rest, ${fps.toFixed(2)} fps working, still renderer 1 frame per apply, 1 canvas and 1 context after 3 mounts`);
  } finally { srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
