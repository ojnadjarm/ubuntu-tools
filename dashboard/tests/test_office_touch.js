// Office phone gestures (T1601-11), driven by real touch events (CDP Input.dispatchTouchEvent) at 400×850 and 768×1024, DPR 2, with a graphics card:
// one finger sideways turns, one finger up or down scrolls the page and leaves the view alone, a pinch zooms, two fingers dragged tilt,
// a tap opens the card, Reset view restores, frames stop within 1 s of release.
// Run: node tests/test_office_touch.js   (fixture API only; SHOTS=<dir> adds 400 px shots: start, turned, zoomed, card)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan"];
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const REST = { ...FIX, sessions: [], agents: { ...FIX.agents, subagents: [] }, staff: FIX.staff.map((t) => ({ ...t, members: t.members.map((m) => ({ ...m, state: "idle", health: "ok" })) })) };
const IDS = ["orchestrator", "mooblox", "discord", "mosaico", "pool", "team-operations", "team-quality", "team-improvement"];
const SIZES = [[400, 850], [768, 1024]];
let rest = false;
const srv = serveStatic((u) => {
  if (u === "/api/status") return STATUS;
  if (u === "/api/office") return rest ? REST : FIX;
  if (u === "/api/org") return { seats: FIX.seats, sessions: FIX.sessions, hidden: 0 };
  if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
  if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
});

/* Opens #org on a touch phone of w×h at DPR 2 and waits for the first 3D frame. */
async function open(b, base, w, h) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 2, hasTouch: true, isMobile: true })).newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForSelector(".office .stage canvas", { timeout: 20000 });
  await p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1, null, { timeout: 30000 });
  await p.waitForTimeout(700);
  return { p, errs, cdp: await p.context().newCDPSession(p) };
}
/* A real gesture: every finger goes from its first point to its second in n moves, then all lift. */
async function drag(p, cdp, fingers, n = 10) {
  const at = (k) => fingers.map(([a, b], id) => ({ id, x: Math.round(a[0] + (b[0] - a[0]) * k), y: Math.round(a[1] + (b[1] - a[1]) * k) }));
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: at(0) });
  for (let i = 1; i <= n; i++) { await p.waitForTimeout(16); await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: at(i / n) }); }
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
}
/* The view as numbers, from the projected room labels: turn (radians), size (pixels), flat (vertical over horizontal spread), centre. */
const view = (p) => p.evaluate((ids) => {
  const q = ids.map((i) => window.__office.project(i)), n = q.length, cx = q.reduce((s, a) => s + a.x, 0) / n, cy = q.reduce((s, a) => s + a.y, 0) / n;
  const sx = Math.sqrt(q.reduce((s, a) => s + (a.x - cx) ** 2, 0) / n), sy = Math.sqrt(q.reduce((s, a) => s + (a.y - cy) ** 2, 0) / n);
  return { turn: Math.atan2(q[5].y - q[1].y, q[5].x - q[1].x), size: Math.hypot(sx, sy), flat: sy / sx, cx, cy, frames: window.__office.stats().frames, scroll: scrollY, hash: location.hash };
}, IDS);
const box = (p) => p.$eval(".office .stage canvas", (e) => { const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; });
const same = (a, b) => Math.abs(a.turn - b.turn) < 0.002 && Math.abs(a.size - b.size) < 0.5 && Math.abs(a.cx - b.cx) < 0.5 && Math.abs(a.cy - b.cy) < 0.5;
const settle = (p) => p.waitForTimeout(350);
/* A spot [x, y] in the stage where every x + d of ds is bare canvas (no tag or button under a finger) at y and at y - span. */
const spot = async (p, ds, span = 0) => {
  const at = await p.evaluate(([ds, span]) => {
    const c = document.querySelector(".office .stage canvas"), r = c.getBoundingClientRect(), lo = Math.min(...ds), hi = Math.max(...ds);
    const bare = (x, y) => ds.every((d) => document.elementFromPoint(x + d, y) === c);
    for (let y = Math.min(r.bottom, innerHeight) - 24; y - span > r.top + 24; y -= 6) for (let x = r.left + 12 - lo; x + hi < r.right - 12; x += 6) if (bare(x, y) && bare(x, y - span)) return [x, y];
    return null;
  }, [ds, span]);
  assert.ok(at, "a bare spot on the canvas for " + ds);
  return at;
};

/* Every gesture at one size; returns the numbers it measured. */
async function gestures(b, base, [w, h], shots) {
  const { p, errs, cdp } = await open(b, base, w, h), shot = (name) => (shots && w === 400 ? p.screenshot({ path: `${shots}/${name}-400.png` }) : null);
  const c = await box(p), v0 = await view(p);
  assert.ok(c.y >= 0 && c.y + c.h <= h, `the stage is whole on the first screen at ${w}`);
  await shot("start");

  const quarter = Math.round(c.h / 4), strokes = [quarter, quarter, quarter, Math.round(c.h) - 3 * quarter];
  let [mx, my] = await spot(p, [0, -quarter]);
  await drag(p, cdp, [[[mx, my], [mx - quarter, my]]]);
  await settle(p);
  const v1 = await view(p);
  assert.ok(Math.abs(v1.turn - v0.turn) > 0.15, `${w}: one finger sideways turns the office (${(v1.turn - v0.turn).toFixed(3)} rad)`);
  assert.deepStrictEqual([v1.scroll, v1.hash], [0, "#org"], `${w}: a sideways finger scrolls nothing and keeps the tab`);
  assert.strictEqual(await p.$$eval("#office-card:popover-open", (l) => l.length), 0, `${w}: a turn opens no card`);
  await shot("turned");
  for (const d of strokes.slice(1)) { [mx, my] = await spot(p, [0, -d]); await drag(p, cdp, [[[mx, my], [mx - d, my + 30]]]); await settle(p); }
  const vr = await view(p);
  assert.ok(Math.abs(vr.turn - v0.turn) < 0.05 && Math.abs(vr.size / v0.size - 1) < 0.03 && Math.abs(vr.flat / v0.flat - 1) < 0.03, `${w}: one finger only turns: the stage's height sideways is one full turn, with no tilt and no zoom: ${JSON.stringify([v0, vr])}`);
  [mx, my] = await spot(p, [0, -quarter]);
  await drag(p, cdp, [[[mx, my], [mx - quarter, my]]]);
  await settle(p);
  const vq = await view(p);

  [mx, my] = await spot(p, [0], 300);
  await drag(p, cdp, [[[mx, my], [mx, my - 300]]]);
  await settle(p);
  const v2 = await view(p);
  assert.ok(v2.scroll > 150, `${w}: one finger up scrolls the page (${v2.scroll} px)`);
  assert.ok(same(vq, v2), `${w}: the scroll leaves the view alone: ${JSON.stringify([vq, v2])}`);
  await drag(p, cdp, [[[mx, 200], [mx, 200 + v2.scroll + 200]]]);
  await settle(p);
  const v3 = await view(p);
  assert.strictEqual(v3.scroll, 0, `${w}: one finger down scrolls back`);
  assert.ok(same(vq, v3), `${w}: scrolling back leaves the view alone`);

  [mx, my] = await spot(p, [-40, 40], 120);
  await drag(p, cdp, [[[mx - 40, my], [mx - 40, my - 120]], [[mx + 40, my], [mx + 40, my - 120]]]);
  await settle(p);
  const vT = await view(p);
  assert.ok(Math.abs(vT.flat / v3.flat - 1) > 0.15, `${w}: two fingers dragged tilt (flat ${v3.flat.toFixed(3)} → ${vT.flat.toFixed(3)})`);
  assert.ok(Math.abs(vT.cx - v3.cx) < 0.03 * w, `${w}: a straight two-finger drag does not slide the office sideways (${(vT.cx - v3.cx).toFixed(1)} px)`);
  assert.strictEqual(vT.scroll, 0, `${w}: two fingers scroll nothing`);

  [mx, my] = await spot(p, [-110, -30, 30, 110]);
  await drag(p, cdp, [[[mx - 30, my], [mx - 110, my]], [[mx + 30, my], [mx + 110, my]]]);
  await settle(p);
  const v4 = await view(p);
  assert.ok(v4.size / vT.size > 1.5, `${w}: a pinch out zooms in (×${(v4.size / vT.size).toFixed(2)})`);
  assert.strictEqual(v4.scroll, 0, `${w}: a pinch scrolls nothing`);
  assert.strictEqual(await p.evaluate(() => visualViewport.scale), 1, `${w}: a pinch does not zoom the page`);
  await shot("zoomed");
  [mx, my] = await spot(p, [-110, -30, 30, 110]);
  await drag(p, cdp, [[[mx - 110, my], [mx - 30, my]], [[mx + 110, my], [mx + 30, my]]]);
  await settle(p);
  const v5 = await view(p);
  assert.ok(v5.size / v4.size < 0.67, `${w}: a pinch in zooms out (×${(v5.size / v4.size).toFixed(2)})`);

  await p.touchscreen.tap(...await p.$eval("#office-reset", (e) => { const r = e.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; }));
  await settle(p);
  const v7 = await view(p);
  assert.ok(same(v0, v7), `${w}: Reset view restores the first view: ${JSON.stringify([v0, v7])}`);

  const m = await p.evaluate(() => { const q = window.__office.project("maintenance"), r = document.querySelector(".office .stage canvas").getBoundingClientRect(); return [r.left + q.x, r.top + q.y + 10]; });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ id: 0, x: Math.round(m[0]), y: Math.round(m[1]) }] });
  await p.waitForTimeout(60);
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await p.waitForSelector("#office-card:popover-open", { timeout: 3000 });
  assert.strictEqual(await p.$eval("#office-card:popover-open h2", (e) => e.firstChild.textContent.trim()), "Briar", `${w}: a tap on a creature opens its card`);
  await shot("card");
  assert.ok(same(v7, await view(p)), `${w}: a tap leaves the view alone`);
  assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), w, `${w}: no sideways scroll`);
  assert.deepStrictEqual(errs, [], `${w}: no page errors`);
  await p.context().close();
  return { turn: +Math.abs(Math.atan2(Math.sin(v1.turn - v0.turn), Math.cos(v1.turn - v0.turn))).toFixed(2), scroll: v2.scroll, zoom: +(v4.size / vT.size).toFixed(2), tilt: +(vT.flat / v3.flat).toFixed(2) };
}

/* Frames after release: none from 1 s on when nobody works, the 8 fps acting clock when somebody does. */
async function release(b, base) {
  const out = [];
  for (const quiet of [true, false]) {
    rest = quiet;
    const { p, cdp } = await open(b, base, 400, 850), [mx, y0] = await spot(p, [-100, -30, 30, 100], 50), my = y0 - 50, f = () => p.evaluate(() => window.__office.stats().frames);
    const f0 = await f();
    await drag(p, cdp, [[[mx + 100, my], [mx - 100, my]]], 20);
    const f1 = await f();
    await drag(p, cdp, [[[mx - 30, my], [mx - 90, my + 50]], [[mx + 30, my], [mx + 90, my - 50]]], 20);
    await p.waitForTimeout(1000);
    const f2 = await f();
    await p.waitForTimeout(2000);
    const n = await f() - f2;
    assert.ok(f1 - f0 >= 5, `a drag draws frames (${f1 - f0})`);
    if (quiet) assert.strictEqual(n, 0, "nobody works: 0 frames from 1 s after release, for 2 s");
    else assert.ok(n >= 8 && n <= 20, `somebody works: the 8 fps clock after release, not the drag's rate (${n} frames in 2 s)`);
    out.push(n);
    await p.context().close();
  }
  rest = false;
  return out;
}

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port, b = await chromium.launch({ headless: true, args: ["--mute-audio", ...GPU] });
  try {
    const only = process.env.ONLY, got = [];
    for (const s of SIZES) if (!only || only === String(s[0])) got.push(await gestures(b, base, s, process.env.SHOTS));
    const fr = !only || only === "release" ? await release(b, base) : [];
    console.log(`ok office touch · ${got.map((g, i) => `${SIZES[i][0]}: turn ${g.turn} rad, scroll ${g.scroll} px, pinch ×${g.zoom}, tilt ×${g.tilt}`).join(" · ")} · tap → card, Reset restores · after release: ${fr[0]} frames in 2 s at rest, ${fr[1]} while 3 work`);
  } finally { rest = false; await b.close(); srv.close(); }
})().catch((e) => { console.error(e.message || e); process.exit(1); });
