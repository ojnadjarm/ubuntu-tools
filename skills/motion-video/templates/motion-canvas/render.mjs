// Headless Motion Canvas render: start Vite, click the editor's Render button, wait for output/*.mp4.
import {spawn} from 'node:child_process';
import {chromium} from 'playwright-core';

const port = process.env.MC_PORT ?? '9123';
const chrome = process.env.MV_CHROME ?? '/usr/bin/google-chrome';
const vite = spawn('node_modules/.bin/vite', ['--port', port, '--strictPort', '--host', '127.0.0.1'], {stdio: ['ignore', 'pipe', 'pipe'], detached: true});
vite.stderr.on('data', d => String(d).includes('CJS build') || process.stderr.write(d));
await new Promise((ok, fail) => {
  vite.stdout.on('data', d => String(d).includes('Local') && ok());
  vite.on('exit', c => fail(new Error(`vite exited ${c}`)));
});
const browser = await chromium.launch({executablePath: chrome, headless: true, args: ['--mute-audio', '--autoplay-policy=user-gesture-required']});
let code = 0;
try {
  const page = await browser.newPage();
  page.on('pageerror', e => console.error('page:', e.message));
  await page.goto(`http://127.0.0.1:${port}/`);
  if (!(await page.locator('#render').isVisible())) await page.click('#rendering-tab');
  const t0 = Date.now();
  await page.click('#render');
  await page.waitForSelector('#render[data-rendering]', {timeout: 30_000});
  await page.waitForSelector('#render[data-rendering]', {state: 'detached', timeout: 60 * 60_000});
  console.log(`rendered in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
} catch (e) {
  console.error(e.message);
  code = 1;
} finally {
  await browser.close();
  process.kill(-vite.pid, 'SIGTERM');
}
process.exit(code);
