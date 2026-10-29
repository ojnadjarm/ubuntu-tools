// shotlist.mjs — shot list schema check and the narration unit it implies (one edge clip per step).
// CLI: node shotlist.mjs check|unit <shots.json>   ·   node shotlist.mjs resolve <shots.json> <outdir>
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const TOP_KEYS = new Set(['ticket', 'phase', 'voice', 'front_user', 'back_user', 'steps', 'say', 'recall', 'overrides']);
const STEP_KEYS = new Set(['say', 'site', 'go', 'click', 'fill', 'wait', 'settle', 'highlight', 'overlay', 'ws', 'ws_title', 'still', 'hold', 'pre']);
const SEL = /^(link|button|tab|text|css):./;

export function validate(s) {
  const e = [];
  if (!/^[a-z0-9][a-z0-9-]*$/.test(s.ticket || '')) e.push('ticket: lowercase slug like jira29');
  if (!['antes', 'despues'].includes(s.phase)) e.push('phase: antes|despues');
  for (const k of Object.keys(s)) if (!TOP_KEYS.has(k)) e.push(`unknown key ${k}`);
  if (!Array.isArray(s.steps) || !s.steps.length) e.push('steps: non-empty list');
  for (const [i, st] of (s.steps || []).entries()) {
    const at = `steps[${i}]`;
    for (const k of Object.keys(st)) if (!STEP_KEYS.has(k)) e.push(`${at}: unknown key ${k}`);
    if (!st.say || typeof st.say !== 'string') e.push(`${at}.say: the Spanish line is required`);
    if (st.site && !['front', 'back'].includes(st.site)) e.push(`${at}.site: front|back`);
    if ((st.site || 'front') === 'front' && st.go && !s.front_user && !/^https?:/.test(st.go)) e.push(`${at}: front step needs front_user`);
    if (st.site === 'back' && !s.back_user) e.push(`${at}: back step needs back_user`);
    for (const sel of [].concat(st.click || [], [].concat(st.wait || []).filter(w => typeof w === 'string'))) {
      if (typeof sel === 'string' && !SEL.test(sel)) e.push(`${at}: selector "${sel}" must start with link:|button:|tab:|text:|css:`);
    }
    if (st.ws && (!Array.isArray(st.ws) || st.ws.some(w => !w.fn || !w.user || !Array.isArray(w.pick) || !w.pick.length))) {
      e.push(`${at}.ws: list of {label, fn, user, args, pick:[fields]} (pick is required: never dump whole payloads)`);
    }
    if (st.still && !/^[a-z0-9-]+$/.test(st.still)) e.push(`${at}.still: file-safe slug`);
    const say = typeof st.say === 'string' ? st.say : '';
    if ((say.match(/\{(\w+)\}/g) || []).some(m => m !== '{hl}')) e.push(`${at}.say: the only cue mark is {hl}`);
    if (say.includes('{hl}') && !st.highlight && !st.overlay) e.push(`${at}.say: {hl} with nothing to show`);
  }
  if (s.steps?.[0] && !s.steps[0].go && !s.steps[0].ws && !s.steps[0].pre?.some(a => a.go)) e.push('steps[0]: must open a page (go) or a ws view');
  return e;
}

// Playwright errors carry request headers (cookies, JWTs, wstokens): keep the first line, redacted.
export function redact(e) {
  return String(e?.message || e).split('\n')[0]
    .replace(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g, '<redacted>').replace(/((?:ws)?token|password|sesskey)=[^&\s;]+/gi, '$1=<redacted>');
}

export function toUnit(s) {
  return { voice: { engine: 'edge', voice: s.voice || 'es', speed: 1.0 },
    clips: s.steps.map((st, i) => ({ id: `s${i + 1}`, sentences: [st.say] })) };
}

// A después list without steps reuses the antes steps named in <outdir>/guion-antes.md ("Shot list: <path>"):
// same screens and actions, new lines in `say` (one per antes step, null drops it), an optional `recall` line first.
export function resolveDespues(s, outdir) {
  if (s.phase !== 'despues' || s.steps) return s;
  const guion = path.join(outdir, 'guion-antes.md');
  if (!fs.existsSync(guion)) throw new Error(`despues without steps needs ${guion} (run the antes video first) or its own steps`);
  const m = fs.readFileSync(guion, 'utf8').match(/^Shot list: `?(.+?)`?$/m);
  if (!m) throw new Error(`${guion} names no "Shot list:"`);
  const src = m[1].replace(/^~(?=\/)/, os.homedir());
  const antes = JSON.parse(fs.readFileSync(src, 'utf8'));
  if (!Array.isArray(s.say) || s.say.length !== antes.steps.length) {
    throw new Error(`say: list of ${antes.steps.length} lines (one per antes step, null to drop the step)`);
  }
  const over = s.overrides || {};
  // A dropped step's actions (go, click, fill, wait) still run, silently, before the next kept step.
  let pre = [];
  const steps = antes.steps.map((st, i) => {
    if (s.say[i] == null) {
      if (!st.ws) pre.push(Object.fromEntries(Object.entries(st).filter(([k]) => ['site', 'go', 'click', 'fill', 'wait'].includes(k))));
      return null;
    }
    const { overlay, say, ...keep } = st;
    const out = { ...keep, ...(over[i] || {}), say: s.say[i], ...(pre.length ? { pre } : {}) };
    pre = [];
    return out;
  }).filter(Boolean);
  if (s.recall) steps[0].say = `${s.recall} ${steps[0].say}`;
  return { ticket: s.ticket, phase: 'despues', voice: s.voice || antes.voice,
    front_user: s.front_user || antes.front_user, back_user: s.back_user || antes.back_user, recall: s.recall, steps };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [cmd, f, outdir] = process.argv.slice(2);
  let s = JSON.parse(fs.readFileSync(f, 'utf8'));
  if (cmd === 'resolve') {
    try { s = resolveDespues(s, outdir); } catch (err) { console.error(err.message); process.exit(1); }
  }
  const e = s.phase === 'despues' && !s.steps ? [] : validate(s);
  if (e.length) { console.error(e.join('\n')); process.exit(1); }
  if (cmd === 'unit') console.log(JSON.stringify(toUnit(s), null, 1));
  else if (cmd === 'resolve') console.log(JSON.stringify(s, null, 1));
  else console.log(s.steps ? 'shot list ok' : 'despues list: steps come from guion-antes.md at render time');
}
