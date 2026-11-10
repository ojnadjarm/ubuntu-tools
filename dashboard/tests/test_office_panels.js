// Office boards (T1601-09, PLAN 2.1 O1, O9, R1-R3, C8): under the office, Next runs (soonest first, a progress bar, the bad
// mark, a name button opens the staff card), Sessions (6 columns, the protected row), Claims (who, note, short paths with the
// full one on hover, the empty line); text is escaped; the band line; 5 widths without sideways scroll, equal margins, two
// Next runs in columns from 1100 px; on the phone Next runs and Claims are folded (Sessions open, as on Org), a tap opens one and it stays open through the next read.
// Run: node tests/test_office_panels.js   (fixture API only)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const SIZES = [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]];
const MEMBERS = FIX.staff.flatMap((t) => t.members);
const NEXT = MEMBERS.filter((m) => m.on && m.next).sort((a, b) => Date.parse(a.next) - Date.parse(b.next));
const BAD = NEXT.filter((m) => m.health === "bad").map((m) => m.name);
let reads = 0;
const srv = serveStatic((u) => {
  if (u === "/api/status") return STATUS;
  if (u === "/api/office") { reads++; return FIX; }
  if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
  if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
});

async function open(b, base, w, h) {
  const touch = w < 900, p = await (await b.newContext({ viewport: { width: w, height: h }, ...(touch ? { hasTouch: true, isMobile: true } : {}) })).newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(String(e)));
  await p.goto(base + "/#org", { waitUntil: "load" });
  await p.waitForSelector(".office .opanels [data-panel]", { timeout: 20000 });
  await p.waitForTimeout(1200);
  return { p, errs };
}
const boards = (p) => p.$$eval(".office .opanels [data-panel]", (l) => l.map((d) => ({ id: d.dataset.panel, open: d.open, box: (({ left, right, top, width }) => [left, right, top, width])(d.getBoundingClientRect()) })));

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const { p, errs } = await open(b, base, 1366, 768);
    assert.deepStrictEqual((await boards(p)).map((x) => [x.id, x.open]), [["next", true], ["sessions", true], ["claims", true]], "boards Next runs, Sessions, Claims, open on a desktop");

    const rows = await p.$$eval(".office [data-panel=next] li", (l) => l.map((li) => ({ name: li.querySelector("[data-who] b").textContent, who: li.querySelector("[data-who]").dataset.who,
      when: li.querySelector(".in").textContent, bar: li.querySelector("progress") && +li.querySelector("progress").value, bad: li.classList.contains("bad") })));
    assert.deepStrictEqual(rows.map((r) => r.name), NEXT.map((m) => m.name), "R2: a row per staff member on with a next run, soonest first");
    assert.deepStrictEqual(rows.map((r) => r.who), NEXT.map((m) => m.id), "R2: the name is the staff card's button");
    assert.ok(rows.every((r) => /^in (\d+ (min|h|d)|—)$/.test(r.when)), "R2: in <time> on every row: " + rows.map((r) => r.when));
    assert.ok(rows.every((r) => r.bar >= 0 && r.bar <= 100), "R3: a progress bar 0..100 on every row");
    assert.deepStrictEqual(rows.filter((r) => r.bad).map((r) => r.name), BAD, "R2: the bad mark on the bad ones only");
    assert.ok(await p.$eval(".office [data-panel=next] li.bad", (li) => /last run failed/.test(li.textContent)), "R2: the bad mark is said in words too");
    await p.click(`.office [data-panel=next] [data-who="${NEXT[0].id}"]`);
    assert.strictEqual(await p.$eval("#office-card:popover-open h2", (h) => h.firstChild.textContent.trim()), NEXT[0].name, "a Next runs name opens its staff card");
    await p.keyboard.press("Escape");

    const ses = await p.$$eval(".office [data-panel=sessions] table.ses tr", (l) => l.map((r) => [...r.children].map((c) => c.textContent)));
    assert.deepStrictEqual(ses[0], ["Session", "Seat", "Folder", "State", "Started by", "Last active"], "O9: the same 6 columns");
    assert.strictEqual(ses.length - 1, FIX.sessions.length, "O9: a row per session");
    assert.ok(ses.some((r) => r[0] === "protected project" && r[2] === "hidden" && r[4] === "—"), "O9: the protected row says protected project, hidden");

    const claims = await p.$$eval(".office [data-panel=claims] .claims li", (l) => l.map((li) => ({ who: li.querySelector("b").textContent, note: li.querySelector("em").textContent,
      paths: [...li.querySelectorAll("span[title]")].map((s) => [s.textContent, s.title]) })));
    assert.deepStrictEqual(claims.map((c) => c.who), ["T9001", "T9003"], "C8: who holds files");
    assert.strictEqual(claims[0].note, "core · 2026-11-10 16:21", "C8: the note");
    assert.deepStrictEqual(claims[0].paths, [["dashboard/static/next/js/office/model.js", "dashboard/static/next/js/office/model.js"], ["dashboard/tests/test_office_model.js", "dashboard/tests/test_office_model.js"]], "C8: a short path per claimed path, the full one on hover");
    assert.strictEqual(await p.$eval(".office [data-panel=claims] h2 s", (s) => s.textContent), "2", "C8: the count");

    const odd = await p.evaluate(async () => {
      const { panels } = await import("/static/next/js/office/overlay/panels.js");
      const x = "<img src=x onerror=window.__pwn=1>", t = document.createElement("div");
      t.innerHTML = panels({ panels: { next: [{ id: x, name: x, next: "", last: "", bad: false }], running: [], recent: [], sessions: [], claims: [{ who: x, note: x, paths: [{ short: x, full: x }] }] } });
      const empty = document.createElement("div");
      empty.innerHTML = panels({ panels: { next: [], running: [], recent: [], sessions: [], claims: [] } });
      return { imgs: t.querySelectorAll("img").length, text: t.querySelector("[data-panel=claims] b").textContent, empty: [...empty.querySelectorAll("[data-panel] ul li, [data-panel] ol li, [data-panel] tbody td")].map((e) => e.textContent) };
    });
    assert.deepStrictEqual([odd.imgs, odd.text], [0, "<img src=x onerror=window.__pwn=1>"], "text is escaped, never markup");
    assert.deepStrictEqual(odd.empty, ["no run scheduled", "no live session", "empty · nobody holds a file"], "the empty lines");

    const band = await p.$eval(".office .band .bsum", (e) => e.textContent);
    assert.ok(/^\d+ Claude sessions? on this laptop, \d+ working · \d+ of \d+ staff on · next up .+ in .+$/.test(band), "O1, R1: the band line: " + band);
    assert.ok(band.includes(`· next up ${NEXT[0].name} in `), "R1: next up is the first Next runs row");
    assert.deepStrictEqual(errs, [], "no page error");
    await p.context().close();

    for (const [w, h] of SIZES) {
      const { p, errs } = await open(b, base, w, h);
      const m = await p.evaluate(() => {
        const o = document.querySelector(".office .opanels").getBoundingClientRect(), de = document.documentElement;
        const over = [...document.querySelectorAll(".office .opanels [data-panel] *")].filter((e) => { const r = e.getBoundingClientRect(), q = e.closest("[data-panel]").getBoundingClientRect(); return r.width && (r.left < q.left - 1 || r.right > q.right + 1); }).length;
        return { sw: de.scrollWidth, vw: de.clientWidth, l: o.left, r: de.clientWidth - o.right, over, band: document.querySelector(".office .band").getBoundingClientRect().height };
      });
      assert.ok(m.sw <= m.vw, `${w}: no sideways scroll (${m.sw} > ${m.vw})`);
      assert.ok(Math.abs(m.l - m.r) <= 1, `${w}: equal margins ${m.l} / ${m.r}`);
      assert.strictEqual(m.over, 0, `${w}: nothing sticks out of its board`);
      const B = await boards(p), by = Object.fromEntries(B.map((x) => [x.id, x]));
      if (w >= 1100) {
        const cols = await p.$$eval(".office [data-panel=next] li", (l) => new Set(l.map((li) => Math.round(li.getBoundingClientRect().left))).size);
        assert.ok(cols >= 2, `${w}: Next runs in ${cols} columns, at least 2`);
        assert.ok(B.every((x) => Math.abs(x.box[3] - by.next.box[3]) <= 1), `${w}: every board full width`);
      }
      if (w <= 700) {
        assert.ok(m.band <= 120, `${w}: band ${m.band} px > 120`);
        assert.deepStrictEqual(B.map((x) => x.open), [false, true, false], `${w}: Next runs and Claims are folded on the phone, Sessions open`);
        const tall = await p.$$eval(".office .opanels [data-panel] > summary", (l) => l.map((s) => s.getBoundingClientRect().height));
        assert.ok(tall.every((t) => t >= 44), `${w}: a 44 px tap target per fold: ${tall}`);
        await p.tap(".office [data-panel=claims] > summary");
        assert.ok(await p.$eval(".office [data-panel=claims]", (d) => d.open), `${w}: a tap opens Claims`);
        const was = reads;
        for (let i = 0; i < 80 && reads === was; i++) await p.waitForTimeout(100);
        assert.ok(reads > was, `${w}: a new read came`);
        await p.waitForTimeout(300);
        assert.deepStrictEqual((await boards(p)).map((x) => x.open), [false, true, true], `${w}: Claims stays open through the next read, Next runs stays folded`);
      } else assert.ok(B.every((x) => x.open), `${w}: the boards are open`);
      assert.deepStrictEqual(errs, [], `${w}: no page error`);
      await p.context().close();
    }
    console.log(`ok office panels · Next runs ${NEXT.length} rows soonest first, ${BAD.length} bad, bars, name → card · Sessions 6 columns, ${FIX.sessions.length} rows, protected · Claims ${FIX.agents.claims.length}, short + full paths · escaped, empty lines · band line · 5 widths: no sideways scroll, equal margins, Next runs in columns ≥ 1100 · phone: 2 folded, 44 px, open survives a read`);
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e.message || e); process.exit(1); });
