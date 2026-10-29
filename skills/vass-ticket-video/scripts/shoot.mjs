// shoot.mjs — record a VASS shot list headless, one narration clip per step, marks + stills into <work>.
// Usage: node shoot.mjs <shots.json> <work>   (work holds vo/cues.json, ws-<n>.json; writes raw.webm, marks.json, still-*.png)
//        node shoot.mjs --check <shots.json>  validate the shot list only (no browser)
import fs from 'node:fs';
import path from 'node:path';
import { validate, redact } from './shotlist.mjs';

const args = process.argv.slice(2);
if (args[0] === '--check') {
  const errs = validate(JSON.parse(fs.readFileSync(args[1], 'utf8')));
  if (errs.length) { console.error(errs.join('\n')); process.exit(1); }
  console.log('shot list ok'); process.exit(0);
}
const [shotsPath, work] = args;
const shots = JSON.parse(fs.readFileSync(shotsPath, 'utf8'));
const errs = validate(shots);
if (errs.length) { console.error(errs.join('\n')); process.exit(1); }

const env = process.env;
const BASE = { front: env.VASS_FRONT_URL, back: env.VASS_MOODLE_URL };
const cues = JSON.parse(fs.readFileSync(path.join(work, 'vo/cues.json'), 'utf8')).clips;

// Pick the first npx Playwright build whose Chromium is installed (a newer build may lack its browser).
async function loadChromium() {
  const root = path.join(env.HOME, '.npm/_npx');
  const cands = (env.PLAYWRIGHT_MJS ? [env.PLAYWRIGHT_MJS] : []).concat(
    fs.existsSync(root) ? fs.readdirSync(root).map(d => path.join(root, d, 'node_modules/playwright/index.mjs')) : []);
  for (const c of cands.filter(fs.existsSync)) {
    const { chromium } = await import(c);
    try { if (fs.existsSync(chromium.executablePath())) return chromium; } catch { /* next */ }
  }
  throw new Error('no Playwright build with an installed Chromium (set PLAYWRIGHT_MJS)');
}


const ctxopts = { viewport: { width: 1280, height: 720 }, ignoreHTTPSErrors: true, timezoneId: 'Europe/Madrid', locale: 'es-ES' };

// The front shows a first-login profile gate; report the profile as confirmed client-side.
async function skipProfileGate(ctx) {
  await ctx.route('**/users/get-user-preferences*', async (route) => {
    try {
      const r = await route.fetch(); const j = await r.json(); const prefs = j?.data?.preferences;
      if (Array.isArray(prefs)) {
        const f = prefs.find(x => x.name === 'is_first_time');
        if (f) f.value = '1'; else prefs.push({ name: 'is_first_time', value: '1' });
      }
      await route.fulfill({ response: r, body: JSON.stringify(j) });
    } catch { /* context closing */ }
  });
}

async function frontLogin(p, email) {
  if (!env.VASS_STUDENT_PASSWORD) throw new Error('VASS_STUDENT_PASSWORD unset (config.env)');
  await p.goto(BASE.front + '/auth');
  await p.fill('input[name=email]', email);
  await p.fill('input[name=password]', env.VASS_STUDENT_PASSWORD);
  await p.getByRole('button', { name: 'Acceso', exact: true }).click();
  await p.waitForURL(u => !u.pathname.startsWith('/auth'), { timeout: 30000 });
}

async function backLogin(p, user) {
  if (!env.VASS_MOODLE_PASSWORD) throw new Error('VASS_MOODLE_PASSWORD unset (config.env, or MOODLE_ADMIN_PASSWORD)');
  await p.goto(BASE.back + '/login/index.php');
  const fatal = await p.locator('body').innerText();
  if (/Fatal error|Permission denied/.test(fatal)) throw new Error('Moodle login page broken: ' + fatal.trim().split('\n')[0]);
  await p.fill('#username', user);
  await p.fill('#password', env.VASS_MOODLE_PASSWORD);
  await p.click('#loginbtn');
  await p.waitForURL(u => !u.pathname.startsWith('/login'), { timeout: 30000 });
}

const url = (site, u) => /^https?:/.test(u) ? u : BASE[site] + u;

function locator(p, sel) {
  const [kind, ...rest] = sel.split(':'); const v = rest.join(':');
  if (kind === 'link' || kind === 'button' || kind === 'tab') return p.getByRole(kind, { name: v, exact: true }).first();
  if (kind === 'text') return p.getByText(v).first();
  if (kind === 'css') return p.locator(v).first();
  throw new Error(`bad selector ${sel}`);
}

// Outline the bordered box around each label (exact text; a trailing * matches a prefix; css:... a selector).
const highlight = (p, labels) => p.evaluate((labels) => {
  document.querySelectorAll('[data-vtv-hl]').forEach(e => { e.style.outline = ''; e.removeAttribute('data-vtv-hl'); });
  const boxed = (el) => {
    for (let e = el, i = 0; e && i < 5; e = e.parentElement, i++) {
      const s = getComputedStyle(e);
      if (parseFloat(s.borderTopWidth) > 0 || s.boxShadow !== 'none') return e;
    }
    return el;
  };
  for (const t of labels) {
    let el;
    if (t.startsWith('css:')) el = document.querySelector(t.slice(4));
    else {
      const all = [...document.querySelectorAll('body *')].filter(x => x.children.length === 0 || x.tagName === 'P');
      el = all.find(x => t.endsWith('*') ? x.textContent.trim().startsWith(t.slice(0, -1)) : x.textContent.trim() === t);
    }
    if (!el) continue;
    const box = boxed(el);
    box.style.outline = '4px solid #e11d48'; box.style.outlineOffset = '3px'; box.setAttribute('data-vtv-hl', '1');
  }
}, labels);

const esc = (s) => String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

const overlay = (p, o) => p.evaluate((html) => {
  const d = document.createElement('div'); d.innerHTML = html;
  Object.assign(d.style, { position: 'fixed', left: '50%', top: '160px', transform: 'translateX(-50%)', background: '#fff',
    border: '3px solid #0f172a', borderRadius: '16px', padding: '28px 40px', textAlign: 'center', font: '24px sans-serif',
    zIndex: 99999, boxShadow: '0 10px 40px #0005' });
  document.body.appendChild(d);
}, `<div style="font:600 30px sans-serif;margin-bottom:18px">${esc(o.title || '')}</div><div style="display:flex;gap:60px;justify-content:center">`
  + (o.cols || []).map(c => `<div>${esc(c.label)}<br><b style="font-size:56px;color:${esc(c.color || '#2563eb')}">${esc(c.value)}</b>`
  + `<br><small>${esc(c.note || '')}</small></div>`).join('') + '</div>');

// Side-by-side JSON panes of WS results fetched before recording (ws-<step>.json).
function wsPage(step, data) {
  const panes = data.map(d => `<div class="pane"><h2>${esc(d.label)}</h2><div class="fn">${esc(d.fn)}</div>`
    + `<pre>${esc(JSON.stringify(d.result, null, 2))}</pre></div>`).join('');
  return `<!doctype html><meta charset="utf-8"><style>body{margin:0;font:18px system-ui;background:#0f172a;color:#e2e8f0}
h1{font-size:26px;margin:24px 32px 8px}.row{display:flex;gap:24px;padding:16px 32px}.pane{flex:1;background:#1e293b;border-radius:12px;padding:16px 20px}
h2{margin:0 0 4px;font-size:24px;color:#fff}.fn{font:14px monospace;color:#94a3b8}pre{font:20px/1.5 monospace;white-space:pre-wrap;margin:12px 0 0}</style>
<h1>${esc(step.ws_title || 'Respuesta de los servicios web')}</h1><div class="row">${panes}</div>`;
}

const chromium = await loadChromium();
const b = await chromium.launch({ headless: true, args: ['--mute-audio'] });
let c; let p; let stepNo = 0;
try {
  const l = await b.newContext(ctxopts); await skipProfileGate(l);
  const lp = await l.newPage();
  if (shots.front_user) await frontLogin(lp, shots.front_user);
  if (shots.back_user) await backLogin(lp, shots.back_user);
  const state = await l.storageState(); await l.unrouteAll({ behavior: 'ignoreErrors' }); await l.close();

  c = await b.newContext({ ...ctxopts, storageState: state, recordVideo: { dir: path.join(work, 'vid'), size: { width: 1280, height: 720 } } });
  await skipProfileGate(c);
  p = await c.newPage(); const t0 = Date.now(); const marks = {};
  const now = () => (Date.now() - t0) / 1000;
  const W = (ms) => ms > 0 ? p.waitForTimeout(ms) : null;

  for (const [i, step] of shots.steps.entries()) {
    stepNo = i + 1;
    const id = `s${i + 1}`; const site = step.site || 'front';
    const act = async (a) => {
      if (a.go) await p.goto(url(a.site || 'front', a.go));
      for (const sel of [].concat(a.click || [])) { await locator(p, sel).click(); }
      for (const f of [].concat(a.fill || [])) { await locator(p, f.sel).fill(f.value); }
      for (const w of [].concat(a.wait || [])) {
        if (typeof w === 'number') await W(w); else await locator(p, w).waitFor({ timeout: 30000 });
      }
    };
    for (const a of step.pre || []) await act(a);
    if (step.ws) await p.setContent(wsPage(step, JSON.parse(fs.readFileSync(path.join(work, `ws-${i + 1}.json`), 'utf8'))));
    await act({ ...step, site });
    await W(step.settle ?? 1200);
    marks[id] = now();
    const clip = cues[id]; const cueAt = clip.marks?.hl;
    const apply = async () => {
      if (step.highlight) await highlight(p, step.highlight);
      if (step.overlay) await overlay(p, step.overlay);
    };
    if (cueAt == null) await apply();
    else { await W((marks[id] + cueAt) * 1000 - now() * 1000); await apply(); }
    const end = marks[id] + clip.duration + (step.hold ?? 0.6);
    if (step.still) { await W((end - 0.4) * 1000 - now() * 1000); await p.screenshot({ path: path.join(work, `still-${i + 1}-${step.still}.png`) }); }
    await W(end * 1000 - now() * 1000);
  }
  marks.end = now();
  const v = p.video(); await c.unrouteAll({ behavior: 'ignoreErrors' }); await c.close(); c = null;
  fs.renameSync(await v.path(), path.join(work, 'raw.webm'));
  fs.writeFileSync(path.join(work, 'marks.json'), JSON.stringify(marks, null, 1));
  console.log('shoot: steps', shots.steps.length, 'length', marks.end.toFixed(1), 's');
} catch (e) {
  console.error(`shoot failed at step ${stepNo}:`, redact(e), `(screen: ${path.join(work, 'fail.png')})`);
  process.exitCode = 1;
  if (p) await p.screenshot({ path: path.join(work, 'fail.png') }).catch(() => {});
} finally {
  if (c) { await c.unrouteAll({ behavior: 'ignoreErrors' }).catch(() => {}); await c.close().catch(() => {}); }
  await b.close();
}
