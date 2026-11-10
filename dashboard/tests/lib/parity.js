// Office parity (T1601-14) runner: the fixture server, the page at a width, its cards by clicks, the facts the rows assert, and the PARITY.md table.
"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path");
const { pathToFileURL } = require("url");
const { execFileSync } = require("child_process");
const { chromium, serveStatic } = require("./browser");
const { fixture, STATUS, setFix, iso, dmOf } = require("./parity-fixture");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan", "--mute-audio"];

let mode = "", say = false, hits = [], base = "";
const srv = serveStatic((u, res) => {
  hits.push([u, Date.now()]);
  const F = fixture(Date.now(), mode === "stale" ? "office source failed: agents" : "");
  if (u === "/api/status") return STATUS;
  if (u === "/api/office") {
    if (mode === "fail") { res.writeHead(500, { "Content-Type": "application/json" }); return res.end("{}"); }
    if (mode === "slow") { res.writeHead(200, { "Content-Type": "application/json" }); setTimeout(() => res.end(JSON.stringify(F)), 4000); return; }
    return F;
  }
  if (u === "/api/org") return { seats: F.seats, sessions: F.sessions, hidden: 0 };
  if (u === "/api/agents") return { ...F.agents, agents: [], roster: [] };
  if (u.startsWith("/api/chat")) return { messages: say ? [{ id: 9, from: "alpha", kind: "dm", ch: dmOf("alpha"), text: "zone 3 is in", t: iso(Date.now()) }] : [{ id: 1, from: "owner", kind: "dm", text: "hi" }], channels: [], wakes: { cap: 12, today: {} } };
});

/* Opens #org at width w, the renderer's apply wrapped so the test sees each model the scene draws. */
async function open(b, w, wait = true) {
  const p = await (await b.newContext({ viewport: { width: w, height: w < 600 ? 850 : 768 }, deviceScaleFactor: 1 })).newPage(), errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.addInitScript(() => {
    let R = null;
    window.__drawn = [];
    Object.defineProperty(window, "__office", { configurable: true, get: () => R, set: (v) => { R = v; const a = v.apply; v.apply = (M, plan, patch) => { window.__drawn.push({ t: Date.now(), M }); return a.call(v, M, plan, patch); }; } });
  });
  hits = [];
  await p.goto(base + "/#org", { waitUntil: "load" });
  if (wait) await p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1 && !window.__office.stats().pending, null, { timeout: 30000 });
  return { p, errs };
}

/* Every card reachable by clicks: list buttons, then the chips and room lines on each card; text, rows, links, state and bar of each. */
async function crawl(p) {
  const route = {}, cards = {};
  for (const id of await p.$$eval(".office .olist [data-who]", (b) => b.map((x) => x.dataset.who))) route[id] = route[id] || [id];
  const todo = Object.keys(route);
  while (todo.length) {
    const id = todo.shift();
    if (cards[id]) continue;
    const c = await p.evaluate((r) => {
      const card = document.getElementById("office-card");
      if (card && card.matches(":popover-open")) card.hidePopover();
      document.querySelector(`.office .olist [data-who="${CSS.escape(r[0])}"]`).click();
      for (const id of r.slice(1)) document.querySelector(`#office-card [data-who="${CSS.escape(id)}"]`).click();
      const c = document.getElementById("office-card"), q = (s) => [...c.querySelectorAll(s)], fold = c.querySelector("details.cdet");
      if (fold) fold.open = true;
      const rows = q("dl").flatMap((dl) => [...dl.children].filter((e) => e.tagName === "DT").map((dt) => [dt.textContent, dt.nextElementSibling.textContent, dt.nextElementSibling.className]));
      const st = c.querySelector(".st");
      return { id: c.dataset.for, title: c.querySelector("h2").textContent, text: c.innerText, rows, hrefs: q("a[href]").map((a) => a.getAttribute("href")), titles: q("[title]").map((e) => e.title),
        chips: q("[data-who]").map((e) => e.dataset.who), heads: q("h3").map((e) => e.textContent), st: st && st.className, stText: st && st.textContent, dim: !!c.querySelector(".dim"),
        bar: c.querySelector("progress") ? +c.querySelector("progress").value : null, fig: !!c.querySelector(".cfig svg, .cfig .fam") };
    }, route[id]);
    cards[id] = c;
    for (const k of c.chips) if (!route[k]) { route[k] = [...route[id], k]; todo.push(k); }
  }
  await p.evaluate(() => document.getElementById("office-card").hidePopover());
  return cards;
}

/* The facts of one width: band, cards, scene anchors and model, the talk, the badge, the poll gaps, the slow, failing and stale reads. */
async function facts(b, w) {
  const X = { claimRow: (await import(pathToFileURL(path.join(__dirname, "..", "..", "static", "next", "js", "claims.js")).href)).claimRow };
  const lib = path.join(__dirname, "..", "..", "..", "lib");
  X.hidden = JSON.parse(execFileSync("python3", ["-c", "import sys,json;sys.path.insert(0,sys.argv[1]);import staff;d=staff.load();print(json.dumps({'hidden':d['hidden'],'teams':staff.assign(d['teams'],d['hidden'],[{'name':'hello'}],[])}))", lib], { encoding: "utf8" }));
  mode = ""; say = false;
  const { p, errs } = await open(b, w);
  X.band = await p.$eval(".office .band .bsum", (e) => e.textContent);
  X.T = Date.now();
  X.cards = await crawl(p);
  X.anchor = await p.evaluate((ids) => Object.fromEntries(ids.map((id) => [id, window.__office.project(id).ok])), Object.keys(X.cards));
  X.M = await p.evaluate(() => { const M = window.__drawn[window.__drawn.length - 1].M; return { ceo: { live: M.ceo.live, pose: M.ceo.pose }, rooms: M.rooms.map((r) => ({ id: r.id, team: r.team })), who: Object.fromEntries(Object.entries(M.who).map(([k, v]) => [k, { pose: v.pose }])) }; });
  X.nest = await p.evaluate(() => Object.fromEntries([...document.querySelectorAll(".office .olist .seat[data-seat]")].map((s) => { const up = s.closest("li").parentElement.closest("li"); return [s.dataset.seat, up && up.querySelector(":scope > .seat").dataset.seat]; })));
  X.badge = await p.$eval('#subs a[data-nav="org"]', (a) => (a.querySelector("i:not(.live)") || {}).textContent || "");
  await p.evaluate(() => document.querySelector('.office .olist [data-who="alpha"]').click());
  const t1 = Date.now(); say = true;
  X.talkCard = await p.waitForFunction(() => document.querySelector("#office-card .st.talking"), null, { timeout: 8000 }).then(() => true, () => false);
  X.talkScene = await p.evaluate((t1) => window.__drawn.some((d) => d.t >= t1 && d.M.who.alpha.pose === "talking"), t1);
  say = false;
  hits = [];
  await p.waitForTimeout(20000);
  X.gaps = Object.fromEntries(["/api/office", "/api/agents"].map((u) => { const T = hits.filter((h) => h[0] === u).map((h) => h[1]); return [u, { n: T.length, max: Math.max(...T.slice(1).map((t, i) => t - T[i])) }]; }));
  assert.deepStrictEqual(errs, [], "page errors");
  await p.context().close();
  for (const m of ["stale", "slow", "fail"]) {
    mode = m;
    const o = await open(b, w, false);
    if (m === "stale") { await o.p.waitForSelector(".office .band .bsum", { timeout: 20000 }); X.staleBand = await o.p.$eval(".office .band .bsum", (e) => e.textContent); }
    else X[m] = await o.p.waitForFunction((m) => { const t = (document.querySelector("#grid .nxs.skel p") || {}).textContent || ""; return (m === "slow" ? t.includes("reading") : t.includes("unreadable")) && t; }, m, { timeout: 15000 }).then((h) => h.jsonValue(), () => "");
    await o.p.context().close();
  }
  mode = "";
  return X;
}

/* The PARITY.md table from the results: one row per kept item; the dropped 4 named under it. */
function table(ROWS, res) {
  const cell = (s) => String(s).replace(/\|/g, "/").replace(/\n/g, " ");
  const lines = ROWS.map((r) => {
    if (!r.fn) return `| ${r.id} | ${cell(r.item)} | ${cell(r.found)} | — | — | removed | Recent 24 h: not a loss (owner's word) |`;
    const v = res[r.id], ok = Object.values(v).every((x) => x === true), note = Object.entries(v).filter(([, x]) => x !== true).map(([w, x]) => w + ": " + x)[0] || "";
    return `| ${r.id} | ${cell(r.item)} | ${cell(r.found)} | ${v[1366] === true ? "ok" : "red"} | ${v[400] === true ? "ok" : "red"} | ${ok ? "pass" : "FAIL"} | ${cell(note).slice(0, 300)} |`;
  });
  return `# T1601-14 office parity (written by dashboard/tests/test_office_parity.js, ${new Date().toISOString().slice(0, 16)}Z)\n\n` +
    `Each kept item of PLAN §2.1, asserted from the old screens' source at 1366 and 400 px on one fixture (every field). A card counts as reached when a click opens it ` +
    `(list button, then chips and room lines on cards); its subject must stand in the 3D scene. Office is avatar-only (T1601-17): mapping in done/17.md.\n\n` +
    `| # | item (old screen) | where found in the office | 1366 | 400 | result | note |\n|---|---|---|---|---|---|---|\n${lines.join("\n")}\n\n` +
    `Dropped by PLAN §2.1, named and not tested: O3 owner card "You" (owner's order), C6 Court fold button (Reset view), C9 Court eye and rings (drawing), R3 Roster countdown rings (drawing; the number is the bar).\n`;
}

/* Runs the rows of every area (each `area(row, view)` adds its rows over the fixture view of that width) at 1366 and 400; with out, writes the table there. */
async function run(areas, { out = "", name = "test_office_parity" } = {}) {
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ headless: true, args: GPU }), res = {};
  let ROWS = [];
  try {
    for (const w of [1366, 400]) {
      const X = await facts(b, w), V = setFix(X.T);
      ROWS = [];
      for (const a of areas) a((id, item, found, fn) => ROWS.push({ id, item, found, fn }), V);
      for (const r of ROWS.filter((r) => r.fn)) {
        res[r.id] = res[r.id] || {};
        try { r.fn(X); res[r.id][w] = true; console.log(`ok ${w} ${r.id}`); } catch (e) { res[r.id][w] = (e.message || String(e)).split("\n")[0]; console.log(`FAIL ${w} ${r.id}: ${res[r.id][w]}`); }
      }
    }
  } finally { await b.close(); srv.close(); }
  if (out) fs.writeFileSync(out, table(ROWS, res));
  const red = Object.entries(res).filter(([, v]) => Object.values(v).some((x) => x !== true)).map(([k]) => k), kept = ROWS.filter((r) => r.fn).length;
  console.log(`${red.length ? "FAIL" : "ok"} ${name}: ${kept - red.length} of ${kept} kept rows green${red.length ? "; red: " + red.join(" ") : ""}${out ? "; table " + out : ""}`);
  return red.length ? 1 : 0;
}

/* Runs areas as a script: exit 0 when every row is green. */
const main = (areas, opts) => run(areas, opts).then((c) => process.exit(c), (e) => { console.error("FAIL " + (e && e.stack || e)); process.exit(1); });

module.exports = { run, main };
