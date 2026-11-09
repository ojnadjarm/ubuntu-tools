// Panel screenshots at five widths plus metrics.json; POSTs blocked; exit 1 if any shot scrolls sideways.
// Usage: node tools/shots.mjs <out-dir> [screen,screen|all] [base-url]
import fs from 'node:fs'; import path from 'node:path'; import { createRequire } from 'node:module'; import { fileURLToPath } from 'node:url';
const dir = path.join(path.dirname(process.execPath), '..', 'lib', 'node_modules', '@playwright/mcp/node_modules/playwright-core');
const { chromium } = createRequire(path.join(dir, 'package.json'))(dir);
const registry = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'static/next/js/screens.js');
const all = [...fs.readFileSync(registry, 'utf8').matchAll(/\{ id: "([\w-]+)", sec:/g)].map((m) => m[1]);
const out = process.argv[2], pick = process.argv[3], base = process.argv[4] || 'http://127.0.0.1:19998';
if (!out) { console.error('usage: shots.mjs <out-dir> [screen,screen|all] [base-url]'); process.exit(2); }
const screens = !pick || pick === 'all' ? all : pick.split(',');
fs.mkdirSync(out, { recursive: true });
const sizes = [[400, 850], [768, 1024], [1366, 768], [1920, 1080], [2560, 1440]];
const b = await chromium.launch({ headless: true, args: ['--mute-audio'] });
const rows = [];
for (const [w, h] of sizes) for (const s of screens) {
  const ctx = await b.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  const p = await ctx.newPage();
  const errs = []; let reqs = 0, bytes = 0;
  p.on('console', (m) => { if (m.type() === 'error') errs.push(m.text().slice(0, 140)); });
  p.on('pageerror', (e) => errs.push(String(e).slice(0, 140)));
  p.on('response', async (r) => { reqs++; const l = +(r.headers()['content-length'] || 0); bytes += l; });
  await p.route('**/*', (r) => (r.request().method() === 'GET' ? r.continue() : r.abort()));
  const t0 = Date.now();
  await p.goto(`${base}/#${s}`, { waitUntil: 'load', timeout: 60000 }).catch((e) => errs.push('goto ' + e.message.slice(0, 80)));
  await p.waitForFunction(() => !document.querySelector('#grid .empty, .skel'), null, { timeout: 15000 }).catch(() => errs.push('still loading at 15 s'));
  const ready = Date.now() - t0;
  await p.waitForTimeout(3500);
  const m = await p.evaluate(() => {
    const de = document.documentElement, vw = innerWidth;
    const over = [...document.querySelectorAll('#board *, #rail *, #subs *')].filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && (r.right > vw + 1 || r.left < -1) && getComputedStyle(e).position !== 'fixed'; }).slice(0, 4).map((e) => (e.className && String(e.className).split(' ')[0]) || e.tagName);
    const small = [...document.querySelectorAll('#board a, #board button, #subs a, .dock a')].filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && (r.height < 32 || r.width < 32); }).length;
    const tiny = [...document.querySelectorAll('#board *')].filter((e) => e.children.length === 0 && e.textContent.trim() && parseFloat(getComputedStyle(e).fontSize) < 11).length;
    const main = document.querySelector('#board').getBoundingClientRect();
    return { sw: de.scrollWidth, vw, sh: de.scrollHeight, vh: innerHeight, over, small, tiny, nodes: document.querySelectorAll('*').length, boardW: Math.round(main.width) };
  }).catch((e) => ({ err: String(e).slice(0, 100) }));
  await p.screenshot({ path: `${out}/${s}-${w}.png`, timeout: 60000 }).catch((e) => errs.push('shot ' + e.message.slice(0, 80)));
  rows.push({ s, w, ready, reqs, kb: Math.round(bytes / 1024), ...m, errs });
  console.log(JSON.stringify(rows[rows.length - 1]));
  await ctx.close();
}
fs.writeFileSync(path.join(out, 'metrics.json'), JSON.stringify(rows, null, 1));
await b.close();
const side = rows.filter((r) => !(r.sw <= r.vw));
if (side.length) { console.error(`sideways scroll: ${side.map((r) => `${r.s}-${r.w} (${r.sw ?? r.err} > ${r.vw})`).join(', ')}`); process.exit(1); }
