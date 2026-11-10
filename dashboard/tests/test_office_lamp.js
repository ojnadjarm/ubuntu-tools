// Office lamp (T1601-12, gap of T1601-10 C4): the CEO's needs-you lamp follows the store's status verdict on the next status
// tick, without waiting for the next /api/office read.
// Run: node tests/test_office_lamp.js   (fixture API only)
"use strict";
const assert = require("assert");
const { chromium, serveStatic } = require("./lib/browser");
const FIX = require("./fixtures/office.json");
const OK = { host: "fixture", sites: [], units: [], timers: [], docker: [], plans: [], drop: { files: [] }, verdict: { ok: true, problems: [], needs: [] } };
const NEED = { ...OK, verdict: { ok: false, problems: [], needs: [{ kind: "need", text: "fixture needs you", t: "2026-11-10T17:00:00" }] } };
let status = OK, reads = 0;
const srv = serveStatic((u) => {
  if (u === "/api/status") return status;
  if (u === "/api/office") { reads++; return FIX; }
  if (u === "/api/agents") return { ...FIX.agents, agents: [], roster: [] };
  if (u === "/api/chat") return { messages: [], channels: [], wakes: { cap: 12, today: {} } };
});

(async () => {
  await new Promise((ok) => srv.listen(0, "127.0.0.1", ok));
  const b = await chromium.launch({ args: ["--disable-3d-apis", "--mute-audio"] });
  try {
    const p = await (await b.newContext({ viewport: { width: 1366, height: 768 } })).newPage(), errs = [];
    p.on("pageerror", (e) => errs.push(String(e)));
    await p.goto("http://127.0.0.1:" + srv.address().port + "/#org", { waitUntil: "load" });
    await p.waitForFunction(() => window.__office, null, { timeout: 20000 });
    await p.evaluate(() => { const R = window.__office, a = R.apply; window.__lamps = []; R.apply = (M, ...x) => { window.__lamps.push(M.ceo.live.lamp); return a(M, ...x); }; });
    const was = reads;
    status = NEED;
    await p.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
    await p.waitForFunction(() => window.__lamps.includes("needs"), null, { timeout: 5000 });
    assert.strictEqual(reads, was, "the lamp changed without a new /api/office read");
    status = OK;
    await p.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
    await p.waitForFunction(() => window.__lamps[window.__lamps.length - 1] === "ok", null, { timeout: 5000 });
    assert.deepStrictEqual(errs, [], "no page error");
    console.log(`ok office lamp · needs on the next status tick, ok again on the one after, ${reads - was} office reads`);
  } finally { await b.close(); srv.close(); }
})().catch((e) => { console.error(e.message || e); process.exit(1); });
