// Library › Memory (T1599-M12): the index and one page on a synthetic fixture store at 400, 768, 1366, 1920 and 2560 px:
// no sideways scroll, page text escaped (no markup from the store), links only to #…, PRIVATE rows by name only, 44 px rows on touch.
// Run: node tests/test_memory_screen.js   (fixture API only; nothing reads the real store)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const STATUS = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const T = 1794261588;
const INDEX = { count: 5, private: 1, pages: [
  { page: "core/CORE.md", bytes: 310, mtime: T },
  { page: "core/ledger.md", bytes: 120, mtime: T - 86400 },
  { page: "domains/garden/DOMAIN.md", bytes: 240, mtime: T - 3600 },
  { page: "domains/garden/photos.md", bytes: 90, mtime: T - 7200 },
  { page: "domains/vault/DOMAIN.md", private: true }] };
const LONG = "x".repeat(400);
const PAGES = {
  "core/CORE.md": ["# Core card", "## Output", "- Reports are three lines. (26-01-05)", "- Charts use <img src=x onerror=window.__pwned=1> teal `code<b>` & amber. (26-01-06)",
    "- A very long unbroken token " + LONG + " stays inside the reader.", "", "Plain <script>window.__pwned=1</script> paragraph."],
  "domains/garden/DOMAIN.md": ["# Garden", "- Seed photos are 800 px wide. (26-02-01) → photos", "- An unknown topic stays text. → nowhere"],
  "domains/garden/photos.md": ["# Photos", "- Crop to the seed head. (26-02-03)"],
};
const asked = [];
const srv = serveStatic((u, res) => {
  if (u === "/api/status") return STATUS;
  if (u === "/api/memory") return INDEX;
  if (u === "/api/memory/page") {
    const p = new URL(res.req.url, "http://x").searchParams.get("p");
    asked.push(p);
    if (p === "domains/vault/DOMAIN.md") { res.writeHead(403, { "Content-Type": "application/json" }); res.end('{"error":"private page"}'); return; }
    if (!PAGES[p]) { res.writeHead(400, { "Content-Type": "application/json" }); res.end('{"error":"not a memory page"}'); return; }
    return { page: p, bytes: 300, mtime: T, lines: PAGES[p] };
  }
});
const SIZES = [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]];

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + srv.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    for (const [w, h] of SIZES) {
      const touch = w <= 768;
      const ctx = await b.newContext({ viewport: { width: w, height: h }, reducedMotion: "reduce", hasTouch: touch, isMobile: touch });
      const p = await ctx.newPage();
      const errs = [];
      p.on("pageerror", (e) => errs.push(String(e)));
      await p.goto(base + "/#memory");
      await p.waitForSelector(".mem .mlist .mrow", { timeout: 15000 });
      const idx = await p.evaluate(() => ({
        rows: [...document.querySelectorAll(".mem .mlist li")].map((li) => li.textContent),
        links: [...document.querySelectorAll(".mem .mlist a")].map((a) => a.getAttribute("href")),
        priv: [...document.querySelectorAll(".mem li.priv")].map((li) => [li.querySelector("a") === null, li.textContent]),
        sum: document.querySelector(".mem .bsum").textContent,
        fold: [...document.querySelectorAll(".mem .mfold tbody tr")].map((tr) => [tr.cells[0].textContent, tr.cells[1].textContent, !!tr.querySelector("a")]),
        sw: document.documentElement.scrollWidth,
        small: [...document.querySelectorAll(".mem a.mrow, .mem .mfold a")].filter((a) => a.getBoundingClientRect().height < 44).length,
      }));
      assert.strictEqual(idx.rows.length, 5, w + ": 5 rows");
      assert.ok(idx.links.length === 4 && idx.links.every((l) => l.startsWith("#memory?p=")), w + ": links only to #memory?p= " + idx.links);
      assert.deepStrictEqual(idx.priv, [[true, "DOMAIN.mdprivate · name only"]], w + ": private by name only");
      assert.ok(/5 pages · 1 private/.test(idx.sum), w + ": band " + idx.sum);
      assert.deepStrictEqual(idx.fold, [["core", "2", true], ["domains/garden", "2", true], ["domains/vault", "1", false]], w + ": folder table, no link into a private folder");
      assert.strictEqual(idx.sw, w, w + ": no sideways scroll on the index");
      if (touch) assert.strictEqual(idx.small, 0, w + ": rows and folder links 44 px on touch");
      assert.ok(!asked.includes("domains/vault/DOMAIN.md"), w + ": the private page is never asked for");

      await p.click('.mem a.mrow[data-mp="core/CORE.md"]');
      await p.waitForSelector(".mem .mtext li", { timeout: 15000 });
      const pg = await p.evaluate(() => ({
        hash: location.hash, pwned: window.__pwned === 1,
        img: document.querySelectorAll(".mem .mtext img, .mem .mtext script, .mem .mtext b").length,
        text: document.querySelector(".mem .mtext").textContent,
        lis: document.querySelectorAll(".mem .mtext li").length, h3: document.querySelector(".mem .mtext h3").textContent,
        hrefs: [...document.querySelectorAll(".mem a")].map((a) => a.getAttribute("href")),
        sw: document.documentElement.scrollWidth,
        list: getComputedStyle(document.querySelector(".mem .mlist")).display,
        back: getComputedStyle(document.querySelector(".mem .mback")).display,
      }));
      assert.strictEqual(pg.hash, "#memory?p=core%2FCORE.md", w + ": hash names the page");
      assert.strictEqual(pg.img, 0, w + ": no element from page text");
      assert.ok(!pg.pwned, w + ": no script ran");
      assert.ok(pg.text.includes("<img src=x onerror=window.__pwned=1>") && pg.text.includes("code<b>") && pg.text.includes("<script>"), w + ": markup shown as text");
      assert.strictEqual(pg.lis, 3, w + ": 3 list lines");
      assert.strictEqual(pg.h3, "Core card", w + ": heading");
      assert.ok(pg.hrefs.every((x) => x.startsWith("#")), w + ": every link is #…: " + pg.hrefs.filter((x) => !x.startsWith("#")));
      assert.strictEqual(pg.sw, w, w + ": no sideways scroll on a page with a 400-char token");
      assert.strictEqual(pg.list, w < 900 ? "none" : "block", w + ": index beside the reader from 900 px, hidden on the phone");
      assert.strictEqual(pg.back, w < 900 ? "inline-flex" : "none", w + ": back link on the phone only");

      await p.goto(base + "/#memory?p=" + encodeURIComponent("domains/garden/DOMAIN.md"));
      await p.waitForSelector(".mem a.mt", { timeout: 15000 });
      const topic = await p.evaluate(() => [...document.querySelectorAll(".mem a.mt")].map((a) => [a.getAttribute("href"), a.textContent]));
      assert.deepStrictEqual(topic, [["#memory?p=domains%2Fgarden%2Fphotos.md", "→ photos"]], w + ": → topic links to its listed page only");
      await p.click(".mem a.mt");
      await p.waitForFunction(() => (document.querySelector(".mem .mtext h3") || {}).textContent === "Photos", null, { timeout: 15000 });
      await p.goBack();
      await p.waitForFunction(() => (document.querySelector(".mem .mtext h3") || {}).textContent === "Garden", null, { timeout: 15000 });
      if (w < 900) {
        await p.click(".mem .mback");
        await p.waitForFunction(() => location.hash === "#memory" && getComputedStyle(document.querySelector(".mem .mlist")).display !== "none", null, { timeout: 15000 });
      }
      if (process.env.SHOTS) await p.screenshot({ path: `${process.env.SHOTS}/memory-fixture-${w}.png` });
      assert.deepStrictEqual(errs, [], w + ": page errors");
      await ctx.close();
    }
    console.log("memory screen: 5 widths · index, private by name only, escaped page, # links, → topic, back, no sideways scroll");
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e.message); process.exit(1); });
