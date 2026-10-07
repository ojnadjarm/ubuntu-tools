// Headless stills on the GPU: node tools/shot.mjs <url> <width> <outprefix> <t1,t2,…> — one page, seeks with __seek, 16:9 viewport;
// prints the look gate (tools/look.mjs) for each still over the casing when the casing is on screen.
import { chromium } from 'playwright-core';
import { look, misses } from './look.mjs';
const GPU = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-angle=vulkan', '--enable-gpu', '--ignore-gpu-blocklist'];
const [url, w = '1920', pre = 'out/s', times = '6'] = process.argv.slice(2);
const W = +w, H = Math.round((W * 9) / 16);
const b = await chromium.launch({ headless: true, args: GPU });
const p = await b.newPage({ viewport: { width: W, height: H }, ignoreHTTPSErrors: true });
const logs = [];
p.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') logs.push(m.text().slice(0, 300)); });
p.on('pageerror', (e) => logs.push('ERR ' + e.message));
await p.goto(url + (url.includes('?') ? '&' : '?') + 't=0');
await p.waitForFunction(() => window.__probe?.ready > 0, null, { timeout: 30000 }).catch(() => logs.push('no ready'));
const info = await p.evaluate(() => {
  const g = document.querySelector('canvas')?.getContext('webgl2'), e = g?.getExtension('WEBGL_debug_renderer_info');
  const { fw, ...r } = window.__probe;
  return { ...r, fwMax: Math.max(0, ...fw), gl: e ? g.getParameter(e.UNMASKED_RENDERER_WEBGL) : '-', scrollW: document.documentElement.scrollWidth };
});
console.log(JSON.stringify(info));
for (const t of times.split(',')) {
  await p.evaluate((t) => window.__seek(t), +t);
  await p.waitForTimeout(250);
  const buf = await p.screenshot({ path: `${pre}-${W}-${t}.png` });
  const r = await p.evaluate(() => window.__casingPx?.());
  if (r) { const m = await look(p, buf, r.map(Math.round).join(',')); const f = misses(m); console.log(`t=${t}`, JSON.stringify(m), f.length ? 'LOOK FAIL: ' + f.join('; ') : 'LOOK OK'); }
}
if (logs.length) console.log(logs.join('\n'));
await b.close();
