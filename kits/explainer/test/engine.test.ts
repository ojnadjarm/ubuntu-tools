import { test } from 'node:test';
import assert from 'node:assert/strict';
import { layoutClips, CueBinder } from '../src/motion/cues';
import { Timeline } from '../src/motion/timeline';
import { Captions } from '../src/captions';
import { stateKey, stateKeyer } from '../src/loop';
import { ManualClock } from '../src/core/clock';
import { NullVoice } from '../src/audio/voice';
import { DetentHand } from '../src/play/hand';
import { Director } from '../src/unit/director';
import { WatchBeat } from '../src/unit/watch';
import { GuidedPlay, all, handAt, settled } from '../src/unit/guided';
import { Exercise } from '../src/unit/exercise';
import { dialHand, cutawayEasing } from '../adapters/cutaway/view';
import type { CueSheet, UnitBundle } from '../src/content/types';
import type { ShellPort, UnitDef, View } from '../src/unit/ports';

const CUES: CueSheet = {
  bias: 0,
  clips: {
    w1: { src: 'w1', duration: 2, marks: { dial: 0.5, gauge: 1.5 }, words: [{ w: 'The', s: 0, e: 0.2 }, { w: 'dial.', s: 0.5, e: 0.9 }, { w: 'A', s: 1.2, e: 1.3 }, { w: 'gauge.', s: 1.5, e: 1.9 }] },
    w2: { src: 'w2', duration: 1, marks: { end: 0.8 }, words: [{ w: 'Done.', s: 0.1, e: 0.5 }] },
    ask: { src: 'ask', duration: 0.01, marks: {}, words: [] }, ok: { src: 'ok', duration: 0.01, marks: {}, words: [] },
    hint: { src: 'hint', duration: 0.01, marks: {}, words: [] }, pass: { src: 'pass', duration: 0.01, marks: {}, words: [] },
    fail: { src: 'fail', duration: 0.01, marks: {}, words: [] },
  },
};
const SPEC = { clips: [{ id: 'w1', sentences: ['The {dial}dial.', 'A {gauge}gauge.'] }, { id: 'w2', sentences: ['Done.'] }] };

interface S { v: number; lbl: number; glow: number }
const geom = { cx: 0, cy: 0, r: 10, min: -3, max: 3, step: 0.5, angle: (v: number) => -v, value: (a: number) => -a };
const proj = { toWorld: (x: number, y: number): [number, number] => [x, y], toScreen: (x: number, y: number): [number, number] => [x, y] };

function rig() {
  const shell = { ctas: [] as (string | null)[], go: null as (() => void) | null, ended: false };
  const port: ShellPort = { cta: (l, g) => { shell.ctas.push(l); shell.go = g ?? null; }, caption: () => {}, playing: () => {}, pausable: () => {}, status: () => {}, end: () => { shell.ended = true; } };
  let draws = 0;
  const view: View<S> = { el: {} as HTMLElement, canvas: {} as HTMLElement, draw: () => { draws++; }, resize: () => {}, ...proj };
  const unit: UnitDef<S> = {
    initial: () => ({ v: 0, lbl: 0, glow: 0 }),
    watch: { order: ['w1', 'w2'], lead: 1, gap: 0.5, build: (s, cue) => new Timeline().to(s, { lbl: 1, duration: 0.2, ease: 'none' }, cue.at('w1', 'dial')).mark('end', cue.at('w2', 'end')).end(cue.end('w2') + 1) } };
  const bundle: UnitBundle = { spec: SPEC, cues: CUES, base: '' };
  const clock = new ManualClock(0, false), voice = new NullVoice();
  const hand = new DetentHand(geom, proj, 2.4);
  const d = new Director<S>({ unit, bundle, view, voice, clock, shell: port, controls: [{ hand, key: 'v', glow: 'glow' }] });
  return { d, shell, clock, voice, hand, draws: () => draws };
}
const run = (d: Director<S>, secs: number, dt = 1 / 60): void => { for (let t = 0; t < secs; t += dt) d.tick(dt); };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

test('clips are laid on one axis and cues bind to it', () => {
  const { offsets, end } = layoutClips(CUES, ['w1', 'w2'], 1, 0.5);
  assert.deepEqual(offsets, { w1: 1, w2: 3.5 });
  assert.equal(end, 5);
  const cue = new CueBinder(CUES, offsets);
  assert.equal(cue.at('w1', 'gauge'), 2.5);
  assert.equal(cue.word('w1', 'gauge'), 2.5);
  assert.equal(cue.end('w2'), 4.5);
  assert.throws(() => cue.at('w1', 'nope'), /missing cue w1.nope/);
});

test('captions follow word timings on the watch axis', () => {
  const c = new Captions(CUES, SPEC);
  const offsets = { w1: 1, w2: 3.5 };
  assert.equal(c.watch(1.1, offsets), 'The dial.');
  assert.equal(c.watch(2.5, offsets), 'A gauge.');
  assert.equal(c.watch(3.7, offsets), 'Done.');
});

test('the per-frame state key equals stateKey through moves, sub-rounding moves, NaN, -0, added and removed keys', () => {
  const key = stateKeyer(), s: Record<string, unknown> = { a: 0, b: 1.5, c: 'x' };
  const steps: ((o: Record<string, unknown>) => void)[] = [() => {}, (o) => { o.a = 0.00001; }, (o) => { o.a = 0.0001; }, (o) => { o.b = NaN; }, (o) => { o.b = -0; },
    (o) => { o.d = 2; }, (o) => { delete o.a; }, (o) => { o.c = { _gsap: 1 }; }, (o) => { for (const k of Object.keys(o)) delete o[k]; }, (o) => { o.z = 'only'; }, (o) => { o.z = 3; }];
  for (const f of steps) { f(s); assert.equal(key(s), stateKey(s)); assert.equal(key(s), stateKey(s)); }
});

test('a detent hand turns two clicks and settles on the value', () => {
  const h = new DetentHand(geom, proj, 2.4);
  const seen: number[] = [];
  h.onDetent = (v) => seen.push(v);
  h.place(0); h.turn(2);
  for (let i = 0; i < 90; i++) h.update(1 / 60);
  assert.equal(h.value(), 1);
  assert.ok(h.settled());
  assert.deepEqual(seen, [0.5, 1]);
  assert.equal(h.snap(0.74), 0.5);
});

test('key presses faster than the spring add up: four turn(+1) in one frame land four steps on', () => {
  const h = new DetentHand(geom, proj, 2.4);
  h.place(0);
  for (let i = 0; i < 4; i++) h.turn(1);
  h.update(1 / 60); h.turn(-1); h.turn(1);
  for (let i = 0; i < 120; i++) h.update(1 / 60);
  assert.equal(h.value(), 2);
  h.place(-1); h.turn(1);
  for (let i = 0; i < 120; i++) h.update(1 / 60);
  assert.equal(h.value(), -0.5);
});

test('watch: state is a function of the clock, touch pauses with a snapshot, CTA at the end mark', () => {
  const { d, shell, clock, voice } = rig();
  d.beats.add('watch', new WatchBeat(d, { next: 'drive' }));
  d.go('watch');
  assert.deepEqual(voice.log.map((x) => x.id), ['w1', 'w2']);
  clock.set(1.4); d.tick(0.016);
  assert.equal(d.s.lbl, 0);
  clock.set(1.8); d.tick(0.016);
  assert.equal(d.s.lbl, 1);
  d.beats.touched();
  assert.equal(clock.playing(), false);
  assert.equal(shell.ctas.at(-1), 'Resume');
  d.s.lbl = 0.3; d.beats.toggle();
  assert.equal(d.s.lbl, 1);
  assert.equal(clock.playing(), true);
  clock.set(4.3); d.tick(0.016);
  assert.equal(shell.ctas.at(-1), 'Your turn');
});

test('watch: with advance, playing to the end goes on to the next beat by itself; without it the plate waits', () => {
  for (const advance of [true, false]) {
    const { d, clock } = rig();
    d.beats.add('watch', new WatchBeat(d, { next: 'x', advance }));
    d.beats.add('x', { label: 'X', enter() {}, update() {}, exit() {} });
    d.go('watch');
    clock.set(d.tl.duration() + 0.1); d.tick(0.016);
    assert.equal(d.beats.name, advance ? 'x' : 'watch');
  }
});

test('render on demand: no draws once nothing changes', () => {
  const { d, draws } = rig();
  d.beats.add('watch', new WatchBeat(d, { next: 'x' }));
  d.go('watch'); d.clock.stop();
  run(d, 3);
  const n = draws();
  run(d, 1);
  assert.equal(draws(), n);
});

test('guided play: step done after the hold, hint when stuck, events in order', async () => {
  const { d, shell, voice, hand } = rig();
  d.beats.add('drive', new GuidedPlay(d, 'drive', [{ hand: 0, ask: 'ask', ok: 'ok', done: all(handAt(0, 1), settled), hint: 'hint', hintAfter: 0.5 }], { next: 'end' }));
  d.go('drive');
  assert.equal(hand.enabled, true);
  run(d, 0.6);
  assert.ok(voice.log.some((x) => x.id === 'hint'));
  hand.turn(2);
  run(d, 1.5);
  assert.equal(hand.enabled, false);
  await sleep(40);
  assert.equal(shell.ctas.at(-1), 'Continue');
  assert.deepEqual(d.events.log.map((e) => e.type), ['beat', 'step', 'hint', 'step', 'complete']);
});

test('exercise: a miss says the fail line and a hint, then retries; a pass completes', async () => {
  const { d, shell, voice, hand } = rig();
  let give: boolean | null = null;
  d.beats.add('ex', new Exercise(d, 'ex', [{ ask: 'ask', pass: 'pass', fail: 'fail', hints: ['hint'], hold: 0.1, verdict: () => give, setup: (x) => { x.hands[0].place(0); } }], { next: 'end', label: 'Try' }));
  d.go('ex');
  await sleep(40);
  assert.equal(hand.enabled, true);
  give = false; d.tick(0.016);
  assert.equal(hand.enabled, false);
  await sleep(60);
  assert.deepEqual(voice.log.map((x) => x.id), ['ask', 'fail', 'hint']);
  assert.equal(hand.enabled, true);
  give = true; run(d, 0.2);
  await sleep(40);
  assert.equal(shell.ctas.at(-1), 'Continue');
  const attempts = d.events.log.filter((e) => e.type === 'attempt').map((e) => (e.type === 'attempt' ? [e.pass, e.tries] : null));
  assert.deepEqual(attempts, [[false, 1], [true, 2]]);
  assert.equal(d.events.log.at(-1)?.type, 'complete');
});

test('goal easing lands on the goal within eps, then drawing stops', () => {
  const { d, draws } = rig();
  d.goal.lbl = 1;
  run(d, 2.1);
  assert.equal(d.s.lbl, 1);
  run(d, 2.6);
  const n = draws();
  run(d, 1);
  assert.equal(draws(), n);
  assert.equal(cutawayEasing.eps.lampX, 0.5);
});

test('dialHand turns a cutaway Dial into a detent hand; spring overshoot crosses extra detents before it settles', () => {
  const dial = { cx: 5, cy: 6, r: 100, scale: { min: -3, max: 3, step: 0.5 }, angle: (v: number) => -0.4 * v, value: (a: number) => -a / 0.4 };
  const h = dialHand(dial, proj);
  assert.deepEqual([h.g.cx, h.g.cy, h.g.r, h.g.min, h.g.max, h.g.step], [5, 6, 110, -3, 3, 0.5]);
  let crossings = 0, settledChanges = 0, last = 0;
  h.place(0); h.onDetent = () => { crossings++; };
  h.turn(5);
  for (let i = 0; i < 240; i++) { h.update(1 / 120); if (h.settled() && h.value() !== last) { settledChanges += Math.round(Math.abs(h.value() - last) / 0.5); last = h.value(); } }
  assert.equal(h.value(), 2.5);
  assert.equal(settledChanges, 5);
  assert.equal(crossings, 7);
});
