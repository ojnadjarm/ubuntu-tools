// Office name boards (T1601-17c, owner 2026-11-10: "something similar to the servers + screen approach is the way"): every room (seat, team, pool, CEO)
// has exactly one board built into its own chunk (two racks, a screen between them, upright, on the room's floor, moving with the room's cell); no name on
// the floor; no HTML label over the canvas; a click or a 400 px tap on a board opens its room's card (the CEO's opens the CEO's); the pointer shows a hand;
// a drag from a board turns the office and opens nothing; capitals are at least 11 px tall at the default 1920 camera; a board is a 44 px target at 400.
// Run: node tests/test_office_signs.js   (fixture API only; ONLY=pure|400|1920)
"use strict";
process.env.TZ = "UTC";
const assert = require("assert");
const path = require("path");
const { pathToFileURL } = require("url");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan", "--mute-audio"];
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const NOW = Date.parse("2026-11-10T15:00:00Z"), ONLY = process.env.ONLY || "", MIN_TEXT = 11, TAP = 44;
const JS = path.join(__dirname, "..", "static", "next", "js");
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
const ink = (text) => ({ w: text.length * 7 + 2, h: 14, runs: [...text].flatMap((c, i) => (c === " " ? [] : [4, 7, 10].map((y) => [1 + i * 7, 6 + i * 7, y]))) });
let n = 0, ROOMS = [];
const ok = (name) => console.log("ok " + ++n + " " + name);

/* The builders under node: one upright board per room chunk, inside the room's cell, moving with it; no lettering on the floor. */
async function pure() {
  const Mo = await load("office/model.js"), L = await load("office/layout.js"), Bd = await load("office/build/index.js"), { THEME } = await load("office/theme.js"), { decode } = await load("office/kit.js"), { DOT } = await load("office/build/props.js");
  const kit = decode(require("../static/next/office/kit.json")), M = Mo.build(FIX, { now: NOW, needs: false }), P = L.plan(M), rooms = [M.ceo, ...M.rooms, ...M.staff];
  const far = JSON.parse(JSON.stringify(P));
  for (const c of Object.values(far.cells)) { c.x += 5; c.z += 3; }
  for (const R of rooms) {
    const c = Bd.chunk(R.id, M, P, THEME, kit, ink), signs = c.labels.filter((l) => l.quad), s = signs[0], cell = P.cells[R.id], up = R.kind === "ceo" ? 1.34 : 0;
    assert.strictEqual(signs.length, 1, R.id + ": exactly one board");
    assert.strictEqual(s.who || s.id, R.kind === "ceo" ? R.id : R.sign, R.id + ": the board opens its room's card");
    assert.ok(M.who[s.who || s.id], R.id + ": the card exists");
    const [a, b, d, e] = s.quad;
    assert.ok(Math.abs(a[1] - b[1]) < 1e-6 && Math.abs(d[1] - e[1]) < 1e-6 && d[1] - a[1] > 0.4 && Math.hypot(e[0] - a[0], e[2] - a[2]) < 1e-6, R.id + ": the screen stands upright");
    assert.ok(a[1] - up > 0.2 && d[1] - up < 2.5, R.id + ": the screen hangs between floor and wall top");
    for (const q of s.quad) assert.ok(Math.abs(q[0] - cell.x) <= cell.w / 2 + 0.2 && Math.abs(q[2] - cell.z) <= cell.d / 2 + 0.3, R.id + ": the board stands in its room's cell");
    const feet = [a, b].map((q) => { let best = 1e9; for (let i = 0; i < c.position.length; i += 3) if (Math.hypot(c.position[i] - q[0], c.position[i + 2] - q[2]) < 0.6) best = Math.min(best, c.position[i + 1]); return best; });
    assert.ok(feet.every((y) => Math.abs(y - up) < 0.02), R.id + ": a rack stands on the floor at each end of the screen " + feet);
    const dots = c.quads.filter((q) => q.kind === DOT);
    assert.ok(dots.length > 3 && dots.every((q) => Math.abs(q.p[0][1] - q.p[3][1]) > 1e-4), R.id + ": the name is lettered upright, none on the floor");
    assert.ok(c.lamps.some((l) => Math.hypot(l.x - s.pos[0], l.y - s.pos[1], l.z - s.pos[2]) < 0.6 && l.i > 0), R.id + ": the screen lights its room");
    const moved = Bd.chunk(R.id, M, far, THEME, kit, ink).labels.find((l) => l.quad);
    assert.ok(moved.quad.every((q, i) => Math.abs(q[0] - s.quad[i][0] - 5) < 1e-6 && Math.abs(q[2] - s.quad[i][2] - 3) < 1e-6 && q[1] === s.quad[i][1]), R.id + ": the board moves with its room");
  }
  ROOMS = rooms.map((R) => (R.kind === "ceo" ? "sign-" + R.id : R.sign));
  ok(`${rooms.length} rooms (seat, team, pool, CEO): one upright board each, racks on the floor, in the room's cell, moving with the room, lit, no floor lettering`);
}

/* Opens #org at w×h with the GPU, waits for the first frame. */
async function open(b, base, w, h) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1, hasTouch: w < 900 })).newPage(), errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1 && !window.__office.stats().pending, null, { timeout: 30000 });
  await p.waitForTimeout(500);
  return { p, errs };
}
/* Per board: the page point on it nearest its centre that picks its card 4 px clear of any other target (a creature may stand in front), the height of its capitals in px, and the box of the canvas pixels that pick it. */
const measure = (p, ids) => p.evaluate((ids) => {
  const c = document.querySelector(".office .stage canvas").getBoundingClientRect(), R = window.__office, out = {};
  for (const id of ids) {
    const q = R.project(id), t = R.project(id + "/cap0"), u = R.project(id + "/cap1"), who = id.replace(/^sign-/, "");
    let at = null;
    for (let r = 0; r < 30 && !at; r += 2) for (let a = 0; a < 6.28 && !at; a += 0.4) {
      const x = Math.round(q.x + r * Math.cos(a)), y = Math.round(q.y + r * Math.sin(a) * 0.5);
      if ([[0, 0], [4, 0], [-4, 0], [0, 4], [0, -4]].every(([dx, dy]) => R.pick(x + dx, y + dy) === who)) at = [x, y];
    }
    let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
    for (let y = Math.round(q.y) - 60; y <= q.y + 60; y++) for (let x = Math.round(q.x) - 90; x <= q.x + 90; x++) if (R.pick(x, y) === who) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
    out[id] = { ok: q.ok && !!at, page: at && [Math.round(c.left) + at[0], Math.round(c.top) + at[1]], cap: Math.hypot(t.x - u.x, t.y - u.y), w: x1 - x0 + 1, h: y1 - y0 + 1 };
  }
  return out;
}, ids);
const card = (p) => p.evaluate(() => { const c = document.getElementById("office-card"); return c && c.matches(":popover-open") ? c.dataset.for : null; });
const view = (p, id) => p.evaluate((id) => window.__office.project(id), id);

async function screen(b, base, w, h) {
  const { p, errs } = await open(b, base, w, h), m = await measure(p, ROOMS), caps = Object.values(m).map((s) => s.cap);
  const dom = await p.evaluate(() => { const st = document.querySelector(".office .stage"), c = st.querySelector("canvas").getBoundingClientRect(); return { tags: document.querySelectorAll(".otag, .otags, .osign").length, top: document.elementFromPoint(c.left + c.width / 2, c.top + c.height / 2).tagName, canvases: st.querySelectorAll("canvas").length }; });
  assert.deepStrictEqual(dom, { tags: 0, top: "CANVAS", canvases: 1 }, `${w}: no HTML label over the canvas`);
  assert.ok(Object.values(m).every((s) => s.ok), `${w}: every board is on screen at the default camera`);
  ok(`${w}: ${ROOMS.length} boards on screen in the one canvas, 0 HTML labels`);
  const small = Object.entries(m).filter(([, s]) => s.w < TAP || s.h < TAP).map(([id, s]) => `${id} ${s.w}x${s.h}`);
  assert.deepStrictEqual(small, [], `${w}: every board is a ${TAP} px target`);
  ok(`${w}: every board picks over at least ${TAP}×${TAP} px (smallest ${Math.min(...Object.values(m).map((s) => Math.min(s.w, s.h)))} px)`);
  console.log(`# ${w}: capital height at the default camera: min ${Math.min(...caps).toFixed(1)} px, max ${Math.max(...caps).toFixed(1)} px`);
  if (w > 900) {
    assert.ok(Math.min(...caps) >= MIN_TEXT, `${w}: capitals at least ${MIN_TEXT} px: ${JSON.stringify(Object.fromEntries(Object.entries(m).map(([k, s]) => [k, +s.cap.toFixed(1)])))}`);
    ok(`${w}: capitals of every name at least ${MIN_TEXT} px tall (min ${Math.min(...caps).toFixed(1)})`);
    await p.mouse.move(...m["team-quality"].page);
    await p.waitForTimeout(120);
    assert.ok(await p.$eval(".office .stage canvas", (c) => c.classList.contains("hot")), "hover on a board: pointer cursor");
    ok(`${w}: the pointer over a board is a hand`);
  }
  for (const [id, who] of [["team-quality", "team-quality"], ["room-vass", "room-vass"], ["pool", "pool"], ["sign-orchestrator", "orchestrator"]]) {
    if (w < 900) await p.touchscreen.tap(...m[id].page); else await p.mouse.click(...m[id].page);
    assert.strictEqual(await card(p), who, `${w}: ${id} opens the card of ${who}`);
    await p.keyboard.press("Escape");
  }
  ok(`${w}: a ${w < 900 ? "tap" : "click"} on a team, seat, pool and CEO board opens that room's card`);
  const before = await view(p, "team-quality"), [x, y] = m["team-quality"].page;
  await p.mouse.move(x, y); await p.mouse.down(); await p.mouse.move(x + 40, y, { steps: 4 }); await p.mouse.move(x + 90, y, { steps: 4 }); await p.mouse.up();
  await p.waitForTimeout(200);
  const after = await view(p, "team-quality");
  assert.ok(Math.hypot(after.x - before.x, after.y - before.y) > 10 && (await card(p)) === null, `${w}: a drag from a board turns the office and opens nothing`);
  ok(`${w}: a drag from a board turns the office, no card`);
  assert.deepStrictEqual(errs, []);
  await p.context().close();
}

(async () => {
  await pure();
  if (ONLY === "pure") return;
  const srv = serveStatic((u) => {
    if (u === "/api/status") return STATUS;
    if (u === "/api/office") return FIX;
    if (u === "/api/org") return { seats: FIX.seats, sessions: FIX.sessions, hidden: 0 };
    if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
    if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
  });
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + srv.address().port, b = await chromium.launch({ headless: true, args: GPU });
  try { for (const [w, h] of [[400, 850], [1920, 1080]]) if (!ONLY || ONLY === String(w)) await screen(b, base, w, h); }
  finally { await b.close(); srv.close(); }
  console.log(`ok test_office_signs: ${n} checks`);
})().catch((e) => { console.error("FAIL " + (e && e.stack || e)); process.exit(1); });
