// Chat message text (T1545-B): rich(text) escapes first, then http(s) links, fenced code blocks with a Copy button, `code`
// spans, kept line breaks; a long line of code scrolls inside its block and never widens a 400 px page.
// Run: node tests/test_chat_text.js [shot-dir] [--before]   (fixture server only; a shot-dir gets the fixture conversation
// at 400-2560 px; --before shoots it with the old formatter and skips the checks)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const SHOTS = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "", BEFORE = process.argv.includes("--before");
const MOD = "/static/next/js/screens/chat-text.js";
const CODE = "for f in ~/agents/state/*.json; do jq -r '.seat + \" \" + .state' \"$f\"; done | sort | uniq -c | sort -rn | head -n 20 # " + "x".repeat(140);
const ROWS = [
  ["Orchestrator", "", "The shots are up: https://example.test/drop/T1545-B/after/?w=400&h=850. Open one per width."],
  ["You", " him", "Thanks. What did you run?"],
  ["Orchestrator", "", "This, on the fixture only:\n```bash\n" + CODE + "\nnode tests/test_chat_text.js\n```\nThen `claims done T1545-B` (see https://example.test/guide)."],
];
const PAGE = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="/static/eye.css"><link rel="stylesheet" href="/static/css/chat.css">
<main id="board"><div class="chat"><section class="cell stream"><ol class="msgs" id="m"></ol></section></div></main>
<script type="module">
import { esc } from "/static/js/core/fmt.js";
const old = (t) => esc(t).replace(/\`([^\`\\n]+)\`/g, "<code>$1</code>");
const fmt = ${BEFORE} ? old : (await import("${MOD}")).rich;
document.getElementById("m").innerHTML = ${JSON.stringify(ROWS)}.map(([who, c, t]) =>
  '<li class="msg' + c + '"><span class="av"></span><div><p class="who"><b>' + who + '</b></p><div class="tx">' + fmt(t) + '</div></div></li>').join("");
document.body.dataset.ready = "1";
</script>`;
const WIDTHS = [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]];

/* Each case: [name, input, expected HTML]. */
const CASES = [
  ["plain text is escaped", "a < b & c > d", "a &lt; b &amp; c &gt; d"],
  ["<script> stays text", "<script>alert(1)</script>", "&lt;script&gt;alert(1)&lt;/script&gt;"],
  ['"onerror= stays text', '<img src=x "onerror=alert(1)>', '&lt;img src=x &quot;onerror=alert(1)&gt;'],
  ["https URL with query and trailing dot", "see https://a.test/p?x=1&y=2.", 'see <a href="https://a.test/p?x=1&amp;y=2" target="_blank" rel="noopener noreferrer">https://a.test/p?x=1&amp;y=2</a>.'],
  ["http URL in parentheses, trailing ),; outside", "(http://a.test/x),;", '(<a href="http://a.test/x" target="_blank" rel="noopener noreferrer">http://a.test/x</a>),;'],
  ["a quote ends the URL", 'https://a.test/"onerror="x', '<a href="https://a.test/" target="_blank" rel="noopener noreferrer">https://a.test/</a>&quot;onerror=&quot;x'],
  ["javascript: never links", "javascript:alert(1) JavaScript://x", "javascript:alert(1) JavaScript://x"],
  ["data: never links", "data:text/html,<b>x</b>", "data:text/html,&lt;b&gt;x&lt;/b&gt;"],
  ["fence with language", "run:\n```js\nif (a < b) x();\n```\ndone", 'run:<div class="cb"><span class="lang">js</span><button type="button" class="btn" data-copy>Copy</button><pre><code>if (a &lt; b) x();</code></pre></div>done'],
  ["fence without language", "```\nline 1\n  line 2\n```", '<div class="cb"><span class="lang"></span><button type="button" class="btn" data-copy>Copy</button><pre><code>line 1\n  line 2</code></pre></div>'],
  ["no link or span inside a fence", "```\nhttps://a.test `x`\n```", '<div class="cb"><span class="lang"></span><button type="button" class="btn" data-copy>Copy</button><pre><code>https://a.test `x`</code></pre></div>'],
  ["unclosed fence stays text", "```js\nnot closed", "```js\nnot closed"],
  ["backtick span", "run `a <b>` now", "run <code>a &lt;b&gt;</code> now"],
  ["no link inside a backtick span", "`https://a.test`", "<code>https://a.test</code>"],
  ["line breaks kept", "one\ntwo\n\nthree", "one\ntwo\n\nthree"],
  ["no bold, headings or images", "**b** # h ![i](https://a.test/i.png)", '**b** # h ![i](<a href="https://a.test/i.png" target="_blank" rel="noopener noreferrer">https://a.test/i.png</a>)'],
];

const api = serveStatic(() => undefined);
(async () => {
  await new Promise((ok) => api.listen(0, "127.0.0.1", ok));
  const base = "http://127.0.0.1:" + api.address().port;
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const ctx = await b.newContext({ viewport: { width: 400, height: 850 } });
    await ctx.grantPermissions(["clipboard-read", "clipboard-write"], { origin: base });
    await ctx.route(base + "/fixture", (r) => r.fulfill({ contentType: "text/html", body: PAGE }));
    const p = await ctx.newPage(), errs = [];
    p.on("pageerror", (e) => errs.push(String(e)));
    await p.goto(base + "/fixture", { waitUntil: "load" });
    await p.waitForSelector("body[data-ready]", { timeout: 10000 });

    if (!BEFORE) {
      const got = await p.evaluate(async ([mod, cases]) => { const { rich } = await import(mod); return cases.map((c) => rich(c[1])); }, [MOD, CASES]);
      CASES.forEach((c, i) => assert.strictEqual(got[i], c[2], c[0]));
      const long = await p.evaluate(async (mod) => { const { rich } = await import(mod); const s = "w".repeat(2000), t0 = performance.now(); return { out: rich(s), ms: performance.now() - t0, s }; }, MOD);
      assert.strictEqual(long.out, long.s, "a 2000-char line comes back as itself");
      assert.ok(long.ms < 20, "a 2000-char line formats in under 20 ms (" + long.ms.toFixed(1) + ")");
      console.log("ok " + (CASES.length + 1) + " rich cases");

      const css = await p.$$eval('link[href="/static/css/chat-text.css"]', (l) => l.length);
      assert.strictEqual(css, 1, "the module links its stylesheet once");
      const w = await p.evaluate(() => {
        const pre = document.querySelector(".cb pre"), btn = document.querySelector("[data-copy]").getBoundingClientRect();
        return { sw: document.documentElement.scrollWidth, pre: pre.scrollWidth > pre.clientWidth, ox: getComputedStyle(pre).overflowX, btn: Math.round(btn.height) };
      });
      assert.ok(w.sw <= 400, "a 300-char line of code does not widen the 400 px page (" + w.sw + ")");
      assert.ok(w.pre && w.ox === "auto", "the block scrolls sideways inside its row");
      assert.ok(w.btn >= 32, "Copy is at least 32 px tall (" + w.btn + ")");
      const word = await p.evaluate(() => { const t = document.querySelector(".tx"); t.textContent = "w".repeat(2000); const r = document.documentElement.scrollWidth; return r; });
      assert.ok(word <= 400, "a 2000-char word wraps (" + word + ")");
      await p.reload({ waitUntil: "load" }); await p.waitForSelector("body[data-ready]");

      await p.click("[data-copy]");
      const clip = await p.evaluate(() => navigator.clipboard.readText());
      assert.strictEqual(clip, CODE + "\nnode tests/test_chat_text.js", "Copy puts the block text on the clipboard");
      await p.waitForFunction(() => document.querySelector("[data-copy]").textContent === "copied", null, { timeout: 2000 });
      const a = await p.$eval(".tx a", (e) => ({ href: e.getAttribute("href"), rel: e.rel, target: e.target }));
      assert.deepStrictEqual(a, { href: "https://example.test/drop/T1545-B/after/?w=400&h=850", rel: "noopener noreferrer", target: "_blank" }, "the link in the conversation");
      console.log("ok copy, link, 400 px width");

      const touch = await b.newContext({ viewport: { width: 400, height: 850 }, hasTouch: true, isMobile: true });
      await touch.route(base + "/fixture", (r) => r.fulfill({ contentType: "text/html", body: PAGE }));
      const tp = await touch.newPage();
      await tp.goto(base + "/fixture", { waitUntil: "load" }); await tp.waitForSelector("body[data-ready]");
      const th = await tp.$eval("[data-copy]", (e) => Math.round(e.getBoundingClientRect().height));
      assert.ok(th >= 44, "Copy is at least 44 px on touch (" + th + ")");
      await touch.close();
      console.log("ok touch target");
    }

    if (SHOTS) {
      await p.reload({ waitUntil: "load" }); await p.waitForSelector("body[data-ready]");
      for (const [w, h] of WIDTHS) {
        await p.setViewportSize({ width: w, height: h });
        await p.waitForTimeout(150);
        const sw = await p.evaluate(() => document.documentElement.scrollWidth);
        if (!BEFORE) assert.ok(sw <= w, "no sideways scroll at " + w + " (" + sw + ")");
        await p.screenshot({ path: SHOTS + "/chat-text-" + w + ".png", fullPage: true });
      }
      console.log("shots in " + SHOTS);
    }
    assert.deepStrictEqual(errs, [], "no page errors");
    console.log("PASS test_chat_text");
  } finally { await b.close(); api.close(); }
})().catch((e) => { console.error("FAIL", e.message); process.exit(1); });
