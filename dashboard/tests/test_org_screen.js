// Org screen (T1515-P21): a message button per seat opens its direct message in Chat, workers hang under the seat that
// started them (3 shown, the rest folded behind a "hidden N" line), managers wear their own gear, no sideways scroll.
// P35: a card shows avatar, name, state dot and a message icon; the state and description lines live in the avatar's tooltip.
// V3: every creature is a moving Familiar; a new message makes its sender talk for about 2 s, the owner never.
// T1553: the ceo seat's tooltip leads with "DarkSaddler · CEO" (name and rank from the API).
// T1554: every seat's tooltip leads with "Name · Rank" and names its area; a worker row is titled "name · Worker".
// Run: node tests/test_org_screen.js   (fixture API only; POSTs never leave this file's server)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const seat = (id, name, role, parent, wake) => ({ id, name, role, parent, wake, match: null });
const work = (pid, name, parent, state) => ({ seat: null, state, since: 1794262000, pid, parent, name, cwd: "~/w" + pid, started_by: parent, rank: "Worker" });
const ORG = { seats: [
  seat("owner", "You", "owner", null, null), { ...seat("orchestrator", "DarkSaddler", "ceo", "owner", "channel"), rank: "CEO" },
  seat("mooblox", "Mooblox", "po", "orchestrator", "po-inbox"), seat("discord", "Discord", "po", "orchestrator", "po-inbox"),
  { ...seat("mosaico", "Speckle", "manager", "discord", "po-inbox"), rank: "Manager", area: "Mosaico" }],
sessions: [
  { seat: "orchestrator", state: "working", since: 1794262000, pid: 1, parent: "owner", name: "center", cwd: "~", started_by: "owner" },
  work(11, "w-a", "orchestrator", "idle"), work(12, "w-b", "orchestrator", "working"), work(13, "w-c", "orchestrator", "idle"),
  work(14, "w-d", "orchestrator", "working"), work(15, "w-e", "orchestrator", "idle"), work(21, "m-a", "mosaico", "working")], hidden: 0 };

const CHAT = [];
let reads = 0;
const say = (from) => CHAT.push({ id: CHAT.length + 1, ts: new Date().toISOString(), ch: "org", from, to: [], kind: "msg", text: "hello", re: null, hop: 0 });

const shownTip = (p) => p.$eval('.org .seat[data-seat="mooblox"] .av svg', (e) => !!e.querySelector(".mouth") && !!e.querySelector(".say"));
const srv = serveStatic((u, res) => {
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") {
    const after = new URL(res.req.url, "http://x").searchParams.get("after");
    if (after != null) reads++;
    return { messages: CHAT.filter((m) => after == null || m.id > +after), channels: [], wakes: { cap: 12, today: {} } };
  }
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

    const orch = '.org .seat[data-seat="orchestrator"]';
    assert.strictEqual(await p.$$eval(".org .seat > p", (l) => l.length), 0, "no description line on any card");
    const msg = await p.$eval(orch + " a.msg", (a) => { const r = a.getBoundingClientRect(); return [a.textContent.trim(), a.getAttribute("aria-label"), a.title, !!a.querySelector("svg"), r.width >= 32 && r.height >= 32]; });
    assert.deepStrictEqual(msg, ["", "Message DarkSaddler", "Message DarkSaddler", true, true], "the message button is an icon, named, 32 px or more");
    const dot = await p.$eval(orch + " h3 .pill", (d) => [d.textContent.trim() === d.querySelector(".sr-only").textContent.trim(), d.textContent.trim(), d.getBoundingClientRect().width < 20]);
    assert.deepStrictEqual(dot, [true, "working", true], "the state is a dot, its name only for screen readers");
    const tip = await p.$eval(orch + " .avb", (b) => { const t = document.getElementById(b.getAttribute("aria-describedby")); return t && [t.getAttribute("role"), t.textContent]; });
    assert.ok(tip && tip[0] === "tooltip" && /working/.test(tip[1]) && /Runs the fleet/.test(tip[1]) && /Always on/.test(tip[1]), "the avatar describes itself by its tooltip: state and both lines");
    assert.deepStrictEqual(await p.$eval(orch, (c) => [c.querySelector(".tip b").textContent, c.querySelector("h3").firstChild.textContent.trim()]), ["DarkSaddler · CEO", "DarkSaddler"], "T1553: the tooltip leads with name · rank, the card shows the name only");
    assert.deepStrictEqual(await p.$$eval(".org .seat h3", (l) => l.filter((e) => /Orchestrator/.test(e.textContent)).length), 0, "T1553: no seat card says Orchestrator");
    const shown = () => p.$eval(orch + " .tip", (t) => getComputedStyle(t).display !== "none");
    assert.strictEqual(await shown(), false, "the tooltip is closed at rest");
    await p.hover(orch + " .avb");
    assert.strictEqual(await shown(), true, "hover opens it");
    await p.mouse.move(1, 1);
    assert.strictEqual(await shown(), false, "leaving closes it");
    await p.focus(orch + " .avb"); await p.keyboard.press("Shift+Tab"); await p.keyboard.press("Tab");
    assert.strictEqual(await shown(), true, "keyboard focus opens it");
    await p.evaluate(() => document.activeElement.blur());

    const mos = '.org .seat[data-seat="mosaico"]';
    assert.deepStrictEqual(await p.$eval(mos, (c) => [c.querySelector(".tip b").textContent, [...c.querySelectorAll(".tip span")].some((e) => e.textContent === "Mosaico"), c.querySelector("h3").firstChild.textContent.trim(), c.querySelector("h3 .rk").textContent]),
      ["Speckle · Manager", true, "Speckle", "Manager"], "T1554: the tooltip leads with name · rank and names the area, the card shows name and rank");
    assert.strictEqual(await p.$eval(mos + " .crew > li", (l) => l.title), "m-a · Worker", "T1554: a worker row says its rank");
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

    const ph = await (await b.newContext({ viewport: { width: 400, height: 850 }, hasTouch: true, isMobile: true })).newPage();
    await ph.goto(base + "/#org", { waitUntil: "load" });
    await ph.waitForSelector(".org .otree", { timeout: 15000 });
    const tips = ph.locator(".org .tip:visible");
    for (const id of ["orchestrator", "mosaico"]) {
      await ph.tap(`.org .seat[data-seat="${id}"] .avb`);
      assert.strictEqual(await tips.count(), 1, `a tap on ${id}'s avatar opens its tooltip`);
      const r = await tips.first().boundingBox();
      assert.ok(r.x >= 0 && r.x + r.width <= 400, `${id}'s tooltip stays inside 400 px`);
    }
    await ph.tap(".org .band");
    assert.strictEqual(await tips.count(), 0, "a tap elsewhere closes it");

    const talkers = () => p.$$eval(".org .seat:has(.av .cr.talking)", (l) => l.map((x) => x.dataset.seat));
    const anim = () => p.$eval(orch + " .fam", (e) => [getComputedStyle(e).animationName, getComputedStyle(e).animationPlayState]);
    assert.strictEqual(await p.$$eval(".org .seat .av .fam svg.cr, .org .crew .fam svg.cr", (l) => l.length), 8, "every seat and shown worker is a Familiar in a .fam box");
    assert.deepStrictEqual(await p.$eval('.org .seat[data-seat="mooblox"] .av svg', (e) => e.getAttribute("class")), "cr sleep", "an asleep seat rests");
    assert.deepStrictEqual(await anim(), ["fam-bob", "running"], "a working creature moves");
    while (reads < 1) await p.waitForTimeout(200);
    say("owner");
    const n0 = reads;
    while (reads < n0 + 2) await p.waitForTimeout(200);
    assert.deepStrictEqual(await talkers(), [], "the owner's own message animates nothing");
    say("mooblox");
    await p.waitForSelector('.org .seat[data-seat="mooblox"] .av .cr.talking', { timeout: 6000 });
    const t0 = Date.now();
    assert.deepStrictEqual(await talkers(), ["mooblox"], "a new message makes only its sender talk");
    assert.strictEqual(await shownTip(p), true, "the talking creature keeps its mouth and bubble");
    await p.waitForFunction(() => !document.querySelector(".org .cr.talking"), null, { timeout: 4000 });
    assert.ok(Date.now() - t0 > 1200 && Date.now() - t0 < 3200, "talking lasts about 2 s");
    await p.evaluate(() => { Object.defineProperty(document, "hidden", { get: () => true, configurable: true }); document.dispatchEvent(new Event("visibilitychange")); });
    assert.strictEqual((await anim())[1], "paused", "animations pause while the page is hidden");
    await p.evaluate(() => { delete document.hidden; document.dispatchEvent(new Event("visibilitychange")); });
    assert.strictEqual((await anim())[1], "running", "and run again when it is back");
    await p.emulateMedia({ reducedMotion: "reduce" });
    assert.strictEqual((await anim())[0], "none", "prefers-reduced-motion stops the motion");
    await p.emulateMedia({ reducedMotion: "no-preference" });

    await p.click('.org .seat[data-seat="mooblox"] a.msg');
    await p.waitForSelector(".chat .stream header h2", { timeout: 15000 });
    assert.strictEqual(await p.evaluate(() => location.hash), "#chat?ch=dm-mooblox--owner", "the button lands on the direct message");
    assert.strictEqual(await p.textContent(".chat .stream header h2"), "Mooblox", "Chat opens that direct message");
    assert.deepStrictEqual(errs, [], "no page errors");
    console.log("ok · avatar tooltip on hover/focus/tap, inside 400 · state dot · message icon · 4 message buttons -> dm · workers under parent, 3 + hidden 2 · manager gear · Familiars move, sender talks ~2 s, owner silent, paused hidden, reduced motion · no sideways scroll 400/768/1366/1920");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
