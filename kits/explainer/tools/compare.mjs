// Compare two e2e.mjs runs (original vs rebuilt): node tools/compare.mjs a.json b.json
import { readFileSync } from 'node:fs';

const [A, B] = process.argv.slice(2).map((f) => JSON.parse(readFileSync(f, 'utf8')));
const r3 = (x) => +x.toFixed(3);

/** Every moment a field starts moving after being still (the visual events the timeline places on cues). */
function onsets(rows) {
  const out = {};
  for (const k of Object.keys(rows[0].s)) {
    const ev = [];
    for (let i = 1; i < rows.length; i++) {
      const moving = Math.abs(rows[i].s[k] - rows[i - 1].s[k]) > 1e-6, was = i > 1 && Math.abs(rows[i - 1].s[k] - rows[i - 2].s[k]) > 1e-6;
      if (moving && !was) ev.push(rows[i - 1].t);
    }
    out[k] = ev;
  }
  return out;
}

// 1. Frozen sweep: state = f(t) on the same 10 ms grid.
const oa = onsets(A.sweep.rows), ob = onsets(B.sweep.rows);
let events = 0, worst = 0, countMismatch = [];
for (const k of Object.keys(oa)) {
  if (oa[k].length !== (ob[k] ?? []).length) { countMismatch.push(k); continue; }
  oa[k].forEach((t, i) => { events++; worst = Math.max(worst, Math.abs(t - ob[k][i])); });
}
let maxDiff = 0;
A.sweep.rows.forEach((r, i) => { for (const k of Object.keys(r.s)) maxDiff = Math.max(maxDiff, Math.abs(r.s[k] - (B.sweep.rows[i]?.s[k] ?? NaN))); });
const offDiff = Math.max(...Object.keys(A.sweep.offsets).map((k) => Math.abs(A.sweep.offsets[k] - B.sweep.offsets[k])));

// 2. Live audio: where each watch clip actually lands on the clock axis vs where the timeline expects it.
function audio(run) {
  const play = run.live.rows.filter((r) => r.beat === 'watch' && r.clock > 0.5 && r.ctxT > 0);
  const ks = play.map((r) => r.ctxT - r.lat - r.clock).sort((a, b) => a - b), k = ks[Math.floor(ks.length / 2)];
  const offs = run.sweep.offsets, ids = Object.keys(offs);
  const watchSrc = run.live.src.slice(0, ids.length);
  const lats = play.map((r) => r.lat).sort((a, b) => a - b), lat = lats[Math.floor(lats.length / 2)];
  return ids.map((id, i) => ({ id, err: r3(watchSrc[i].when - k - offs[id]), resid: r3(watchSrc[i].when - k - offs[id] - lat - 0.02) }));
}
const aa = audio(A), ab = audio(B);

// 3. Live cue onsets: first frame each engraved label or callout starts, in clock seconds.
function liveOnsets(run) {
  const rows = run.live.rows.filter((r) => r.beat === 'watch'), out = {};
  for (const k of Object.keys(rows[0].s).filter((k) => /^(lbl|c[A-Z]|markOn|net$|chamberOn|flowOn)/.test(k))) {
    const hit = rows.find((r) => r.s[k] > 1e-3);
    if (hit) out[k] = r3(hit.clock);
  }
  return out;
}
const la = liveOnsets(A), lb = liveOnsets(B);
const liveWorst = Math.max(...Object.keys(la).map((k) => Math.abs(la[k] - lb[k])));

// 4. Perf while playing the watch.
function perf(run) {
  const dts = run.live.rows.filter((r) => r.beat === 'watch').slice(3).map((r) => r.dt);
  const fw = [...run.live.fw].sort((a, b) => a - b);
  return { rafMax: r3(Math.max(...dts)), over20: dts.filter((x) => x > 20).length, drawP50: fw[Math.floor(fw.length / 2)], drawMax: fw.at(-1), idleWatch: run.idleWatch, idleEnd: run.idleEnd, sw: run.live.sw };
}

console.log(JSON.stringify({
  sweep: { dur: [A.sweep.dur, B.sweep.dur], rows: [A.sweep.rows.length, B.sweep.rows.length], offsetsMaxDiff: offDiff, stateMaxDiff: maxDiff, onsetEvents: events, onsetWorstMs: Math.round(worst * 1000), countMismatch },
  audioErrMs: { a: aa.map((x) => `${x.id}:${Math.round(x.err * 1000)}`), b: ab.map((x) => `${x.id}:${Math.round(x.err * 1000)}`), residA: aa.map((x) => Math.round(x.resid * 1000)), residB: ab.map((x) => Math.round(x.resid * 1000)) },
  liveOnsets: { n: Object.keys(la).length, worstMs: Math.round(liveWorst * 1000), a: la, b: lb },
  e2e: { a: { cta1: A.cta1, cta2: A.cta2, end: A.endBeat, marks: A.marks, errors: A.errors.length }, b: { cta1: B.cta1, cta2: B.cta2, end: B.endBeat, marks: B.marks, errors: B.errors.length } },
  perf: { a: perf(A), b: perf(B) },
}, null, 1));
