import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chapterList, type Chapter } from '../src/unit/chapters';
import { isFinished, landing, resumeLine, type ResumePoint } from '../src/unit/resume';
import { lessonPoint } from '../src/unit/sections';
import { BeatMachine, type Beat } from '../src/unit/beats';
import { Events } from '../src/core/events';
import type { ShellPort } from '../src/unit/ports';

const SECTIONS = [{ name: 'Practice', tabs: [{ label: 'Exercises', beat: 'practice' }, { label: 'Tuning', beat: 'tunes' }], back: { label: 'Back to the lesson', to: 'end' } }];
const SPECS = [
  { id: 'c1', numeral: 'I', title: 'The neuron', clips: ['w1'] }, { id: 'c2', numeral: 'II', title: 'The valve', clips: ['w2'] },
  { id: 'bench', numeral: 'III', title: 'Workbench', beat: 'bench' },
  { id: 'close', numeral: 'IV', title: "What one neuron can't do", beat: 'click', clips: ['payoff', 'close'] },
];
const rows = (furthest: number, completed: string[] = [], visited: string[] = []): Chapter[] =>
  chapterList(SPECS, { w1: 0, w2: 5 }, 10, { furthest, visited: new Set(visited), completed: new Set(completed) });
const beat = (o: Partial<Beat> = {}): Beat => ({ label: 'Beat', enter() {}, update() {}, exit() {}, ...o });

test('L1 a chapter with a beat is that beat\'s chapter even when it lists clips (they only time it)', () => {
  const c = rows(10, ['bench'], ['bench', 'click'])[3];
  assert.deepEqual([c.beat, c.t, c.reached, c.done], ['click', undefined, true, false]);
  assert.equal(rows(10, ['bench', 'click'])[3].done, true);
});

test('L2 finished: the end was reached, or every chapter is done', () => {
  assert.equal(isFinished(rows(10, ['bench']), new Set(['bench'])), false);
  assert.equal(isFinished(rows(10, ['bench']), new Set(['bench', 'unit'])), true, 'finished before the closing chapter existed');
  assert.equal(isFinished(rows(10, ['bench', 'click']), new Set(['bench', 'click'])), true);
});

test('L3 landing: Begin on a first visit, Continue / Start over unfinished, the finished unit\'s own choices once done', () => {
  const resume: ResumePoint = { beat: 'bench', enter: {}, label: 'You stopped in chapter III, Workbench.' };
  const done = { line: 'You finished this plate.', choices: [{ label: 'Practice exercises', to: 'practice', kind: 'primary' as const }, { label: 'Practice tuning', to: 'tunes', kind: 'secondary' as const }, { label: 'Watch again', to: 'watch', kind: 'quiet' as const }] };
  assert.deepEqual(landing(null, false, done), { line: null, choices: [{ label: 'Begin', kind: 'primary', value: 'continue' }] });
  assert.deepEqual(landing(resume, false, done).choices.map((c) => [c.label, c.kind, c.value]), [['Continue', 'primary', 'continue'], ['Start over', 'secondary', 'start']]);
  assert.equal(landing(resume, false, done).line, resume.label);
  const f = landing(resume, true, done);
  assert.deepEqual([f.line, f.choices.map((c) => [c.label, c.kind, c.value])], ['You finished this plate.', [['Practice exercises', 'primary', 'practice'], ['Practice tuning', 'secondary', 'tunes'], ['Watch again', 'quiet', 'watch']]]);
  assert.equal(landing(resume, true).choices[0].label, 'Continue', 'without a finished offer a unit keeps Continue');
});

test('L4 the resume line is readable, never an id: watch chapter, beat chapter, section tab, the beat\'s own line, then where', () => {
  const list = rows(7, [], ['bench', 'click']);
  assert.equal(resumeLine({ beat: 'watch', t: 6 }, list, SECTIONS, beat()), 'You stopped in chapter II, The valve.');
  assert.equal(resumeLine({ beat: 'bench' }, list, SECTIONS, beat()), 'You stopped in chapter III, Workbench.');
  assert.equal(resumeLine({ beat: 'click' }, list, SECTIONS, beat()), "You stopped in chapter IV, What one neuron can't do.");
  assert.equal(resumeLine({ beat: 'tunes' }, list, SECTIONS, beat()), 'You stopped in Practice, Tuning.');
  assert.equal(resumeLine({ beat: 'fork' }, list, SECTIONS, beat({ resumeLine: () => 'You finished the explanation.' })), 'You finished the explanation.');
  assert.equal(resumeLine({ beat: 'odd' }, list, SECTIONS, beat({ where: () => 'the odd place' })), 'You stopped at the odd place.');
});

test('L5 back to the lesson without a beat to return to: the end once finished, else the first chapter not done', () => {
  assert.deepEqual(lessonPoint(rows(10, ['bench', 'click']), 10, true, 'end'), { name: 'end', enter: {} });
  assert.deepEqual(lessonPoint(rows(3), 3, false, 'end'), { name: 'watch', enter: { at: 3 } }, 'an unheard watch chapter: the furthest second');
  assert.deepEqual(lessonPoint(rows(10, ['bench']), 10, false, 'end'), { name: 'click', enter: {} });
  assert.deepEqual(lessonPoint(rows(10), 10, false, 'end'), { name: 'bench', enter: {} });
});

test('L6 the beat machine remembers the beat it left and how to enter it again: the watch at its second, the end card open, others from a snapshot', () => {
  const port = { hush() {}, events: new Events(), shell: { cta() {}, pausable() {}, status() {} } as unknown as ShellPort };
  const m = new BeatMachine(port);
  m.add('watch', beat({ leaving: () => ({ at: 12.5 }) })).add('bench', beat({ snapshot: () => ({ i: 2 }) })).add('end', beat({ leaving: () => ({}) })).add('p', beat());
  m.go('watch'); m.go('p');
  assert.deepEqual(m.left, { name: 'watch', enter: { at: 12.5 } });
  m.go('bench'); m.go('p');
  assert.deepEqual(m.left, { name: 'bench', enter: { snap: { i: 2 } } });
  m.go('end'); m.go('p');
  assert.deepEqual(m.left, { name: 'end', enter: {} });
});
