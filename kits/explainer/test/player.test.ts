import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Timeline } from '../src/motion/timeline';
import { Captions } from '../src/captions';
import { ManualClock } from '../src/core/clock';
import { NullVoice } from '../src/audio/voice';
import { DetentHand } from '../src/play/hand';
import { disc } from '../src/play/hotspots';
import { PointerRouter } from '../src/play/pointer';
import { MarkerRouter } from '../src/play/markers';
import { KEYS, pressKey } from '../src/play/keys';
import { LearnerStore, MemoryStorage, type Storage } from '../src/core/store';
import { lintUnit } from '../src/content/lint';
import { stateKey } from '../src/loop';
import { Director } from '../src/unit/director';
import { WatchBeat } from '../src/unit/watch';
import { GuidedPlay, handAt, settled, all } from '../src/unit/guided';
import { EndBeat } from '../src/unit/end';
import { chapterAt, chapterList } from '../src/unit/chapters';
import { sectionOf, sectionView, type SectionSpec } from '../src/unit/sections';
import { restore, track } from '../src/unit/resume';
import { Player } from '../src/player';
import type { Shell } from '../src/shell/shell';
import type { CueSheet, UnitBundle, UnitSpec } from '../src/content/types';
import type { Explained, NamedTerm, ShellPort, UnitDef, View, Working } from '../src/unit/ports';

const line = (id: string) => ({ src: id, duration: 0.01, marks: {}, words: [] });
const CUES: CueSheet = {
  bias: 0,
  clips: {
    w1: { src: 'w1', duration: 2, marks: { dial: 0.5, gauge: 1.5 }, words: [{ w: 'The', s: 0, e: 0.2 }, { w: 'dial.', s: 0.5, e: 0.9 }, { w: 'A', s: 1.2, e: 1.3 }, { w: 'gauge.', s: 1.5, e: 1.9 }] },
    w2: { src: 'w2', duration: 1, marks: { end: 0.8 }, words: [{ w: 'Done.', s: 0.1, e: 0.5 }] },
    ask1: line('ask1'), ok1: line('ok1'), ask2: line('ask2'), ok2: line('ok2'), hint2: line('hint2'), bye: line('bye'),
  },
};
const SPEC: UnitSpec = {
  introduces: [
    { id: 'weight', word: 'weight', gloss: 'how much an input counts', namedCue: 'w1.dial', part: 'dial' },
    { id: 'gauge', word: 'gauge', gloss: 'shows the output', namedCue: 'w1.gauge', part: 'gauge' },
    { id: 'click', word: 'click', gloss: 'one turn to the next mark', namedCue: 'ok1' },
  ],
  parts: [{ id: 'dial', n: 1, name: 'Dial', term: 'weight' }, { id: 'gauge', n: 2, name: 'Gauge', term: 'gauge' }],
  clips: [{ id: 'w1', sentences: ['The {dial}dial.', 'A {gauge}gauge.'] }, { id: 'w2', sentences: ['Done.'] },
    { id: 'ask1', beat: 'drive', sentences: ['Turn the first dial.'] }, { id: 'ok1', beat: 'drive', sentences: ['One click.'] },
    { id: 'ask2', beat: 'drive', sentences: ['Turn the second dial.'] }],
};

interface S { v: number; v2: number; lbl: number; glow: number }
const geom = (cx: number) => ({ cx, cy: 0, r: 10, min: -3, max: 3, step: 0.5, angle: (v: number) => -v, value: (a: number) => -a });
const proj = { toWorld: (x: number, y: number): [number, number] => [x, y], toScreen: (x: number, y: number): [number, number] => [x, y] };
const run = (d: Director<S>, secs: number, dt = 1 / 60): void => { for (let t = 0; t < secs; t += dt) d.tick(dt); };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/** Turn a hand to detent `v` from wherever the last beat left it. */
const to = (h: DetentHand, v: number): void => h.turn((v - h.value()) / 0.5);

function rig(storage?: Storage, sections?: SectionSpec[]) {
  const rec = { ctas: [] as (string | null)[], go: null as (() => void) | null, ended: false, instr: [] as (string | null)[], progress: null as [number | null, number, number] | null,
    card: null as { choices: { label: string; go(): void }[] } | null, working: [] as Working[], terms: [] as NamedTerm[], explained: null as Explained | null, lit: null as string | null };
  const port: ShellPort = {
    cta: (l, g) => { rec.ctas.push(l); rec.go = g ?? null; }, caption: () => {}, playing: () => {}, pausable: () => {}, status: () => {}, end: (_r, c) => { rec.ended = true; rec.card = c ?? null; },
    instruction: (t) => rec.instr.push(t), progress: (t, dur, f) => { rec.progress = [t, dur, f]; }, working: (b) => { rec.working = b; },
    terms: (l) => { rec.terms = l; }, explain: (c) => { rec.explained = c; },
  };
  const modes: string[] = [];
  const view: View<S> = { el: {} as HTMLElement, canvas: { style: {} } as HTMLElement, draw: () => {}, resize: () => {}, labels: (m) => { modes.push(m); }, light: (p) => { rec.lit = p; }, ...proj };
  const unit: UnitDef<S> = {
    initial: () => ({ v: 0, v2: 0, lbl: 0, glow: 0 }),
    watch: { order: ['w1', 'w2'], lead: 1, gap: 0.5, build: (s, cue) => new Timeline()
      .to(s, { lbl: 1, duration: 0.2, ease: 'none' }, cue.at('w1', 'dial')).to(s, { v: 1.5, duration: 2, ease: 'none' }, cue.at('w1', 'gauge'))
      .mark('end', cue.at('w2', 'end')).end(cue.end('w2') + 1) },
    live: { now: (id, s) => (id === 'weight' ? `dial at ${s.v}` : null),
      working: (s) => (s.lbl > 0.5 ? [{ title: 'Note', rows: [`dial ${s.v}`] }] : []) },
  };
  const bundle: UnitBundle = { spec: SPEC, cues: CUES, base: '' };
  const clock = new ManualClock(0, false), voice = new NullVoice();
  const h0 = new DetentHand(geom(0), proj, 2.4), h1 = new DetentHand(geom(40), proj, 2.4);
  const d = new Director<S>({ unit, bundle, view, voice, clock, shell: port, controls: [{ hand: h0, key: 'v', glow: 'glow' }, { hand: h1, key: 'v2' }],
    hotspots: [disc('dial', 'weight', 0, 0, 10), disc('gauge', 'gauge', 100, 0, 20)] });
  d.beats.add('watch', new WatchBeat(d, { next: 'drive' }));
  d.beats.add('drive', new GuidedPlay(d, 'drive', [
    { hand: 0, ask: 'ask1', ok: 'ok1', done: all(handAt(0, 1), settled) },
    { hand: 1, ask: 'ask2', ok: 'ok2', done: all(handAt(1, 3), settled), hint: 'hint2' },
  ], { next: 'end' }));
  d.beats.add('end', new EndBeat(d, 'The end', { say: 'bye' }));
  const store = new LearnerStore(storage ?? new MemoryStorage());
  const shell = { captions() {}, muted() {}, section() {}, pops: { close: () => false }, closeEnd: () => false } as unknown as Shell;
  const markers = new MarkerRouter([{ n: 1, part: 'dial', term: 'weight', r: 8, at: () => [30, 30] }, { n: 2, part: 'gauge', term: 'gauge', r: 8, at: () => null }]);
  const player = new Player({ d, shell, view, voice, store, markers, sections });
  return { d, rec, clock, voice, h0, h1, store, player, view, modes };
}
const fresh = (t: number): string => { const { d, clock } = rig(); d.go('watch'); clock.stop(); clock.set(t); d.tick(0.016); return stateKey(d.s); };

test('P1 seek: lands on a span start with the state of a fresh ?t= frame, even after a dial was turned; voice starts there; clamped to what was heard', () => {
  const { d, clock, voice } = rig();
  d.go('watch'); d.reach(d.tl.duration());
  clock.set(1.4); d.tick(0.016);
  d.beats.touched(); d.hands[0].turn(4); run(d, 1);
  assert.equal(d.hands[0].value(), 2);
  d.beats.cur!.seek!(3.9, true);
  assert.equal(clock.now(), 3.5);
  assert.equal(stateKey(d.s), fresh(3.5));
  assert.equal(voice.log.at(-1)!.from, clock.now());
  const e = d.events.log.filter((x) => x.type === 'seek').at(-1);
  assert.deepEqual(e, { type: 'seek', from: 1.4, to: 3.5 });
  const b = rig(); b.d.go('watch'); b.clock.set(2.5); b.d.tick(0.016);
  b.d.beats.cur!.seek!(4.4);
  assert.equal(b.clock.now(), 2.2, 'forward seeks stop at the sentence holding the furthest second heard');
});

test('P1/P3/P17 spans cover the axis; chapter ticks sit inside their chapters; progress reports t, length, furthest', () => {
  const { d, clock, rec } = rig();
  assert.deepEqual(d.spans.map((x) => [x.s, x.e]), [[0, 2.2], [2.2, 3.5], [3.5, d.tl.duration()]]);
  const list = d.chapters();
  assert.deepEqual(list.map((c) => [c.numeral, c.t]), [['I', 0], ['II', 3.5]]);
  for (const c of list) assert.equal(chapterAt(list, c.t!), c);
  d.go('watch'); clock.set(2.4); d.tick(0.016);
  assert.deepEqual(rec.progress, [2.4, d.tl.duration(), 2.4]);
});

test('P2 back: more than 1 s into a sentence restarts it, within 1 s goes to the one before; forward stops at what was heard', () => {
  const { d, clock } = rig();
  d.go('watch'); clock.set(3.9); d.tick(0.016);
  d.beats.cur!.back!(); assert.equal(clock.now(), 2.2);
  clock.set(3.4); d.beats.cur!.back!(); assert.equal(clock.now(), 2.2, '1.2 s in: restart');
  d.beats.cur!.back!(); assert.equal(clock.now(), 0, 'at the start: the one before');
  d.beats.cur!.fwd!(); assert.equal(clock.now(), 2.2);
  d.beats.cur!.fwd!(); assert.equal(clock.now(), 3.5);
  d.beats.cur!.fwd!(); assert.equal(clock.now(), 3.5, 'nothing heard past it');
});

test('P8/P16 keys: every key on the sheet is handled; arrows step sentences in the watch until a dial is picked', () => {
  const { d, clock, h0 } = rig();
  const calls: string[] = [];
  const a = Object.fromEntries(['toggle', 'back', 'fwd', 'home', 'help', 'mute', 'cc', 'transcript', 'hint', 'commit', 'zoom'].map((k) => [k, () => { calls.push(k); }]));
  const act = { ...a, close: () => { calls.push('close'); return true; } } as never;
  const name: Record<string, string> = { Space: ' ', '←': 'ArrowLeft', '→': 'ArrowRight', '↑': 'ArrowUp', '↓': 'ArrowDown', Esc: 'Escape', '−': '-' };
  d.go('watch'); clock.set(3.9); d.tick(0.016);
  for (const row of KEYS) for (const k of row.keys) assert.ok(pressKey(d, act, name[k] ?? k), `key ${k}`);
  assert.ok(!KEYS.some((r) => r.keys.includes('G')) && !pressKey(d, act, 'g'), 'no Parts key');
  assert.ok(calls.includes('back') && calls.includes('fwd') && calls.includes('help'));
  d.picked = false; d.activeHand = 0; calls.length = 0;
  pressKey(d, act, 'ArrowLeft'); assert.deepEqual(calls, ['back']);
  pressKey(d, act, 'ArrowUp'); assert.equal(d.picked, true);
  const was = h0.value();
  pressKey(d, act, 'ArrowRight'); run(d, 1);
  assert.equal(h0.value(), was + 0.5, 'a picked dial turns');
  assert.equal(clock.playing(), false, 'turning a dial pauses the watch');
});

test('P4 re-watch keeps the dials: drive step 2 → watch → back restores both dials, says the ask once, one step start', async () => {
  const { d, voice, h0, h1, rec, player } = rig();
  d.go('drive'); run(d, 0.1);
  h0.turn(2); run(d, 1.5); await sleep(40); run(d, 0.1);
  h1.turn(1); run(d, 1.2);
  assert.deepEqual([h0.value(), h1.value()], [1, 0.5]);
  player.seek(1.2);
  assert.equal(d.beats.name, 'watch');
  run(d, 0.05);
  assert.equal(rec.ctas.at(-1), 'Back to your turn · step 2');
  const asks = voice.log.filter((x) => x.id === 'ask2').length;
  rec.go!();
  assert.equal(d.beats.name, 'drive');
  run(d, 0.1);
  assert.deepEqual([h0.value(), h1.value(), d.s.v, d.s.v2], [1, 0.5, 1, 0.5]);
  assert.equal(voice.log.filter((x) => x.id === 'ask2').length, asks + 1);
  assert.equal(d.events.log.filter((e) => e.type === 'step' && e.index === 1 && e.phase === 'start').length, 1);
  assert.equal(h1.enabled, true);
});

test('P5a a short press on a dial is a tap (callout, value unchanged); past the slop it grabs; a long gloss fails lint', () => {
  const on: Record<string, (e: unknown) => void> = {};
  const el = { style: {} as Record<string, string>, addEventListener: (k: string, f: (e: unknown) => void) => { on[k] = f; }, getBoundingClientRect: () => ({ left: 0, top: 0 }), setPointerCapture() {} } as unknown as HTMLElement;
  const h = new DetentHand(geom(0), proj, 2.4); h.enabled = true; h.place(0);
  const r = new PointerRouter(el, proj, [h]);
  let taps = 0, grabs = 0; r.onTap = () => { taps++; }; r.onGrab = () => { grabs++; };
  const ev = (x: number, y: number) => ({ clientX: x, clientY: y, pointerType: 'mouse', pointerId: 1 });
  on.pointerdown(ev(2, 8)); on.pointermove(ev(5, 8)); on.pointerup(ev(5, 8));
  assert.deepEqual([taps, grabs, h.grabbed, h.value()], [1, 0, false, 0]);
  on.pointerdown(ev(2, 8)); on.pointermove(ev(22, 8)); on.pointerup(ev(22, 8));
  assert.deepEqual([taps, grabs], [1, 1]);

  const { d, clock, player } = rig();
  d.go('watch'); clock.set(3.9); d.tick(0.016);
  const v = d.s.v;
  player.tap(2, 3, 2, 3);
  assert.equal(d.opened, null, 'a tap on the dial body opens nothing');
  player.tap(30, 30, 30, 30);
  assert.equal(d.opened, 'weight', 'a tap on its number opens its callout');
  assert.equal(d.s.v, v);
  assert.equal(clock.playing(), false);
  player.tap(2, 3, 2, 3);
  assert.equal(d.opened, 'weight', 'a tap on a part body leaves the open callout open');
  player.tap(200, 0, 200, 0);
  assert.equal(d.opened, null, 'a tap on bare paper closes it');
  player.tap(30, 30, 30, 30); player.tap(30, 30, 30, 30);
  assert.equal(d.opened, null, 'a second tap on the same number closes it');
  const long = { ...SPEC, introduces: [{ id: 'x', word: 'x', gloss: 'one two three four five six seven eight nine ten eleven twelve thirteen', namedCue: 'w1.dial' }] };
  assert.match(lintUnit(long).join('\n'), /x: gloss has 13 words/);
  assert.deepEqual(lintUnit(SPEC, CUES), []);
});

test('P5c hover: only a number marker answers (help cursor + its part outlined, as before); a part body or paper draws nothing; a number tap opens, Esc closes and resumes', () => {
  const { d, clock, player, rec, view } = rig();
  d.go('watch'); d.reach(d.tl.duration()); clock.set(2.9); d.tick(0.016);
  player.hover(0, 0); d.tick(0.016);
  assert.deepEqual([rec.lit, view.canvas.style.cursor, rec.explained, clock.playing()], [null, '', null, true], 'the dial body: nothing');
  player.hover(28, 33); d.tick(0.016);
  assert.deepEqual([rec.lit, view.canvas.style.cursor, rec.explained, clock.playing()], ['dial', 'help', null, true], 'its number: help cursor and outline');
  player.hover(30 + 10, 30);
  assert.equal(rec.lit, 'dial', 'a mouse: the drawn circle + 2 px');
  player.hover(30 + 14, 30);
  assert.equal(rec.lit, null, 'a mouse 6 px outside the circle is not on it');
  player.hover(200, 0);
  assert.deepEqual([rec.lit, view.canvas.style.cursor], [null, ''], 'paper: nothing');
  player.hover(28, 33); player.hover(null, null);
  assert.deepEqual([rec.lit, view.canvas.style.cursor], [null, '']);
  player.tap(30, 30, 30, 30);
  assert.deepEqual([rec.explained?.title, clock.playing()], ['weight', false]);
  assert.ok(player.close());
  assert.deepEqual([rec.explained, d.opened, clock.now(), clock.playing()], [null, null, 2.2, true]);
  assert.equal(player.close(), false, 'nothing left to close');
});

test('P5d label mode: the watch is named before its end mark and numbered after it, a re-watch names again, other beats are numbered; the view hears each change once', () => {
  const { d, clock, modes } = rig();
  d.go('watch'); clock.set(1); d.tick(0.016); d.tick(0.016);
  assert.equal(d.labels, 'named');
  d.reach(d.tl.duration()); clock.set(4.6); d.tick(0.016);
  assert.equal(d.labels, 'numbered');
  clock.set(1); d.tick(0.016);
  assert.equal(d.labels, 'named');
  d.go('drive'); d.tick(0.016); d.tick(0.016);
  assert.equal(d.labels, 'numbered');
  assert.deepEqual(modes, ['named', 'numbered', 'named', 'numbered']);
});

test('P5b a callout holds the clock and resumes at the sentence start; a term not named yet has no gloss; HEAR IT in the drive keeps step and dials', async () => {
  const { d, clock, rec, voice, h0 } = rig();
  d.go('watch'); clock.set(1.3); d.tick(0.016);
  d.explain('gauge');
  assert.equal(rec.explained!.available, false);
  assert.equal(rec.explained!.now, null);
  assert.equal(rec.explained!.chapter!.numeral, 'I');
  d.explain(null);
  clock.set(3.4); d.tick(0.016);
  d.explain('weight');
  assert.equal(clock.playing(), false);
  assert.equal(rec.explained!.now, `dial at ${d.s.v}`);
  d.explain(null);
  assert.deepEqual([clock.now(), clock.playing()], [2.2, true]);

  d.go('drive'); run(d, 0.1);
  h0.turn(1); run(d, 1);
  const before = [h0.value(), d.s.v];
  d.explain('weight'); d.hear('weight');
  const seg = voice.log.at(-1)!;
  assert.deepEqual([seg.id, seg.at], ['w1', -2]);
  assert.equal(d.beats.name, 'drive');
  assert.deepEqual([h0.value(), d.s.v], before);
  assert.equal(h0.enabled, true);
});

test('P6/P7/P13 caption words become term links; named terms carry their second; the working gets its text; a play line names its term', async () => {
  const { d, clock, rec } = rig();
  assert.deepEqual(Captions.tokens('Two weights, one gauge.', SPEC.introduces!), ['Two ', { term: 'weight', text: 'weights' }, ', one ', { term: 'gauge', text: 'gauge' }, '.']);
  assert.deepEqual(Captions.glued(Captions.tokens('Two weights, one gauge.', SPEC.introduces!)), ['Two ', { term: 'weight', text: 'weights', tail: ',' }, ' one ', { term: 'gauge', text: 'gauge', tail: '.' }]);
  d.go('watch'); clock.set(3); d.tick(0.016);
  assert.deepEqual(rec.terms.map((t) => [t.id, t.at]), [['weight', 1.5], ['gauge', 2.5]]);
  clock.stop(); d.tick(0.016);
  assert.ok(d.s.v > 0 && d.s.v < 1.5, 'paused mid-turn');
  assert.deepEqual(rec.working, [{ title: 'Note', rows: ['dial 1.5'] }], 'paused, the working reads where the motion is heading');
  clock.start(3.2); d.tick(0.016);
  assert.deepEqual(rec.working, [{ title: 'Note', rows: [`dial ${d.s.v}`] }], 'playing, it follows the motion');
  d.go('drive'); run(d, 0.1);
  to(d.hands[0], 1); run(d, 1.5); await sleep(40);
  assert.ok(rec.terms.some((t) => t.id === 'click' && t.at === Infinity));
});

test('P11 the instruction stays until done; a hint only on request; P12 the end says its closing line', async () => {
  const { d, rec, voice, h0, player } = rig();
  d.go('drive'); run(d, 0.1);
  assert.equal(rec.instr.at(-1), 'Turn the first dial.');
  assert.equal(player.hint(), false, 'step 1 has no hint');
  h0.turn(2); run(d, 1.5); await sleep(40); run(d, 0.1);
  assert.equal(rec.instr.at(-1), 'Turn the second dial.');
  run(d, 30);
  assert.ok(!voice.log.some((x) => x.id === 'hint2'), 'no hint on a timer');
  assert.equal(player.hint(), true);
  assert.equal(voice.log.at(-1)!.id, 'hint2');
  d.go('end');
  assert.equal(rec.instr.at(-1), null);
  assert.equal(voice.log.at(-1)!.id, 'bye');
  assert.equal(rec.ended, true);
  const was = d.s.v;
  h0.turn(1); run(d, 1.5);
  assert.ok(Math.abs(d.s.v - (was + 0.5)) < 1e-6, 'the finished plate stays live: its dials turn');
});

test('P9 resume: a reload restores the beat, the second and the dials; a throwing store falls back to memory', async () => {
  const mem = new MemoryStorage();
  const a = rig(mem);
  const tr = track(a.d, a.store, { unit: 'U9', states: { drive: 'driven' } });
  a.d.go('watch'); a.clock.set(3.7); a.d.tick(0.016);
  let b = rig(new MemoryStorage(mem.read()));
  const p = restore(b.d, b.store, { unit: 'U9' })!;
  assert.deepEqual(p.enter, { at: 3.5 });
  b.d.go(p.beat, p.enter);
  assert.equal(b.clock.now(), 3.5);
  assert.ok(b.d.available('weight'));

  a.d.go('drive'); run(a.d, 0.1);
  to(a.h0, 1); run(a.d, 1.5); await sleep(40); run(a.d, 0.1);
  to(a.h1, 0.5); run(a.d, 1.2);
  tr.flush();
  b = rig(new MemoryStorage(mem.read()));
  const q = restore(b.d, b.store, { unit: 'U9' })!;
  assert.equal(q.beat, 'drive');
  assert.match(q.label, /step 2/);
  b.d.go(q.beat, q.enter); run(b.d, 0.2);
  assert.deepEqual([b.h0.value(), b.h1.value()], [1, 0.5]);
  assert.ok(b.d.available('click'));
  assert.equal(JSON.parse(mem.read()!).resume.unit, 'U9');
  a.d.go('end');
  const e = rig(new MemoryStorage(mem.read()));
  const r = restore(e.d, e.store, { unit: 'U9' })!;
  assert.match(r.label, /^You finished this plate\. Continue opens it/);
  e.d.go(r.beat, r.enter);
  assert.equal(e.rec.ended, false, 'a return visit opens the finished plate, not the same card again');
  assert.ok(e.h0.enabled);

  const bad: Storage = { read: () => { throw new Error('blocked'); }, write: () => { throw new Error('blocked'); } };
  const s = new LearnerStore(bad);
  s.save('U9', { beat: 'watch', t: 2 });
  assert.equal(s.unit('U9').t, 2);
  const w: Storage = { read: () => null, write: () => { throw new Error('quota'); } };
  const s2 = new LearnerStore(w); s2.save('U9', { beat: 'end', state: 'seen' }); s2.save('U9', { beat: 'end', state: 'driven' }); s2.save('U9', { state: 'seen' });
  assert.equal(s2.unit('U9').state, 'driven', 'state only moves forward');
});

test('P14 voice and effects volumes and mute go to the buses and the preferences', () => {
  const { voice, store, player } = rig();
  player.volume('sfx', 0.4);
  assert.equal(voice.volumes.sfx, 0.4);
  player.mute();
  assert.deepEqual(voice.volumes, { voice: 0, sfx: 0 });
  player.mute();
  assert.deepEqual(voice.volumes, { voice: 1, sfx: 0.4 });
  assert.deepEqual(store.prefs(), { sfx: 0.4, muted: false });
});

test('P18 badge hit areas: a mouse must be on the drawn circle + 2 px; touch reaches 22 px, capped at half the distance to the nearest drawn badge', () => {
  const at = (x: number) => (): [number, number] => [x, 0];
  const m = new MarkerRouter([{ n: 1, part: 'a', term: 'a', r: 14, at: at(0) }, { n: 2, part: 'b', term: 'b', r: 14, at: at(36) }, { n: 3, part: 'c', term: 'c', r: 14, at: () => null }]);
  assert.equal(m.hit(15, 0, proj, true)?.n, 1, '1 px outside, a mouse');
  assert.equal(m.hit(0, 20, proj, true), null, '6 px outside is not a hit');
  assert.equal(m.hit(-18, 0, proj, false)?.n, 1, 'touch reaches half the gap to the neighbour');
  assert.equal(m.hit(-19, 0, proj, false), null, 'and no farther, even on the free side');
  const lone = new MarkerRouter([{ n: 1, part: 'a', term: 'a', r: 14, at: at(0) }]);
  assert.equal(lone.hit(0, 22, proj, false)?.n, 1, 'a lone badge: 22 px');
  assert.equal(lone.hit(0, 23, proj, false), null);
  assert.equal(m.hit(17, 0, proj, false)?.n, 1);
  assert.equal(m.hit(19, 0, proj, false)?.n, 2, 'past the midpoint the neighbour answers: no shared area');
  const far = new MarkerRouter([{ n: 1, part: 'a', term: 'a', r: 6, at: at(0) }, { n: 2, part: 'b', term: 'b', r: 6, at: at(30) }]);
  assert.equal(far.hit(-16, 0, proj, false), null, 'capped at half the gap (15 px) even with room behind');
});

test('P19 the end card as a chooser: its choices go to their beats; a fork does not complete the unit; a return visit opens it closed', () => {
  const { d, rec } = rig();
  d.beats.add('fork', new EndBeat(d, 'Choose', { complete: false, choices: [{ label: 'Exercises', to: 'drive' }, { label: 'Watch again', to: 'watch' }], card: { title: 'What next?' } }));
  d.go('fork');
  assert.deepEqual(rec.card?.choices.map((c) => c.label), ['Exercises', 'Watch again']);
  assert.equal(d.events.log.filter((e) => e.type === 'complete').length, 0, 'a fork is not the end of the unit');
  rec.card!.choices[0].go();
  assert.equal(d.beats.name, 'drive');
  d.go('end');
  assert.equal(rec.card, null, 'the plain end card lists the chapters');
  assert.equal(d.events.log.filter((e) => e.type === 'complete').length, 1);
});

test('P20 saved completion: sets only grow, an unknown resume beat still restores, a done beat chapter is reachable, pressing on at the watch\'s end hears it', () => {
  const mem = new MemoryStorage(), s = new LearnerStore(mem);
  s.save('U9', { furthest: 3, terms: ['weight'], done: ['drive'], visited: ['drive'] });
  s.save('U9', { furthest: 1, terms: [], done: [], visited: ['watch'], beat: 'gone' });
  assert.deepEqual([s.unit('U9').furthest, s.unit('U9').terms, s.unit('U9').done, s.unit('U9').visited], [3, ['weight'], ['drive'], ['drive', 'watch']]);
  const b = rig(new MemoryStorage(mem.read()));
  assert.equal(restore(b.d, b.store, { unit: 'U9' }), null);
  assert.ok(b.d.completed.has('drive') && b.d.visited.has('drive') && b.d.available('weight') && b.d.furthest === 3);
  const specs = [{ id: 'a', numeral: 'I', title: 'A', clips: ['w1'] }, { id: 'b', numeral: 'II', title: 'B', beat: 'drive' }];
  const row = chapterList(specs, { w1: 0 }, 2, { furthest: 2, visited: new Set(), completed: new Set(['drive']) })[1];
  assert.deepEqual([row.reached, row.done], [true, true]);
  const { d, clock, rec } = rig();
  d.go('watch'); clock.set(d.tl.duration() - 0.9); d.reach(clock.now()); d.tick(0.016);
  assert.equal(rec.ctas.at(-1), 'Your turn');
  rec.go!();
  assert.equal(d.furthest, d.tl.duration(), 'the silent tail after the end mark counts as heard');
  assert.ok(d.chapters().every((c) => c.done));
});

test('P21 sections: a beat maps to its section (lesson beats to none); the view marks the open tab and its ways go to their beats', () => {
  const specs = [{ name: 'Practice', tabs: [{ label: 'Exercises', beat: 'p' }, { label: 'Tuning', beat: 't' }], back: { label: 'Back', to: 'end' } }];
  assert.equal(sectionOf(specs, 'drive'), null);
  assert.equal(sectionOf(specs, null), null);
  assert.equal(sectionOf(specs, 't')?.name, 'Practice');
  const went: string[] = [], v = sectionView(specs, 't', (b) => went.push(b))!;
  assert.deepEqual(v.tabs.map((t) => [t.label, t.current]), [['Exercises', false], ['Tuning', true]]);
  v.tabs[0].go(); v.back.go();
  assert.deepEqual(went, ['p', 'end']);
  assert.equal(sectionView(specs, 'drive', () => {}), null);
});

test('P22 back to the lesson returns where the learner left: the watch at its sentence, the drive at its step with its dials; an unfinished unit never completes on the way', async () => {
  const sections = [{ name: 'Practice', tabs: [{ label: 'Exercises', beat: 'practice' }], back: { label: 'Back to the lesson', to: 'end' } }];
  const { d, clock, player, h0 } = rig(undefined, sections);
  d.beats.add('practice', { label: 'Practice', enter() {}, update() {}, exit() {} });
  d.go('watch'); d.reach(3); clock.set(2.9); d.tick(0.016);
  d.go('practice'); player.lesson('practice');
  assert.deepEqual([d.beats.name, clock.now()], ['watch', 2.2], 'the same sentence');
  d.go('drive'); run(d, 0.1);
  to(h0, 1); run(d, 1.5); await sleep(40); run(d, 0.1);
  d.go('practice'); d.go('practice'); player.lesson('practice');
  run(d, 0.3);
  assert.deepEqual([d.beats.name, h0.value()], ['drive', 1], 'the drive at step 2, dial 1 kept');
  assert.equal(d.events.log.filter((e) => e.type === 'complete' && e.beat === 'unit').length, 0);
  d.go('end'); d.go('practice'); player.lesson('practice');
  assert.equal(d.beats.name, 'end', 'from the end card, back to it');
});
