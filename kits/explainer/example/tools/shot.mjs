// Headless stills: node tools/shot.mjs <url> <width> <outprefix> <t1,t2,…|beat:drive> — one page, seeks with __rec, GPU flags on.
import { chromium } from 'playwright-core';
const GPU = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-angle=vulkan', '--enable-gpu', '--ignore-gpu-blocklist'];
const [url, w = '1920', pre = 'out/s', times = '6'] = process.argv.slice(2);
const W = +w, H = Math.round((W * 9) / 16);
const b = await chromium.launch({ headless: true, args: GPU });
const p = await b.newPage({ viewport: { width: W, height: H }, ignoreHTTPSErrors: true });
const logs = []; p.on('console', (m) => { if (m.type() !== 'log') logs.push(m.text().slice(0, 300)); }); p.on('pageerror', (e) => logs.push('ERR ' + e.message));
const t0 = Date.now();
await p.goto(url + (url.includes('?') ? '&' : '?') + 't=0');
await p.waitForFunction(() => window.__probe?.ready > 0, null, { timeout: 30000 }).catch(() => logs.push('no ready'));
console.log('ready', Date.now() - t0, 'ms', JSON.stringify(await p.evaluate(() => ({ r: Math.round(window.__probe.ready), lt: window.__probe.longtasks, gl: (() => { const g = document.querySelector('canvas')?.getContext('webgl2'); const e = g?.getExtension('WEBGL_debug_renderer_info'); return e ? g.getParameter(e.UNMASKED_RENDERER_WEBGL) : '-'; })(), sw: document.documentElement.scrollWidth }))));
for (const t of times.split(',')) {
  if (t.startsWith('beat:')) await p.evaluate((b) => window.__rec.go(b), t.slice(5));
  else if (t.startsWith('turn:')) { const [i, n] = t.slice(5).split('/').map(Number); await p.evaluate(([i, n]) => window.__rec.turn(i, n), [i, n]); await p.waitForTimeout(1500); }
  else if (t.startsWith('wait:')) await p.waitForTimeout(+t.slice(5));
  else await p.evaluate((t) => window.__rec.watch(t), +t);
  await p.waitForTimeout(250);
  await p.screenshot({ path: `${pre}-${W}-${t.replace(/[:/]/g, '_')}.png` });
}
if (logs.length) console.log(logs.join('\n'));
await b.close();
