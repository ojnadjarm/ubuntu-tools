// Office chat panel and full screen (T1658). A creature's card → Message opens that seat's direct message in a dialog over the live office
// (history, attachment, who is thinking, composer); a send posts to this file's fixture server only; Esc, × and a click outside close it and
// the camera is where it was; Open in Chat lands on the Chat screen; the list's message button opens it too; the office keeps reading while
// it is open; 400 px: a bottom sheet with the office visible above it and the composer above a keyboard; Full screen on and off with the card
// and panel inside, and the fill-the-window fallback where element fullscreen does not exist; no sideways scroll at 5 widths.
// Run: node tests/test_office_chat.js   (fixture API only: every POST lands in this file's server, nothing reaches the real store)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan"];
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ORG = { seats: [{ id: "owner", name: "You", role: "owner", parent: null, wake: null }, ...FIX.seats], sessions: FIX.sessions, hidden: 0 };
const CH = "dm-mooblox--owner", T0 = Date.now() - 3600e3;
const row = (id, from, text, files) => ({ id, ts: new Date(id).toISOString(), ch: CH, from, to: [], kind: "msg", text, re: null, hop: 0, ...(files ? { files } : {}) });
const SIZES = [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]];
let store, thinking, posts, office;
const reset = () => {
  store = [row(T0, "owner", "How is the trading screen coming along?"), row(T0 + 60e3, "mooblox", "Two of three panels are done."),
    row(T0 + 120e3, "mooblox", "The test log.", [{ id: "f1", name: "run-log.txt", mime: "text/plain", size: 18432 }])];
  thinking = [{ seat: "mooblox", ch: CH, state: "thinking" }]; posts = []; office = 0;
};
reset();
const srv = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return STATUS;
  if (u === "/api/office") { office++; return FIX; }
  if (u === "/api/org") return ORG;
  if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
  if (u === "/api/chat") return { messages: (q.get("ch") === CH ? store : []).filter((m) => m.id > +(q.get("after") || 0)), channels: [{ ch: CH, unread: 0 }], wakes: { today: {} }, thinking };
});
const files = srv.listeners("request")[0];
srv.removeAllListeners("request");
srv.on("request", (req, res) => {
  if (req.method !== "POST") return files(req, res);
  let b = "";
  req.on("data", (d) => (b += d));
  req.on("end", () => {
    const body = JSON.parse(b || "{}");
    if (req.url.startsWith("/api/chat/post")) { posts.push(body); store.push({ ...row(Date.now(), "owner", body.text) }); res.end(JSON.stringify({ id: Date.now(), wakes: [{ seat: "mooblox", outcome: "woken" }] })); return; }
    res.end('{"ok":true}');
  });
});

let base;
async function office0(b, w, h, init) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, ...(w < 900 ? { hasTouch: true, isMobile: true } : {}) })).newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  if (init) await p.addInitScript(init);
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1, null, { timeout: 30000 });
  return { p, errs };
}
const at = (p, id) => p.evaluate((i) => { const q = window.__office.project(i), r = document.querySelector(".office .stage canvas").getBoundingClientRect(); return { x: r.left + q.x, y: r.top + q.y }; }, id);
const isOpen = (p) => p.evaluate(() => !!document.querySelector("dialog.otalk[open]"));
/* Tap Mossfang, then the card's Message button: the panel opens with its first read. */
async function talk(p) {
  const m = await at(p, "mooblox");
  await p.mouse.click(m.x, m.y + 14);
  await p.waitForSelector("#office-card:popover-open a.btn", { timeout: 5000 });
  await p.click("#office-card a.btn");
  await p.waitForSelector("dialog.otalk[open] .msgs .msg", { timeout: 8000 });
}
const box = (p, sel) => p.$eval(sel, (e) => { const r = e.getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom, w: r.width, h: r.height }; });

async function desktop(b) {
  const { p, errs } = await office0(b, 1366, 768);
  const cam0 = await at(p, "mooblox");
  await talk(p);
  assert.strictEqual(await p.evaluate(() => location.hash), "#org", "the Message button keeps the office on screen");
  assert.strictEqual(await p.$$eval("#office-card:popover-open", (l) => l.length), 0, "the card gives way to the panel");
  const v = await p.evaluate(() => { const d = document.querySelector("dialog.otalk"); return { label: d.getAttribute("aria-label"), h2: d.querySelector("h2").firstChild.textContent, rows: d.querySelectorAll(".msgs .msg").length,
    att: !!d.querySelector(".att.file"), think: d.querySelector(".thinking") && d.querySelector(".thinking").textContent.trim(), st: d.querySelector(".st").textContent, box: document.activeElement.id,
    full: d.querySelector("[data-full]").getAttribute("href"), canvas: document.querySelector(".office .stage canvas").isConnected }; });
  assert.deepStrictEqual(v, { label: "Talk to Mossfang", h2: "Mossfang", rows: 3, att: true, think: "Mossfang is thinking", st: "Mossfang is thinking", box: "say", full: "#chat?ch=" + CH, canvas: true }, "the panel: history, attachment, thinking, composer focused, the office behind");
  const d = await box(p, "dialog.otalk");
  assert.ok(d.w <= 1366 * 0.45 && d.r <= 1366 && d.b <= 768 && d.t >= 0, "desktop: a floating panel leaving most of the office visible: " + JSON.stringify(d));
  const n0 = office;
  for (let i = 0; i < 24 && office === n0; i++) await p.waitForTimeout(500);
  assert.ok(office > n0, `the office keeps reading /api/office behind the panel (${n0} → ${office})`);

  await p.fill("#say", "Ship the chart today, please.");
  await p.keyboard.press("Enter");
  await p.waitForFunction(() => [...document.querySelectorAll("dialog.otalk .msgs .msg .tx")].some((e) => e.textContent === "Ship the chart today, please."), null, { timeout: 8000 });
  assert.deepStrictEqual(posts, [{ ch: CH, text: "Ship the chart today, please." }], "Enter posts to the fixture seat's direct message");
  assert.match(await p.textContent("dialog.otalk .compose .hint"), /Sent\. Woke Mossfang\./, "the send's outcome under the box");

  await p.keyboard.press("Escape");
  assert.strictEqual(await isOpen(p), false, "Esc closes the panel");
  assert.strictEqual(await p.evaluate(() => location.hash), "#org", "Esc stays on the office");
  await talk(p);
  await p.click("dialog.otalk [data-shut]");
  assert.strictEqual(await isOpen(p), false, "× closes the panel");
  await talk(p);
  await p.mouse.click(60, 400);
  assert.strictEqual(await isOpen(p), false, "a click outside closes the panel");
  const cam1 = await at(p, "mooblox");
  assert.ok(Math.hypot(cam1.x - cam0.x, cam1.y - cam0.y) < 1, `closing returns to the same camera position: ${JSON.stringify([cam0, cam1])}`);

  await p.evaluate(() => document.querySelector('.office .olist a.msg[href="#chat?ch=dm-discord--owner"]').click());
  await p.waitForFunction(() => { const d = document.querySelector("dialog.otalk[open] h2"); return d && d.firstChild.textContent === "Cobalt"; }, null, { timeout: 8000 });
  await p.keyboard.press("Escape");

  await talk(p);
  await p.click("dialog.otalk [data-full]");
  await p.waitForSelector(".chat .stream header h2", { timeout: 15000 });
  assert.strictEqual(await p.evaluate(() => location.hash), "#chat?ch=" + CH, "Open in Chat lands on the same conversation");
  assert.match(await p.textContent(".chat .stream header h2"), /^Mossfang/, "Chat opens that direct message");
  assert.strictEqual(await p.$$eval("dialog.otalk", (l) => l.length), 0, "no panel node is left behind");
  assert.deepStrictEqual(errs, [], "no page errors at 1366");
  await p.context().close();
}

async function fullscreen(b) {
  const { p, errs } = await office0(b, 1366, 768);
  await p.click("#office-full");
  await p.waitForFunction(() => document.fullscreenElement === document.documentElement && document.documentElement.classList.contains("ofill"), null, { timeout: 5000 });
  const r0 = await box(p, ".office .stage");
  assert.deepStrictEqual([r0.l, r0.t, r0.w, r0.h].map(Math.round), [0, 0, 1366, 768], "full screen: the stage fills the screen");
  assert.strictEqual(await p.textContent("#office-full"), "Exit full screen", "the button says how to leave");
  await p.waitForTimeout(400);
  await talk(p);
  const inside = await p.evaluate(() => { const r = document.querySelector("dialog.otalk").getBoundingClientRect(); return !!document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2).closest("dialog.otalk"); });
  assert.ok(inside, "card and panel work inside full screen (the panel is on top)");
  await p.keyboard.press("Escape");
  await p.click("#office-full");
  await p.waitForFunction(() => !document.fullscreenElement && !document.documentElement.classList.contains("ofill"), null, { timeout: 5000 });
  assert.strictEqual(await p.textContent("#office-full"), "Full screen", "the button leaves full screen");
  await p.context().close();

  const f = await office0(b, 400, 850, () => { Object.defineProperty(Document.prototype, "fullscreenEnabled", { get: () => false }); });
  await f.p.click("#office-full");
  const fill = await f.p.evaluate(() => { const r = document.querySelector(".office .stage").getBoundingClientRect(), hit = document.elementFromPoint(20, 20);
    return { cls: document.documentElement.classList.contains("ofill"), r: [r.left, r.top, r.width, r.height].map(Math.round), top: !!hit.closest(".office .stage"), sw: document.documentElement.scrollWidth }; });
  assert.deepStrictEqual(fill, { cls: true, r: [0, 0, 400, 850], top: true, sw: 400 }, "no element fullscreen (iPhone): the stage fills the window over the chrome");
  await talk(f.p);
  assert.ok(await isOpen(f.p), "the panel opens in fill mode");
  await f.p.click("dialog.otalk [data-shut]");
  await f.p.keyboard.press("Escape");
  assert.strictEqual(await f.p.evaluate(() => document.documentElement.classList.contains("ofill")), false, "Esc leaves fill-the-window mode");
  assert.deepStrictEqual([...errs, ...f.errs], [], "no page errors in full screen");
  await f.p.context().close();
}

async function phone(b) {
  const { p, errs } = await office0(b, 400, 850);
  await talk(p);
  const s = await box(p, "dialog.otalk"), st = await box(p, ".office .stage"), c = await box(p, "dialog.otalk .compose");
  assert.ok(Math.round(s.b) === 850 && s.l === 0 && s.w === 400, "400: a bottom sheet: " + JSON.stringify(s));
  assert.ok(s.t > Math.max(st.t, 0) + 100, `400: the office shows above the sheet: sheet top ${s.t}, stage top ${st.t}`);
  assert.ok(c.b <= 850, "400: the composer is inside the sheet");
  const kb = await p.evaluate(() => {
    Object.defineProperty(visualViewport, "height", { configurable: true, get: () => 430 });
    visualViewport.dispatchEvent(new Event("resize"));
    return new Promise((ok) => requestAnimationFrame(() => { const r = document.querySelector("dialog.otalk .compose").getBoundingClientRect(); ok(Math.round(r.bottom)); }));
  });
  assert.ok(kb <= 430, `400: with the keyboard up (visual viewport 430 px) the composer stays above it: bottom ${kb}`);
  assert.deepStrictEqual(errs, [], "no page errors at 400");
  await p.context().close();
}

async function widths(b) {
  for (const [w, h] of SIZES) {
    const { p, errs } = await office0(b, w, h);
    await talk(p);
    const r = await p.evaluate(() => { const d = document.querySelector("dialog.otalk").getBoundingClientRect(); return { sw: document.documentElement.scrollWidth, l: d.left, r: d.right, t: d.top, b: d.bottom }; });
    assert.ok(r.sw === w && r.l >= 0 && r.r <= w && r.t >= 0 && Math.round(r.b) <= h, `${w}: panel inside the window, no sideways scroll: ${JSON.stringify(r)}`);
    assert.deepStrictEqual(errs, [], `${w}: no page errors`);
    await p.context().close();
  }
}

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ headless: true, args: ["--mute-audio", ...GPU] });
  const only = process.env.ONLY;
  try {
    for (const [k, fn] of [["desktop", desktop], ["full", fullscreen], ["phone", phone], ["widths", widths]]) {
      if (only && only !== k) continue;
      reset();
      await fn(b);
      console.log("ok " + k);
    }
    console.log("ok · panel over the office, send to the fixture seat, Esc/×/outside close, same camera, Open in Chat, list button, office reads on, sheet + keyboard at 400, full screen + fill fallback, 5 widths");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
