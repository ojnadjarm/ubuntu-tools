// Office avatar only (T1601-17, owner 2026-11-10: no boards, no tags): nothing over the 3D room at 400 and 1920 but the card a click opens;
// a click on a creature opens its card (its fields, a line naming its room, the room's running sub-agents), a click on a room's hung screen opens
// the room's card (members, next runs, sessions, held files, sub-agents; empty parts one quiet line); the card's × (44 px, named), Esc and a click
// outside close it; Recent 24 h is gone (owner addition 3); every other row the old boards carried sits on a card (mapping: ~/agent-work/research/2026-11-10/T1601/done/17.md).
// Text on the cards is escaped and the band line holds (ported from test_office_panels.js).
// Run: node tests/test_office_avatar_only.js   (fixture API only; ONLY=pure|400|1920|odd; SHOTS=<dir> adds a 1920 shot with the room card open)
"use strict";
process.env.TZ = "UTC";
const assert = require("assert");
const path = require("path");
const { pathToFileURL } = require("url");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan", "--mute-audio"];
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const NOW = Date.parse("2026-11-10T15:00:00Z"), ONLY = process.env.ONLY || "";
const JS = path.join(__dirname, "..", "static", "next", "js");
const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
const X = "<img src=x onerror=window.__pwn=1>", EVIL = JSON.parse(JSON.stringify(FIX));
EVIL.agents.claims[0] = `T9001 · dashboard/${X} · ${X} · 2026-11-10 16:21`;
EVIL.sessions[1].cwd = X;
EVIL.agents.subagents[1].doing = X;
let n = 0, evil = false;
const ok = (name) => console.log("ok " + ++n + " " + name);

/* Every board row is on a card: next runs, running, recent, sessions, claims. */
async function pure() {
  const Mo = await load("office/model.js"), F = await load("office/fields.js"), M = Mo.build(FIX, { now: NOW, needs: true }), C = (id) => F.card(M.who[id], NOW);
  const heads = (c) => (c.parts || []).map((x) => x.h), rowsOf = (c, h) => (c.parts.find((x) => x.h === h) || { rows: [] }).rows, chipsOf = (c, h) => (c.parts.find((x) => x.h === h) || { chips: [] }).chips;
  for (const r of M.panels.next) assert.ok(C(r.id).rows.some(([k, v]) => k === "Next run" && /^in /.test(v)), r.id + ": its card has its next run");
  for (const r of M.panels.running) { const c = C(r.id); assert.deepStrictEqual(["Type", "Running since", "Now"].map((k) => !!c.rows.find((x) => x[0] === k)), [true, true, true], r.id + ": agent rows"); }
  const ceo = C("orchestrator");
  assert.deepStrictEqual(heads(ceo), ["Needs you", "Sessions"]);
  assert.deepStrictEqual(rowsOf(ceo, "Needs you").length, 1, "needs-you on the CEO card");
  assert.ok(!("recent" in M.panels) && !JSON.stringify(Object.values(M.who).filter((p) => !p.people).map((p) => F.card(p, NOW))).includes("Recent"), "Recent 24 h is gone (owner 2026-11-10)");
  ok("Next runs → staff card · Next run; Running now → agent card · Type, Running since, Now; needs-you → CEO card; Recent 24 h nowhere");
  const where = (pick) => [...Object.values(M.who).filter((p) => p.people), ceo.parts && { info: M.ceo.people[0].raw.loose }].filter(Boolean).filter((r) => pick(r.info)).length;
  for (const s of M.panels.sessions) assert.strictEqual(where((I) => I.sessions.some((x) => x.id === s.id)) + (s.id === "pid1001" ? 1 : 0), 1, s.id + ": on one room card or the CEO's");
  for (const c of M.panels.claims) assert.strictEqual(where((I) => I.claims.includes(c)), 1, c.who + ": held on one room card or the CEO's");
  ok("Sessions and Claims rows: each on exactly one room's card (by its owner) or the CEO's (no avatar)");
  const seat = C("tiny-epic-narrator"), room = C("room-tiny-epic-narrator");
  assert.deepStrictEqual(heads(seat), ["Sessions", "Sub-agents running"]);
  assert.deepStrictEqual(seat.home, { id: "room-tiny-epic-narrator", text: "Team · Tiny Epic Narrator" });
  assert.match((seat.rows.find((x) => x[0] === "Files held") || [])[1], /^\d+ · T9001$/, "the seat holds T9001's files (its worker's claim)");
  assert.deepStrictEqual(rowsOf(seat, "Sessions").map((x) => x[0]), ["agent-po-tiny-epic-narrator", "agent-T9001", "agent-T9004"]);
  assert.deepStrictEqual([room.title, room.rank, heads(room)], ["Tiny Epic Narrator", "Project", ["Next runs", "Sessions", "Sub-agents running"]]);
  assert.deepStrictEqual(room.roll, ["tiny-epic-narrator", "pid1003", "pid1004"]);
  ok("seat card: its sessions, held files, sub-agents, the line to its room; the room card: members, next runs, sessions, held files, sub-agents");
  const pool = C("pool"), agent = C("a0000000000000002"), team = C("team-operations"), staff = C(M.panels.next[0].id);
  assert.deepStrictEqual(chipsOf(pool, "Sub-agents running").map((x) => x.name), ["T9002", "T9003-04"]);
  assert.ok(chipsOf(pool, "Sub-agents running").every((x) => /^since \S+ · /.test(x.note)), "a chip: running since and now");
  assert.match((pool.rows.find((x) => x[0] === "Files held") || [])[1], /^\d+ · T9003$/, "a claim by a ticket's base goes to its agent's room");
  assert.deepStrictEqual([agent.home.id, heads(agent)], ["pool", ["Sub-agents running"]]);
  assert.ok(rowsOf(team, "Next runs").length > 0 && rowsOf(team, "Sessions").length === 0, "a team: its next runs, no sessions");
  assert.deepStrictEqual(team.parts.find((x) => x.h === "Sessions").empty, "no sessions", "an empty part has its one quiet line");
  assert.strictEqual(staff.home.text.startsWith("Team · "), true);
  ok("pool and team cards; an agent and a staff card link their room; empty parts carry one quiet line");
}

/* Opens #org at w×h with the GPU, waits for the first frame. */
async function open(b, base, w, h) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 })).newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1 && !window.__office.stats().pending, null, { timeout: 30000 });
  await p.waitForTimeout(500);
  return { p, errs };
}
/* The page point of a creature's body (a bit under its head point) or of a sign's centre. */
const at = (p, id, down) => p.evaluate(([id, down]) => { const c = document.querySelector(".office .stage canvas").getBoundingClientRect(), q = window.__office.project(id); return q.ok ? [c.left + q.x, c.top + q.y + down] : null; }, [id, down]);
/* A page point on the sign of room id that picks the sign (not a creature in front of it), scanned round its centre, 4 px clear of any creature's target. */
const onSign = (p, id) => p.evaluate((id) => {
  const c = document.querySelector(".office .stage canvas").getBoundingClientRect(), R = window.__office, q = R.project(id);
  for (let r = 0; r < 40; r += 2) for (let a = 0; a < 6.28; a += 0.4) {
    const x = Math.round(q.x + r * Math.cos(a)), y = Math.round(q.y + r * Math.sin(a) * 0.5);
    if ([[0, 0], [4, 0], [-4, 0], [0, 4], [0, -4]].every(([dx, dy]) => R.pick(x + dx, y + dy) === id)) return [Math.round(c.left) + x, Math.round(c.top) + y];
  }
  return null;
}, id);
const card = (p) => p.evaluate(() => { const c = document.getElementById("office-card"), x = c && c.querySelector(".cx"); return c && c.matches(":popover-open") ? { who: c.dataset.for, heads: [...c.querySelectorAll("h3")].map((h) => h.textContent), quiet: c.querySelectorAll(".quiet").length,
  x: x && { label: x.getAttribute("aria-label"), w: x.offsetWidth, h: x.offsetHeight, top: x.getBoundingClientRect().top - c.getBoundingClientRect().top, right: c.getBoundingClientRect().right - x.getBoundingClientRect().right }, home: (c.querySelector(".home [data-who]") || {}).dataset } : null; });

async function shoot(b, base, w, h) {
  const { p, errs } = await open(b, base, w, h);
  const over = await p.evaluate(() => {
    const st = document.querySelector(".office .stage").getBoundingClientRect(), L = document.querySelector(".office .olist").getBoundingClientRect();
    return { tags: document.querySelectorAll(".otag, .otags").length, boards: document.querySelectorAll(".opanels, details.ob, [data-panel]").length, list: L.width * L.height, still: document.querySelector(".office .stage").dataset.still, sw: document.documentElement.scrollWidth, st: Math.round(st.width) };
  });
  assert.deepStrictEqual([over.tags, over.boards, over.list <= 1, over.still, over.sw <= w], [0, 0, true, "", true], `${w}: ${JSON.stringify(over)}`);
  ok(`${w}: 0 tags, 0 boards in the DOM, the list hidden from sight, 3D on, no sideways scroll`);
  const seat = await at(p, "mooblox", 12);
  await p.mouse.move(...seat);
  if (w > 900) { await p.waitForTimeout(100); assert.ok(await p.$eval(".office .stage canvas", (c) => c.classList.contains("hot")), "hover on a creature: pointer cursor"); }
  await p.mouse.click(...seat);
  let c = await card(p);
  assert.ok(c && c.who === "mooblox", `${w}: a click on the creature opens its card ${JSON.stringify(c)}`);
  assert.deepStrictEqual([c.x.label, c.x.w >= 44, c.x.h >= 44, c.x.top < 16, c.x.right < 16], ["Close", true, true, true, true], `${w}: the × top right ${JSON.stringify(c.x)}`);
  assert.deepStrictEqual([c.home.who, c.heads], ["room-mooblox", ["Sessions", "Sub-agents running"]], `${w}: seat card parts`);
  ok(`${w}: a click on a creature opens its card: × (44 px, "Close") top right, its parts, the line to its room`);
  await p.click("#office-card .home [data-who]");
  c = await card(p);
  assert.deepStrictEqual([c.who, c.heads, c.quiet], ["room-mooblox", ["Members", "Next runs", "Sessions", "Sub-agents running"], 3], `${w}: the room card from the line`);
  await p.click("#office-card .cx");
  assert.strictEqual(await card(p), null, `${w}: × closes`);
  const sign = await onSign(p, "team-operations");
  const team = () => p.mouse.click(...sign);
  assert.ok(sign, `${w}: the Operations sign is on screen`);
  await team();
  c = await card(p);
  assert.deepStrictEqual([c && c.who, c && c.heads], ["team-operations", ["Members", "Next runs", "Sessions", "Sub-agents running"]], `${w}: a click on the sign opens the team's card`);
  if (process.env.SHOTS && w === 1920) await p.screenshot({ path: path.join(process.env.SHOTS, "team-card-1920.png") });
  await p.keyboard.press("Escape");
  assert.strictEqual(await card(p), null, `${w}: Esc closes`);
  await team();
  await p.mouse.click(4, 4);
  assert.strictEqual(await card(p), null, `${w}: a click outside closes`);
  ok(`${w}: a click on a room's sign opens the team's card; Esc and a click outside close it`);
  assert.deepStrictEqual(errs, []);
  await p.context().close();
}

/* Text is data: markup in a claim, a folder and a sub-agent's step shows as text on every card (ported from test_office_panels.js); the band line (O1, R1). */
async function odd(b, base) {
  evil = true;
  const p = await (await b.newContext({ viewport: { width: 1366, height: 768 } })).newPage(), errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForSelector('.office .olist [data-who="tiny-epic-narrator"]', { state: "attached", timeout: 20000 });
  const band = await p.$eval(".office .band .bsum", (e) => e.textContent);
  assert.ok(/^\d+ Claude sessions? on this laptop, \d+ working · \d+ of \d+ staff on · next up .+ in .+$/.test(band), "O1, R1: the band line: " + band);
  const seen = [];
  for (const [id, home] of [["tiny-epic-narrator"], ["a0000000000000002"], ["a0000000000000002", true]]) {
    await p.$eval(`.office .olist [data-who="${id}"]`, (e) => e.click());
    if (home) await p.click("#office-card .home [data-who]");
    seen.push(await p.$eval("#office-card:popover-open", (c) => [c.querySelectorAll("img").length, (c.innerText.match(/<img src=x onerror=window\.__pwn=1>/g) || []).length > 0]));
    await p.keyboard.press("Escape");
  }
  assert.deepStrictEqual([seen, await p.evaluate(() => window.__pwn), errs], [[[0, true], [0, true], [0, true]], undefined, []], "text is escaped on the seat, agent and pool cards, never markup");
  ok("1366: markup in a claim, a folder and a sub-agent's step is text on the cards; the band line");
  await p.context().close();
  evil = false;
}

(async () => {
  if (!ONLY || ONLY === "pure") await pure();
  if (ONLY === "pure") return;
  const srv = serveStatic((u) => {
    if (u === "/api/status") return STATUS;
    if (u === "/api/office") return evil ? EVIL : FIX;
    if (u === "/api/org") return { seats: FIX.seats, sessions: FIX.sessions, hidden: 0 };
    if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
    if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
  });
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + srv.address().port, b = await chromium.launch({ headless: true, args: GPU });
  try {
    for (const [w, h] of [[400, 850], [1920, 1080]]) if (!ONLY || ONLY === String(w)) await shoot(b, base, w, h);
    if (!ONLY || ONLY === "odd") await odd(b, base);
  }
  finally { await b.close(); srv.close(); }
  console.log(`ok test_office_avatar_only: ${n} checks`);
})().catch((e) => { console.error("FAIL " + (e && e.stack || e)); process.exit(1); });
