// Headless end-to-end run of an explainer-kit unit, from the unit's folder: node <kit>/tools/e2e.mjs <url> <out.json> [actions]
// Frozen sweep (state = f(t) every 10 ms), live run with audio (clip schedule vs clock, cue onsets, frame times), the hands-on
// beats driven by `actions`, idle frame counts. actions: comma list of turn:<hand>/<clicks> · hand:<i> (wait until enabled) ·
// wait:<ms> · cta (wait for the call to action, click it) · end (wait for the end card). Default: the A01 example's drive.
// marks: ms from the first action to the end of each; a repeated action gets #2, #3, …
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
const { chromium } = createRequire(process.cwd() + '/')('playwright-core');

const GPU = ['--enable-features=Vulkan', '--use-angle=vulkan', '--enable-gpu', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'];
const [url, out, actions = 'wait:800,turn:0/2,hand:1,turn:1/1,cta,end'] = process.argv.slice(2);
const b = await chromium.launch({ headless: true, args: GPU });
const ctx = await b.newContext({ viewport: { width: 1920, height: 1080 }, ignoreHTTPSErrors: true });
const errors = [];
const page = async (u) => {
  const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push(e.message));
  p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });
  await p.addInitScript(() => {
    window.__src = [];
    const start = AudioBufferSourceNode.prototype.start;
    AudioBufferSourceNode.prototype.start = function (when = 0, offset = 0, ...r) {
      window.__src.push({ when, offset, dur: this.buffer?.duration ?? 0, now: this.context.currentTime });
      return start.call(this, when, offset, ...r);
    };
  });
  await p.goto(u, { waitUntil: 'commit' });
  return p;
};

// 1. Frozen sweep: the watch timeline sampled every 10 ms of narration time.
const f = await page(url + '?t=0');
await f.waitForFunction(() => window.__probe?.ready > 0, null, { timeout: 30000 });
const sweep = await f.evaluate(() => {
  const d = window.__d, dur = d.tl.duration(), rows = [];
  for (let i = 0; i * 0.01 <= dur + 1e-9; i++) { const t = +(i * 0.01).toFixed(2); d.tl.seek(t); rows.push({ t, s: Object.fromEntries(Object.entries(d.s).filter(([, v]) => typeof v === 'number')) }); }
  return { dur, offsets: window.__rec.offsets, rows };
});
await f.close();

// 2. Live run with audio: Begin, sample every frame, then guided play to the end card.
const p = await page(url);
await p.waitForFunction(() => window.__probe?.frames > 0, null, { timeout: 30000, polling: 'raf' });
await p.click('[data-k=begin]');
await p.waitForFunction(() => window.__probe.ready > 0 && window.__d?.beats?.name === 'watch', null, { timeout: 30000 });
await p.evaluate(() => {
  const d = window.__d, ctx = window.__d.voice.ctx, rows = (window.__live = []);
  let last = performance.now();
  const f = (now) => {
    rows.push({ clock: d.clock.now(), ctxT: ctx ? ctx.currentTime : 0, lat: ctx ? ctx.outputLatency || 0 : 0, dt: now - last, beat: d.beats.name, s: Object.fromEntries(Object.entries(d.s).filter(([, v]) => typeof v === 'number')) });
    last = now;
    if (rows.length < 20000) requestAnimationFrame(f);
  };
  requestAnimationFrame(f);
});
const fw0 = await p.evaluate(() => window.__probe.fw.length);
await p.waitForSelector('[data-k=cta]:not([hidden])', { timeout: 150000 });
const cta1 = await p.textContent('[data-k=cta]');
const watchEnd = await p.evaluate(() => window.__d.clock.now());
// Idle after the watch ends: director draws over 2 s (the sampler's own rAF does not draw).
await p.waitForTimeout(5000);
const idleWatch = await p.evaluate(async () => { const n = window.__probe.frames; await new Promise((r) => setTimeout(r, 2000)); return window.__probe.frames - n; });
await p.click('[data-k=cta]');
const t0 = Date.now(), marks = {}, cta2 = [];
for (const a of actions.split(',')) {
  const [k, v = ''] = a.split(':');
  if (k === 'turn') { const [i, n] = v.split('/').map(Number); await p.evaluate(([i, n]) => window.__rec.turn(i, n), [i, n]); }
  else if (k === 'hand') await p.waitForFunction((i) => window.__d.hands[i].enabled, +v, { timeout: 60000 });
  else if (k === 'wait') await p.waitForTimeout(+v);
  else if (k === 'cta') { await p.waitForSelector('[data-k=cta]:not([hidden])', { timeout: 60000 }); cta2.push(await p.textContent('[data-k=cta]')); await p.click('[data-k=cta]'); }
  else if (k === 'end') await p.waitForSelector('[data-k=end]:not([hidden])', { timeout: 60000 });
  marks[a in marks ? `${a}#${Object.keys(marks).filter((m) => m === a || m.startsWith(a + '#')).length + 1}` : a] = Date.now() - t0;
}
const endBeat = await p.evaluate(() => window.__d.beats.name);
await p.waitForTimeout(3000);
const idleEnd = await p.evaluate(async () => { const n = window.__probe.frames; await new Promise((r) => setTimeout(r, 2000)); return window.__probe.frames - n; });
const live = await p.evaluate((n) => ({ rows: window.__live, src: window.__src, fw: window.__probe.fw.slice(n + 2), sw: document.documentElement.scrollWidth }), fw0);
await b.close();

writeFileSync(out, JSON.stringify({ url, sweep, live, cta1, cta2, watchEnd, marks, endBeat, idleWatch, idleEnd, errors }));
console.log(JSON.stringify({ url, dur: sweep.dur, rows: sweep.rows.length, liveRows: live.rows.length, cta1, cta2, watchEnd: +watchEnd.toFixed(2), marks, endBeat, idleWatch, idleEnd, errors: errors.length }));
