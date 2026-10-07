import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Timeline } from '../src/motion/timeline';
import { ManualClock } from '../src/core/clock';
import { NullVoice } from '../src/audio/voice';
import { evalAssert } from '../src/content/asserts';
import { lintUnit } from '../src/content/lint';
import { Director } from '../src/unit/director';
import { WatchBeat } from '../src/unit/watch';
import type { CueSheet, UnitBundle, UnitSpec } from '../src/content/types';
import type { ShellPort, UnitDef, View } from '../src/unit/ports';

const CUES: CueSheet = {
  bias: 0,
  clips: {
    w1: { src: 'w1', duration: 2, marks: { dial: 0.5, gauge: 1.5 }, words: [{ w: 'The', s: 0, e: 0.2 }, { w: 'dial.', s: 0.5, e: 0.9 }, { w: 'A', s: 1.2, e: 1.3 }, { w: 'gauge.', s: 1.5, e: 1.9 }] },
    w2: { src: 'w2', duration: 1, marks: { end: 0.8 }, words: [{ w: 'Done', s: 0.1, e: 0.5 }, { w: 'now.', s: 0.8, e: 0.95 }] },
  },
};
const SPEC: UnitSpec = {
  introduces: [
    { id: 'weight', word: 'weight', gloss: 'how much an input counts', namedCue: 'w1.dial' },
    { id: 'gauge', word: 'gauge', gloss: 'shows the output', namedCue: 'w1.gauge' },
  ],
  chapters: [{ id: 'one', numeral: 'I', title: 'The dial', clips: ['w1'] }, { id: 'two', numeral: 'II', title: 'The reading', clips: ['w2'] }],
  callouts: [{ id: 'reading', term: 'gauge', title: 'Reading', what: 'the number on the gauge', cue: 'w2.end' }],
  parts: [
    { id: 'dial', n: 1, name: 'Dial', term: 'weight' },
    { id: 'gauge', n: 2, name: 'Gauge', term: 'gauge', callout: 'reading' },
  ],
  clips: [{ id: 'w1', sentences: ['The {dial}dial.', { text: 'A {gauge}gauge.', asserts: ['v == 0'] }] }, { id: 'w2', sentences: ['Done {end}now.'] }],
};

interface S { v: number; lbl: number }

function rig(stops: boolean) {
  const rec = { ctas: [] as (string | null)[], go: null as (() => void) | null, drawn: [] as (string | null)[] };
  const port: ShellPort = {
    cta: (l, g) => { rec.ctas.push(l); rec.go = g ?? null; }, caption: () => {}, playing: () => {}, pausable: () => {}, status: () => {}, end: () => {},
  };
  const view: View<S> = { el: {} as HTMLElement, canvas: {} as HTMLElement, draw: () => {}, resize: () => {}, toWorld: (x, y) => [x, y], toScreen: (x, y) => [x, y],
    explain: (c) => { rec.drawn.push(c ? c.title : null); } };
  const unit: UnitDef<S> = {
    initial: () => ({ v: 0, lbl: 0 }),
    watch: { order: ['w1', 'w2'], lead: 1, gap: 0.5, build: (s, cue) => new Timeline().to(s, { lbl: 1, duration: 0.2, ease: 'none' }, cue.at('w1', 'dial')).mark('end', cue.at('w2', 'end')).end(cue.end('w2') + 1) },
    live: { now: (id, s) => (id === 'reading' ? `reads ${s.v}` : null) },
  };
  const bundle: UnitBundle = { spec: SPEC, cues: CUES, base: '' };
  const clock = new ManualClock(0, false);
  const d = new Director<S>({ unit, bundle, view, voice: new NullVoice(), clock, shell: port });
  d.beats.add('watch', new WatchBeat(d, { next: 'drive', stops }));
  return { d, rec, clock };
}

test('asserts: names, prev, the minus sign, and / or / not, a tolerance; anything else throws', () => {
  const now = { x1: 2, w1: 1.5, p1: 3, t: 2.5, out: 2, miss: 0.5, sum: -1.2 };
  assert.ok(evalAssert('p1 == x1 * w1', now));
  assert.ok(evalAssert('miss == t − out', now));
  assert.ok(evalAssert('abs(miss) < abs(prev.miss)', now, { miss: -1 }));
  assert.ok(evalAssert('sum < 0 and not (out < 0) or p1 != 3', now));
  assert.ok(evalAssert('0.1 + 0.2 == 0.3', {}));
  assert.ok(evalAssert('round(p1 / 2) == 2', now));
  assert.throws(() => evalAssert('x1 >', now), /ends early/);
  assert.throws(() => evalAssert('x1 = 2', now), /cannot read/);
  assert.throws(() => evalAssert('zz > 0', now), /no value zz/);
  assert.throws(() => evalAssert('out > prev.out', now), /no value out/);
});

test('lint: a broken assert, a callout cue that is no mark, and a part whose callout does not exist', () => {
  assert.deepEqual(lintUnit(SPEC, CUES), []);
  const bad: UnitSpec = { ...SPEC,
    clips: [{ id: 'w1', sentences: ['The {dial}dial.', { text: 'A {gauge}gauge.', asserts: ['v >'] }] }, SPEC.clips[1]],
    callouts: [{ ...SPEC.callouts![0], cue: 'w2.nope' }],
    parts: [{ ...SPEC.parts![0], callout: 'nope' }] };
  assert.deepEqual(lintUnit(bad, CUES), ['clip w1 sentence 2: assert "v >": ends early', 'callout reading: cue w2.nope is no mark', 'part dial: no callout nope']);
});

test('a callout is locked until its cue, naming its chapter', () => {
  const { d, clock } = rig(false);
  d.go('watch');
  clock.set(1.4); d.tick(0.016);
  let c = d.callout('reading');
  assert.equal(c.available, false);
  assert.equal(c.chapter?.numeral, 'II');
  assert.equal(c.now, null);
  clock.set(4.4); d.tick(0.016);
  c = d.callout('reading');
  assert.deepEqual([c.available, c.title, c.what, c.now, c.term.id], [true, 'Reading', 'the number on the gauge', 'reads 0', 'gauge']);
});

test('chapter stops: playing into a chapter lead-in stops there with that chapter as the call to action; play or the call goes on', () => {
  const { d, rec, clock } = rig(true);
  d.go('watch');
  clock.set(3.0); d.tick(0.016);
  assert.equal(clock.playing(), true);
  clock.set(3.25); d.tick(0.016);
  assert.equal(clock.playing(), false);
  assert.equal(clock.now(), 3.2);
  assert.equal(rec.ctas.at(-1), 'Chapter II: The reading');
  assert.deepEqual(d.events.log.filter((e) => e.type === 'stop'), [{ type: 'stop', chapter: 'two' }]);
  d.beats.cur!.toggle!();
  assert.equal(rec.ctas.at(-1), null, 'playing on hides the call');
  clock.set(3.3); d.tick(0.016);
  assert.equal(clock.playing(), true, 'no second stop at the same chapter');
  const b = rig(true);
  b.d.go('watch'); b.clock.set(3.25); b.d.tick(0.016);
  b.rec.go!();
  assert.deepEqual([b.clock.now(), b.clock.playing(), b.d.furthest >= 3.5], [3.5, true, true]);
  const c = rig(false);
  c.d.go('watch'); c.clock.set(3.25); c.d.tick(0.016);
  assert.equal(c.clock.playing(), true, 'without stops the watch plays through');
});

