// Org pop-up (T1560): order "Name · Rank", project about, role line, state; a viewport-based width (32-40 characters a
// line at 400 px, 45-70 from 768 px); fully inside the viewport for a top, a bottom-row and two edge cards at 5 widths;
// hover, keyboard focus and a tap open it; opening it never moves the tree.
// Run: node tests/test_org_tip.js   (fixture API only)
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
const srv = serveStatic((u) => (u === "/api/status" ? STATUS : u === "/api/org" ? ORG : u === "/api/chat" ? { messages: [], channels: [] } : undefined));
const CARDS = [["orchestrator", "start"], ["mosaico", "end"], ["narrador-interactivo-ia", "center"], ["mooblox", "center"]];

/* The open pop-up of seat id: its box, characters a line, line texts, the tree's box. */
const measure = (p, id) => p.evaluate((id) => {
  const t = document.getElementById("tip-" + id), r = t.getBoundingClientRect(), cs = getComputedStyle(t);
  const z = document.createElement("span"); z.textContent = "0".repeat(20); z.style.cssText = "position:absolute;visibility:hidden;white-space:nowrap";
  t.appendChild(z); const ch = z.getBoundingClientRect().width / 20; z.remove();
  const inner = t.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
  const tr = document.querySelector(".org .otree");
  return { shown: cs.display !== "none", l: r.left, r: r.right, t: r.top, b: r.bottom, vw: document.documentElement.clientWidth, vh: innerHeight,
    cpl: inner / ch, lines: [...t.children].map((e) => e.textContent), tree: [tr.offsetLeft, tr.offsetTop, tr.offsetWidth, tr.offsetHeight] };
}, id);

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  let fails = 0;
  try {
    for (const [w, h] of [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]]) {
      const touch = w < 800, ctx = await b.newContext({ viewport: { width: w, height: h }, hasTouch: touch, isMobile: touch });
      const p = await ctx.newPage();
      const errs = [];
      p.on("pageerror", (e) => errs.push(String(e)));
      await p.goto(base + "/#org", { waitUntil: "load" });
      await p.waitForSelector(".org .otree", { timeout: 15000 });
      for (const [id, at] of CARDS) {
        const av = `.org .seat[data-seat="${id}"] .avb`;
        await p.$eval(av, (e, at) => e.scrollIntoView({ block: at }), at);
        const tree0 = (await measure(p, id)).tree;
        if (touch) await p.tap(av); else await p.click(av);
        const m = await measure(p, id);
        const where = `${w}px ${id} (${at})`;
        try {
          assert.ok(m.shown, `${where}: a tap opens the pop-up`);
          assert.ok(m.l >= 0 && m.t >= 0 && m.r <= m.vw && m.b <= m.vh, `${where}: inside the viewport ${JSON.stringify(m)}`);
          const [lo, hi] = w < 768 ? [32, 40] : [45, 70];
          assert.ok(m.cpl >= lo && m.cpl <= hi, `${where}: ${m.cpl.toFixed(1)} characters a line, want ${lo}-${hi}`);
          assert.deepStrictEqual(m.tree, tree0, `${where}: opening it moves nothing in the tree`);
          if (id !== "orchestrator") {
            const ab = m.lines.findIndex((l) => l.endsWith(ABOUT)), role = m.lines.findIndex((l) => /^(Product owner|Project manager)/.test(l)), now = m.lines.findIndex((l) => /^Now /.test(l));
            assert.ok(/ · (Manager|Product Owner)$/.test(m.lines[0]) && ab > 0 && ab < role && role < now, `${where}: Name · Rank, about, role, state: ${JSON.stringify(m.lines)}`);
          }
        } catch (e) { fails++; console.error("not ok " + e.message); }
        if (touch) await p.tap(".org .band"); else await p.mouse.click(2, h - 2);
      }
      if (!touch) {
        const av = '.org .seat[data-seat="mosaico"] .avb';
        await p.$eval(av, (e) => e.scrollIntoView({ block: "end" }));
        await p.hover(av);
        const hov = await measure(p, "mosaico");
        await p.mouse.move(1, 1);
        const left = await measure(p, "mosaico");
        await p.focus('.org .seat[data-seat="tiny-epic-narrator"] .avb'); await p.keyboard.press("Shift+Tab"); await p.keyboard.press("Tab");
        const key = await measure(p, "tiny-epic-narrator");
        try {
          assert.ok(hov.shown && hov.b <= hov.vh && hov.t >= 0, `${w}px: hover opens it inside the viewport ${JSON.stringify(hov)}`);
          assert.ok(!left.shown, `${w}px: leaving closes it`);
          assert.ok(key.shown && key.b <= key.vh && key.r <= key.vw, `${w}px: keyboard focus opens it inside the viewport`);
        } catch (e) { fails++; console.error("not ok " + e.message); }
      }
      if (errs.length) { fails++; console.error(`not ok ${w}px page errors: ${errs.join(" | ")}`); }
      await ctx.close();
    }
  } finally { await b.close(); srv.close(); }
  console.log(fails ? `FAIL ${fails}` : "ok test_org_tip");
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
