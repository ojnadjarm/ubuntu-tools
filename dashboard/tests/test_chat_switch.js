// Chat switch (T1545-H): a view opened before in this page load paints its kept rows within 60 ms of the click, never the
// "No messages" line, at its newest row; the read after it asks `after=<last id>` and adds a new row once; a first visit
// shows "reading…" until the first answer; older pages still load after a cached open; chat-cache.js keeps 10 views, 200 rows each.
// Run: node tests/test_chat_switch.js   (fixture API only, every /api/chat answer 400 ms late; waits up to 90 s for quiet-gate before the 60 ms budget)
"use strict";
const assert = require("assert");
const { spawnSync } = require("child_process");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ORG = { seats: [
  { id: "owner", name: "You", role: "owner", parent: null, wake: null, match: null },
  { id: "orchestrator", name: "Orchestrator", role: "ceo", parent: "owner", wake: "channel", match: "~" },
  { id: "mooblox", name: "Mooblox", role: "po", parent: "orchestrator", wake: "po-inbox", match: null }], sessions: [], hidden: 0 };
const T0 = Date.now() - 3600e3, DELAY = 400, PAGE = 50;
const row = (id, ch, from, text) => ({ id, ts: new Date(id).toISOString(), ch, from, to: [], kind: "msg", text, re: null, hop: 0 });
const STORE = {
  harness: Array.from({ length: 80 }, (_, i) => row(T0 + i, "harness", i % 2 ? "orchestrator" : "mooblox", "harness line " + i)),
  org: Array.from({ length: 6 }, (_, i) => row(T0 + 1000 + i, "org", "orchestrator", "org line " + i)),
  mooblox: [row(T0 + 2000, "mooblox", "mooblox", "mooblox line")],
};
const asked = [];
const api = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") {
    const ch = q.get("ch") || "", after = +(q.get("after") || 0), before = +(q.get("before") || 0);
    let all = ch ? STORE[ch] || [] : Object.values(STORE).flat().sort((a, b) => a.id - b.id);
    if (after) all = all.filter((m) => m.id > after);
    if (before) all = all.filter((m) => m.id < before);
    const page = after ? all : all.slice(-PAGE);
    return { messages: page, more: !after && all.length > PAGE, channels: Object.keys(STORE).map((c) => ({ ch: c, unread: 0 })), wakes: { today: {} }, thinking: [] };
  }
});
const files = api.listeners("request")[0];
api.removeAllListeners("request");
/* Every /api/chat GET answers DELAY ms late; POSTs land here and nowhere else. */
api.on("request", (req, res) => {
  if (req.method === "POST") return res.end('{"ok":true}');
  if (req.url.startsWith("/api/chat?")) { asked.push(req.url); return setTimeout(() => files(req, res), DELAY); }
  files(req, res);
});

/* Clicks channel c's row; ms until a row of c is in the stream, whether "No messages" or "reading…" showed, and the box at its end. */
const open = (p, c) => p.evaluate((c) => new Promise((ok) => {
  const t0 = performance.now(), seen = { empty: false, reading: false };
  document.querySelector(`.chat .chans a[data-ch="${c}"]`).click();
  const tick = () => {
    const box = document.querySelector(".chat .msgs"), t = box ? box.textContent : "", m = box && box.querySelector(".msg");
    if (/No messages/.test(t)) seen.empty = true;
    if (/reading…/.test(t)) seen.reading = true;
    if (m && m.dataset.mch === c) return ok({ ms: performance.now() - t0, ...seen, end: box.scrollHeight - box.scrollTop - box.clientHeight < 40 });
    if (performance.now() - t0 > 5000) return ok({ ms: -1, ...seen });
    requestAnimationFrame(tick);
  };
  tick();
}), c);
const ids = (p) => p.$$eval(".chat .msgs .msg", (l) => l.map((e) => e.dataset.mid));
const settle = (p) => p.waitForTimeout(DELAY * 2 + 300);

(async () => {
  spawnSync(process.env.HOME + "/agents/bin/quiet-gate", ["--wait", "90"], { encoding: "utf8" });
  await new Promise((ok) => api.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + api.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const p = await (await b.newContext({ viewport: { width: 1366, height: 768 } })).newPage(), errs = [];
    p.on("pageerror", (e) => errs.push(String(e)));
    await p.goto(base + "/#chat?ch=harness", { waitUntil: "load" });
    await p.waitForSelector(".chat .msgs .msg", { timeout: 15000 });
    await settle(p);

    const first = await open(p, "org");
    assert.ok(first.reading && !first.empty, `first visit shows "reading…", never "No messages" (${JSON.stringify(first)})`);
    assert.ok(first.ms >= DELAY - 50, `first visit waits for the read (${Math.round(first.ms)} ms)`);
    await settle(p);

    const n0 = asked.length, back = await open(p, "harness");
    assert.ok(back.ms >= 0 && back.ms < 60, `second open shows its rows within 60 ms (${Math.round(back.ms)} ms)`);
    assert.ok(!back.empty && !back.reading, "second open never shows the empty or reading line");
    assert.ok(back.end, "second open is at the newest row");
    await settle(p);
    const last = STORE.harness.at(-1).id;
    assert.ok(asked.some((u) => u.includes("ch=harness") && u.includes("after=" + last)), "the read after a cached open asks only what is newer");
    assert.ok(!asked.slice(n0).some((u) => u.includes("ch=harness") && !u.includes("after=")), "no full re-read of the cached channel");

    await open(p, "org");
    STORE.harness.push(row(Date.now(), "harness", "mooblox", "arrived meanwhile"));
    const again = await open(p, "harness");
    assert.ok(again.ms < 60 && !again.empty, `cached open again within 60 ms (${Math.round(again.ms)} ms)`);
    await p.waitForFunction(() => [...document.querySelectorAll(".chat .msg .tx")].some((e) => e.textContent === "arrived meanwhile"), null, { timeout: 5000 });
    await settle(p);
    const got = await ids(p);
    assert.strictEqual(got.filter((x) => x === String(STORE.harness.at(-1).id)).length, 1, "the new row appears once");
    assert.strictEqual(new Set(got).size, got.length, "no duplicate ids");
    assert.ok(await p.$eval(".chat .msgs", (b) => b.scrollHeight - b.scrollTop - b.clientHeight < 40), "at the newest row after the read");
    assert.ok(await p.$eval(".chat [data-newer]", (e) => e.hidden), "no new-messages pill while at the end");

    await p.$eval(".chat .msgs", (b) => { b.scrollTop = 0; });
    await p.waitForFunction((n) => document.querySelectorAll(".chat .msgs .msg").length === n, STORE.harness.length, { timeout: 5000 });
    assert.ok(asked.some((u) => u.includes("ch=harness") && u.includes("before=")), "older page loads after a cached open");

    const cache = await p.evaluate(async () => {
      const { keep, take } = await import("/static/next/js/screens/chat-cache.js");
      for (let i = 0; i < 11; i++) keep("v" + i, { msgs: [{ id: i }], more: false });
      const rows = Array.from({ length: 250 }, (_, i) => ({ id: i }));
      keep("big", { msgs: rows, more: false });
      const k = take("big");
      return { gone: [0, 1].map((i) => take("v" + i)), kept: [2, 10].map((i) => !!take("v" + i)), n: k.msgs.length, first: k.msgs[0].id, more: k.more };
    });
    assert.deepStrictEqual(cache.gone, [null, null], "11 views (+1) keep 10: the oldest go");
    assert.deepStrictEqual(cache.kept, [true, true], "the newest views stay");
    assert.deepStrictEqual([cache.n, cache.first, cache.more], [200, 50, true], "a view keeps its newest 200 rows and more = true");
    assert.deepStrictEqual(errs, [], "no page errors");
    console.log(`ok · first visit reading… ${Math.round(first.ms)} ms · cached open ${Math.round(back.ms)} / ${Math.round(again.ms)} ms (API ${DELAY} ms) · after= read, new row once · older page · cache 10 views, 200 rows`);
  } finally { await b.close(); api.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
