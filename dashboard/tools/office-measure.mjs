// Office budgets of T1601 PLAN §5 on the real #org: rest %, 3-working %, hidden frames, fps, first-visit KB, list ms, first 3D frame ms; one JSON line.
// Usage: node tools/office-measure.mjs [--gate] [base-url]   (--gate: exit 0 every gate met, 1 one missed, 3 machine not quiet)
import fs from 'node:fs'; import path from 'node:path'; import { createRequire } from 'node:module'; import { execSync, spawnSync } from 'node:child_process';
const dir = path.join(path.dirname(process.execPath), '..', 'lib', 'node_modules', '@playwright/mcp/node_modules/playwright-core');
const { chromium } = createRequire(path.join(dir, 'package.json'))(dir);
const gate = process.argv.includes('--gate'), base = process.argv.slice(2).find((a) => !a.startsWith('--')) || 'http://127.0.0.1:19998';
const GPU = ['--enable-gpu', '--ignore-gpu-blocklist', '--use-angle=vulkan', '--enable-features=Vulkan'];
const SIZES = [[400, 850], [768, 1024], [1920, 1080], [2560, 1440], [1366, 768]];
const MARK = '--office-measure-' + process.pid, HZ = 100, WINDOW_S = 20, CALM_S = 40, HIDE_S = 10;
const GATES = { restCpu: (v) => v < 2, workCpu: (v) => v <= 5.7, hiddenFrames: (v) => v === 0, downloadKB: (v) => v < 5120, listMs: (v) => Math.max(...Object.values(v)) <= 1000, first3dMs: (v) => v <= 2500 };

/* True when quiet-gate finds the CPU and the GPU quiet. */
const quiet = () => spawnSync('quiet-gate', ['--gpu'], { stdio: 'ignore' }).status === 0;
/* The process and all its descendants. */
const tree = (pid) => [pid, ...execSync(`pgrep -P ${pid} || true`).toString().split(/\s+/).filter(Boolean).flatMap(tree)];
/* utime + stime clock ticks of the processes. */
const ticks = (pids) => pids.reduce((t, p) => { try { const f = fs.readFileSync(`/proc/${p}/stat`, 'utf8').split(') ')[1].split(' '); return t + +f[11] + +f[12]; } catch { return t; } }, 0);
const sleep = (s) => new Promise((ok) => setTimeout(ok, s * 1000));

/* The payload of a scenario: nobody works (rest), or the first 3 seats below the CEO work (work). */
function scenario(j, kind) {
  const calm = (s) => (s.state === 'working' ? { ...s, state: 'idle' } : s);
  const o = { ...j, sessions: (j.sessions || []).map(calm), agents: { ...(j.agents || {}), subagents: ((j.agents || {}).subagents || []).map((a) => (a.state === 'working' ? { ...a, state: 'done' } : a)) },
    staff: (j.staff || []).map((t) => ({ ...t, members: t.members.map((m) => (m.state === 'working' ? { ...m, state: 'idle' } : m)) })) };
  if (kind !== 'work') return o;
  const three = (j.seats || []).filter((s) => s.role !== 'owner' && s.role !== 'ceo').slice(0, 3).map((s) => s.id);
  o.sessions = [...o.sessions.filter((s) => !three.includes(s.seat)), ...three.map((seat, i) => ({ seat, state: 'working', pid: 990001 + i, since: new Date().toISOString(), parent: 'owner', name: seat, folder: '~' }))];
  return o;
}

if (!quiet()) { console.log(JSON.stringify({ quiet: false })); process.exit(3); }
const b = await chromium.launch({ headless: true, args: ['--mute-audio', ...GPU, MARK] });
const ctx = await b.newContext({ viewport: { width: 1366, height: 768 }, deviceScaleFactor: 1 });
await ctx.addInitScript(() => {
  let hid = false;
  Object.defineProperty(document, 'hidden', { get: () => hid });
  Object.defineProperty(document, 'visibilityState', { get: () => (hid ? 'hidden' : 'visible') });
  window.__hide = (h) => { hid = h; document.dispatchEvent(new Event('visibilitychange')); };
});
let kind = 'rest';
await ctx.route('**/*', async (r) => {
  const q = r.request();
  if (q.method() !== 'GET') return r.abort();
  const u = new URL(q.url()).pathname;
  if (u !== '/api/office' && u !== '/api/agents') return r.continue();
  const h = { ...q.headers() };
  delete h['if-none-match'];
  const j = await (await r.fetch({ headers: h })).json();
  const body = u === '/api/office' ? scenario(j, kind) : { ...j, subagents: (j.subagents || []).map((a) => (a.state === 'working' ? { ...a, state: 'done' } : a)) };
  return r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
});
const p = await ctx.newPage(), errs = [];
let bytes = 0;
p.on('pageerror', (e) => errs.push(String(e).slice(0, 140)));
p.on('requestfinished', async (q) => { try { const s = await q.sizes(); bytes += s.responseBodySize + s.responseHeadersSize; } catch { /* aborted */ } });
const frames = () => p.evaluate(() => [window.__office ? window.__office.stats().frames : 0, window.__stage ? window.__stage.frames() : 0]);
const first3d = () => p.waitForFunction(() => window.__office && window.__office.stats().frames > 0 && performance.now(), null, { timeout: 20000 }).then((h) => h.jsonValue());

await p.goto(base + '/#org', { waitUntil: 'load' });
await first3d();
await p.waitForLoadState('networkidle');
const downloadKB = Math.round(bytes / 1024), still = await p.evaluate(() => window.__office.still);

const listMs = {};
let first3dMs = 0;
for (const [w, h] of SIZES) {
  await p.setViewportSize({ width: w, height: h });
  const t0 = Date.now();
  await p.reload({ waitUntil: 'commit' });
  await p.waitForSelector('.office .olist [data-who]', { state: 'visible', timeout: 20000 });
  listMs[w] = Date.now() - t0;
}
first3dMs = Math.round(await first3d());

/* CPU % of one core of the browser tree and frames (office, eye) over s seconds. */
async function window_(s) {
  const pids = tree(execSync(`pgrep -o -f -- ${MARK}`).toString().trim()), f0 = await frames(), k0 = ticks(pids), t0 = Date.now();
  await sleep(s);
  const f1 = await frames(), dt = (Date.now() - t0) / 1000;
  return { cpu: +((100 * (ticks(pids) - k0)) / HZ / dt).toFixed(2), office: f1[0] - f0[0], eye: f1[1] - f0[1], dt };
}
await sleep(CALM_S);
const rest = await window_(WINDOW_S);
kind = 'work';
await p.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
await p.waitForFunction(() => /\b3 working\b/.test((document.querySelector('.office .bsum') || {}).textContent || ''), null, { timeout: 30000 });
await sleep(CALM_S);
const work = await window_(WINDOW_S);
await p.evaluate(() => window.__hide(true));
await sleep(1);
const hid = await window_(HIDE_S);
await b.close();

const out = { restCpu: rest.cpu, workCpu: work.cpu, hiddenFrames: hid.office + hid.eye, fps: +(work.office / work.dt).toFixed(2), downloadKB, listMs, first3dMs,
  restFrames: [rest.office, rest.eye], workEyeFrames: work.eye, hiddenCpu: hid.cpu, still, errs };
const missed = Object.keys(GATES).filter((k) => !GATES[k](out[k])).concat(still ? ['still'] : []);
const after = quiet();
console.log(JSON.stringify({ ...out, missed, quiet: after }));
if (gate) process.exit(!after ? 3 : missed.length ? 1 : 0);
