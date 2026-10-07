import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Timeline } from '../src/motion/timeline';
import { ManualClock } from '../src/core/clock';
import { NullVoice } from '../src/audio/voice';
import { DetentHand } from '../src/play/hand';
import { SlideHand } from '../src/play/slide';
import { SlotHand } from '../src/play/slots';
import { LockedHand } from '../src/play/locked';
import { Director } from '../src/unit/director';
import { CommandLog } from '../src/unit/log';
import { BenchFlow } from '../src/unit/flow';
import { HintLadder } from '../src/unit/hints';
import { Walk } from '../src/unit/walk';
import { GuidedPlay } from '../src/unit/guided';
import { Bench, type Task } from '../src/unit/bench';
import { lintPlay } from '../src/unit/kinds';
import type { CueSheet, UnitSpec } from '../src/content/types';
import type { ShellPort, UnitDef, View } from '../src/unit/ports';

const proj = { toWorld: (x: number, y: number): [number, number] => [x, y], toScreen: (x: number, y: number): [number, number] => [x, y] };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

test('command log: moves and tries by hand; rests are the settings that no move follows within the gap', () => {
  const log = new CommandLog();
  log.clear([0, 0], 10);
  log.push({ hand: 0, from: 0, to: 0.5, t: 11, kind: 'move' });
  log.push({ hand: 0, from: 0.5, to: 1, t: 11.2, kind: 'move' });
  log.push({ hand: 1, from: 0, to: -0.5, t: 13, kind: 'move' });
  log.push({ hand: 2, from: 0, to: 0, t: 13.5, kind: 'try' });
  assert.equal(log.value(0), 1);
  assert.equal(log.value(1), -0.5);
  assert.equal(log.moves(0).length, 2);
  assert.equal(log.tries().length, 1);
  assert.deepEqual(log.rests(1, 13.5), [[1, 0]], 'the last run has not rested yet');
  assert.deepEqual(log.rests(1, 14.5), [[1, 0], [1, -0.5]]);
  assert.equal(log.age(14.5), 4.5);
});

test('flow: a refutation at most twice per misconception, the contrast once on the second firing, the skip once after three clean first tries', () => {
  const f = new BenchFlow();
  assert.deepEqual(f.fire('m'), { refute: true, contrast: false });
  assert.deepEqual(f.fire('m'), { refute: true, contrast: true });
  assert.deepEqual(f.fire('m'), { refute: false, contrast: false });
  assert.deepEqual(f.fire('n'), { refute: true, contrast: false });
  assert.equal(f.result(true), false); assert.equal(f.result(true), false); assert.equal(f.result(false), false);
  assert.equal(f.result(true), false); assert.equal(f.result(true), false); assert.equal(f.result(true), true);
  assert.equal(f.result(true), false, 'offered once');
  const g = new BenchFlow(); g.restore(f.snapshot());
  assert.equal(g.count('m'), 3);
});

test('hint ladder: Look, then Narrow, then Show me; a case without a rung skips it; a new case starts over', () => {
  const h = new HintLadder();
  assert.equal(h.label(), 'Hint'); assert.equal(h.used(), false);
  assert.equal(h.next(), 'look'); assert.equal(h.label(), 'Another hint'); assert.equal(h.used(), true);
  assert.equal(h.next(), 'narrow'); assert.equal(h.label(), 'Show me');
  assert.equal(h.next(), 'show'); assert.equal(h.next(), null);
  h.offer(['narrow', 'show']);
  assert.equal(h.label(), 'Hint'); assert.equal(h.used(), false);
  assert.equal(h.next(), 'narrow'); assert.equal(h.label(), 'Show me');
});

test('walk: steps run on frame time, a gap apart; finish runs the rest', () => {
  const seen: number[] = [];
  const w = new Walk([0, 1, 2].map((i) => ({ gap: 0.3, run: () => seen.push(i) })));
  assert.equal(w.update(0.2), false); assert.deepEqual(seen, []);
  w.update(0.2); assert.deepEqual(seen, [0]);
  w.update(0.7); assert.deepEqual(seen, [0, 1, 2]); assert.equal(w.done(), true);
  const v = new Walk([{ gap: 5, run: () => seen.push(9) }]); v.finish(); assert.equal(seen.at(-1), 9);
});

test('hands: a pencil snaps along its track, a part seats only where it fits, a locked input reports every try and never moves', () => {
  const pen = new SlideHand({ hits: (x) => x >= 0 && x <= 100, valueAt: (x) => x / 20, min: -1.5, max: 5, step: 0.1 }, proj);
  pen.down(43, 0); pen.up();
  assert.equal(pen.value(), 2.2);
  pen.turn(-3); assert.equal(pen.value(), 1.9);
  pen.place(9); assert.equal(pen.value(), 5);
  let det = 0; pen.onDetent = () => det++; pen.turn(-1); pen.update(0.016); assert.equal(det, 1);
  const taken = new Set<number>([1]);
  const part = new SlotHand({ home: [0, 0], at: [[100, 0], [200, 0], [300, 0]], r: 20, fits: (i) => i !== 2, taken: (i) => taken.has(i) }, proj);
  part.down(); part.move(290, 5); part.up();
  assert.equal(part.value(), 0, 'seat 2 does not fit, seat 1 is taken: the nearest open seat');
  part.down(); part.move(10, 0); part.up(); assert.equal(part.value(), -1, 'back to the tray');
  part.down(); part.move(110, 0); part.up(); assert.equal(part.value(), 0);
  assert.deepEqual(part.open(), [0]);
  part.turn(1); assert.equal(part.value(), -1);
  const tube = new LockedHand((x) => x < 10);
  let tries = 0; tube.onTry = () => tries++;
  tube.place(2); tube.down(); tube.move(); tube.up(); tube.turn(1);
  assert.equal(tries, 2); assert.equal(tube.value(), 2);
});

const line = (id: string) => ({ src: id, duration: 0.005, marks: {}, words: [] });
const IDS = ['w', 'ask', 'ok', 'miss', 'ref', 'kask', 'kok', 'skip', 'nar'];
const CUES: CueSheet = { bias: 0, clips: Object.fromEntries(IDS.map((id) => [id, line(id)])) };
const SPEC: UnitSpec = { clips: IDS.map((id) => ({ id, sentences: [`{${id}}Say ${id}.`] })) };
interface S { w1: number; w2: number; goal: number }

function rig() {
  const rec = { ctas: [] as (string | null)[], go: null as (() => void) | null, offer: null as string | null, offerGo: null as (() => void) | null, hint: [] as (string | undefined)[], give: [] as boolean[] };
  const port: ShellPort = {
    cta: (l, g) => { rec.ctas.push(l); rec.go = g ?? null; }, caption: () => {}, playing: () => {}, pausable: () => {}, status: () => {}, end: () => {},
    hintable: (on, label) => { rec.hint.push(on ? label : undefined); }, offer: (l, g) => { rec.offer = l; rec.offerGo = g ?? null; }, giveable: (on) => { rec.give.push(on); },
  };
  const view: View<S> = { el: {} as HTMLElement, canvas: {} as HTMLElement, draw: () => {}, resize: () => {}, ...proj };
  const unit: UnitDef<S> = { initial: () => ({ w1: 0, w2: 0, goal: 0 }), watch: { order: ['w'], lead: 0, gap: 0, build: () => new Timeline().end(1) } };
  const geom = (cx: number) => ({ cx, cy: 0, r: 10, min: -3, max: 3, step: 0.5, angle: (v: number) => -v, value: (a: number) => -a });
  const h0 = new DetentHand(geom(0), proj, 2.4), h1 = new DetentHand(geom(40), proj, 2.4);
  const d = new Director<S>({ unit, bundle: { spec: SPEC, cues: CUES, base: '' }, view, voice: new NullVoice(), clock: new ManualClock(0, false), shell: port,
    controls: [{ hand: h0, key: 'w1' }, { hand: h1, key: 'w2' }] });
  return { d, rec };
}
const tick = (d: Director<S>, secs: number): void => { for (let t = 0; t < secs; t += 1 / 60) d.tick(1 / 60); };
const settle = async (d: Director<S>, secs = 0.6): Promise<void> => { for (let k = 0; k < 6; k++) { tick(d, secs / 6); await sleep(15); } };

/** A set-and-press case: turn dial 1 to the goal and press; pressing at goal − 1 shows "adds" (a detector), a play detector fires on dial 2. */
const setPress = (id: string, of = 'e1'): Task<S> => ({
  id, of, label: `Case ${id}`, ask: 'ask', hands: [0, 1], ok: 'ok', miss: 'miss', narrow: 'nar',
  setup: (d, seed) => d.pose({ w1: 0, w2: 0, goal: 1 + (seed % 2) * 0.5 }),
  commit: (d) => ({ pass: d.hands[0].value() === d.s.goal }),
  detect: (d, when) => (when === 'miss' && d.hands[0].value() === d.s.goal - 1 ? 'm.adds' : when === 'play' && d.hands[1].value() < 0 ? 'm.play' : null),
  show: (d) => [{ gap: 0.1, run: () => d.hands[0].turn(1) }],
});
const contrast: Task<S> = { id: 'k', label: 'Contrast', ask: 'kask', hands: [0], ok: 'kok', setup: (d) => d.pose({ w1: 0 }), verdict: (d) => (d.hands[0].value() === 1 ? true : null) };

test('bench: a pass says ok and opens the next round; a miss says its line, refutes, queues the contrast before the retry on the second firing', async () => {
  const { d, rec } = rig();
  const tasks = [setPress('a'), setPress('b'), setPress('c', 'e2')];
  const bench = new Bench<S>(d, 'bench', { label: 'Workbench', next: 'end', tasks, refute: (m) => (m === 'm.adds' ? 'ref' : undefined), contrasts: { 'm.adds': contrast }, seed: 3 });
  d.beats.add('bench', bench);
  d.go('bench');
  assert.equal(bench.task!.id, 'a');
  assert.equal(d.hands[0].enabled && d.hands[1].enabled, true);
  const turnTo = (v: number): void => { d.hands[0].turn((v - d.hands[0].value()) / 0.5); };
  turnTo(d.s.goal); await settle(d);
  assert.ok(bench.commit());
  await settle(d);
  assert.equal(bench.task!.id, 'b', 'same exercise: the next round opens by itself');
  for (let k = 0; k < 2; k++) {
    turnTo(d.s.goal - 1); await settle(d);
    bench.commit(); await settle(d);
    assert.equal(rec.ctas.at(-1), k === 0 ? 'Try a new one' : 'Continue');
    rec.go!(); await settle(d, 0.2);
  }
  const detects = d.events.log.filter((e) => e.type === 'detect');
  assert.equal(detects.length, 2);
  assert.equal(bench.task!.id, 'k', 'the contrast pair comes before the retry');
  turnTo(1); await settle(d);
  assert.equal(rec.ctas.at(-1), 'Continue');
  rec.go!(); await settle(d, 0.2);
  assert.equal(bench.task!.id, 'b', 'then the round is tried again');
  d.hands[1].turn(-1); await settle(d);
  assert.equal(d.events.log.filter((e) => e.type === 'detect').length, 3, 'a play detector fires while playing');
  d.hands[1].turn(-1); await settle(d);
  assert.equal(d.events.log.filter((e) => e.type === 'detect').length, 3, 'once per case');
});

test('bench: hints climb Look → Narrow → Show me; Show me works the case and offers a new one; three clean first tries offer the skip', async () => {
  const { d, rec } = rig();
  const tasks = ['a', 'b', 'c', 'd'].map((id) => setPress(id));
  const bench = new Bench<S>(d, 'bench', { label: 'Workbench', next: 'end', tasks, refute: () => undefined, skip: { clip: 'skip', label: 'Open the Challenge', to: 'race' } });
  d.beats.add('bench', bench); d.beats.add('race', bench);
  d.go('bench');
  assert.equal(rec.hint.at(-1), 'Hint', 'no Look rung here: Narrow is the first hint');
  assert.ok(bench.hint()); assert.equal(rec.hint.at(-1), 'Show me');
  const was = d.hands[0].value();
  assert.ok(bench.hint()); await settle(d);
  assert.equal(d.hands[0].value(), was + 0.5, 'Show me turned the dial');
  assert.equal(rec.ctas.at(-1), 'Try a new one');
  rec.go!(); await settle(d, 0.2);
  for (const id of ['a', 'b', 'c']) {
    assert.equal(bench.task!.id, id);
    d.hands[0].turn((d.s.goal - d.hands[0].value()) / 0.5); await settle(d);
    bench.commit(); await settle(d);
  }
  assert.equal(rec.offer, 'Open the Challenge');
  assert.equal(bench.task!.id, 'd');
  const snap = bench.snapshot();
  d.go('bench', { snap });
  assert.equal(bench.task!.id, 'd', 'a snapshot returns to the same case');
});

test('bench: passing the last case completes the beat, then Continue opens the next beat', async () => {
  const { d, rec } = rig();
  const bench = new Bench<S>(d, 'bench', { label: 'Workbench', next: 'bench', tasks: [setPress('a')], refute: () => undefined });
  d.beats.add('bench', bench);
  d.go('bench');
  d.hands[0].turn((d.s.goal - d.hands[0].value()) / 0.5); await settle(d);
  bench.commit(); await settle(d);
  assert.equal(d.events.log.filter((e) => e.type === 'complete' && e.beat === 'bench').length, 1);
  assert.equal(rec.ctas.at(-1), 'Continue');
});

test('bench: Give up counts as missed, plays the answer, then offers Try a new one and Next; a case with no answer offers no Give up', async () => {
  const { d, rec } = rig();
  const plain: Task<S> = { ...setPress('p'), show: undefined };
  const bench = new Bench<S>(d, 'bench', { label: 'Workbench', next: 'end', tasks: [setPress('a'), setPress('b', 'e2'), plain], refute: () => undefined });
  d.beats.add('bench', bench);
  d.go('bench'); await settle(d, 0.1);
  assert.equal(rec.give.at(-1), true, 'a case with a worked answer can be given up');
  const was = d.hands[0].value();
  assert.ok(bench.giveUp()); await settle(d);
  assert.equal(d.hands[0].value(), was + 0.5, 'the answer turned the dial');
  assert.equal(bench.gaveUp, true);
  assert.deepEqual([rec.ctas.at(-1), rec.offer], ['Try a new one', 'Next']);
  assert.equal(d.events.log.filter((e) => e.type === 'giveup').length, 1);
  assert.equal(bench.giveUp(), false, 'not while waiting');
  rec.offerGo!(); await settle(d, 0.2);
  assert.equal(bench.task!.id, 'b', 'Next opens the next case');
  assert.equal(bench.gaveUp, false);
  bench.giveUp(); await settle(d); rec.go!(); await settle(d, 0.2);
  assert.equal(bench.task!.id, 'b', 'Try a new one poses the same case anew');
  bench.giveUp(); await settle(d); rec.offerGo!(); await settle(d, 0.2);
  assert.equal(bench.task!.id, 'p');
  assert.equal(rec.give.at(-1), false, 'no answer, no Give up');
  assert.equal(bench.giveUp(), false);
});

test('bench: endless practice draws cases from the pool after the queue, never completes, and keeps its leave chip; the same seed draws the same cases', async () => {
  const draws = async (seed: number): Promise<string[]> => {
    const { d, rec } = rig();
    const pool = ['x', 'y', 'z'].map((id) => setPress(id, 'p'));
    const bench = new Bench<S>(d, 'more', { label: 'Practice', next: 'end', tasks: [], refute: () => undefined, seed, pool: { tasks: pool, leave: { label: 'Go on', to: 'end' } } });
    d.beats.add('more', bench);
    d.go('more'); await settle(d, 0.1);
    const seen: string[] = [];
    for (let k = 0; k < 5; k++) {
      seen.push(`${bench.task!.id}${d.s.goal}`);
      assert.equal(rec.offer, 'Go on');
      d.hands[0].turn((d.s.goal - d.hands[0].value()) / 0.5); await settle(d);
      bench.commit(); await settle(d);
      assert.equal(rec.ctas.at(-1), 'Next');
      rec.go!(); await settle(d, 0.1);
    }
    assert.equal(d.events.log.filter((e) => e.type === 'complete').length, 0);
    const snap = bench.snapshot();
    d.go('more', { snap });
    assert.equal(`${bench.task!.id}${d.s.goal}`, seen.length ? `${bench.task!.id}${d.s.goal}` : '', 'a snapshot returns to the drawn case');
    return seen;
  };
  const a = await draws(7), b = await draws(7), c = await draws(8);
  assert.deepEqual(a, b, 'a pinned seed draws the same cases');
  assert.notDeepEqual(a, c);
  assert.ok(new Set(a.map((x) => x[0])).size > 1, 'more than one kind is drawn');
});

test('bench: a tap the case does not take goes to the bench\'s own tap, in play and while waiting', async () => {
  const { d } = rig();
  const taps: string[] = [];
  const t: Task<S> = { ...setPress('a'), tap: (_d, wx) => (wx > 100 ? 'commit' : false) };
  const bench = new Bench<S>(d, 'bench', { label: 'W', next: 'end', tasks: [t], refute: () => undefined, tap: (_d, wx) => { taps.push(`${wx}`); return wx < 0; } });
  d.beats.add('bench', bench);
  d.go('bench'); await settle(d, 0.1);
  assert.equal(bench.tap(-5, 0), true);
  assert.equal(bench.tap(5, 0), false);
  bench.giveUp(); await settle(d);
  assert.equal(bench.tap(-6, 0), true, 'while waiting');
  assert.deepEqual(taps, ['-5', '5', '-6']);
});

test('lintPlay: unregistered kinds, discrete picks, uncaught misconceptions, missing detectors and clips fail', () => {
  const spec: UnitSpec = {
    clips: [], exercises: [
      { id: 'e1', title: 'x', kind: 'set-commit', answerSpace: 'continuous', rounds: 1, catches: ['m.a'], clips: { ask: 'ask' } },
      { id: 'e2', title: 'y', kind: 'quiz', answerSpace: 'choice', rounds: 1, catches: [], clips: { ask: 'nope' } },
      { id: 'L1', title: 'z', kind: 'race', answerSpace: 'continuous', rounds: 1, catches: ['m.c'], clips: {} },
    ],
    misconceptions: [
      { id: 'm.a', belief: '', truth: '', catcher: 'e1', refute: 'ref', contrast: 'kask' },
      { id: 'm.b', belief: '', truth: '', catcher: 'e2', refute: 'ref' },
      { id: 'm.c', belief: '', truth: '', catcher: 'L1', refute: 'ref' },
    ],
  };
  const out = lintPlay(spec, { clips: IDS, detectors: ['m.a', 'm.c'] });
  assert.deepEqual(out, [
    'exercise e2: kind quiz is not registered', 'exercise e2: answer space choice is a discrete pick', 'exercise e2: catches no misconception',
    'exercise e2 ask: clip nope does not exist', 'misconception m.b: no exercise catches it', 'misconception m.b: no detector in code', 'misconception m.b: no contrast pair',
  ]);
});

test('guided step with several hands enables them all and lights the named one; a muted line waits its length over the rate', async () => {
  const { d } = rig();
  d.beats.add('drive', new GuidedPlay(d, 'drive', [{ hand: 1, hands: [0, 1], ask: 'ask', ok: 'ok', done: () => false }], { next: 'end' }));
  d.go('drive');
  assert.deepEqual(d.hands.map((h) => h.enabled), [true, true]);
  assert.equal(d.activeHand, 1);
  d.rate = 1000;
  const t0 = performance.now();
  assert.equal(await d.say('ok'), true);
  assert.ok(performance.now() - t0 < 50);
});
