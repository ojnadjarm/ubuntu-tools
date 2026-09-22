// Pronunciation page: a late answer never paints into another step, and redoing a cleared step
// never moves the path forward or back. Run: node tests/test_pronunciation_page.js [page.js]
"use strict";
const path = require("path"), assert = require("assert"), { pathToFileURL } = require("url");

const PAGE = process.argv[2] || path.join(__dirname, "..", "static", "js", "voice", "pronunciation.js");
const PROMPTS = [
  { id: "d01", text: "one", pattern: "v-b", day: 1, len: "short", targets: [{ word: "very" }] },
  { id: "d02", text: "two", pattern: "v-b", day: 2, len: "short", targets: [{ word: "vote" }] },
  { id: "d03", text: "three", pattern: "v-b", day: 3, len: "short", targets: [{ word: "view" }] }
];
const hit = (p) => ({ id: "t-" + p.id, prompt_id: p.id, recorded_at: "2026-09-22T10:00:00", seconds: 2,
  transcript: p.text, verdict: p.targets.map((t) => ({ word: t.word, status: "hit" })), diff: [] });
const miss = (p) => ({ id: "m-" + p.id, prompt_id: p.id, recorded_at: "2026-09-22T10:01:00", seconds: 2,
  transcript: "x", verdict: p.targets.map((t) => ({ word: t.word, status: "miss", heard: "zzzheard", reason: "b for v" })), diff: [] });

function element() {
  return { textContent: "", innerHTML: "", className: "", hidden: false, disabled: false,
    dataset: {}, style: {}, onclick: null, addEventListener() {} };
}

let loads = 0;
function load(opts) {
  const els = {};
  const posts = [];
  const doc = {
    getElementById: (id) => (els[id] = els[id] || element()),
    addEventListener() {}, querySelector: () => null, querySelectorAll: () => []
  };
  const fetch = (url, o) => {
    if (o && o.method === "POST") posts.push(String(url));
    let body = {};
    if (String(url).indexOf("/api/voice/clear") === 0) {
      const pid = JSON.parse(o.body).prompt_id;
      body = { prompt_id: pid, archived: (opts.takes[pid] || []).length };
      delete opts.takes[pid];
    }
    if (String(url).indexOf("/api/voice/prompts") === 0) body = PROMPTS;
    else if (String(url).indexOf("/api/voice/stats") === 0) body = { takes: opts.takes, clips: 1, seconds: 2 };
    else if (String(url).indexOf("/api/voice/progress") === 0) body = { cleared: opts.cleared };
    const answer = { ok: true, status: 200, json: () => Promise.resolve(body) };
    const wait = String(url).indexOf("/api/voice/stats") === 0 ? opts.statsDelay || 0 : 0;
    return new Promise((r) => setTimeout(() => r(answer), wait));
  };
  const G = {
    document: doc, fetch,
    navigator: { mediaDevices: { getUserMedia: () => new Promise(() => {}) }, vibrate() {} },
    isSecureContext: true, scrollTo() {}, Audio: function () { return { play: () => Promise.resolve(), pause() {} }; },
    MediaRecorder: function () {}, crypto: undefined, localStorage: { getItem: () => null, setItem() {} }
  };
  G.MediaRecorder.isTypeSupported = () => true;
  for (const k of Object.keys(G)) Object.defineProperty(globalThis, k, { value: G[k], configurable: true, writable: true });
  globalThis.window = globalThis;
  globalThis.__pron = undefined;
  // a fresh page module per load; its imports are stateless and shared
  return import(pathToFileURL(PAGE).href + "?load=" + (++loads)).then(() => new Promise((r) => {
    const ready = () => (globalThis.__pron && globalThis.__pron.state().ready
      ? r({ api: globalThis.__pron, els, posts }) : setTimeout(ready, 20));
    ready();
  }));
}

async function lateAnswerNeverPaintsIntoTheNextStep() {
  const { api, els } = await load({ cleared: { d01: "t" }, takes: { d02: [miss(PROMPTS[1])] }, statsDelay: 200 });
  const S = api.state();
  assert.strictEqual(S.P[S.idx].id, "d02");
  api.settle(miss(PROMPTS[1]));            // the machine answers for step 2…
  S.cleared.d02 = "t"; api.go(2);          // …while he has already moved to step 3
  await new Promise((r) => setTimeout(r, 400));
  assert.strictEqual(S.P[S.idx].id, "d03");
  assert.strictEqual(els.alert.hidden, true, "step 2's message is still on screen under step 3");
  assert.ok(els.takeList.innerHTML.indexOf("zzzheard") < 0, "step 2's take text is still on screen under step 3");
}

async function redoingAClearedStepDoesNotMoveTheFurthestStep() {
  const { api, posts } = await load({ cleared: { d01: "t", d02: "t" }, takes: { d01: [hit(PROMPTS[0])] } });
  const S = api.state();
  assert.strictEqual(api.firstOpen(), 2, "the path starts at the first step not cleared");
  api.go(0);
  assert.strictEqual(S.revisit, true);
  assert.strictEqual(api.reachable(2), true, "the step the path is on stays reachable");
  assert.strictEqual(api.reachable(2 + 1), false, "future steps stay locked");
  S.takes.d01 = [hit(PROMPTS[0]), hit(PROMPTS[0])];
  api.settle(hit(PROMPTS[0]));
  await new Promise((r) => setTimeout(r, 100));
  assert.strictEqual(api.firstOpen(), 2, "a better take on an old step moved the path");
  assert.ok(posts.every((u) => u.indexOf("/api/voice/progress") < 0), "redoing a cleared step wrote progress again");
  api.go(api.firstOpen());
  assert.strictEqual(S.revisit, false);
  assert.strictEqual(S.idx, 2);
}

async function clearAttemptsOnlyAfterConfirmAndStartsTheWindowFresh() {
  const p = PROMPTS[1], takes = { d02: [miss(p), miss(p), miss(p), miss(p)], d01: [hit(PROMPTS[0])] };
  takes.d02.forEach((t, i) => { t.id = "m-" + i; });
  const { api, els, posts } = await load({ cleared: { d01: "t" }, takes });
  const S = api.state();
  assert.strictEqual(S.P[S.idx].id, "d02");
  assert.ok(els.clearBox.innerHTML.indexOf('id="clearAsk"') >= 0, "no Clear attempts button with takes on screen");
  assert.ok(els.clearBox.innerHTML.indexOf("clearYes") < 0, "confirm shown before he asked");
  assert.strictEqual(els.takeCount.textContent, "take 3 of 3");
  await new Promise((r) => setTimeout(r, 100));
  assert.ok(posts.every((u) => u.indexOf("/api/voice/clear") < 0), "cleared without his tap");
  const ask = api.clearAsk();
  assert.strictEqual(ask.action, "Clear 4", "confirm does not name every take");
  assert.strictEqual(ask.item, "4 takes of step 2");
  await api.clearAttempts();
  assert.deepStrictEqual(posts.filter((u) => u.indexOf("/api/voice/clear") === 0), ["/api/voice/clear"]);
  assert.strictEqual((S.takes.d02 || []).length, 0);
  assert.strictEqual(els.takeCount.textContent, "nothing said yet");
  assert.strictEqual(els.clearBox.innerHTML, "", "button still shown with no takes");
  assert.strictEqual(api.earned(p), false);
  assert.ok(els.alert.innerHTML.indexOf("Cleared 4 takes") >= 0);
  assert.strictEqual(S.takes.d01.length, 1, "another step's takes were touched");
  assert.ok(posts.every((u) => u.indexOf("/api/voice/progress") < 0), "clearing wrote progress");
}

async function pathRowAndOnlyNewestTakeOpen() {
  const p = PROMPTS[1], takes = { d02: [miss(p), miss(p)] };
  takes.d02.forEach((t, i) => { t.id = "m-" + i; });
  const { api, els } = await load({ cleared: { d01: "t" }, takes });
  assert.strictEqual((els.pbar.innerHTML.match(/<i /g) || []).length, 3, "one path segment per step");
  assert.ok(els.pbar.innerHTML.indexOf('<i class="ok"></i><i class="cur"></i><i class=""></i>') === 0, "segments do not show cleared, current, locked");
  assert.strictEqual(els.pathCount.textContent, "1 / 3");
  assert.strictEqual(els.takes.hidden, false);
  assert.strictEqual((els.takeList.innerHTML.match(/<details class="take[^>]* open>/g) || []).length, 1, "only the newest take is open");
  assert.ok(els.progSum.innerHTML.indexOf("v/b <u>100</u>") >= 0, "error summary missing");
  api.go(0);
  assert.strictEqual(els.pathCount.hidden, true, "count shown while revisiting");
  assert.strictEqual(els.resume.hidden, false);
  assert.strictEqual(els.takes.hidden, true, "empty take section shown");
}

(async () => {
  for (const t of [lateAnswerNeverPaintsIntoTheNextStep, redoingAClearedStepDoesNotMoveTheFurthestStep, clearAttemptsOnlyAfterConfirmAndStartsTheWindowFresh, pathRowAndOnlyNewestTakeOpen]) {
    await t();
    console.log("ok  " + t.name);
  }
})().catch((e) => { console.error("FAIL " + e.message); process.exit(1); });
