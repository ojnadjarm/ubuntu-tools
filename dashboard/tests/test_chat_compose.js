// Chat composer @ list (T1545-E): `@` at a word start opens the seats he can wake (not the owner, not pull seats), name + id + state;
// typing filters by name or id; Up/Down, Enter, Tab or a tap insert `@<id> `; Esc closes; Enter with the list open does not post;
// `a@b` does not open; the hint names who a send wakes; the list survives the 3 s repaint; at 400 it sits above the box, rows 44 px.
// Drafts and the reply chip (T1545-G): each channel keeps its box text across a switch, a reload and a poll repaint (caret in place),
// in localStorage chat.draft.<ch>; a 200 send or an emptied box clears it, a 422 keeps it; `chat:reply` shows "Replying to …" with ×,
// the post carries `re`, the chip goes after a send, ×, Esc in an empty box or a channel change; at 400 it fits, × is 44 px.
// Run: node tests/test_chat_compose.js [shot-dir]   (fixture API only; a shot-dir gets the open list and a draft + reply chip at the 5 widths)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ORG = { seats: [
  { id: "owner", name: "You", role: "owner", parent: null, wake: null, match: null },
  { id: "orchestrator", name: "Orchestrator", role: "ceo", parent: "owner", wake: "channel", match: "~" },
  { id: "discord-po", name: "Discord product owner", role: "po", parent: "orchestrator", wake: "po-inbox", match: "~/agents/po-discord" },
  { id: "tiny-epic-narrator", name: "Tiny Epic Narrator manager", role: "manager", parent: "orchestrator", wake: "po-inbox", match: "~/projects/x" },
  { id: "vass", name: "Vass", role: "po", parent: "orchestrator", wake: "pull", match: "~/vass" }],
  sessions: [{ seat: "orchestrator", pid: 11, state: "working" }], hidden: 0 };
const T0 = Date.UTC(2026, 10, 10, 9, 0);
const ROWS = [{ id: T0, ts: new Date(T0).toISOString(), ch: "harness", from: "orchestrator", to: [], kind: "msg", text: "hello", re: null, hop: 0 }];
const WIDTHS = [400, 768, 1366, 1920, 2560], SHOTS = process.argv[2], posts = [];

const api = serveStatic((u, res) => {
  const q = new URL(res.req.url, "http://x").searchParams;
  if (u === "/api/status") return STATUS;
  if (u === "/api/org") return ORG;
  if (u === "/api/chat") {
    const msgs = q.get("ch") === "harness" && !q.get("after") ? ROWS : [];
    return { messages: msgs, more: false, channels: [{ ch: "harness", unread: 0 }, { ch: "org", unread: 0 }], wakes: { cap: 12, today: {} } };
  }
});
const statics = api.listeners("request")[0];
api.removeAllListeners("request");
api.on("request", (req, res) => {
  if (req.method !== "POST") return statics(req, res);
  const parts = [];
  req.on("data", (d) => parts.push(d));
  req.on("end", () => {
    const body = req.url.startsWith("/api/chat/post") ? JSON.parse(Buffer.concat(parts)) : {};
    if (body.ch) posts.push(body);
    const held = /HOLD/.test(body.text || "");
    res.writeHead(held ? 422 : 200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(held ? { error: "held", held: "a secret" } : { id: T0 + 1, wakes: [] }));
  });
});

const BOX = ".chat .compose textarea", LIST = ".chat .compose [role=listbox]";
(async () => {
  await new Promise((ok) => api.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + api.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const ctx = await b.newContext({ viewport: { width: 1366, height: 768 } });
    const p = await ctx.newPage(), errs = [];
    p.on("pageerror", (e) => errs.push(String(e)));
    await p.goto(base + "/#chat?ch=harness", { waitUntil: "load" });
    await p.waitForSelector(BOX, { timeout: 15000 });
    await p.waitForTimeout(600);
    const typeIn = async (t) => { await p.fill(BOX, ""); await p.focus(BOX); await p.keyboard.type(t); await p.waitForTimeout(150); };
    const open = () => p.$eval(LIST, (l) => !l.hidden).catch(() => false);
    const ids = () => p.$$eval(LIST + " [role=option]", (o) => o.map((x) => x.dataset.id));
    const val = () => p.$eval(BOX, (t) => t.value);

    if (SHOTS) {
      for (const w of WIDTHS) {
        await p.setViewportSize({ width: w, height: w < 900 ? 850 : w > 2000 ? 1440 : w > 1500 ? 1080 : 768 });
        await typeIn("@");
        await p.waitForTimeout(400);
        await p.screenshot({ path: `${SHOTS}/compose-mention-${w}.png` });
      }
      await p.setViewportSize({ width: 1366, height: 768 });
    }

    await typeIn("@");
    assert.ok(await open(), "@ at a word start opens the list");
    assert.deepStrictEqual(await ids(), ["orchestrator", "discord-po", "tiny-epic-narrator"], "every seat he can wake, not the owner, not a pull seat");
    const row = await p.$eval(LIST + " [role=option]", (o) => ({ name: o.querySelector(".nm").textContent, id: o.querySelector(".id").textContent, st: o.querySelector(".pill").textContent }));
    assert.deepStrictEqual(row, { name: "Orchestrator", id: "@orchestrator", st: "working" }, "a row: name, id, state");
    const aria = await p.$eval(BOX, (t) => ({ exp: t.getAttribute("aria-expanded"), act: t.getAttribute("aria-activedescendant"), ctl: t.getAttribute("aria-controls") }));
    const first = await p.$eval(LIST + " [role=option]", (o) => ({ id: o.id, sel: o.getAttribute("aria-selected") }));
    assert.deepStrictEqual(aria, { exp: "true", act: first.id, ctl: await p.$eval(LIST, (l) => l.id) }, "the box is expanded, points at the active row and the list");
    assert.strictEqual(first.sel, "true", "the active row is selected");

    await p.waitForTimeout(3500);
    assert.ok(await open(), "the list survives the poll's repaint");
    assert.deepStrictEqual(await ids(), ["orchestrator", "discord-po", "tiny-epic-narrator"], "same rows after the repaint");

    await typeIn("@product");
    assert.deepStrictEqual(await ids(), ["discord-po"], "filters by name");
    await typeIn("@epic-n");
    assert.deepStrictEqual(await ids(), ["tiny-epic-narrator"], "filters by id");
    await typeIn("@vas");
    assert.ok(!(await open()), "a pull seat is never listed: nothing matches, the list closes");

    await typeIn("@");
    await p.keyboard.press("ArrowDown");
    await p.keyboard.press("ArrowDown");
    await p.keyboard.press("ArrowUp");
    assert.strictEqual(await p.$eval(BOX, (t) => t.getAttribute("aria-activedescendant")), await p.$eval(LIST + " [role=option]:nth-child(2)", (o) => o.id), "Down, Down, Up: the second row");
    await p.keyboard.press("Enter");
    await p.waitForTimeout(300);
    assert.strictEqual(await val(), "@discord-po ", "Enter inserts the active id");
    assert.ok(!(await open()), "and closes the list");
    assert.deepStrictEqual(posts, [], "Enter with the list open does not post");

    await typeIn("hi @tin");
    await p.keyboard.press("Tab");
    assert.strictEqual(await val(), "hi @tiny-epic-narrator ", "Tab inserts");
    assert.ok(await p.$eval(BOX, (t) => t === document.activeElement), "focus stays in the box");

    await typeIn("x @");
    await p.click(LIST + ' [data-id="orchestrator"]');
    await p.waitForTimeout(200);
    assert.strictEqual(await val(), "x @orchestrator ", "a tap inserts");
    assert.strictEqual(await p.$eval(BOX, (t) => t.selectionStart), "x @orchestrator ".length, "the caret after the inserted id");

    await typeIn("@");
    await p.keyboard.press("Escape");
    assert.ok(!(await open()), "Esc closes");
    assert.strictEqual(await p.$eval(BOX, (t) => t.getAttribute("aria-expanded")), "false", "the box says closed");
    assert.strictEqual(await val(), "@", "Esc leaves the text");

    await typeIn("mail a@b");
    assert.ok(!(await open()), "a@b (mail-like) does not open");

    const hint = () => p.$eval(".chat .compose .hint", (h) => h.textContent);
    await typeIn("@discord-po @orchestrator @vass @nobody hi");
    assert.strictEqual(await hint(), "Wakes Discord product owner, Orchestrator.", "the hint names who a send wakes");
    await p.waitForTimeout(3200);
    assert.strictEqual(await hint(), "Wakes Discord product owner, Orchestrator.", "the hint survives the repaint");
    await typeIn("plain");
    assert.ok(/^Put @ and a name/.test(await hint()), "no mention: the usual hint");

    await p.goto(base + "/#chat?ch=dm-discord-po--owner", { waitUntil: "load" });
    await p.waitForSelector(BOX, { timeout: 15000 });
    await p.waitForTimeout(600);
    assert.strictEqual(await hint(), "A direct message wakes Discord product owner now.", "the direct-message hint stays");
    await typeIn("ask @orchestrator");
    assert.strictEqual(await hint(), "A direct message wakes Discord product owner now. Also wakes Orchestrator.", "a mention in a direct message adds to it");

    await p.setViewportSize({ width: 400, height: 850 });
    await p.waitForTimeout(400);
    await typeIn("@");
    const lay = await p.evaluate(() => {
      const l = document.querySelector(".chat .compose [role=listbox]").getBoundingClientRect(), t = document.querySelector(".chat .compose textarea").getBoundingClientRect();
      const hs = [...document.querySelectorAll(".chat .compose [role=option]")].map((o) => Math.round(o.getBoundingClientRect().height));
      return { inside: l.left >= 0 && l.right <= innerWidth && l.top >= 0 && l.bottom <= innerHeight, above: l.bottom <= t.top + 1, rows: hs.every((h) => h >= 44), sw: document.documentElement.scrollWidth };
    });
    assert.deepStrictEqual(lay, { inside: true, above: true, rows: true, sw: 400 }, "at 400: the list above the box, inside the screen, rows 44 px, no sideways scroll");
    await p.setViewportSize({ width: 1366, height: 768 });
    await p.waitForTimeout(300);
    const desk = await p.$$eval(LIST + " [role=option]", (o) => o.length === 3 && o.every((x) => Math.round(x.getBoundingClientRect().height) >= 32));
    assert.ok(desk, "at 1366 rows are 32 px targets at least");
    assert.deepStrictEqual(posts, [], "nothing posted in the whole run");
    assert.deepStrictEqual(errs, [], "no page errors");
    console.log("ok · @ opens · name/id/state rows · no owner, no pull seat · survives repaint · filter by name and id · Up/Down/Enter/Tab/tap · Enter does not post · Esc · a@b · hint names wakes · DM hint · 400 above, 44 px · 1366 32 px");
    posts.length = 0;
    const c2 = await b.newContext({ viewport: { width: 1366, height: 768 } });
    const q = await c2.newPage();
    q.on("pageerror", (e) => errs.push(String(e)));
    const CHIP = ".chat .compose .reply", value = () => q.$eval(BOX, (t) => t.value);
    const to = async (c) => { await q.evaluate((c) => { location.hash = "#chat?ch=" + c; }, c); await q.waitForFunction((c) => { const f = document.querySelector(".chat .compose"); return f && f.dataset.to === c; }, c); await q.waitForTimeout(250); };
    const stored = (c) => q.evaluate((c) => localStorage.getItem("chat.draft." + c), c);
    const reply = (d) => q.evaluate((d) => document.dispatchEvent(new CustomEvent("chat:reply", { detail: d })), d);
    const chipOn = () => q.$eval(CHIP, (c) => !c.hidden && c.getBoundingClientRect().height > 0).catch(() => false);
    const typeQ = async (t) => { await q.focus(BOX); await q.keyboard.type(t); await q.waitForTimeout(150); };
    const LONG = "hello there, this is a long message that goes on well past the sixty characters of the chip";
    await q.goto(base + "/#chat?ch=harness", { waitUntil: "load" });
    await q.waitForSelector(BOX, { timeout: 15000 });
    await q.waitForTimeout(600);

    if (SHOTS) {
      for (const w of WIDTHS) {
        await q.setViewportSize({ width: w, height: w < 900 ? 850 : w > 2000 ? 1440 : w > 1500 ? 1080 : 768 });
        await q.fill(BOX, "");
        await typeQ("A draft kept across a channel switch");
        await to("org"); await to("harness");
        await reply({ ch: "harness", id: T0, name: "Orchestrator", text: LONG });
        await q.waitForTimeout(400);
        await q.screenshot({ path: `${SHOTS}/compose-draft-reply-${w}.png` });
        await q.fill(BOX, ""); await q.dispatchEvent(BOX, "input");
        await q.click(CHIP + " button").catch(() => {});
      }
      await q.setViewportSize({ width: 1366, height: 768 });
      await q.goto(base + "/#chat?ch=harness", { waitUntil: "load" });
      await q.evaluate(() => localStorage.clear());
      await q.reload({ waitUntil: "load" });
      await q.waitForSelector(BOX, { timeout: 15000 });
      await q.waitForTimeout(600);
    }

    await typeQ("draft one");
    assert.strictEqual(await stored("harness"), "draft one", "the draft is stored as chat.draft.harness");
    await q.keyboard.press("Home");
    for (let i = 0; i < 3; i++) await q.keyboard.press("ArrowRight");
    await q.waitForTimeout(3500);
    const kept = await q.$eval(BOX, (t) => ({ v: t.value, at: t.selectionStart, f: t === document.activeElement }));
    assert.deepStrictEqual(kept, { v: "draft one", at: 3, f: true }, "a poll repaint keeps the text, the caret and the focus");
    await to("org");
    assert.strictEqual(await value(), "", "another channel has its own (empty) box");
    await typeQ("org text");
    await to("harness");
    assert.strictEqual(await value(), "draft one", "back in harness: its draft");
    await to("org");
    assert.strictEqual(await value(), "org text", "back in org: its draft");
    await q.reload({ waitUntil: "load" });
    await q.waitForSelector(BOX, { timeout: 15000 });
    await q.waitForTimeout(600);
    assert.strictEqual(await value(), "org text", "a reload puts the draft back");
    await q.fill(BOX, ""); await q.dispatchEvent(BOX, "input");
    assert.strictEqual(await stored("org"), null, "an emptied box removes the draft");

    await to("harness");
    await q.fill(BOX, ""); await typeQ("please HOLD this");
    await q.keyboard.press("Enter");
    await q.waitForFunction(() => /^Held/.test(document.querySelector(".chat .compose .hint").textContent));
    assert.strictEqual(await value(), "please HOLD this", "a held post keeps the box");
    assert.strictEqual(await stored("harness"), "please HOLD this", "and the stored draft");
    await q.fill(BOX, ""); await typeQ("sent text");
    await q.keyboard.press("Enter");
    await q.waitForFunction(() => /^Sent/.test(document.querySelector(".chat .compose .hint").textContent));
    assert.strictEqual(await value(), "", "a sent post empties the box");
    assert.strictEqual(await stored("harness"), null, "and removes the draft");
    await to("org"); await to("harness");
    assert.strictEqual(await value(), "", "still empty after a switch");

    await reply({ ch: "harness", id: T0, name: "Orchestrator", text: LONG });
    await q.waitForTimeout(200);
    assert.ok(await chipOn(), "chat:reply shows the chip");
    assert.strictEqual(await q.$eval(CHIP + " .q", (c) => c.textContent), "Replying to Orchestrator: " + LONG.slice(0, 60) + "…", "name and the first 60 characters");
    assert.ok(await q.$eval(BOX, (t) => t === document.activeElement), "the box takes the focus");
    await q.waitForTimeout(3300);
    assert.ok(await chipOn(), "the chip survives the poll's repaint");
    await typeQ("my answer");
    await q.keyboard.press("Enter");
    await q.waitForFunction(() => /^Sent/.test(document.querySelector(".chat .compose .hint").textContent));
    assert.deepStrictEqual(posts[posts.length - 1], { ch: "harness", text: "my answer", re: T0 }, "the post carries re");
    assert.ok(!(await chipOn()), "the chip goes after a send");

    await reply({ ch: "harness", id: T0, name: "Orchestrator", text: "hello" });
    await q.waitForTimeout(200);
    await q.click(CHIP + " button");
    await q.waitForTimeout(200);
    assert.ok(!(await chipOn()), "× removes the chip");
    await typeQ("no quote");
    await q.keyboard.press("Enter");
    await q.waitForFunction(() => /^Sent/.test(document.querySelector(".chat .compose .hint").textContent));
    assert.deepStrictEqual(posts[posts.length - 1], { ch: "harness", text: "no quote" }, "no re once removed");

    await reply({ ch: "harness", id: T0, name: "Orchestrator", text: "hello" });
    await q.waitForTimeout(200);
    await q.keyboard.press("Escape");
    await q.waitForTimeout(200);
    assert.ok(!(await chipOn()), "Esc in an empty box removes the chip");
    await reply({ ch: "org", id: T0, name: "Orchestrator", text: "hello" });
    await q.waitForTimeout(200);
    assert.ok(!(await chipOn()), "a reply for another channel shows nothing here");
    await reply({ ch: "harness", id: T0, name: "Orchestrator", text: "hello" });
    await q.waitForTimeout(200);
    await to("org");
    assert.ok(!(await chipOn()), "a channel change drops the chip");
    await to("harness");
    assert.ok(!(await chipOn()), "and it does not come back");

    await q.setViewportSize({ width: 400, height: 850 });
    await q.waitForTimeout(300);
    await reply({ ch: "harness", id: T0, name: "Tiny Epic Narrator manager", text: LONG });
    await q.waitForTimeout(300);
    const fit = await q.evaluate(() => {
      const c = document.querySelector(".chat .compose .reply").getBoundingClientRect(), x = document.querySelector(".chat .compose .reply button").getBoundingClientRect();
      return { inside: c.left >= 0 && c.right <= innerWidth, x: Math.round(x.width) >= 44 && Math.round(x.height) >= 44, sw: document.documentElement.scrollWidth };
    });
    assert.deepStrictEqual(fit, { inside: true, x: true, sw: 400 }, "at 400: the chip inside the screen, × 44 px, no sideways scroll");
    assert.deepStrictEqual(errs, [], "no page errors");
    await c2.close();
    console.log("ok · drafts per channel: switch, reload, poll repaint with caret, emptied, 200 clears, 422 keeps · reply chip: 60 chars, focus, repaint, re sent, gone after send/×/Esc/switch, other channel ignored, 400 fits");
  } finally { await b.close(); api.close(); }
})().catch((e) => { console.error(e); process.exit(1); });
