// Office talk panel moves (T1666). From 900 px the header drags the panel anywhere by mouse, touch and pen, clamped inside the window; a
// resize pulls it back; the drag never closes it or turns the camera; ×, the composer and a click outside still work; message text still
// selects; the spot is kept for the next panel; below 900 px the bottom sheet stays put.
// Run: node tests/test_office_drag.js   (fixture API only: the one post lands in this file's server)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan"];
const ORG = { seats: [{ id: "owner", name: "You", role: "owner", parent: null, wake: null }, ...FIX.seats], sessions: FIX.sessions, hidden: 0 };
const CH = "dm-mooblox--owner", T0 = Date.now() - 3600e3;
const row = (id, from, text) => ({ id, ts: new Date(id).toISOString(), ch: CH, from, to: [], kind: "msg", text, re: null, hop: 0 });
const store = [row(T0, "owner", "How is the trading screen coming along?"), row(T0 + 60e3, "mooblox", "Two of three panels are done.")], posts = [];
const srv = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
  if (u === "/api/office") return FIX;
  if (u === "/api/org") return ORG;
  if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
  if (u === "/api/chat") return { messages: (q.get("ch") === CH ? store : []).filter((m) => m.id > +(q.get("after") || 0)), channels: [{ ch: CH, unread: 0 }], wakes: { today: {} }, thinking: [] };
});
const files = srv.listeners("request")[0];
srv.removeAllListeners("request");
srv.on("request", (req, res) => {
  if (req.method !== "POST") return files(req, res);
  let b = "";
  req.on("data", (d) => (b += d));
  req.on("end", () => {
    const body = JSON.parse(b || "{}");
    if (req.url.startsWith("/api/chat/post")) { posts.push(body); store.push(row(Date.now(), "owner", body.text)); res.end(JSON.stringify({ id: Date.now(), wakes: [] })); return; }
    res.end('{"ok":true}');
  });
});

let base;
async function office(b, w, h, touch) {
  const p = await (await b.newContext({ viewport: { width: w, height: h }, ...(touch ? { hasTouch: true } : {}), ...(w < 900 ? { isMobile: true } : {}) })).newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForFunction(() => window.__office && window.__office.stats().frames >= 1, null, { timeout: 30000 });
  return { p, errs };
}
const at = (p, id) => p.evaluate((i) => { const q = window.__office.project(i), r = document.querySelector(".office .stage canvas").getBoundingClientRect(); return { x: r.left + q.x, y: r.top + q.y }; }, id);
const isOpen = (p) => p.evaluate(() => !!document.querySelector("dialog.otalk[open]"));
const rect = (p) => p.$eval("dialog.otalk", (e) => { const r = e.getBoundingClientRect(); return { l: Math.round(r.left), t: Math.round(r.top), r: Math.round(r.right), b: Math.round(r.bottom) }; });
const grip = (p) => p.$eval("dialog.otalk h2", (e) => { const r = e.getBoundingClientRect(); return { x: r.left + 12, y: r.top + r.height / 2 }; });
async function talk(p) {
  const m = await at(p, "mooblox");
  await p.mouse.click(m.x, m.y + 14);
  await p.waitForSelector("#office-card:popover-open a.btn", { timeout: 5000 });
  await p.click("#office-card a.btn");
  await p.waitForSelector("dialog.otalk[open] .msgs .msg", { timeout: 8000 });
}
/* A real pointer drag from the header's name to (x, y): mouse or pen through CDP mouse events, touch through CDP touch events. */
async function drag(p, x, y, kind = "mouse") {
  const s = await grip(p), n = 12;
  if (kind === "touch") {
    const c = await p.context().newCDPSession(p);
    await c.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: s.x, y: s.y }] });
    for (let i = 1; i <= n; i++) await c.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: s.x + (x - s.x) * i / n, y: s.y + (y - s.y) * i / n }] });
    await c.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await c.detach();
  } else if (kind === "pen") {
    const c = await p.context().newCDPSession(p), ev = (type, px, py, extra = {}) => c.send("Input.dispatchMouseEvent", { type, x: px, y: py, pointerType: "pen", ...extra });
    await ev("mousePressed", s.x, s.y, { button: "left", buttons: 1, clickCount: 1 });
    for (let i = 1; i <= n; i++) await ev("mouseMoved", s.x + (x - s.x) * i / n, s.y + (y - s.y) * i / n, { button: "left", buttons: 1 });
    await ev("mouseReleased", x, y, { button: "left", buttons: 0, clickCount: 1 });
    await c.detach();
  } else {
    await p.mouse.move(s.x, s.y); await p.mouse.down();
    await p.mouse.move(x, y, { steps: n }); await p.mouse.up();
  }
  await p.waitForTimeout(150);
}

async function desktop(b) {
  const { p, errs } = await office(b, 1366, 768);
  const cam0 = await at(p, "mooblox");
  await talk(p);
  const r0 = await rect(p), s0 = await grip(p);
  await drag(p, s0.x - 300, s0.y - 100);
  const r1 = await rect(p);
  assert.ok(await isOpen(p), "a header drag keeps the panel open");
  assert.ok(Math.abs(r1.l - (r0.l - 300)) <= 1 && Math.abs(r1.t - (r0.t - 100)) <= 1, `the panel follows the pointer: ${JSON.stringify([r0, r1])}`);

  await drag(p, -400, -400);
  assert.deepStrictEqual([(await rect(p)).l, (await rect(p)).t], [0, 0], "dragged past the top left corner it stops at the edge");
  await drag(p, 3000, 3000);
  const r2 = await rect(p);
  assert.ok(await isOpen(p) && r2.r === 1366 && r2.b === 768, "past the bottom right corner it stops inside, still open: " + JSON.stringify(r2));
  const cam1 = await at(p, "mooblox");
  assert.ok(Math.hypot(cam1.x - cam0.x, cam1.y - cam0.y) < 1, `the drags never turned the camera: ${JSON.stringify([cam0, cam1])}`);

  await p.mouse.click((await grip(p)).x, (await grip(p)).y);
  assert.ok(await isOpen(p), "a click on the header without moving keeps the panel open");
  const sel = await p.evaluate(() => { const t = document.querySelector("dialog.otalk .msgs .msg .tx"), r = t.getBoundingClientRect(); return { x: r.left + 2, y: r.top + r.height / 2, w: Math.min(r.width - 4, 120) }; });
  const r3 = await rect(p);
  await p.mouse.move(sel.x, sel.y); await p.mouse.down(); await p.mouse.move(sel.x + sel.w, sel.y, { steps: 6 }); await p.mouse.up();
  assert.ok((await p.evaluate(() => getSelection().toString())).length > 3, "message text still selects by mouse");
  assert.deepStrictEqual(await rect(p), r3, "selecting text does not move the panel");

  await p.fill("#say", "Moved panel, fixture message.");
  await p.keyboard.press("Enter");
  await p.waitForFunction(() => [...document.querySelectorAll("dialog.otalk .msgs .msg .tx")].some((e) => e.textContent === "Moved panel, fixture message."), null, { timeout: 8000 });
  assert.deepStrictEqual(posts, [{ ch: CH, text: "Moved panel, fixture message." }], "the composer still posts to the fixture seat");

  await drag(p, 500, 200);
  const kept = await rect(p);
  await p.click("dialog.otalk [data-shut]");
  assert.strictEqual(await isOpen(p), false, "× still closes it");
  await p.evaluate(() => document.querySelector('.office .olist a.msg[href="#chat?ch=dm-discord--owner"]').click());
  await p.waitForFunction(() => { const d = document.querySelector("dialog.otalk[open] h2"); return d && d.firstChild.textContent === "Cobalt"; }, null, { timeout: 8000 });
  assert.deepStrictEqual(await rect(p), kept, "the next agent's panel opens where he left the last one");

  await p.mouse.click(kept.r + 60 < 1366 ? kept.r + 60 : 20, 400);
  assert.strictEqual(await isOpen(p), false, "a click outside still closes it");

  await talk(p);
  await drag(p, 3000, 3000);
  await p.setViewportSize({ width: 1000, height: 600 });
  await p.waitForTimeout(200);
  const r4 = await rect(p);
  assert.ok(r4.l >= 0 && r4.t >= 0 && r4.r <= 1000 && r4.b <= 600, "a smaller window pulls the panel back inside: " + JSON.stringify(r4));
  await p.setViewportSize({ width: 800, height: 900 });
  await p.waitForTimeout(200);
  const r5 = await rect(p);
  assert.ok(r5.l === 0 && r5.r === 800 && r5.b === 900, "below 900 px the bottom sheet comes back: " + JSON.stringify(r5));
  assert.deepStrictEqual(errs, [], "no page errors at 1366");
  await p.context().close();
}

async function touchPen(b) {
  const { p, errs } = await office(b, 1366, 768, true);
  await talk(p);
  const dx = (await grip(p)).x - (await rect(p)).l;
  await drag(p, 300, 150, "touch");
  const r = await rect(p);
  assert.ok(await isOpen(p) && Math.abs(r.l - (300 - dx)) <= 2, "a finger on the header moves the panel: " + JSON.stringify(r));
  await drag(p, 900, 500, "pen");
  const q = await rect(p);
  assert.ok(await isOpen(p) && Math.abs(q.l - (900 - dx)) <= 2, "a pen on the header moves the panel: " + JSON.stringify(q));
  assert.deepStrictEqual(errs, [], "no page errors with touch and pen");
  await p.context().close();
}

async function phone(b) {
  const { p, errs } = await office(b, 400, 850, true);
  await talk(p);
  const r0 = await rect(p);
  await drag(p, 200, 100, "touch");
  assert.ok(await isOpen(p), "400: a drag on the sheet's header keeps it open");
  assert.deepStrictEqual(await rect(p), r0, "400: the bottom sheet stays put");
  assert.deepStrictEqual(errs, [], "no page errors at 400");
  await p.context().close();
}

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ headless: true, args: ["--mute-audio", ...GPU] });
  const only = process.env.ONLY;
  try {
    for (const [k, fn] of [["desktop", desktop], ["touch", touchPen], ["phone", phone]]) {
      if (only && only !== k) continue;
      await fn(b);
      console.log("ok " + k);
    }
    console.log("ok · header drag by mouse, touch, pen; clamped; resize pulls back; open, camera kept; ×, composer, outside click, text select; spot kept; sheet at 400");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
