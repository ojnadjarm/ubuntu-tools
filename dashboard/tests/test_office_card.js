// Office card from the staff list (T1601-07, replaces test_org_tip.js of T1560): the card reads "Name · Rank", area,
// about, role line, wake line, then the state; 32-40 characters a line at 400 px, 45-70 from 768 px; whole inside the
// viewport for a top, a bottom-row and two edge seats at 5 widths; a tap, a click, or keyboard focus + Enter opens it,
// Escape closes it; opening it moves nothing in the tree; a seat that posts talks on its open card for about 2 s.
// Run: node tests/test_office_card.js   (fixture API only)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const ABOUT = "A long project line that says in plain words what this project is and who it is for, two sentences. It runs on its own.";
const seat = (id, name, role, parent, wake, rank, area) => ({ id, name, role, parent, wake, match: null, rank, area, about: area ? area + ": " + ABOUT : undefined });
const ORG = { seats: [
  seat("owner", "You", "owner", null, null), seat("orchestrator", "DarkSaddler", "ceo", "owner", "channel", "CEO"),
  seat("mooblox", "Mossfang", "po", "orchestrator", "po-inbox", "Product Owner", "Mooblox"), seat("vass", "Thistle", "po", "orchestrator", "pull", "Product Owner", "Vass"),
  seat("discord", "Cobalt", "po", "orchestrator", "po-inbox", "Product Owner", "Discord"),
  ...["tiny-epic-narrator", "spidey-pr-dashboard", "mosaico", "narrador-interactivo-ia"].map((id, i) => seat(id, ["Bramble", "Gloam", "Speckle", "Murmur"][i], "manager", "discord", "po-inbox", "Manager", id))],
sessions: [], hidden: 0 };
const CHAT = [];
const srv = serveStatic((u, res) => {
  if (u === "/api/status") return STATUS;
  if (u === "/api/org" || u === "/api/office") return ORG;
  if (u === "/api/chat") {
    const after = new URL(res.req.url, "http://x").searchParams.get("after");
    return { messages: CHAT.filter((m) => after == null || m.id > +after), channels: [], wakes: { cap: 12, today: {} } };
  }
});
const CARDS = [["orchestrator", "start"], ["mosaico", "end"], ["narrador-interactivo-ia", "center"], ["mooblox", "center"]];

/* The open card: whom it is for, its box, characters a line, its text lines in order, the tree's box. */
const measure = (p) => p.evaluate(() => {
  const c = document.querySelector("#office-card"), tr = document.querySelector(".org .otree"), tree = [tr.offsetLeft, tr.offsetTop, tr.offsetWidth, tr.offsetHeight];
  if (!c || !c.matches(":popover-open")) return { shown: false, tree };
  const r = c.getBoundingClientRect(), body = c.querySelector(".cbody"), ln = body.querySelector("p") || body;
  const z = document.createElement("span"); z.textContent = "0".repeat(20); z.style.cssText = "position:absolute;visibility:hidden;white-space:nowrap";
  ln.appendChild(z); const ch = z.getBoundingClientRect().width / 20; z.remove();
  return { shown: true, for: c.dataset.for, l: r.left, r: r.right, t: r.top, b: r.bottom, vw: document.documentElement.clientWidth, vh: innerHeight,
    cpl: ln.clientWidth / ch, lines: [...body.children].map((e) => e.textContent), tree };
});

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  let fails = 0;
  const check = (fn, msg) => { try { fn(); } catch (e) { fails++; console.error("not ok " + msg + ": " + e.message); } };
  try {
    for (const [w, h] of [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]]) {
      const touch = w < 800, ctx = await b.newContext({ viewport: { width: w, height: h }, hasTouch: touch, isMobile: touch });
      const p = await ctx.newPage();
      const errs = [];
      p.on("pageerror", (e) => errs.push(String(e)));
      await p.goto(base + "/#org", { waitUntil: "load" });
      await p.waitForSelector(".org .otree", { timeout: 15000 });
      for (const [id, at] of CARDS) {
        const av = `.org .seat[data-seat="${id}"] .avb`, where = `${w}px ${id} (${at})`;
        await p.$eval(av, (e, at) => e.scrollIntoView({ block: at }), at);
        const tree0 = (await measure(p)).tree;
        if (touch) await p.tap(av); else await p.click(av);
        const m = await measure(p);
        check(() => assert.ok(m.shown && m.for === id, JSON.stringify(m)), `${where}: a ${touch ? "tap" : "click"} on the avatar opens its card`);
        if (!m.shown) continue;
        check(() => assert.ok(m.l >= 0 && m.t >= 0 && m.r <= m.vw && m.b <= m.vh, JSON.stringify(m)), `${where}: inside the viewport`);
        const [lo, hi] = w < 768 ? [32, 40] : [45, 70];
        check(() => assert.ok(m.cpl >= lo && m.cpl <= hi, `${m.cpl.toFixed(1)}`), `${where}: ${lo}-${hi} characters a line`);
        check(() => assert.deepStrictEqual(m.tree, tree0), `${where}: opening it moves nothing in the tree`);
        if (id !== "orchestrator") {
          const L = m.lines, ab = L.findIndex((l) => l.endsWith(ABOUT)), role = L.findIndex((l) => /^(Product owner|Project manager)/.test(l)), wake = L.findIndex((l) => /^Asleep until/.test(l)), now = L.findIndex((l) => /^Now /.test(l));
          check(() => assert.ok(/ · (Manager|Product Owner)$/.test(L[0]) && ab > 0 && ab < role && role < wake && wake < now, JSON.stringify(L)), `${where}: Name · Rank, about, role, wake, state`);
        }
        await p.keyboard.press("Escape");
        const gone = await measure(p);
        check(() => assert.ok(!gone.shown), `${where}: Escape closes it`);
      }
      if (!touch) {
        await p.focus('.org .seat[data-seat="tiny-epic-narrator"] .avb'); await p.keyboard.press("Shift+Tab"); await p.keyboard.press("Tab"); await p.keyboard.press("Enter");
        const key = await measure(p);
        check(() => assert.ok(key.shown && key.for === "tiny-epic-narrator" && key.b <= key.vh && key.r <= key.vw && key.t >= 0, JSON.stringify(key)), `${w}px: keyboard focus + Enter opens it inside the viewport`);
        await p.keyboard.press("Escape");
      }
      if (w === 1366) {
        await p.click('.org .seat[data-seat="mooblox"] .avb');
        const fig = () => p.$eval("#office-card .cfig svg", (s) => s.getAttribute("class"));
        const rest = await fig();
        CHAT.push({ id: CHAT.length + 1, ts: new Date().toISOString(), ch: "org", from: "mooblox", to: [], kind: "msg", text: "hello", re: null, hop: 0 });
        let t0 = 0, t1 = 0;
        try {
          await p.waitForFunction(() => /talking/.test(document.querySelector("#office-card .cfig svg").getAttribute("class")), null, { timeout: 8000 }); t0 = Date.now();
          await p.waitForFunction(() => !/talking/.test(document.querySelector("#office-card .cfig svg").getAttribute("class")), null, { timeout: 5000 }); t1 = Date.now();
        } catch (e) { /* asserted below */ }
        check(() => assert.ok(!/talking/.test(rest) && t0 && t1 - t0 > 1200 && t1 - t0 < 3200, `${rest} ${t0} ${t1 - t0}`), `${w}px: O8 the open card's creature talks for about 2 s when its seat posts`);
        await p.keyboard.press("Escape");
      }
      check(() => assert.deepStrictEqual(errs, []), `${w}px: no page errors`);
      await ctx.close();
    }
  } finally { await b.close(); srv.close(); }
  console.log(fails ? `FAIL ${fails}` : "ok test_office_card");
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
