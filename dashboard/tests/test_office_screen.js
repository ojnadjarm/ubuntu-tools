// Office screen (T1601-05): #org is the office. One canvas in the stage, the staff list names every seat, team, member and worker,
// a Message link per seat, the Sessions table, a list button opens the card of the same name, no sideways scroll at 5 widths,
// the still note without a graphics card, one canvas through #chat and back, a swipe on the stage keeps the sub-tab,
// /api/office read at most once per 5 s and never while hidden. With the GPU flags: the real chunks, every room and creature in view, no tags, a tap on a creature and on a room sign, + − Reset.
// Staff cards (T1601-08): every Roster row label per runner kind, a seat's runner rows, gold when bad, dim when off, the Unassigned room.
// Run: node tests/test_office_screen.js   (fixture API only; SHOTS=<dir> adds 1366 shots: home, 2 angles, a card, night)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan"];
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const NIGHT = { ...FIX, sessions: [], agents: { ...FIX.agents, subagents: [] }, staff: FIX.staff.map((t) => ({ ...t, members: t.members.map((m) => ({ ...m, state: "idle", health: "ok" })) })) };
const SEATS = FIX.seats.map((s) => s.name), TEAMS = FIX.staff.map((t) => t.name), MEMBERS = FIX.staff.flatMap((t) => t.members.map((m) => m.name));
const WORKERS = ["agent-T9001", "agent-T9004", "T9002", "T9003-04"];
const NOTE = "Still picture: this browser has no graphics acceleration. The list below is live.";
const SIZES = [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]];
const reads = [];
let night = false;
const srv = serveStatic((u) => {
  if (u === "/api/status") return STATUS;
  if (u === "/api/office") { reads.push(Date.now()); return night ? NIGHT : FIX; }
  if (u === "/api/org") return { seats: FIX.seats, sessions: FIX.sessions, hidden: 0 };
  if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
  if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
});

async function open(b, base, w, h, touch) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, ...(touch ? { hasTouch: true, isMobile: true } : {}) })).newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.addInitScript(() => {
    window.__gl = new Set();
    const get = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (kind, ...a) { const c = get.call(this, kind, ...a); if (c && /webgl/.test(kind) && this.id !== "gl") window.__gl.add(this); return c; };
  });
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForSelector(".office .olist [data-who]", { timeout: 20000 });
  await p.waitForSelector(".office .stage canvas", { timeout: 20000 });
  return { p, errs };
}
const canvases = (p) => p.$$eval(".office .stage canvas", (l) => l.length);
const cardName = (p) => p.$eval("#office-card:popover-open h2", (h) => h.firstChild.textContent.trim());
/* A one-finger swipe of dx pixels starting on the element sel. */
const swipe = (p, sel, dx) => p.$eval(sel, (el, d) => {
  const r = el.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + Math.min(r.height / 2, 200);
  const ev = (type, cx) => el.dispatchEvent(new TouchEvent(type, { bubbles: true, changedTouches: [new Touch({ identifier: 1, target: el, clientX: cx, clientY: y })] }));
  ev("touchstart", x); ev("touchend", x + d);
}, dx);

/* The list path at one width, drawn without 3D. */
async function soft(b, base, [w, h]) {
  const touch = w < 900, { p, errs } = await open(b, base, w, h, touch);
  assert.strictEqual(await canvases(p), 1, `${w}: 1 canvas in the stage`);
  const text = await p.$eval(".office .olist", (e) => e.innerText);
  for (const n of [...SEATS, ...TEAMS, ...MEMBERS, ...WORKERS]) assert.ok(text.includes(n), `${w}: the list names ${n}`);
  const who = await p.$$eval(".office .olist [data-who]", (l) => l.map((e) => e.dataset.who));
  assert.ok(who.length >= SEATS.length + TEAMS.length + MEMBERS.length + WORKERS.length, `${w}: a button per seat, team, member and worker, got ${who.length}`);
  assert.deepStrictEqual(await p.$$eval(".office .olist a.msg", (l) => l.map((a) => a.getAttribute("href"))), FIX.seats.map((s) => "#chat?ch=dm-" + ["owner", s.id].sort().join("--")), `${w}: a Message link per seat, none for staff`);
  /* The Sessions rows of the card a list button opens (or of the room its card's line opens): name and text. */
  const ses = async (id, home) => {
    await p.click(`.office .olist [data-who="${id}"]`);
    if (home) await p.click("#office-card .home [data-who]");
    const r = await p.$$eval("#office-card .cpart", (l) => { const x = l.find((c) => c.querySelector("h3").textContent === "Sessions"); return x ? [...x.querySelectorAll("dt")].map((d) => d.textContent + " " + d.nextElementSibling.textContent) : []; });
    await p.keyboard.press("Escape");
    return r;
  };
  const rows = [...await ses("vass"), ...await ses("tiny-epic-narrator"), ...await ses("a0000000000000002", true)];
  await p.click('.office .olist [data-who="orchestrator"]');
  const own = await p.$$eval("#office-card .cbody > dl dt", (l) => l.filter((d) => d.textContent === "Folder").length);
  await p.keyboard.press("Escape");
  assert.strictEqual(rows.length + own, FIX.sessions.length, `${w}: every session on a card (no boards, owner 2026-11-10): ${JSON.stringify(rows)}`);
  assert.ok(rows.some((r) => /^protected project /.test(r) && !/[~/]/.test(r)), `${w}: the protected session row says protected project, no folder`);
  for (const [id, name] of [["maintenance", "Briar"], ["mooblox", "Mossfang"], ["team-quality", "Quality"], ["pid1003", "agent-T9001"]]) {
    await p.click(`.office .olist [data-who="${id}"]`);
    assert.strictEqual(await cardName(p), name, `${w}: the list button of ${id} opens the card named ${name}`);
    const r = await p.$eval("#office-card", (c) => { const q = c.getBoundingClientRect(); return [q.left, q.right, q.top, q.bottom, innerWidth, innerHeight]; });
    assert.ok(r[0] >= 0 && r[1] <= r[4] && r[2] >= 0 && r[3] <= r[5], `${w}: the card of ${id} is inside the viewport: ${r}`);
    if (id === "mooblox") assert.strictEqual(await p.$eval("#office-card a.btn", (a) => a.getAttribute("href")), "#chat?ch=dm-mooblox--owner", `${w}: a seat's card has its Message link`);
    if (id === "maintenance") assert.strictEqual(await p.$$eval("#office-card a.btn", (l) => l.length), 0, `${w}: a staff card has no Message link`);
    if (id === "team-quality") assert.strictEqual(await p.$$eval("#office-card [data-who]", (l) => l.length), 4, `${w}: a team card lists its 4 members`);
    await p.keyboard.press("Escape");
    assert.strictEqual(await p.$$eval("#office-card:popover-open", (l) => l.length), 0, `${w}: Escape closes the card`);
    assert.strictEqual(await p.evaluate(() => location.hash), "#org", `${w}: Escape on a card stays on the Office`);
  }
  assert.deepStrictEqual(await p.$eval(".office .stage .still", (e) => [getComputedStyle(e).display !== "none", e.textContent.trim()]), [true, NOTE], `${w}: software shows the still note`);
  assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), w, `${w}: no sideways scroll`);
  if (touch) {
    await swipe(p, ".office .stage canvas", -160);
    await p.waitForTimeout(300);
    assert.strictEqual(await p.evaluate(() => location.hash), "#org", `${w}: a swipe on the stage keeps the sub-tab`);
  }
  await p.click('#subs a[data-nav="chat"]');
  await p.waitForSelector(".chat", { timeout: 15000 });
  await p.click('#subs a[data-nav="org"]');
  await p.waitForSelector(".office .stage canvas", { timeout: 15000 });
  assert.deepStrictEqual([await canvases(p), await p.evaluate(() => document.querySelectorAll("canvas:not(#gl)").length)], [1, 1], `${w}: #chat and back, still 1 canvas`);
  if (touch) {
    await swipe(p, ".office .olist", -160);
    await p.waitForSelector(".chat", { timeout: 15000 });
  }
  assert.deepStrictEqual(errs, [], `${w}: no page errors`);
  await p.context().close();
}

const LAST4 = ["Last run", "Last exit", "Took", "Report"];
const STAFF = {
  "sentinel-digest": ["Status", "Schedule", "Next run", ...LAST4],
  sentinel: ["Status", "Schedule", "Unit", "Next run", "Last check", "Result", "Took", "Fallback last ran", "Fallback report"],
  "fleet-backup": ["Status", "Schedule", "Unit", "Next run", "Last check", "Result", "Took", "Report"],
  "night-relay": ["Status", "Schedule", "Unit", "Up since", "Unit state", "Tmux", "Report"],
  "ci-fix": ["Status", "Schedule", ...LAST4],
  "tiny-epic-narrator": ["Workers", "Folder", "Started by", "Last active", ...LAST4],
  vass: ["Workers", "Folder", "Last active"],
};
/* The staff cards on the list path: row labels per runner kind, the id line, gold when bad, dim when off, no Message, the Unassigned room. */
async function staffCards(b, base, [w, h]) {
  const { p, errs } = await open(b, base, w, h, w < 900);
  assert.ok(!/\bhello\b/.test(await p.$eval(".office .olist", (e) => e.innerText)), `${w}: a hidden agent is not in the list`);
  for (const [id, labels] of Object.entries(STAFF)) {
    await p.click(`.office .olist [data-who="${id}"]`);
    const c = await p.$eval("#office-card:popover-open", (e) => ({ dt: [...e.querySelectorAll(".cbody > dl dt")].map((d) => d.textContent), gold: [...e.querySelectorAll(".cbody > dl dd.bad")].map((d) => d.previousElementSibling.textContent),
      ln: e.querySelector(".area") && e.querySelector(".area").textContent, dim: !!e.querySelector(".cfig.dim"), msg: e.querySelectorAll("a.btn").length, box: e.getBoundingClientRect().toJSON() }));
    assert.deepStrictEqual(c.dt, labels, `${w}: the card of ${id} has the Roster's rows`);
    assert.ok(c.box.left >= 0 && c.box.right <= w && c.box.top >= 0 && c.box.bottom <= h, `${w}: the card of ${id} is inside the viewport`);
    if (id in FIX.seats.reduce((o, s) => ({ ...o, [s.id]: 1 }), {})) assert.strictEqual(c.msg, 1, `${w}: a seat keeps its Message`);
    else assert.deepStrictEqual([c.ln.split(" · ")[0], c.msg], [id, 0], `${w}: a staff card names its id under its name and has no Message`);
    if (id === "sentinel") assert.deepStrictEqual(c.gold, ["Status", "Result"], `${w}: a bad bash timer's pill and result are gold`);
    if (id === "night-relay") assert.deepStrictEqual(c.gold, [], `${w}: a healthy service has no gold`);
    assert.strictEqual(c.dim, id === "ci-fix", `${w}: only the off agent's card is dim (${id})`);
    await p.keyboard.press("Escape");
  }
  await p.click('.office .olist [data-who="team-unassigned"]');
  assert.deepStrictEqual(await p.$eval("#office-card:popover-open", (e) => [e.querySelector("h2").firstChild.textContent, [...e.querySelectorAll(".roll [data-who]")].map((x) => x.dataset.who)]),
    ["Unassigned", ["night-relay"]], `${w}: the Unassigned room's card rolls the agent no team names`);
  assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), w, `${w}: no sideways scroll with a staff card`);
  assert.deepStrictEqual(errs, [], `${w}: no page errors on the staff cards`);
  await p.context().close();
}

/* The poll: with someone working at most 1 read per 5 s, none while hidden. */
async function poll(b, base) {
  const { p } = await open(b, base, 1366, 768);
  const n0 = reads.length;
  await p.waitForTimeout(16000);
  const mine = reads.slice(n0 - 1), gaps = mine.slice(1).map((t, i) => t - mine[i]);
  assert.ok(gaps.length >= 2, `someone works: /api/office is read again within 16 s (${gaps.length} reads)`);
  assert.ok(Math.min(...gaps) >= 4500, `at most 1 /api/office read per 5 s, gaps ${gaps}`);
  await p.evaluate(() => { Object.defineProperty(document, "hidden", { get: () => true, configurable: true }); document.dispatchEvent(new Event("visibilitychange")); });
  await p.waitForTimeout(1000);
  const h0 = reads.length;
  await p.waitForTimeout(7000);
  assert.strictEqual(reads.length - h0, 0, "no /api/office read while hidden");
  await p.context().close();
  return gaps;
}

/* The 3D path: real chunks, labels, a tap on a creature, the stage buttons, one context for the visit. */
async function gpu(base) {
  const b = await chromium.launch({ headless: true, args: ["--mute-audio", ...GPU] }), shots = process.env.SHOTS;
  try {
    const { p, errs } = await open(b, base, 1366, 768);
    await p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1, null, { timeout: 30000 });
    const st = await p.evaluate(() => ({ still: window.__office.still, ...window.__office.stats() }));
    assert.deepStrictEqual([st.still, st.chunks], [false, 12], "with a graphics card: not still, the fixture's 12 chunks");
    assert.strictEqual(await p.$eval(".office .stage .still", (e) => getComputedStyle(e).display), "none", "no still note with a graphics card");
    const shown = await p.evaluate((ids) => { const c = document.querySelector(".office .stage canvas"); return ids.filter((id) => { const q = window.__office.project(id); return q.ok && q.x >= 0 && q.x <= c.clientWidth && q.y >= 0 && q.y <= c.clientHeight; }); },
      ["orchestrator", "mooblox", "vass", "discord", "tiny-epic-narrator", "mosaico", "pool", "room-mooblox", "team-operations", "team-quality", "team-improvement", "team-unassigned"]);
    for (const id of ["orchestrator", "mooblox", "vass", "discord", "tiny-epic-narrator", "mosaico", "pool", "room-mooblox", "team-operations", "team-quality", "team-improvement", "team-unassigned"]) assert.ok(shown.includes(id), "in view for a click: " + id);
    assert.strictEqual(await p.$$eval(".otag, .otags", (l) => l.length), 0, "no tags (owner 2026-11-10)");
    const at = (id) => p.evaluate((i) => { const q = window.__office.project(i), r = document.querySelector(".office .stage canvas").getBoundingClientRect(); return { x: r.left + q.x, y: r.top + q.y, ok: q.ok }; }, id);
    const m = await at("maintenance");
    await p.mouse.click(m.x, m.y + 14);
    assert.strictEqual(await cardName(p), "Briar", "a tap on a creature opens its card");
    if (shots) await p.screenshot({ path: `${shots}/card-1366.png` });
    await p.keyboard.press("Escape");
    const qs = await p.evaluate(() => { const R = window.__office, q = R.project("team-quality"), c = document.querySelector(".office .stage canvas").getBoundingClientRect();
      for (let r = 0; r < 40; r += 2) for (let a = 0; a < 6.28; a += 0.4) { const x = Math.round(q.x + r * Math.cos(a)), y = Math.round(q.y + r * Math.sin(a) * 0.5); if (R.pick(x, y) === "team-quality") return [c.left + x, c.top + y]; }
      return null; });
    assert.ok(qs, "the Quality room's sign is on screen");
    await p.mouse.click(...qs);
    assert.strictEqual(await cardName(p), "Quality", "a tap on a room's sign opens its card");
    await p.keyboard.press("Escape");
    if (shots) await p.screenshot({ path: `${shots}/home-1366.png` });
    const on = () => p.evaluate(() => window.__office.project("mooblox"));
    const a0 = await on();
    await p.click("#office-zin");
    await p.waitForTimeout(400);
    const a1 = await on();
    assert.ok(Math.hypot(a1.x - a0.x, a1.y - a0.y) > 3, "+ moves the view");
    await p.click("#office-reset");
    await p.waitForTimeout(400);
    const a2 = await on();
    assert.ok(Math.hypot(a2.x - a0.x, a2.y - a0.y) < 1, "Reset view restores it");
    const tag0 = (await on()).x;
    const c = await p.$eval(".office .stage canvas", (e) => { const r = e.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; });
    for (const [k, dx, dy] of [[1, 380, -40], [2, -700, 90]]) {
      await p.mouse.move(c[0], c[1]); await p.mouse.down(); await p.mouse.move(c[0] + dx / 2, c[1] + dy / 2, { steps: 4 }); await p.mouse.move(c[0] + dx, c[1] + dy, { steps: 4 }); await p.mouse.up();
      await p.waitForTimeout(500);
      if (k === 1) {
        assert.ok(Math.abs((await on()).x - tag0) > 3, "a drag turns the office (mooblox moves on screen)");
        assert.strictEqual(await p.$$eval("#office-card:popover-open", (l) => l.length), 0, "a drag opens no card");
      }
      if (shots) await p.screenshot({ path: `${shots}/angle${k}-1366.png` });
    }
    const f0 = await p.evaluate(() => window.__office.stats().frames);
    await p.click('#subs a[data-nav="chat"]');
    await p.waitForSelector(".chat", { timeout: 15000 });
    await p.click('#subs a[data-nav="org"]');
    await p.waitForSelector(".office .stage canvas", { timeout: 15000 });
    await p.waitForFunction((n) => window.__office.stats().frames > n, f0, { timeout: 10000 });
    assert.deepStrictEqual([await canvases(p), await p.evaluate(() => window.__gl.size)], [1, 1], "#chat and back: 1 canvas, 1 office context, a new frame");
    assert.deepStrictEqual(errs, [], "no page errors with a graphics card");
    await p.context().close();

    const ph = await open(b, base, 400, 850, true);
    await ph.p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1, null, { timeout: 30000 });
    const hud = await ph.p.$$eval(".office .stage .hud button", (l) => l.map((x) => { const r = x.getBoundingClientRect(); return Math.min(r.width, r.height); }));
    assert.ok(hud.length === 3 && Math.min(...hud) >= 44, `the 3 stage buttons are 44 px or more on touch: ${hud}`);
    assert.strictEqual(await ph.p.evaluate(() => document.documentElement.scrollWidth), 400, "no sideways scroll at 400 with a graphics card");
    assert.deepStrictEqual(ph.errs, [], "no page errors on the phone");
    await ph.p.context().close();

    if (shots) {
      night = true;
      const n = await open(b, base, 1366, 768);
      await n.p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1, null, { timeout: 30000 });
      await n.p.waitForTimeout(800);
      await n.p.screenshot({ path: `${shots}/night-1366.png` });
      night = false;
    }
    return st;
  } finally { night = false; await b.close(); }
}

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ headless: true, args: ["--disable-3d-apis", "--mute-audio"] });
  let gaps;
  try {
    if (process.env.ONLY === "staff") { for (const s of [SIZES[0], SIZES[2]]) await staffCards(b, base, s); console.log("ok staff cards"); srv.close(); return; }
    for (const s of SIZES) await soft(b, base, s);
    for (const s of [SIZES[0], SIZES[2]]) await staffCards(b, base, s);
    gaps = await poll(b, base);
  } finally { await b.close(); }
  try {
    const st = await gpu(base);
    console.log(`ok office screen · 5 widths: 1 canvas, ${SEATS.length} seats + ${TEAMS.length} teams + ${MEMBERS.length} members + ${WORKERS.length} workers named, ${SEATS.length} Message links, ${FIX.sessions.length} Sessions rows, 4 cards, still note, no sideways scroll, #chat and back 1 canvas, stage swipe stays · poll gaps ${gaps.join("/")} ms, 0 hidden · GPU: ${st.chunks} chunks, ${st.verts} vertices, labels, tap, + − Reset, 1 context, hud 44 px`);
  } finally { srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
