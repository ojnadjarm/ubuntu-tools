// Chat message actions (T1545-F): Reply and Copy on hover and keyboard focus from 900 px, by a tap on the phone (a second tap or a tap
// elsewhere hides them), 32 px targets (44 px on touch), rows never shift; Copy writes the clipboard and says "Copied" 1.5 s; Reply fires
// chat:reply {ch, id, name, text} and focuses #say; Copy only in Recent and search; the grouping rule; the full date on <time>; a poll
// changes no row; the search view's side column lists the results' senders.
// Run: node tests/test_chat_actions.js   (fixture API only; SHOTS=<dir> also writes actions-<w>.png)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ORG = { seats: [
  { id: "owner", name: "You", role: "owner", parent: null, wake: null, match: null },
  { id: "orchestrator", name: "Orchestrator", role: "ceo", parent: "owner", wake: "channel", match: "~" },
  { id: "mooblox", name: "Mooblox", role: "po", parent: "orchestrator", wake: "po-inbox", match: null }], sessions: [], hidden: 0 };
const D = new Date(); D.setHours(9, 0, 0, 0);
const T0 = D.getTime(), S = 1000;
const row = (id, ch, from, text, kind = "msg", re = null) => ({ id, ts: new Date(id).toISOString(), ch, from, to: [], kind, text, re, hop: 0 });
const STORE = {
  org: [row(T0, "org", "orchestrator", "Deploy is green."), row(T0 + 60 * S, "org", "orchestrator", "Logs are in the drop folder."),
    row(T0 + 120 * S, "org", "orchestrator", "Next: the phone check."), row(T0 + 200 * S, "org", "owner", "Thanks, ship it."),
    row(T0 + 260 * S, "org", "mooblox", "Can I close the deploy ticket?", "ask"), row(T0 + 400 * S, "org", "orchestrator", "Yes, close it.", "answer", T0 + 260 * S)],
  harness: [row(T0 + 30 * S, "harness", "mooblox", "how do I drop a link?")],
};
const srv = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  const all = Object.values(STORE).flat().sort((a, b) => a.id - b.id);
  if (u === "/api/chat") {
    const ch = q.get("ch") || "", after = +(q.get("after") || 0);
    return { messages: (ch ? STORE[ch] || [] : all).filter((m) => m.id > after), channels: Object.keys(STORE).map((c) => ({ ch: c, unread: 0 })), wakes: { today: {} }, thinking: [] };
  }
  if (u === "/api/chat/search") return { q: q.get("q"), messages: all.filter((m) => m.text.toLowerCase().includes(q.get("q").toLowerCase())) };
});
const WIDTHS = [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]];
const msg = (p, t) => p.locator(".chat .msg", { hasText: t });
/* What a row shows: its box, its text box, whether its actions are visible and their button boxes. */
const look = (l) => l.evaluate((li) => {
  const r = (e) => { const b = e.getBoundingClientRect(); return [b.x, b.y, b.width, b.height].map(Math.round).join(","); }, a = li.querySelector(".act");
  return { li: r(li), tx: r(li.querySelector(".tx")), on: !!a && getComputedStyle(a).opacity === "1" && getComputedStyle(a).pointerEvents !== "none",
    btn: a ? [...a.querySelectorAll("button")].map((b) => [b.textContent, Math.round(b.getBoundingClientRect().height), Math.round(b.getBoundingClientRect().width)]) : [] };
});
const wait = (p, f, arg) => p.waitForFunction(f, arg, { timeout: 6000 });
/* Waits until every finite animation (the stream's entrance) has ended, so boxes are settled. */
const settled = (p) => p.waitForFunction(() => document.getAnimations().every((a) => a.effect.getComputedTiming().iterations === Infinity || a.playState === "finished"), null, { timeout: 6000 });

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  const errs = [];
  try {
    if (process.env.SHOTS) {
      for (const [w, h] of WIDTHS) {
        const c = await b.newContext({ viewport: { width: w, height: h } }), p = await c.newPage();
        await p.goto(base + "/#chat?ch=org", { waitUntil: "load" });
        await msg(p, "Logs are in").waitFor({ timeout: 15000 });
        await p.waitForTimeout(1200);
        if (w < 900) await msg(p, "Logs are in").locator(".tx").click(); else await msg(p, "Logs are in").hover();
        await p.waitForTimeout(300);
        await p.screenshot({ path: `${process.env.SHOTS}/actions-${w}.png` });
        await c.close();
      }
    }

    const ctx = await b.newContext({ viewport: { width: 1366, height: 768 } }), p = await ctx.newPage();
    await ctx.grantPermissions(["clipboard-read", "clipboard-write"], { origin: base });
    p.on("pageerror", (e) => errs.push(String(e)));
    await p.goto(base + "/#chat?ch=org", { waitUntil: "load" });
    await msg(p, "Yes, close it.").waitFor({ timeout: 15000 });
    await settled(p);

    const rule = await p.evaluate(async (t0) => {
      const { grouped } = await import("/static/next/js/screens/chat-actions.js");
      const m = (id, from = "orchestrator", o = {}) => ({ id, ts: new Date(id).toISOString(), ch: "org", from, kind: "msg", re: null, text: "x", ...o });
      const late = new Date(t0); late.setHours(23, 59, 0, 0);
      const a = m(t0), five = 5 * 60000;
      return [grouped(a, m(t0 + 60000)), grouped(a, m(t0 + five)), grouped(a, m(t0 + five + 1)), grouped(a, m(t0 + 1000, "mooblox")),
        grouped(m(late.getTime()), m(late.getTime() + 120000)), grouped(a, m(t0 + 1000, "orchestrator", { kind: "answer" })),
        grouped(m(t0, "orchestrator", { kind: "ask" }), m(t0 + 1000)), grouped(a, m(t0 + 1000, "orchestrator", { re: t0 })),
        grouped(a, m(t0 + 1000, "orchestrator", { ch: "harness" })), grouped(null, a)];
    }, T0);
    assert.deepStrictEqual(rule, [true, true, false, false, false, false, false, false, false, false],
      "grouped: same sender, 1 min, 5 min edge in, 5 min + 1 ms out, other sender, day change, answer tag, after a question, quote, other channel, first row");

    const rows = await p.$$eval(".chat .msgs .msg", (l) => l.map((li) => [li.classList.contains("grp"), !!li.querySelector(".who"), !!li.querySelector(".av .fam"), !!li.querySelector(".gt")]));
    assert.deepStrictEqual(rows, [[false, true, true, false], [true, false, false, true], [true, false, false, true], [false, true, false, false], [false, true, true, false], [false, true, true, false]],
      "a run of one sender keeps one header and Familiar; the others show a gutter time");
    const times = await p.$$eval(".chat .msgs time", (l) => l.map((t) => [t.textContent, t.title]));
    assert.ok(times.length === 6 && times.every(([t, title]) => title.includes(t) && title.includes(String(D.getFullYear())) && title.includes(String(D.getDate()))), "every <time> has a title with the full date and time: " + JSON.stringify(times[0]));
    assert.strictEqual(await msg(p, "Logs are in").locator(".gt").evaluate((e) => getComputedStyle(e).visibility), "hidden", "the gutter time hides until hover");

    const still = await look(msg(p, "Logs are in"));
    assert.strictEqual(still.on, false, "actions hidden at rest");
    await msg(p, "Logs are in").hover();
    const hov = await look(msg(p, "Logs are in"));
    assert.deepStrictEqual(hov.btn.map((x) => x[0]), ["Reply", "Copy"], "hover shows Reply and Copy");
    assert.ok(hov.on && hov.btn.every((x) => x[1] >= 32 && x[1] < 44 && x[2] >= 32), "visible, 32 px targets on a mouse: " + JSON.stringify(hov.btn));
    assert.deepStrictEqual([hov.li, hov.tx], [still.li, still.tx], "showing the actions moves no text");
    assert.strictEqual(await msg(p, "Logs are in").locator(".gt").evaluate((e) => getComputedStyle(e).visibility), "visible", "hover shows the gutter time");
    assert.strictEqual((await look(msg(p, "Deploy is green."))).on, false, "only the hovered row");

    await p.mouse.move(5, 5);
    await msg(p, "Deploy is green.").locator("[data-mcopy]").focus();
    await p.keyboard.press("Tab");
    assert.ok(await p.evaluate(() => document.activeElement.matches("[data-reply]") && document.activeElement.closest(".msg").textContent.includes("Logs are in")), "Tab reaches the next row's Reply");
    assert.ok((await look(msg(p, "Logs are in"))).on, "keyboard focus shows the actions");

    await msg(p, "Logs are in").locator("[data-mcopy]").click();
    const t0 = Date.now();
    assert.strictEqual(await msg(p, "Logs are in").locator("[data-mcopy]").textContent(), "Copied", "Copy says Copied");
    assert.strictEqual(await p.evaluate(() => navigator.clipboard.readText()), "Logs are in the drop folder.", "Copy writes the message text");
    await wait(p, () => [...document.querySelectorAll(".chat .msg")].find((l) => l.textContent.includes("Logs are in")).querySelector("[data-mcopy]").textContent === "Copy");
    assert.ok(Date.now() - t0 > 1200 && Date.now() - t0 < 2600, "Copied for about 1.5 s");

    await p.evaluate(() => document.addEventListener("chat:reply", (e) => { window.__reply = e.detail; }));
    await msg(p, "Yes, close it.").hover();
    await msg(p, "Yes, close it.").locator("[data-reply]").click();
    assert.deepStrictEqual(await p.evaluate(() => window.__reply), { ch: "org", id: T0 + 400 * S, name: "Orchestrator", text: "Yes, close it." }, "Reply fires chat:reply with ch, id, name, text");
    assert.strictEqual(await p.evaluate(() => document.activeElement.id), "say", "Reply focuses the box");

    await p.mouse.move(5, 5);
    await p.evaluate(() => { window.__mut = 0; new MutationObserver((l) => { window.__mut += l.length; }).observe(document.querySelector(".chat .msgs"), { subtree: true, childList: true, characterData: true, attributes: true }); });
    await p.waitForTimeout(3500);
    assert.strictEqual(await p.evaluate(() => window.__mut), 0, "a poll with nothing new changes no row (aria-live stays quiet)");

    await p.goto(base + "/#chat?recent=1", { waitUntil: "load" });
    await msg(p, "how do I drop a link?").waitFor({ timeout: 8000 });
    await msg(p, "Logs are in").hover();
    assert.deepStrictEqual((await look(msg(p, "Logs are in"))).btn.map((x) => x[0]), ["Copy"], "Recent: Copy only");
    assert.ok(!(await msg(p, "Logs are in").evaluate((li) => li.classList.contains("grp"))), "Recent: another channel's row in between breaks the group");
    assert.strictEqual(await p.$$eval(".chat .msgs [data-reply]", (l) => l.length), 0, "Recent: no Reply anywhere");

    await p.goto(base + "/#chat?q=close", { waitUntil: "load" });
    await wait(p, () => /results? for close/.test((document.querySelector(".chat .stream header h2") || {}).textContent));
    assert.strictEqual(await p.$$eval(".chat .msgs [data-reply]", (l) => l.length), 0, "search: no Reply");
    assert.strictEqual(await p.$$eval(".chat .msgs [data-mcopy]", (l) => l.length), 2, "search: Copy on each result");
    const side = await p.$eval(".chat .cside", (a) => [a.getAttribute("aria-label"), a.querySelector("h2").textContent, [...a.querySelectorAll(".mem b")].map((e) => e.textContent)]);
    assert.deepStrictEqual(side, ["In these results", "in these results", ["Mooblox", "Orchestrator"]], "search: the side column lists the results' senders, not Recent's");
    assert.strictEqual(await p.evaluate(() => document.documentElement.scrollWidth), 1366, "no sideways scroll at 1366");
    await ctx.close();

    const tc = await b.newContext({ viewport: { width: 400, height: 850 }, hasTouch: true, isMobile: true }), t = await tc.newPage();
    t.on("pageerror", (e) => errs.push(String(e)));
    await t.goto(base + "/#chat?ch=org", { waitUntil: "load" });
    await msg(t, "Logs are in").waitFor({ timeout: 15000 });
    await settled(t);
    const rest = await look(msg(t, "Logs are in"));
    assert.strictEqual(rest.on, false, "phone: hidden at rest");
    await msg(t, "Logs are in").locator(".tx").tap();
    const tapped = await look(msg(t, "Logs are in"));
    assert.ok(tapped.on && tapped.btn.length === 2 && tapped.btn.every((x) => x[1] >= 44 && x[2] >= 44), "phone: a tap shows both, 44 px: " + JSON.stringify(tapped.btn));
    assert.deepStrictEqual([tapped.li, tapped.tx], [rest.li, rest.tx], "phone: showing the actions moves no text");
    await t.waitForTimeout(3300);
    assert.ok((await look(msg(t, "Logs are in"))).on, "phone: open actions survive a poll");
    await msg(t, "Logs are in").locator(".tx").tap();
    assert.strictEqual((await look(msg(t, "Logs are in"))).on, false, "phone: a second tap hides them");
    await msg(t, "Logs are in").locator(".tx").tap();
    await msg(t, "Thanks, ship it.").locator(".tx").tap();
    assert.deepStrictEqual([(await look(msg(t, "Logs are in"))).on, (await look(msg(t, "Thanks, ship it."))).on], [false, true], "phone: a tap on another row moves them there");
    await t.tap(".chat .stream header h2");
    assert.strictEqual((await look(msg(t, "Thanks, ship it."))).on, false, "phone: a tap elsewhere hides them");
    assert.strictEqual(await t.evaluate(() => document.documentElement.scrollWidth), 400, "no sideways scroll at 400");
    await tc.close();

    assert.deepStrictEqual(errs, [], "no page errors");
    console.log("test_chat_actions: ok");
  } finally {
    await b.close();
    srv.close();
  }
})().catch((e) => { console.error(e); process.exit(1); });
