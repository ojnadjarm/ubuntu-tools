// Print load probe fields: node tools/probe.mjs <url>
import { chromium } from 'playwright-core';
const GPU = ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-angle=vulkan', '--enable-gpu', '--ignore-gpu-blocklist'];
const b = await chromium.launch({ headless: true, args: GPU });
const p = await b.newPage({ viewport: { width: 1920, height: 1080 }, ignoreHTTPSErrors: true });
p.on('pageerror', (e) => console.log('ERR', e.message));
await p.goto(process.argv[2]);
await p.waitForFunction(() => window.__probe?.ready > 0, null, { timeout: 30000 });
console.log(JSON.stringify(await p.evaluate(() => { const { fw, ...r } = window.__probe; return { ...r, fwMax: Math.max(...fw), fwN: fw.length }; })));
await b.close();
