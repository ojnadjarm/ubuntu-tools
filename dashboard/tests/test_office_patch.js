// Office patches (T1601-06): a state change rebuilds 1 room and not the scene, a day-night flip is colour only, builds are spread over frames, stats() counts.
// Node: a dry relight equals a fresh night build. GPU page (reduced motion: a frame only per change): the real builders, model and diff on the fixture.
// Screen (#org, no 3D): an equal payload draws nothing, an open card survives a seat change. Times are asserted only when quiet-gate (--gpu --wait 90) reads quiet.
// Run: node tests/test_office_patch.js   (PWC = path to playwright-core; PATCH_DEBUG=1 prints every case)
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan"];
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const js = (f) => import(path.join(__dirname, "../static/next/js/office", f));
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
const ink = (text) => ({ w: text.length * 7 + 2, h: 14, runs: [...text].flatMap((c, i) => (c === " " ? [] : [4, 7, 10].map((y) => [1 + i * 7, 6 + i * 7, y]))) });
const session = (o) => ({ seat: null, since: 1794322500, parent: "orchestrator", cwd: "~", started_by: "fixture", ...o });
const ASLEEP = { ...FIX, sessions: [], agents: { ...FIX.agents, subagents: [] }, staff: FIX.staff.map((t) => ({ ...t, members: t.members.map((m) => ({ ...m, state: "idle", health: "ok" })) })) };

let office = FIX;
const srv = serveStatic((u) => {
  if (u === "/api/status") return STATUS;
  if (u === "/api/office") return office;
  if (u === "/api/org") return { seats: FIX.seats, sessions: FIX.sessions, hidden: 0 };
  if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
  if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
});

/* Under node: every chunk of the fixture takes the other half of the day without geometry and ends equal to a fresh build. */
async function dry() {
  const [{ build }, { plan }, { chunk, stamp, HALL }, { decode }, { THEME }] = await Promise.all(["model.js", "layout.js", "build/index.js", "kit.js", "theme.js"].map(js));
  const kit = decode(JSON.parse(fs.readFileSync(path.join(__dirname, "../static/next/office/kit.json"), "utf8")));
  const M = build(FIX), P = plan(M), N = { ...M, night: !M.night }, ids = [HALL, ...Object.keys(P.cells)];
  for (const id of ids) {
    const c = chunk(id, M, P, THEME, kit, ink), want = chunk(id, N, P, THEME, kit, ink), pos = c.position;
    assert.strictEqual(stamp(id, M, P), stamp(id, N, P), id + ": day or night is not in the stamp");
    assert.strictEqual(c.relight(N, P), true, id + ": a flip needs no geometry");
    const col = c.bake(THEME.env.night, c.lamps);
    assert.ok(col === c.color && pos === c.position, id + ": the buffers are the same objects");
    assert.ok(same(col, want.color), id + ": re-lit colours equal a fresh night build");
    for (const k of ["lamps", "quads", "actors", "labels"]) assert.deepStrictEqual(c[k], want[k], id + ": " + k + " equal a fresh night build");
  }
  const seat = M.rooms.find((r) => r.kind === "seat" && r.pose === "sleep").id;
  const W = build({ ...FIX, sessions: [...FIX.sessions, session({ seat, state: "working", pid: 2001 })] });
  assert.notStrictEqual(stamp(seat, M, P), stamp(seat, W, P), "a seat that wakes has a new stamp");
  assert.strictEqual(ids.filter((id) => stamp(id, M, P) !== stamp(id, W, P)).length, 1, "and no other chunk has");
  return { seat, chunks: ids.length };
}

/* Runs in the page: the renderer on the real builders, wrapped to keep every built Chunk; go(payload) applies the model's own diff and waits until the queue is empty. */
async function mount() {
  const O = "/static/next/js/office/";
  const [gl, B, { build, diff }, { plan }, { THEME }, kitjs] = await Promise.all(["gl/index.js", "build/index.js", "model.js", "layout.js", "theme.js", "kit.js"].map((f) => import(O + f)));
  const kit = await kitjs.load(), canvas = document.createElement("canvas"), cap = {}, calls = [];
  Object.assign(canvas.style, { display: "block", width: "100%", height: "560px" });
  document.getElementById("host").append(canvas);
  const steps = (id, ...a) => { const st = B.steps(id, ...a), end = st.pop(); calls.push(id); return [...st, () => (cap[id] = end())]; };
  const R = createRenderer();
  function createRenderer() { return gl.createRenderer(canvas, { theme: THEME, kit, build: { steps, stamp: B.stamp } }); }
  let M = null, P = null;
  const frame = () => new Promise((ok) => requestAnimationFrame(ok)), refs = () => Object.fromEntries(Object.entries(cap).map(([id, c]) => [id, [c.position, c.color, c.index]]));
  /* Applies model m with patch (default: the model's diff) and reports counts, frames, long tasks and which chunks kept their buffers. */
  window.go = async (payload, force) => {
    const m = force ? { ...M, night: !M.night } : build(payload), patch = force ? { layout: false, night: true, rooms: Object.keys(P.cells), people: [], panels: [], line: false } : diff(M, m);
    const was = refs(), f0 = R.stats().frames, n0 = calls.length, t0 = performance.now();
    if (patch.layout) P = plan(m);
    M = m;
    R.apply(M, P, patch);
    let tasks = 0;
    while (R.stats().pending) { await frame(); tasks++; }
    for (let i = 0; i < 4; i++) await frame();
    await new Promise((ok) => setTimeout(ok, 150));
    const now = refs(), st = R.stats();
    return { patch, st, tasks, frames: st.frames - f0, built: calls.slice(n0), kept: Object.keys(was).filter((id) => now[id] && now[id].every((b, i) => b === was[id][i])),
      long: window.__lt.filter(([t]) => t >= t0 - 1).map(([, d]) => d), night: M.night, label: R.project(M.rooms[0].id).ok };
  };
  return R.still;
}

async function page(b, base, w, h) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, reducedMotion: "reduce" })).newPage(), errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.addInitScript(() => {
    window.__lt = [];
    new PerformanceObserver((l) => l.getEntries().forEach((e) => window.__lt.push([e.startTime, Math.round(e.duration)]))).observe({ type: "longtask", buffered: true });
  });
  await p.goto(base + "/api/blank");
  await p.setContent(`<!doctype html><html><body><div id="host"></div></body></html>`);
  assert.strictEqual(await p.evaluate(mount), false, "with the GPU flags the renderer is not still");
  return { p, errs };
}

/* The PLAN 4.3 table, row by row, on the real builders. */
async function patches(base, seat, total, quiet) {
  const b = await chromium.launch({ headless: true, args: ["--mute-audio", ...GPU] }), out = {};
  const worst = (r) => Math.max(0, ...r.long), log = (k, r) => { out[k] = r; if (process.env.PATCH_DEBUG) console.log(k, JSON.stringify({ ...r, patch: { ...r.patch, people: r.patch.people.length, rooms: r.patch.rooms.length }, kept: r.kept.length })); };
  const others = (r, n) => assert.strictEqual(r.kept.length, n, `${n} chunks keep their position, colour and index buffers, kept ${r.kept.length}`);
  try {
    const phone = await page(b, base, 400, 850), idle = { ...FIX, sessions: [...FIX.sessions, session({ seat, state: "idle", pid: 2001 })] };
    const first = await phone.p.evaluate((f) => window.go(f), idle);
    log("first", first);
    assert.deepStrictEqual([first.st.chunks, first.st.rebuilt, first.frames, first.label], [total, total, 1, true], "first build: every chunk, 1 frame at the end, labels have a point");
    assert.ok(first.tasks >= 3, `the first build is spread over frames, took ${first.tasks}`);
    if (quiet) assert.ok(worst(first) <= 120, `first build at 400 px: longest task ${worst(first)} ms (> 120): ${first.long}`);
    assert.deepStrictEqual(phone.errs, [], "no page errors at 400 px");
    await phone.p.context().close();

    const { p, errs } = await page(b, base, 1366, 768), go = (f, force) => p.evaluate(([x, y]) => window.go(x, y), [f, !!force]);
    await go(idle);
    const equal = await go(idle);
    log("equal", equal);
    assert.deepStrictEqual([equal.st.rebuilt, equal.st.relit, equal.frames, equal.built.length], [0, 0, 0, 0], "an equal payload: rebuilt 0, 0 new frames");

    const working = { ...FIX, sessions: [...FIX.sessions, session({ seat, state: "working", pid: 2001 })] }, work = await go(working);
    log("work", work);
    assert.deepStrictEqual([work.patch.rooms, work.built, work.st.rebuilt, work.st.chunks], [[seat], [seat], 1, total], "1 seat idle → working: rebuilt 1");
    others(work, total - 1);
    assert.ok(work.st.relit >= 1 && work.st.relit < total && work.frames >= 1, `the room and the rooms its lamps reach are re-lit (${work.st.relit}), not the scene`);
    if (quiet) assert.ok(work.st.ms <= 30 && !work.long.length, `1 seat changes state in ${work.st.ms.toFixed(1)} ms (> 30) or a long task: ${work.long}`);

    const worker = await go({ ...working, sessions: [...working.sessions, session({ state: "working", pid: 2002, parent: seat, name: "agent-T9100", rank: "Worker" })] });
    log("worker", worker);
    assert.deepStrictEqual([worker.built, worker.st.rebuilt], [[seat], 1], "a worker added: rebuilt 1");
    others(worker, total - 1);
    if (quiet) assert.ok(worker.st.ms <= 30 && !worker.long.length, `a worker arrives in ${worker.st.ms.toFixed(1)} ms (> 30) or a long task: ${worker.long}`);

    for (const k of ["dusk", "dawn"]) {
      const flip = await go(null, true);
      log(k, flip);
      assert.deepStrictEqual([flip.built, flip.st.rebuilt, flip.st.relit, flip.night], [[], 0, total, k === "dusk"], k + ": 0 geometry rebuilt, every chunk recoloured");
      others(flip, total);
      if (quiet) assert.ok(!flip.long.length, `${k}: a task over 50 ms: ${flip.long}`);
    }

    const added = await go({ ...working, seats: [...FIX.seats, { ...FIX.seats.find((s) => s.id === seat), id: "fixture-new", name: "New seat" }] });
    log("added", added);
    assert.ok(added.patch.layout && added.st.chunks === total + 1 && added.built.includes("hall") && added.built.includes("fixture-new") && added.st.rebuilt < total, `a seat added: the hall and the new room, not the scene (rebuilt ${added.st.rebuilt})`);
    if (quiet) assert.ok(!added.long.length, `a seat added: a task over 50 ms: ${added.long}`);

    await go({ ...ASLEEP, sessions: [session({ seat, state: "idle", pid: 2001 })] });
    const sleep = await go(ASLEEP);
    log("sleep", sleep);
    assert.deepStrictEqual([sleep.patch.night, sleep.night, sleep.built, sleep.st.relit], [true, true, [seat], total], "the last one falls asleep: its room is rebuilt, every chunk recoloured");
    if (quiet) assert.ok(!sleep.long.length, `the last one falls asleep: a task over 50 ms: ${sleep.long}`);
    assert.deepStrictEqual(errs, [], "no page errors");
    return out;
  } finally { await b.close(); }
}

/* The real screen without 3D (a frame only per apply): an open card survives a seat change, an equal payload draws nothing. */
async function screen(base, seat) {
  const b = await chromium.launch({ headless: true, args: ["--mute-audio"] });
  try {
    const p = await (await b.newContext({ viewport: { width: 1366, height: 768 } })).newPage(), errs = [];
    p.on("pageerror", (e) => errs.push(String(e)));
    await p.goto(base + "/#org", { waitUntil: "load" });
    await p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1, null, { timeout: 30000 });
    await p.click(`.office .olist button[data-who="${seat}"]`);
    await p.waitForSelector("#office-card:popover-open", { timeout: 5000 });
    office = { ...FIX, sessions: [...FIX.sessions, session({ seat, state: "working", pid: 2001 })] };
    await p.waitForFunction(() => window.__office.stats().rebuilt === 1 && !window.__office.stats().pending, null, { timeout: 20000 });
    assert.strictEqual(await p.$$eval("#office-card:popover-open", (l) => l.length), 1, "an open card survives a seat change");
    const f0 = await p.evaluate(() => window.__office.stats().frames);
    await p.waitForFunction(() => window.__office.stats().rebuilt === 0, null, { timeout: 20000 });
    await p.waitForTimeout(400);
    assert.strictEqual(await p.evaluate(() => window.__office.stats().frames) - f0, 0, "the next poll brings an equal payload: 0 new frames");
    assert.deepStrictEqual(errs, [], "no page errors on the screen");
  } finally { office = FIX; await b.close(); }
}

(async () => {
  const { seat, chunks } = await dry();
  const gate = spawnSync(process.env.HOME + "/agents/bin/quiet-gate", ["--gpu", "--wait", "90"], { encoding: "utf8" }), quiet = gate.status !== 3;
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  try {
    const r = await patches(base, seat, chunks, quiet);
    await screen(base, seat);
    const ms = (k) => r[k].st.ms.toFixed(1), top = (k) => Math.max(0, ...r[k].long);
    console.log(`ok office patch: first build ${r.first.tasks} tasks, ${ms("first")} ms · equal 0 rebuilt, 0 frames · seat rebuilt 1, relit ${r.work.st.relit}, ${ms("work")} ms · worker rebuilt 1, ${ms("worker")} ms · ` +
      `flip rebuilt 0, relit ${r.dusk.st.relit}, ${ms("dusk")} ms · seat added rebuilt ${r.added.st.rebuilt}, ${ms("added")} ms · long tasks first ${top("first")}, flip ${top("dusk")}, added ${top("added")} ms · card survives · ` +
      (quiet ? "times asserted" : "times not gated: " + (gate.stdout + gate.stderr).trim().split("\n").pop()));
  } finally { srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
