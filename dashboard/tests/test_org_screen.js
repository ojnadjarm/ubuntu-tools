// Org screen (T1515-P21): a message button per seat opens its direct message in Chat, workers hang under the seat that
// started them (3 shown, the rest folded behind a "hidden N" line), managers wear their own gear, no sideways scroll.
// Run: node tests/test_org_screen.js   (fixture API only; POSTs never leave this file's server)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const seat = (id, name, role, parent, wake) => ({ id, name, role, parent, wake, match: null });
const work = (pid, name, parent, state) => ({ seat: null, state, since: 1794262000, pid, parent, name, cwd: "~/w" + pid, started_by: parent });
const ORG = { seats: [
  seat("owner", "You", "owner", null, null), seat("orchestrator", "Orchestrator", "ceo", "owner", "channel"),
  seat("mooblox", "Mooblox", "po", "orchestrator", "po-inbox"), seat("discord", "Discord", "po", "orchestrator", "po-inbox"),
  seat("mosaico", "Mosaico manager", "manager", "discord", "po-inbox")],
sessions: [
  { seat: "orchestrator", state: "working", since: 1794262000, pid: 1, parent: "owner", name: "center", cwd: "~", started_by: "owner" },
  work(11, "w-a", "orchestrator", "idle"), work(12, "w-b", "orchestrator", "working"), work(13, "w-c", "orchestrator", "idle"),
  work(14, "w-d", "orchestrator", "working"), work(15, "w-e", "orchestrator", "idle"), work(21, "m-a", "mosaico", "working")], hidden: 0 };

const srv = serveStatic((u) => {
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
});

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const p = await (await b.newContext({ viewport: { width: 1366, height: 768 } })).newPage();
    const errs = [];
    p.on("pageerror", (e) => errs.push(String(e)));
    await p.goto(base + "/#org", { waitUntil: "load" });
    await p.waitForSelector(".org .otree", { timeout: 15000 });

    const links = await p.$$eval(".org .seat a.msg", (as) => as.map((a) => a.getAttribute("href")));
    assert.deepStrictEqual(links, ["#chat?ch=dm-orchestrator--owner", "#chat?ch=dm-mooblox--owner", "#chat?ch=dm-discord--owner", "#chat?ch=dm-mosaico--owner"], "one message button per seat but the owner's");

    const crew = (id) => p.$$eval(`.org .seat[data-seat="${id}"] .crew > li`, (l) => l.map((x) => x.querySelector("b").textContent));
    assert.deepStrictEqual(await crew("orchestrator"), ["w-b", "w-d", "w-a"], "working first, 3 shown under the seat that started them");
    assert.deepStrictEqual(await crew("mosaico"), ["m-a"], "a manager's worker hangs under the manager");
    assert.deepStrictEqual(await crew("mooblox"), [], "no worker, no list");
    assert.strictEqual((await p.textContent('.org .seat[data-seat="orchestrator"] details.fold summary')).trim(), "hidden 2", "the folded rest is a hidden N line");
    assert.strictEqual(await p.$$eval('.org .seat[data-seat="orchestrator"] details.fold li', (l) => l.length), 2, "the folded workers are in the fold");
    await p.click('.org .seat[data-seat="orchestrator"] details.fold summary');
    assert.ok(await p.isVisible('.org .seat[data-seat="orchestrator"] details.fold li'), "the fold opens");

    const gear = await p.$eval('.org .seat[data-seat="mosaico"] .av svg', (s) => [s.querySelector(".gear-manager") !== null, s.querySelector(".gear-worker") !== null]);
    assert.deepStrictEqual(gear, [true, false], "a manager wears manager gear, not the worker's hard hat");

    for (const w of [400, 768, 1920]) {
      await p.setViewportSize({ width: w, height: 900 });
      const sw = await p.evaluate(() => document.documentElement.scrollWidth);
      assert.strictEqual(sw, w, `no sideways scroll at ${w}`);
    }
    await p.setViewportSize({ width: 1366, height: 768 });

    await p.click('.org .seat[data-seat="mooblox"] a.msg');
    await p.waitForSelector(".chat .stream header h2", { timeout: 15000 });
    assert.strictEqual(await p.evaluate(() => location.hash), "#chat?ch=dm-mooblox--owner", "the button lands on the direct message");
    assert.strictEqual(await p.textContent(".chat .stream header h2"), "Mooblox", "Chat opens that direct message");
    assert.deepStrictEqual(errs, [], "no page errors");
    console.log("ok · 4 message buttons -> dm · workers under parent, 3 + hidden 2 · manager gear · no sideways scroll 400/768/1366/1920");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
