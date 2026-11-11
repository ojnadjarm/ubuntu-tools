// Office managers and their detached workers (T1627, owner 2026-11-11: "Haven't we fix the managers yet?"): a manager whose own run ended
// while its po-work workers run reads "Free to talk · N workers running" with one glance row per worker, and those workers sit in its own
// room, none in the Desk pool; a manager with a live run reads working; at 400 px the card's × covers nothing in its top row.
// Run: node tests/test_office_manager_workers.js   (fixture API only, no GPU, no real units; ONLY=model|close|shots;
//      SHOTS=<dir> also saves the manager and Desk pool cards at 5 widths; RAW=1 serves the payload without office.crews, as before T1627)
"use strict";
const assert = require("assert");
const path = require("path");
const { execFileSync } = require("child_process");
const { pathToFileURL } = require("url");
const { chromium, serveStatic } = require("./lib/browser");

const ROOT = path.join(__dirname, ".."), JS = path.join(ROOT, "static", "next", "js");
const FIX = require("./fixtures/office.json");
const NOW = Date.parse("2026-11-10T15:00:00Z"), T0 = NOW / 1000 - 27 * 60;
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const MATCH = { orchestrator: "~", mooblox: "~/agents/po-mooblox", vass: "~/moodle-envs/vass/moodle", discord: "~/agents/po-discord",
  "tiny-epic-narrator": "~/agents/po-tiny-epic-narrator", mosaico: "~/agents/po-mosaico" };
const ONLY = process.env.ONLY || "", KINDS = ["orchestrator", "mosaico", "tiny-epic-narrator", "team-operations", "pool", "sentinel", "pid1101"];
let n = 0;
const ok = (name) => console.log("ok " + ++n + " " + name);

/* The fixture as sessions.live and agents.job_rows give it: Speckle (mosaico) has no run, two po-work workers sit in its folder. */
function raw() {
  const P = JSON.parse(JSON.stringify(FIX));
  for (const [pid, t, since] of [[1101, "T9101", T0], [1102, "T9102", T0 + 600]]) {
    P.sessions.push({ seat: "mosaico", state: "working", since, pid, parent: "discord", name: "agent-po-mosaico-" + t, cwd: "~/agents/po-mosaico", started_by: "po-mosaico-" + t });
    P.agents.subagents.push({ id: "pid" + pid, label: "po-mosaico-" + t, type: "session", started: new Date(since * 1000).toISOString().replace(/\.\d+Z$/, "Z"),
      last: since, state: "working", doing: "live session · pid " + pid, report: "" });
  }
  return P;
}

/* office.crews (server) over the raw fixture: the seats carry their org.json match, as compose() sees them. */
function served(P) {
  const seats = P.seats.map((s) => ({ ...s, match: MATCH[s.id] || null }));
  const py = "import sys, json; sys.path.insert(0, sys.argv[1]); import server; from dash.services import office\n" +
    "d = json.load(sys.stdin); s, a = office.crews(d['seats'], d['sessions'], d['subagents']); print(json.dumps({'sessions': s, 'subagents': a}))";
  const out = JSON.parse(execFileSync("python3", ["-c", py, ROOT], { input: JSON.stringify({ seats, sessions: P.sessions, subagents: P.agents.subagents }), encoding: "utf8" }));
  return { ...P, sessions: out.sessions, agents: { ...P.agents, subagents: out.subagents } };
}

async function model() {
  const load = (f) => import(pathToFileURL(path.join(JS, f)).href);
  const Mo = await load("office/model.js"), F = await load("office/fields.js"), Ti = await load("office/tier.js");
  const before = raw(), P = served(before);

  const ids = (L) => L.map((s) => s.pid || s.id);
  assert.deepStrictEqual(ids(P.sessions.filter((s) => s.seat === null && s.parent === "mosaico")), [1101, 1102], "crews: both po-work sessions sit under mosaico, no seat");
  assert.deepStrictEqual(P.sessions.filter((s) => s.parent === "mosaico").map((s) => [s.name, s.rank]), [["T9101", "Worker"], ["T9102", "Worker"]], "crews: named by ticket, rank Worker");
  assert.deepStrictEqual(P.sessions.filter((s) => s.pid !== 1101 && s.pid !== 1102), before.sessions.filter((s) => s.pid !== 1101 && s.pid !== 1102), "crews: every other session as given");
  assert.deepStrictEqual(ids(P.agents.subagents), ids(FIX.agents.subagents), "crews: the two po-work rows leave the sub-agents, pid1005 (a CEO session) stays");
  ok("server crews(): po-work sessions move under their seat as Workers named by ticket; their sub-agent rows go; the rest is untouched");

  const M = Mo.build(P, { now: NOW, needs: false }), lead = M.who.mosaico, room = M.rooms.find((r) => r.id === "mosaico"), pool = M.rooms.find((r) => r.id === "pool");
  assert.strictEqual(lead.state, "available");
  assert.notStrictEqual(lead.pose, "working");
  const c = F.card(lead, NOW), T = Ti.tiers(c), part = T.top.parts.find((x) => x.h === "Workers running");
  assert.strictEqual(c.state.text, "Free to talk · 2 workers running");
  assert.ok(part, "the Workers running part shows at a glance");
  assert.deepStrictEqual(part.rows.map((r) => r[0]), ["T9101", "T9102"]);
  assert.ok(/^since \d\d:\d\d · 27 min$/.test(part.rows[0][1]) && /^since \d\d:\d\d · 17 min$/.test(part.rows[1][1]), "each row: since HH:MM · minutes: " + JSON.stringify(part.rows));
  ok("manager with 0 runs + 2 po-work workers: Free to talk · 2 workers running, 2 glance rows (ticket, since, minutes)");

  assert.deepStrictEqual(room.people.filter((p) => p.role === "worker").map((p) => [p.id, p.name, p.pose]), [["pid1101", "T9101", "working"], ["pid1102", "T9102", "working"]]);
  assert.ok(Ti.tiers(F.card(room, NOW)).top.parts.find((x) => x.h === "Workers running").rows.length === 2, "the team's room card lists both workers at a glance");
  assert.ok(!pool.people.some((p) => /^pid110[12]$/.test(p.id) || /T910[12]/.test(p.name)), "Desk pool: no po-work worker");
  assert.ok(!JSON.stringify(F.card(pool, NOW)).includes("T910"), "Desk pool card: no po-work worker");
  assert.strictEqual(F.card(M.who.pid1101, NOW).sub, "Works for Speckle");
  ok("both workers are seated in mosaico's room (hard-hat workers), 0 in the Desk pool");

  const tiny = M.who["tiny-epic-narrator"], tc = F.card(tiny, NOW);
  assert.strictEqual(tiny.state, "working");
  assert.strictEqual(tiny.pose, "working");
  assert.ok(/^Now working · /.test(tc.state.text), tc.state.text);
  ok("manager with a live run (and its own workers): Now working");

  const R = Mo.build(before, { now: NOW, needs: false });
  assert.ok(R.rooms.find((r) => r.id === "pool").people.some((p) => p.id === "pid1101") && R.who.mosaico.state === "working", "the raw payload is the owner's bug: worker in the pool, manager working");
  ok("the raw payload (no crews) still shows the bug: worker in the Desk pool, manager working");
}

/* A page on #org at w×h with the list ready and the clock at NOW; page errors are kept on p.errs. */
async function office(b, base, w, h) {
  const ctx = await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  await ctx.clock.setFixedTime(NOW);
  const p = await ctx.newPage();
  p.errs = []; p.on("pageerror", (e) => p.errs.push(String(e)));
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForSelector('.office .olist [data-who="orchestrator"]', { state: "attached", timeout: 20000 });
  return p;
}
/* Opens the card of id from its list button, else through a chip of another card. */
const open = (p, id) => p.evaluate((id) => {
  const hide = () => { const o = document.getElementById("office-card"); if (o && o.matches(":popover-open")) o.hidePopover(); };
  const btn = (k) => { const q = `.office .olist [data-who="${CSS.escape(k)}"]`; return document.querySelector(q + ":not(.avb)") || document.querySelector(q); };
  hide();
  if (btn(id)) { btn(id).click(); return !!document.querySelector("#office-card:popover-open"); }
  for (const k of new Set([...document.querySelectorAll(".office .olist [data-who]")].map((e) => e.dataset.who))) {
    hide(); btn(k).click();
    const chip = document.querySelector(`#office-card [data-who="${CSS.escape(id)}"]`);
    if (chip) { chip.click(); return document.getElementById("office-card").dataset.for === id; }
  }
  return false;
}, id);

/* Every card at w×h with Details open, scrolled to its top, middle and end: the sticky × box overlaps no box of the card's content (rows, chips, lines, figure). */
async function clear(b, base, w, h) {
  const p = await office(b, base, w, h), out = [];
  for (const id of KINDS) {
    assert.ok(await open(p, id), `${w} ${id}: the card opens`);
    if (await p.$("#office-card .cdet")) await p.click("#office-card .cdet > summary");
    for (const at of [0, 0.5, 1]) {
      const hit = await p.$eval("#office-card", (c, at) => {
        c.scrollTop = at * (c.scrollHeight - c.clientHeight);
        const x = c.querySelector(".cx").getBoundingClientRect(), view = c.getBoundingClientRect();
        return [...c.querySelectorAll(".cfig, .cbody *")].filter((e) => !e.children.length || e.matches(".chip, dd, h2"))
          .map((e) => [e.tagName + "." + e.className, e.getBoundingClientRect()])
          .filter(([, b]) => b.width > 0 && b.bottom > view.top && b.top < view.bottom && b.left < x.right && b.right > x.left && b.top < x.bottom && b.bottom > x.top)
          .map(([k, b]) => `${k} ${Math.round(b.left)}-${Math.round(b.right)} vs × ${Math.round(x.left)}-${Math.round(x.right)}`);
      }, at);
      assert.deepStrictEqual(hit, [], `${w}x${h} ${id} scrolled ${at}: the × overlaps a row`);
    }
    out.push(id);
  }
  assert.deepStrictEqual(p.errs, []);
  ok(`${w}x${h}: Details open, scrolled top, middle, end: the × covers no row of ${out.join(", ")}`);
  await p.context().close();
}

/* The manager's and the Desk pool's cards at 5 widths, the same steps before and after. */
async function shots(b, base, dir) {
  for (const [w, h] of [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]]) {
    const p = await office(b, base, w, h);
    for (const id of ["mosaico", "pool"]) {
      await open(p, id);
      await p.waitForTimeout(300);
      await p.screenshot({ path: path.join(dir, `${id}-${w}.png`) });
    }
    assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), w, `${w}: no sideways scroll`);
    await p.context().close();
  }
  ok("shots in " + dir);
}

(async () => {
  if (!ONLY || ONLY === "model") await model();
  if (ONLY === "model") return console.log(`ok test_office_manager_workers: ${n} checks`);
  const FIXP = process.env.RAW ? raw() : served(raw());
  const srv = serveStatic((u) => {
    if (u === "/api/status") return STATUS;
    if (u === "/api/office") return FIXP;
    if (u === "/api/org") return { seats: FIXP.seats, sessions: FIXP.sessions, hidden: 0 };
    if (u === "/api/agents") return { ...FIXP.agents, agents: [], roster: [] };
    if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
  });
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + srv.address().port, b = await chromium.launch({ headless: true, args: ["--mute-audio"] });
  try {
    if (!ONLY || ONLY === "close") for (const [w, h] of [[400, 800], [1366, 768]]) await clear(b, base, w, h);
    if (process.env.SHOTS) await shots(b, base, process.env.SHOTS);
  } finally { await b.close(); srv.close(); }
  console.log(`ok test_office_manager_workers: ${n} checks`);
})().catch((e) => { console.error("FAIL " + (e && e.stack || e)); process.exit(1); });
