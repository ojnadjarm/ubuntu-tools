// Office: every worker a manager's card counts is drawn in its room and seen (T1630, owner 2026-11-11: "Aplication Coches saids it has
// 1 worker running but I don't see it on the Office"). One crew list feeds the card's count and the room's worker avatars: placed in the
// scene graph, each one on screen at the home view (not hidden behind decor), more workers than desks all placed, the still-mode list
// naming the same number; the server counts neither the manager's own run nor a finished worker.
// Run: node tests/test_office_workers_drawn.js   (fixture API only; ONLY=server|model|gpu|still; SHOTS=<dir> saves the room at 5 widths)
"use strict";
const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");
const { pathToFileURL } = require("url");
const { chromium, serveStatic } = require("./lib/browser");

const ROOT = path.join(__dirname, ".."), JS = path.join(ROOT, "static", "next", "js");
const FIX = require("./fixtures/office.json");
const NOW = Date.parse("2026-11-10T15:00:00Z"), T0 = NOW / 1000 - 27 * 60;
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const MATCH = { mooblox: "~/agents/po-mooblox", discord: "~/agents/po-discord", "tiny-epic-narrator": "~/agents/po-tiny-epic-narrator", mosaico: "~/agents/po-mosaico", "aplicacion-coche": "~/agents/po-aplicacion-coche" };
const GPU = ["--mute-audio", "--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan"];
const ink = (text) => ({ w: text.length * 7 + 2, h: 14, runs: [...text].flatMap((c, i) => (c === " " ? [] : [4, 7, 10].map((y) => [1 + i * 7, 6 + i * 7, y]))) });
const ONLY = process.env.ONLY || "";
let n = 0;
const ok = (name) => console.log("ok " + ++n + " " + name);

/* The fixture with the live org's 8 seat rooms (Aplicación Coche in the last bay, as on 2026-11-11) and k po-work workers in seat's folder (as sessions.live and agents.job_rows give them), passed through office.crews. */
function scenario(seat, k, drop = []) { return scenarios([seat], k, drop); }
function scenarios(list, k, drop = []) {
  const P = JSON.parse(JSON.stringify(FIX));
  for (const [id, name, area] of [["spidey-pr-dashboard", "Gloam", "Spidey PR Dashboard"], ["narrador-interactivo-ia", "Murmur", "Narrador Interactivo IA"], ["aplicacion-coche", "Nettle", "Aplicación Coche"]])
    P.seats.push({ id, name, rank: "Manager", role: "manager", parent: "discord", area, wake: "po-inbox" });
  P.sessions = P.sessions.filter((s) => !drop.includes(s.pid));
  for (const [j, seat] of list.entries()) for (let i = 0; i < k; i++) {
    const pid = 2100 + j * 20 + i, t = "T97" + String(i).padStart(2, "0"), since = T0 + i * 60;
    P.sessions.push({ seat, state: "working", since, pid, parent: "discord", name: `agent-po-${seat}-${t}`, cwd: "~/agents/po-" + seat, started_by: `po-${seat}-${t}` });
    P.agents.subagents.push({ id: "pid" + pid, label: `po-${seat}-${t}`, type: "session", started: new Date(since * 1000).toISOString(), last: since, state: "working", doing: "", report: "" });
  }
  const seats = P.seats.map((s) => ({ ...s, match: MATCH[s.id] || null }));
  const py = "import sys, json; sys.path.insert(0, sys.argv[1]); import server; from dash.services import office\n" +
    "d = json.load(sys.stdin); s, a = office.crews(d['seats'], d['sessions'], d['subagents']); print(json.dumps({'sessions': s, 'subagents': a}))";
  const out = JSON.parse(execFileSync("python3", ["-c", py, ROOT], { input: JSON.stringify({ seats, sessions: P.sessions, subagents: P.agents.subagents }), encoding: "utf8" }));
  return { ...P, sessions: out.sessions, agents: { ...P.agents, subagents: out.subagents } };
}
const ROOMS = ["mooblox", "discord", "tiny-epic-narrator", "spidey-pr-dashboard", "mosaico", "narrador-interactivo-ia", "aplicacion-coche"];
const CASES = [
  { id: "coche-1-worker", seat: "aplicacion-coche", P: () => scenario("aplicacion-coche", 1) },
  { id: "coche-3-workers", seat: "aplicacion-coche", P: () => scenario("aplicacion-coche", 3) },
  { id: "1-worker", seat: "mosaico", P: () => scenario("mosaico", 1) },
  { id: "3-workers", seat: "mosaico", P: () => scenario("mosaico", 3) },
  { id: "8-workers", seat: "mosaico", P: () => scenario("mosaico", 8) },
  { id: "idle-worker", seat: "tiny-epic-narrator", P: () => scenario("tiny-epic-narrator", 0, [1002]) },
  { id: "live-run-0", seat: "tiny-epic-narrator", P: () => scenario("tiny-epic-narrator", 0, [1003, 1004]) },
  { id: "every-room-2", seats: ROOMS, P: () => scenarios(ROOMS, 2, [1003, 1004]) },
].map((C) => ({ seats: [C.seat], ...C }));

/* The number of workers a seat's card counts (its Workers row); a free seat's "Free to talk · N workers running" says the same. */
function counted(c) {
  const n = +((/^(\d+) workers?/.exec((c.rows.find((r) => r[0] === "Workers") || [])[1]) || [0, 0])[1]), run = /· (\d+) workers? running/.exec(c.state.text);
  assert.ok(!run || +run[1] === n, `"${c.state.text}" agrees with Workers ${n}`);
  return n;
}

/* sessions.live over a temp registry: the manager's own run (this test's node pid) and two workers it started (python's pid), one finished. */
function server() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "t1630-")), folder = path.join(dir, "po-x");
  fs.mkdirSync(folder);
  const py = `import sys, os, json; sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2]); import server; import sessions; from dash.services import office
reg, folder = sys.argv[3], sys.argv[4]
start = lambda pid: open("/proc/%d/stat" % pid).read().rsplit(")", 1)[1].split()[19]
me, boss = os.getpid(), os.getppid()
rows = [("boss", boss, start(boss), "agent-po-x", "busy"), ("live", me, start(me), "agent-po-x-T1", "busy"), ("done", me, "1", "agent-po-x-T2", "busy")]
for f, pid, ps, name, st in rows:
    json.dump({"pid": pid, "procStart": ps, "cwd": folder, "name": name, "status": st, "startedAt": 0}, open(os.path.join(reg, f + ".json"), "w"))
seat = {"id": "x", "name": "X", "role": "manager", "parent": "discord", "wake": "po-inbox"}
live = sessions.live(reg, [dict(seat, match=folder)])
s, _ = office.crews([dict(seat, match="~/agents/po-x")], live, [])
print(json.dumps(s))`;
  try {
    const S = JSON.parse(execFileSync("python3", ["-c", py, ROOT, path.join(ROOT, "..", "lib"), dir, folder], { encoding: "utf8", env: { ...process.env, CLAUDE_SESSIONS_DIR: dir } }));
    assert.deepStrictEqual(S.map((s) => [s.seat, s.parent, s.name]).sort(), [["x", "discord", "agent-po-x"], [null, "x", "T1"]].sort(), "live: the manager's run on its seat, 1 live worker under it, the finished T2 gone: " + JSON.stringify(S));
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
  ok("server: sessions.live + office.crews give 1 worker under the seat; the manager's own run stays on its seat, a finished worker is gone");
}

/* Every case under node: the card's count, its Workers running rows and the room chunk's worker actors are the same people. */
async function model() {
  const load = (f) => import(pathToFileURL(path.join(JS, "office", f)).href);
  const [{ build }, { plan }, { chunk }, { decode }, { THEME }, F] = await Promise.all(["model.js", "layout.js", "build/index.js", "kit.js", "theme.js", "fields.js"].map(load));
  const kit = decode(JSON.parse(fs.readFileSync(path.join(ROOT, "static", "next", "office", "kit.json"), "utf8")));
  for (const C of CASES) for (const seat of C.seats) {
    const M = build(C.P(), { now: NOW, needs: false }), R = M.rooms.find((r) => r.id === seat), card = F.card(M.who[seat], NOW), want = counted(card);
    const crew = R.people.slice(1), actors = chunk(seat, M, plan(M), THEME, kit, ink).actors.filter((a) => a.role === "worker");
    assert.strictEqual(actors.length, want, `${C.id}: ${actors.length} worker avatars placed, the card says "${card.state.text}"`);
    assert.deepStrictEqual(actors.map((a) => a.id).sort(), crew.map((p) => p.id).sort(), `${C.id}: the avatars are the room's crew`);
    assert.deepStrictEqual(actors.map((a) => [a.id, a.pose]).sort(), crew.map((p) => [p.id, p.pose]).sort(), `${C.id}: each in its own pose`);
    const part = card.parts.find((x) => x.h === "Workers running") || { rows: [], more: 0 };
    if (card.state.text.startsWith("Free")) assert.strictEqual(part.rows.length + part.more, want, `${C.id}: one Workers running row (or "+N more") per counted worker`);
    const c = plan(M).cells[seat];
    assert.ok(actors.every((a) => Math.abs(a.x - c.x) < c.w / 2 && Math.abs(a.z - c.z) < c.d / 2), `${C.id}: every worker inside the room`);
    assert.strictEqual(new Set(actors.map((a) => a.x.toFixed(2) + "," + a.z.toFixed(2))).size, actors.length, `${C.id}: no two workers on one spot`);
  }
  ok("model: placed worker avatars = card count for " + CASES.map((C) => C.id).join(", ") + " (8 workers > 6 desks all placed)");
}

/* A page on #org serving payload P at w×h; resolves once the office has drawn its first view. */
async function office(b, P, w, h, scale = 1) {
  const srv = serveStatic((u) => {
    if (u === "/api/status") return STATUS;
    if (u === "/api/office") return P;
    if (u === "/api/org") return { seats: P.seats, sessions: P.sessions, hidden: 0 };
    if (u === "/api/agents") return { ...P.agents, agents: [], roster: [] };
    if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
  });
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  const ctx = await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: scale });
  await ctx.clock.setFixedTime(NOW);
  const p = await ctx.newPage();
  p.errs = []; p.on("pageerror", (e) => p.errs.push(String(e)));
  p.done = async () => { await ctx.close(); srv.close(); };
  await p.goto("http://127.0.0.1:" + srv.address().port + "/#org", { waitUntil: "load" });
  await p.waitForSelector('.office .olist [data-who="orchestrator"]', { state: "attached", timeout: 20000 });
  return p;
}

/* With a graphics card at the home view, 1920, 1366 and 400: each counted worker shows at least half its own pixels. */
async function gpu() {
  const b = await chromium.launch({ headless: true, args: GPU });
  try {
    for (const [w, h] of [[1920, 1080], [1366, 768], [400, 850]]) for (const C of CASES) {
      const P = C.P(), M = (await import(pathToFileURL(path.join(JS, "office", "model.js")).href)).build(P, { now: NOW, needs: false });
      const ids = M.rooms.filter((r) => C.seats.includes(r.id)).flatMap((r) => r.people.slice(1).map((x) => x.id)), p = await office(b, P, w, h);
      await p.waitForFunction(() => window.__office && window.__office.stats().chunks > 5 && !window.__office.stats().pending && window.__office.stats().frames > 0, null, { timeout: 30000 });
      assert.strictEqual(await p.evaluate(() => window.__office.still), false, "a graphics card draws the office");
      const seen = await p.evaluate((ids) => ids.map((id) => [id, window.__office.seen(id)]), ids);
      const hid = seen.filter(([, s]) => !(s.alone > 20 && s.seen >= 0.5 * s.alone)).map(([id, s]) => `${id} ${s.seen}/${s.alone} px`);
      if (process.env.DIAG) { console.log(w, C.id, JSON.stringify(seen)); await p.done(); continue; }
      assert.deepStrictEqual(hid, [], `${w}x${h} ${C.id}: workers hidden at the home view`);
      assert.deepStrictEqual(p.errs, []);
      await p.done();
    }
  } finally { await b.close(); }
  ok("gpu 1920, 1366, 400: every worker of " + CASES.map((C) => C.id).join(", ") + " shows ≥ 50 % of its pixels at the home view");
}

/* Still mode (no WebGL): the seat's list names as many workers as its card counts. */
async function still() {
  const b = await chromium.launch({ headless: true, args: ["--disable-3d-apis", "--mute-audio"] }), F = await import(pathToFileURL(path.join(JS, "office", "fields.js")).href);
  try {
    for (const C of CASES) {
      const P = C.P(), M = (await import(pathToFileURL(path.join(JS, "office", "model.js")).href)).build(P, { now: NOW, needs: false }), p = await office(b, P, 400, 850);
      for (const seat of C.seats) {
        const got = await p.$$eval(`.office .olist .seat[data-seat="${seat}"] .hang li`, (L) => L.length);
        assert.strictEqual(got, counted(F.card(M.who[seat], NOW)), `${C.id} ${seat}: still list names ${got} workers`);
      }
      await p.done();
    }
  } finally { await b.close(); }
  ok("still 400: the seat's list names as many workers as the card counts, every case");
}

/* The owner's room (Aplicación Coche) with 1 worker at 5 widths (DPR 2): the page and a close crop around the room's name board. */
async function shots(dir) {
  fs.mkdirSync(dir, { recursive: true });
  const b = await chromium.launch({ headless: true, args: GPU });
  try {
    for (const [w, h] of [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]]) {
      const p = await office(b, CASES[0].P(), w, h, 2);
      await p.waitForFunction(() => window.__office && !window.__office.stats().pending && window.__office.stats().frames > 0, null, { timeout: 30000 });
      await p.waitForTimeout(500);
      const st = await p.$eval(".office .stage", (e) => { const r = e.getBoundingClientRect(); return [r.left + scrollX, r.top + scrollY]; });
      const at = await p.evaluate((id) => window.__office.project("room-" + id), CASES[0].seat), s = Math.max(110, w / 9);
      await p.screenshot({ path: path.join(dir, `office-${w}.png`) });
      await p.screenshot({ path: path.join(dir, `room-${w}.png`), clip: { x: Math.max(0, st[0] + at.x - s), y: Math.max(0, st[1] + at.y - s * 0.6), width: 2 * s, height: 2 * s } });
      assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), w, `${w}: no sideways scroll`);
      await p.done();
    }
  } finally { await b.close(); }
  ok("shots in " + dir);
}

(async () => {
  if (!ONLY || ONLY === "server") server();
  if (!ONLY || ONLY === "model") await model();
  if (!ONLY || ONLY === "gpu") await gpu();
  if (!ONLY || ONLY === "still") await still();
  if (process.env.SHOTS) await shots(process.env.SHOTS);
  console.log(`ok test_office_workers_drawn: ${n} checks`);
})().catch((e) => { console.error("FAIL " + (e && e.stack || e)); process.exit(1); });
