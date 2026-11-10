// Chat attachments and history (T1515-P33): Recent across channels with channel tags, attachments in the stream (thumbnail
// links to full size, file chip downloads), 50 per channel then older on scroll-up, paste / drop / attach chips in the
// composer, removable, uploaded then posted; the 10 MiB cap; no sideways scroll at 400.
// Run: node tests/test_chat_attach.js [shot-dir]   (fixture API only: every request lands in this file's server; a shot-dir gets PNGs of Recent and the chips)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ORG = { seats: [
  { id: "owner", name: "You", role: "owner", parent: null, wake: null, match: null },
  { id: "orchestrator", name: "Orchestrator", role: "ceo", parent: "owner", wake: "channel", match: "~" },
  { id: "mooblox", name: "Mooblox", role: "po", parent: "orchestrator", wake: "po-inbox", match: "~/agents/po-mooblox" }], sessions: [], hidden: 0 };
const T0 = Date.UTC(2026, 10, 9, 21, 0);
const IMG = "aaaaaaaaaaaaaaaa", PDF = "bbbbbbbbbbbbbbbb";
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC", "base64");
const row = (id, ch, from, text, files) => ({ id, ts: new Date(id).toISOString(), ch, from, to: [], kind: "msg", text, re: null, hop: 0, ...(files ? { files } : {}) });
const HARNESS = Array.from({ length: 60 }, (_, i) => row(T0 + i * 1000, "harness", "mooblox", "h" + i));
const RECENT = [
  row(T0 - 3000, "org", "orchestrator", "org news"),
  row(T0 - 2000, "dm-mooblox--owner", "mooblox", "the screenshot", [{ id: IMG, name: "screen.png", size: 69, mime: "image/png" }]),
  row(T0 - 1000, "mooblox", "mooblox", "the report", [{ id: PDF, name: "report.pdf", size: 1258291, mime: "application/pdf" }]),
  HARNESS[59]];
const page = (rows, q) => {
  const after = +(q.get("after") || 0), before = +(q.get("before") || 0);
  if (after) return { messages: rows.filter((m) => m.id > after), more: false };
  const older = rows.filter((m) => !before || m.id < before);
  return { messages: older.slice(-50), more: older.length > 50 };
};
const uploads = [], posts = [], gets = [], SHOTS = process.argv[2];
let n = 0;

const api = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") {
    gets.push(res.req.url);
    const got = q.get("recent") === "1" ? page(RECENT, q) : q.get("ch") === "harness" ? page(HARNESS, q) : { messages: [], more: false };
    return { ...got, channels: [{ ch: "harness", unread: 0 }, { ch: "org", unread: 0 }, { ch: "mooblox", unread: 0 }, { ch: "dm-mooblox--owner", unread: 0 }], wakes: { cap: 12, today: {} } };
  }
  if (u.startsWith("/api/chat/file/")) { res.writeHead(200, { "Content-Type": "image/png" }); return res.end(PNG); }
});
const statics = api.listeners("request")[0];
api.removeAllListeners("request");
api.on("request", (req, res) => {
  if (req.method !== "POST") return statics(req, res);
  const parts = [];
  req.on("data", (d) => parts.push(d));
  req.on("end", () => {
    const body = Buffer.concat(parts), u = req.url.split("?")[0];
    res.writeHead(200, { "Content-Type": "application/json" });
    if (u === "/api/chat/upload") {
      const m = { id: (++n).toString(16).padStart(16, "0"), name: decodeURIComponent(req.headers["x-file-name"]), size: body.length, mime: "application/octet-stream" };
      uploads.push({ name: m.name, size: body.length });
      return res.end(JSON.stringify(m));
    }
    if (u === "/api/chat/post") { posts.push(JSON.parse(body)); return res.end(JSON.stringify({ id: T0 + 99000, wakes: [] })); }
    res.end("{}");
  });
});

(async () => {
  await new Promise((ok) => api.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + api.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const ctx = await b.newContext({ viewport: { width: 1366, height: 768 } });
    const p = await ctx.newPage(), errs = [];
    p.on("pageerror", (e) => errs.push(String(e)));

    await p.goto(base + "/#chat", { waitUntil: "load" });
    await p.waitForFunction(() => (document.querySelector(".chat .stream header h2") || {}).textContent === "Recent", null, { timeout: 15000 });
    assert.strictEqual(await p.getAttribute(".chat .chans a.on", "data-ch"), "", "Chat opens on Recent");
    assert.ok(gets.some((g) => g.includes("recent=1")), "Recent reads ?recent=1");
    const tags = await p.$$eval(".chat .msg .chtag", (t) => t.map((x) => x.textContent));
    assert.deepStrictEqual(tags, ["# org", "Mooblox", "# mooblox", "# harness"], "every Recent message carries its channel");
    assert.strictEqual(await p.$eval(".chat .msg:last-of-type .tx", (e) => e.textContent), "h59", "newest at the bottom");
    assert.strictEqual(await p.$$eval(".chat .compose", (f) => f.length), 0, "Recent has no composer: it names no channel");
    if (SHOTS) { await p.waitForTimeout(2500); await p.screenshot({ path: SHOTS + "/fixture-recent-1366.png" }); }

    const img = await p.$eval(".chat .att.img", (a) => ({ href: a.getAttribute("href"), src: a.querySelector("img").getAttribute("src"), alt: a.querySelector("img").alt }));
    assert.deepStrictEqual(img, { href: "/api/chat/file/" + IMG, src: "/api/chat/file/" + IMG + "?thumb=1", alt: "screen.png" }, "an image: its thumbnail, tap opens full size");
    const doc = await p.$eval(".chat .att.file", (a) => ({ href: a.getAttribute("href"), dl: a.getAttribute("download"), text: a.textContent }));
    assert.deepStrictEqual(doc, { href: "/api/chat/file/" + PDF, dl: "report.pdf", text: "report.pdf1.2 MB" }, "a file: a chip with name and size that downloads");

    await p.click('.chat .chans [data-ch="harness"]');
    await p.waitForFunction(() => document.querySelectorAll(".chat .msg").length === 50, null, { timeout: 5000 });
    assert.strictEqual(await p.$eval(".chat .msg .tx", (e) => e.textContent), "h10", "a channel opens on its newest 50");
    await p.$eval(".chat .msgs", (e) => { e.scrollTop = 0; });
    await p.waitForFunction(() => document.querySelectorAll(".chat .msg").length === 60, null, { timeout: 5000 });
    assert.ok(gets.some((g) => g.includes("ch=harness") && g.includes("before=" + HARNESS[10].id)), "scroll-up asks for what is before the oldest shown");
    assert.strictEqual(await p.$$eval(".chat .older", (e) => e.length), 0, "nothing older: no loader");

    const chips = () => p.$$eval(".chat .compose .chip", (c) => c.map((x) => x.querySelector(".nm").textContent + (x.querySelector("img") ? "+img" : "")));
    await p.evaluate((b64) => {
      const dt = new DataTransfer(), raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      dt.items.add(new File([raw], "clip.png", { type: "image/png" }));
      document.querySelector(".chat .compose textarea").dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
    }, PNG.toString("base64"));
    await p.waitForFunction(() => document.querySelectorAll(".chat .compose .chip").length === 1, null, { timeout: 3000 });
    assert.deepStrictEqual(await chips(), ["clip.png+img"], "paste: an image from the clipboard becomes a chip with its preview");

    await p.evaluate(() => {
      const dt = new DataTransfer();
      dt.items.add(new File(["some notes"], "notes.txt", { type: "text/plain" }));
      const s = document.querySelector(".chat .stream");
      s.dispatchEvent(new DragEvent("dragover", { dataTransfer: dt, bubbles: true, cancelable: true }));
      s.dispatchEvent(new DragEvent("drop", { dataTransfer: dt, bubbles: true, cancelable: true }));
    });
    await p.waitForFunction(() => document.querySelectorAll(".chat .compose .chip").length === 2, null, { timeout: 3000 });
    assert.deepStrictEqual(await chips(), ["clip.png+img", "notes.txt"], "drop: a dropped file becomes a chip");

    await p.setInputFiles(".chat .compose input[type=file]", { name: "doc.pdf", mimeType: "application/pdf", buffer: Buffer.from("%PDF-1.4 x") });
    await p.waitForFunction(() => document.querySelectorAll(".chat .compose .chip").length === 3, null, { timeout: 3000 });
    assert.deepStrictEqual(await chips(), ["clip.png+img", "notes.txt", "doc.pdf"], "attach: the picker's file becomes a chip");

    await p.click('.chat .compose .chip:nth-child(2) button[aria-label^="Remove"]');
    await p.waitForFunction(() => document.querySelectorAll(".chat .compose .chip").length === 2, null, { timeout: 3000 });
    assert.deepStrictEqual(await chips(), ["clip.png+img", "doc.pdf"], "a chip is removable before sending");

    await p.setInputFiles(".chat .compose input[type=file]", { name: "huge.bin", mimeType: "application/octet-stream", buffer: Buffer.alloc(10 * 1024 * 1024 + 1) });
    await p.waitForFunction(() => /10 MiB/.test(document.querySelector(".chat .compose .hint").textContent), null, { timeout: 3000 });
    assert.strictEqual((await chips()).length, 2, "over 10 MiB: not added, the hint says why");

    if (SHOTS) {
      await p.screenshot({ path: SHOTS + "/fixture-chips-1366.png" });
      await p.setViewportSize({ width: 400, height: 850 });
      await p.waitForTimeout(300);
      await p.screenshot({ path: SHOTS + "/fixture-chips-400.png" });
      await p.setViewportSize({ width: 1366, height: 768 });
    }
    await p.fill(".chat .compose textarea", "look");
    await p.press(".chat .compose textarea", "Enter");
    await p.waitForFunction(() => /^Sent\./.test(document.querySelector(".chat .compose .hint").textContent), null, { timeout: 5000 });
    assert.deepStrictEqual(uploads, [{ name: "clip.png", size: PNG.length }, { name: "doc.pdf", size: 10 }], "each chip uploaded once, as raw bytes with its name");
    assert.deepStrictEqual(posts, [{ ch: "harness", text: "look", files: ["0000000000000001", "0000000000000002"] }], "then one post carries the file ids");
    assert.deepStrictEqual(await chips(), [], "a sent message clears the chips");

    await p.fill(".chat .compose textarea", "half a sentence");
    await p.$eval(".chat .compose textarea", (t) => { t.focus(); t.kept = 1; });
    const kept = () => p.evaluate(() => { const t = document.querySelector(".chat .compose textarea"); return [t.value, t.kept === 1, document.activeElement === t]; });
    await p.setInputFiles(".chat .compose input[type=file]", { name: "late.txt", mimeType: "text/plain", buffer: Buffer.from("x") });
    await p.waitForFunction(() => document.querySelectorAll(".chat .compose .chip").length === 1, null, { timeout: 3000 });
    assert.deepStrictEqual(await kept(), ["half a sentence", true, true], "attaching keeps the typed text, the same box and its focus");
    await p.click('.chat .compose .chip button[aria-label^="Remove"]');
    await p.waitForFunction(() => document.querySelectorAll(".chat .compose .chip").length === 0, null, { timeout: 3000 });
    assert.deepStrictEqual((await kept()).slice(0, 2), ["half a sentence", true], "removing the last chip keeps the typed text and the same box");
    assert.strictEqual(await p.$eval(".chat .compose .chips", (u) => getComputedStyle(u).display), "none", "no files: the chips list takes no space");
    await p.fill(".chat .compose textarea", "");

    await p.setViewportSize({ width: 400, height: 850 });
    await p.waitForTimeout(500);
    const lay = await p.evaluate(() => { const a = document.querySelector(".chat .compose .attach").getBoundingClientRect(); return { sw: document.documentElement.scrollWidth, left: a.left >= 0, right: a.right <= innerWidth, h: Math.round(a.height) }; });
    assert.deepStrictEqual(lay, { sw: 400, left: true, right: true, h: 44 }, "at 400 the attach button is a 44 px target in view, no sideways scroll");
    assert.deepStrictEqual(errs, [], "no page errors");
    console.log("ok · Recent with channel tags · thumbnail + file chip · 50 then older on scroll-up · paste / drop / attach chips · remove · 10 MiB cap · upload then post · 400 px");
  } finally { await b.close(); api.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
