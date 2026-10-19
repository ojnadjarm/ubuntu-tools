// Recorder upload: the client waits longer than the server's worst case, and a timeout refreshes the take list.
// Run: node tests/test_recorder.js
"use strict";
const path = require("path"), assert = require("assert"), { pathToFileURL } = require("url");

const ROOT = path.join(__dirname, "..");
require("module").registerHooks({ resolve: (spec, ctx, next) => next(spec.startsWith("/static/") ? pathToFileURL(path.join(ROOT, spec)).href : spec, ctx) });
// save_clip worst case: ffmpeg 60 s + transcribe 90 s (dash/services/voice.py)
const SERVER_WORST_MS = 150000;

function element() { return { onload: null, style: {}, dataset: {}, addEventListener() {} }; }
let sent = null;
function XHR() { sent = this; this.upload = {}; this.headers = {}; }
XHR.prototype.open = function (m, u) { this.url = u; };
XHR.prototype.setRequestHeader = function (k, v) { this.headers[k] = v; };
XHR.prototype.send = function (b) { this.body = b; };
function Rec() { this.state = "inactive"; this.mimeType = "audio/webm"; }
Rec.prototype.start = function () { this.state = "recording"; };
Rec.prototype.stop = function () { this.state = "inactive"; this.ondataavailable({ data: new Blob([new Uint8Array(2000)]) }); this.onstop(); };
Rec.isTypeSupported = () => true;
const G = {
  document: { getElementById: () => element(), createElement: () => element(), head: { appendChild: (l) => l.onload && l.onload() }, querySelector: () => null, querySelectorAll: () => [], addEventListener() {} },
  navigator: { mediaDevices: { getUserMedia: () => Promise.resolve({ getTracks: () => [] }) }, vibrate() {} },
  isSecureContext: true, scrollTo() {}, MediaRecorder: Rec, XMLHttpRequest: XHR, crypto: undefined,
  fetch: () => new Promise(() => {}), localStorage: { getItem: () => null, setItem() {} }
};
for (const k of Object.keys(G)) Object.defineProperty(globalThis, k, { value: G[k], configurable: true, writable: true });
globalThis.window = globalThis;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const { recorder } = await import(pathToFileURL(path.join(ROOT, "static", "next", "js", "voice", "recorder.js")).href);
  const P = { id: "d01", text: "one", len: "short" }, S = { takes: {}, session: 0 }, alerts = [];
  let refreshed = 0;
  const r = recorder({ S, cur: () => P, render() {}, alert: (h) => alerts.push(h), saved() {},
    stats: () => { refreshed++; return Promise.resolve({}); }, words: { item: "step", line: "the line", refreshing: "refreshing…", list: "the step" } });
  r.start();
  await wait(800);
  assert.strictEqual(S.rs, "recording", "the take never started recording");
  await wait(600);
  r.stop();
  assert.ok(sent, "the clip was not uploaded");
  assert.ok(sent.timeout > SERVER_WORST_MS, "client timeout " + sent.timeout + " ms gives up before the server's " + SERVER_WORST_MS + " ms worst case");
  sent.ontimeout();
  await wait(10);
  assert.strictEqual(refreshed, 1, "a timeout claims nothing was saved without refreshing the take list");
  assert.strictEqual(S.rs, "idle");
  assert.ok(alerts.length && alerts[alerts.length - 1].indexOf("may") >= 0, "the timeout message still says the clip was not saved: " + alerts[alerts.length - 1]);
  console.log("ok test_recorder");
  process.exit(0);
})().catch((e) => { console.error(e.stack || e); process.exit(1); });
