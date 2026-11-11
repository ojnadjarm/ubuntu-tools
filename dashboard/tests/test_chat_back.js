// Chat Back on the phone (T1691): from every way into a conversation (a tap on the list, a link from another screen, a cold deep link,
// a reload inside it, the Chat tab reopening the last one) Back shows the conversation list, Back from the list leaves Chat; the page's
// back arrow does the same; several conversations in a row add no history entries; from 900 px a click adds none (as before).
// Run: node tests/test_chat_back.js   (fixture API only; nothing is posted but the seen cursor)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ORG = { seats: [
  { id: "owner", name: "You", role: "owner", parent: null, wake: null, match: null },
  { id: "orchestrator", name: "Orchestrator", role: "ceo", parent: "owner", wake: "channel", match: "~" },
  { id: "mooblox", name: "Mooblox", role: "po", parent: "orchestrator", wake: "po-inbox", match: null }], sessions: [], hidden: 0 };
const T0 = Date.now() - 3600e3;
const row = (id, ch, from, text) => ({ id, ts: new Date(id).toISOString(), ch, from, to: [], kind: "msg", text, re: null, hop: 0 });
const STORE = {
  harness: [row(T0, "harness", "mooblox", "how do I drop a link?")],
  org: [row(T0 + 1000, "org", "orchestrator", "morning")],
  "dm-orchestrator--owner": [row(T0 + 2000, "dm-orchestrator--owner", "orchestrator", "done, link in the drop")],
};
const DM = "dm-orchestrator--owner";
const posted = [];
const srv = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") {
    const ch = q.get("ch") || "", after = +(q.get("after") || 0);
    const rows = ch ? STORE[ch] || [] : Object.values(STORE).flat().sort((a, b) => a.id - b.id);
    return { messages: rows.filter((m) => m.id > after), channels: Object.keys(STORE).map((c) => ({ ch: c, unread: 0 })), wakes: { today: {} }, thinking: [] };
  }
});
const files = srv.listeners("request")[0];
srv.removeAllListeners("request");
srv.on("request", (req, res) => { if (req.method === "POST") { posted.push(req.url); return res.end('{"ok":true}'); } files(req, res); });

const hash = (p) => p.evaluate(() => location.hash);
const len = (p) => p.evaluate(() => history.length);
const wait = (p, f, arg) => p.waitForFunction(f, arg, { timeout: 8000 });
/* The conversation ch is on screen. */
const inConv = (p, ch) => wait(p, (c) => location.hash === "#chat?ch=" + c && document.querySelector("#grid > .nxs.chat.conv"), ch);
/* The conversation list is on screen. */
const inList = (p) => wait(p, () => location.hash === "#chat" && document.querySelector("#grid > .nxs.chat.list .chans a"));
/* The browser's Back (the phone's gesture or button). */
async function back(p) { await p.goBack({ waitUntil: "commit" }).catch(() => {}); await p.waitForTimeout(250); }
/* Back from a conversation must show the list, then Back from the list must land on `left` (a hash, or "about:blank"). */
async function backTwice(p, label, left) {
  await back(p);
  await inList(p).catch(() => {});
  assert.strictEqual(await hash(p) + (await p.$("#grid > .nxs.chat.list") ? " list" : ""), "#chat list", label + ": Back from the conversation shows the list");
  await back(p);
  const now = await p.evaluate(() => (location.href === "about:blank" ? "about:blank" : location.hash));
  assert.strictEqual(now, left, label + ": Back from the list leaves Chat");
}
/* The page's own back arrow shows the list, then Back leaves Chat. */
async function arrow(p, label, left) {
  await p.tap(".chat [data-back]");
  await inList(p);
  await back(p);
  const now = await p.evaluate(() => (location.href === "about:blank" ? "about:blank" : location.hash));
  assert.strictEqual(now, left, label + ": after the back arrow, Back from the list leaves Chat");
}
/* A tap on a conversation in the phone list. */
async function tap(p, ch) { await p.tap(`.chat.list .chans [data-ch="${ch}"]`); await inConv(p, ch); }

const PATHS = {
  /* Eye, then Chat, then a tap on a conversation. */
  async tap(p, base, how) {
    await p.goto(base + "/#eye", { waitUntil: "load" });
    await p.evaluate(() => { location.hash = "#chat"; });
    await inList(p);
    await tap(p, DM);
    return ["#eye", how];
  },
  /* A link from another screen (the Office card's Message, its talk panel's Open in Chat): a hash link to the thread. */
  async link(p, base, how) {
    await p.goto(base + "/#eye", { waitUntil: "load" });
    await p.waitForSelector("#grid > *", { timeout: 15000 });
    await p.evaluate((c) => { location.hash = "#chat?ch=" + c; }, DM);
    await inConv(p, DM);
    return ["#eye", how];
  },
  /* A cold open on the thread: a push notification, a shared link, the PWA started on it. */
  async cold(p, base, how) {
    await p.goto(base + "/#chat?ch=" + DM, { waitUntil: "load" });
    await inConv(p, DM);
    return ["about:blank", how];
  },
  /* A reload (or the PWA restored) inside a thread opened from the list. */
  async reload(p, base, how) {
    await PATHS.tap(p, base);
    await p.reload({ waitUntil: "load" });
    await inConv(p, DM);
    return ["#eye", how];
  },
  /* The Chat tab reopening the conversation he left for another screen. */
  async tab(p, base, how) {
    await PATHS.tap(p, base);
    await p.evaluate(() => { const a = document.createElement("a"); a.dataset.nav = "eye"; a.href = "#eye"; document.body.appendChild(a); a.click(); a.remove(); });
    await wait(p, () => location.hash === "#eye" && !document.querySelector("#grid > .nxs.chat"));
    await p.evaluate(() => { const a = document.createElement("a"); a.dataset.nav = "chat"; a.href = "#chat"; document.body.appendChild(a); a.click(); a.remove(); });
    await inConv(p, DM);
    return ["#eye", how];
  },
};

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  const only = process.env.ONLY, fails = [];
  try {
    const run = async (name, how) => {
      if (only && only !== name) return;
      const ctx = await b.newContext({ viewport: { width: 400, height: 850 }, hasTouch: true, isMobile: true });
      const p = await ctx.newPage(), errs = [];
      p.on("pageerror", (e) => errs.push(String(e)));
      try {
        const [left] = await PATHS[name](p, base, how);
        if (how === "arrow") await arrow(p, name + " (arrow)", left); else await backTwice(p, name, left);
        assert.deepStrictEqual(errs, [], name + ": no page errors");
        console.log("ok · " + name + " · " + how);
      } catch (e) { fails.push(e.message); console.log("FAIL · " + e.message); }
      await ctx.close();
    };
    for (const name of Object.keys(PATHS)) { await run(name, "back"); await run(name, "arrow"); }

    if (!only || only === "row") {
      const ctx = await b.newContext({ viewport: { width: 400, height: 850 }, hasTouch: true, isMobile: true });
      const p = await ctx.newPage();
      try {
        await p.goto(base + "/#eye", { waitUntil: "load" });
        await p.evaluate(() => { location.hash = "#chat"; });
        await inList(p);
        const n0 = await len(p);
        for (const ch of ["org", "harness", DM, "org"]) { await tap(p, ch); await back(p); await inList(p); }
        await tap(p, "harness"); await p.tap(".chat [data-back]"); await inList(p);
        assert.strictEqual(await len(p), n0 + 1, "row: five conversations in a row leave one entry above the list");
        await back(p);
        assert.strictEqual(await hash(p), "#eye", "row: Back from the list leaves Chat");
        console.log("ok · row · 5 conversations, 1 entry");
      } catch (e) { fails.push(e.message); console.log("FAIL · " + e.message); }
      await ctx.close();
    }

    if (!only || only === "desk") {
      const ctx = await b.newContext({ viewport: { width: 1366, height: 768 } });
      const p = await ctx.newPage();
      try {
        await p.goto(base + "/#chat?ch=org", { waitUntil: "load" });
        await p.waitForSelector(".chat .chans a", { timeout: 15000 });
        const n0 = await len(p);
        for (const ch of ["harness", DM, "org"]) {
          await p.click(`.chat .chans [data-ch="${ch}"]`);
          await wait(p, (c) => location.hash === "#chat?ch=" + c, ch);
        }
        assert.strictEqual(await len(p), n0, "desk: a channel click adds no history entry from 900 px");
        assert.ok(await p.$eval(".chat .stream", (e) => getComputedStyle(e).display !== "none") && await p.$eval(".chat .chans", (e) => getComputedStyle(e).visibility === "visible"), "desk: list and stream side by side");
        console.log("ok · desk · 1366 unchanged");
      } catch (e) { fails.push(e.message); console.log("FAIL · " + e.message); }
      await ctx.close();
    }
    assert.deepStrictEqual(posted.filter((u) => !u.startsWith("/api/chat/seen")), [], "nothing posted");
  } finally { await b.close(); srv.close(); }
  if (fails.length) { console.error(fails.length + " failed"); process.exit(1); }
})().catch((e) => { console.error(e); process.exit(1); });
