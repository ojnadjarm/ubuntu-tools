// Measure theme edit -> repainted pixels via HMR: node tools/hmr.mjs <devurl>
import { chromium } from 'playwright-core';
import { readFileSync, writeFileSync } from 'node:fs';
const GPU = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-angle=vulkan', '--enable-gpu', '--ignore-gpu-blocklist'];
const F = 'src/plate/theme.ts', src = readFileSync(F, 'utf8');
const b = await chromium.launch({ headless: true, args: GPU });
const p = await b.newPage({ viewport: { width: 1920, height: 1080 }, ignoreHTTPSErrors: true });
let reloads = 0; p.on('load', () => reloads++);
await p.goto(process.argv[2] + '?t=58');
await p.waitForFunction(() => window.__probe?.ready > 0);
const runs = [];
for (const c of ['#0f7a5a', '#1d5fb0', '#0f7a5a', '#1d5fb0', '#0f7a5a']) {
  const t0 = Date.now();
  writeFileSync(F, src.replace(/signal: '#[0-9a-f]{6}'/, `signal: '${c}'`));
  await p.waitForFunction((c) => window.__probe.accentDrawn === c, c, { timeout: 10000, polling: 'raf' });
  runs.push(Date.now() - t0);
  await p.waitForTimeout(300);
}
await p.screenshot({ path: 'out/hmr-green.png' });
writeFileSync(F, src);
console.log(JSON.stringify({ runs, reloads }));
await b.close();
