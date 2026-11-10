// Office by keyboard and screen reader (T1601-13, PLAN 4.4): Tab walks the staff list CEO → seats → each team then its members,
// one stop per person, never the canvas or a tag; Enter opens the card (a named dialog, focus inside it), Esc closes it and
// returns focus to its button; the same with the still picture and with WebGL; reduced motion draws 1 frame per change;
// 0 serious or critical axe findings and 0 contrast findings on the office and its open card.
// Run: node tests/test_office_keys.js   (fixture API only; axe-core from $AXE, else a Moodle env's lib/behat/axe; ONLY=still|gpu)
"use strict";
const assert = require("assert");
const fs = require("fs"), os = require("os"), path = require("path");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = fs.readFileSync(path.join(__dirname, "fixtures", "office.json"), "utf8");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const GPU = ["--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=vulkan", "--enable-features=Vulkan"];
const AXE = [process.env.AXE, ...["5.3", "5.2"].map((v) => path.join(os.homedir(), "moodle-envs", v, "www/public/lib/behat/axe/axe.min.js"))].find((f) => f && fs.existsSync(f));
let office = JSON.parse(FIX);
const srv = serveStatic((u) => {
  if (u === "/api/status") return STATUS;
  if (u === "/api/office") return office;
  if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
});

/* What has focus: its role in the office. */
const focused = (p) => p.evaluate(() => {
  const a = document.activeElement, card = a && a.closest("#office-card");
  return { tag: a.tagName, who: a.dataset.who || null, cls: String(a.className || ""), list: !!a.closest(".olist"), card: !!card,
    canvas: a.tagName === "CANVAS", otag: !!a.closest(".otag, .otags"),
    team: !!a.closest(".team h3"), member: !!a.closest(".mem"), ceo: !!a.closest(".otree > li.ceo > .seat > h3") };
});

/* Tabs from the top of the page to its end: every stop, in order. */
async function walk(p) {
  await p.evaluate(() => { document.activeElement && document.activeElement.blur(); window.scrollTo(0, 0); });
  const stops = [];
  for (let i = 0; i < 400; i++) {
    await p.keyboard.press("Tab");
    const f = await focused(p);
    if (f.tag === "BODY" || (stops.length && f.list === false && stops.some((s) => s.list) && !stops[stops.length - 1].list && f.tag === stops[0].tag && f.who === stops[0].who && f.cls === stops[0].cls)) break;
    stops.push(f);
  }
  return stops;
}

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  let fails = 0;
  const check = (fn, msg) => { try { fn(); console.log("ok " + msg); } catch (e) { fails++; console.error("not ok " + msg + ": " + e.message); } };
  const modes = [["still", ["--disable-3d-apis"]], ["gpu", GPU]].filter(([m]) => !process.env.ONLY || process.env.ONLY === m);
  for (const [mode, args] of modes) {
    const b = await chromium.launch({ args: ["--mute-audio", ...args] });
    try {
      for (const [w, h] of mode === "still" ? [[400, 850], [1366, 768]] : [[1366, 768]]) {
        const where = `${mode} ${w}px`;
        office = JSON.parse(FIX);
        const ctx = await b.newContext({ viewport: { width: w, height: h } }), p = await ctx.newPage(), errs = [];
        p.on("pageerror", (e) => errs.push(String(e)));
        await p.goto(base + "/#org", { waitUntil: "load" });
        await p.waitForSelector(".office .olist .otree .who", { timeout: 15000 });
        await p.waitForFunction((m) => { const s = document.querySelector(".office .stage"); return s && s.querySelector("canvas") && (m === "still" ? s.dataset.still === "1" : window.__office && !window.__office.still && document.querySelectorAll(".otags .otag").length > 0); }, mode, { timeout: 20000 });

        const hid = await p.evaluate(() => {
          const s = document.querySelector(".office .stage"), c = s.querySelector("canvas"), t = s.querySelector(".otags");
          return { canvas: c.getAttribute("aria-hidden"), ctab: c.tabIndex, tags: t.getAttribute("aria-hidden"), n: t.children.length, tabbable: [...t.children].filter((e) => e.tabIndex >= 0).length };
        });
        check(() => assert.ok(hid.canvas === "true" && hid.ctab < 0 && hid.tags === "true" && hid.tabbable === 0, JSON.stringify(hid)), `${where}: canvas and tags hidden from assistive tech, out of the tab order`);

        const stops = await walk(p), L = stops.filter((s) => s.list && s.who), ids = L.map((s) => s.who);
        const all = await p.evaluate(() => [...new Set([...document.querySelectorAll(".olist [data-who]")].filter((e) => !e.closest("details:not([open])")).map((e) => e.dataset.who))]);
        check(() => assert.ok(!stops.some((s) => s.canvas || s.otag), JSON.stringify(stops.filter((s) => s.canvas || s.otag))), `${where}: Tab never lands on the canvas or a tag (${stops.length} stops)`);
        check(() => assert.ok(L.length && L[0].ceo && L[0].who === "orchestrator", JSON.stringify(L[0])), `${where}: the first list stop is the CEO`);
        check(() => assert.deepStrictEqual(ids.filter((id, i) => ids.indexOf(id) !== i), []), `${where}: one stop per person`);
        check(() => assert.deepStrictEqual(all.filter((id) => !ids.includes(id)), []), `${where}: every person in the list is reachable`);
        const firstTeam = L.findIndex((s) => s.team), seatsAfter = L.slice(firstTeam).filter((s) => !s.team && !s.member);
        const order = [];
        L.slice(firstTeam).forEach((s) => { if (s.team) order.push([s.who]); else if (s.member && order.length) order[order.length - 1].push(s.who); });
        const teams = await p.evaluate(() => [...document.querySelectorAll(".olist .team")].map((t) => [t.querySelector("h3 [data-who]").dataset.who, ...[...t.querySelectorAll(".mem [data-who]")].map((e) => e.dataset.who)]));
        check(() => assert.ok(firstTeam > 0 && !seatsAfter.length, JSON.stringify(seatsAfter)), `${where}: the seats come before the teams`);
        check(() => assert.deepStrictEqual(order, teams), `${where}: each team, then its members`);

        const key = async (sel, label) => {
          await p.focus(sel); await p.keyboard.press("Shift+Tab"); await p.keyboard.press("Tab");
          const from = await focused(p);
          await p.keyboard.press("Enter");
          await p.waitForFunction(() => { const c = document.querySelector("#office-card"); return c && c.matches(":popover-open"); }, null, { timeout: 3000 }).catch(() => {});
          const open = await p.evaluate(() => { const c = document.querySelector("#office-card"); return { shown: !!c && c.matches(":popover-open"), role: c && c.getAttribute("role"), name: c && c.getAttribute("aria-label"), h2: c && c.querySelector("h2") && c.querySelector("h2").textContent, inside: !!c && c.contains(document.activeElement) }; });
          check(() => assert.ok(open.shown && open.role === "dialog" && /^About \S/.test(open.name) && open.inside, JSON.stringify(open)), `${where}: Enter on ${label} opens a named dialog with focus inside it`);
          return { from, open };
        };
        const esc = async (from, label) => {
          await p.keyboard.press("Escape");
          const back = await p.evaluate(() => ({ shown: document.querySelector("#office-card").matches(":popover-open"), screen: !!document.querySelector(".nxs.office") }));
          const now = await focused(p);
          check(() => assert.ok(!back.shown && back.screen && now.who === from.who && now.cls === from.cls && now.list, JSON.stringify({ back, now, from })), `${where}: Esc closes the card of ${label} and returns focus to its button`);
        };
        const ceo = await key(".otree > li.ceo > .seat h3 .who", "the CEO");
        if (ceo.open.shown && !process.env.NOAXE && AXE) {
          await p.addScriptTag({ content: fs.readFileSync(AXE, "utf8") });
          const r = await p.evaluate(async () => {
            const run = async (el) => (await window.axe.run(el, { resultTypes: ["violations"] })).violations;
            const v = [...await run(document.querySelector(".nxs.office")), ...await run(document.querySelector("#office-card"))];
            return v.map((x) => ({ id: x.id, impact: x.impact, n: x.nodes.length, at: x.nodes.slice(0, 2).map((n) => n.target.join(" ") + " " + (n.any[0] && n.any[0].message || "").slice(0, 120)) }));
          });
          check(() => assert.deepStrictEqual(r.filter((x) => x.impact === "serious" || x.impact === "critical"), []), `${where}: 0 serious axe findings (${r.length} minor: ${r.map((x) => x.id).join(",") || "none"})`);
          check(() => assert.deepStrictEqual(r.filter((x) => x.id === "color-contrast"), []), `${where}: text contrast >= 4.5`);
        } else if (!AXE) { fails++; console.error("not ok axe-core not found: set AXE=<axe.min.js>"); }
        await esc(ceo.from, "the CEO");
        const team = await key(".olist .team h3 .who", "a team");
        if (team.open.shown) {
          const chip = await p.evaluate(() => !!document.querySelector("#office-card .chip"));
          if (chip) {
            for (let i = 0; i < 20 && !(await p.evaluate(() => !!document.activeElement.closest("#office-card .chip"))); i++) await p.keyboard.press("Tab");
            const to = await p.evaluate(() => document.activeElement.dataset.who);
            await p.keyboard.press("Enter");
            const sw = await p.evaluate(() => { const c = document.querySelector("#office-card"); return { for: c.dataset.for, inside: c.contains(document.activeElement) }; });
            check(() => assert.ok(sw.for === to && sw.inside, JSON.stringify({ to, sw })), `${where}: Enter on a member chip shows its card, focus stays in the card`);
          }
          await esc(team.from, "a team (after a chip)");
        }

        if (mode === "gpu") {
          const frames = () => p.evaluate(() => window.__office.stats().frames);
          await p.emulateMedia({ reducedMotion: "reduce" });
          await p.evaluate(() => window.__office.stats().pending === 0 || new Promise((ok) => { const t = setInterval(() => { if (window.__office.stats().pending === 0) { clearInterval(t); ok(); } }, 100); }));
          await p.waitForTimeout(600);
          const f0 = await frames(); await p.waitForTimeout(2500); const f1 = await frames();
          check(() => assert.strictEqual(f1 - f0, 0, `${f1 - f0} frames`), `${where}: reduced motion, ${await p.evaluate(() => document.querySelectorAll(".otags .otag.working").length)} acting: 0 frames at rest in 2.5 s`);
          await p.click("#office-zin"); await p.waitForTimeout(1500);
          const f2 = await frames();
          check(() => assert.strictEqual(f2 - f1, 1, `${f2 - f1} frames`), `${where}: reduced motion: one zoom = 1 frame`);
        }
        check(() => assert.deepStrictEqual(errs, []), `${where}: no page errors`);
        await ctx.close();
      }
    } finally { await b.close(); }
  }
  srv.close();
  console.log(fails ? `FAIL ${fails}` : "ok test_office_keys");
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
