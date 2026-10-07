import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { framingFaults, heldFaults, textFaults, DESKTOP, type Sample } from 'cutaway-kit/framing.ts';
import { CueBinder, layoutClips, type CueSheet } from 'cutaway-kit/motion.ts';
import { SHEET, SHOTS, WHOLE, SHOWN_BY, REST } from '../src/layout.ts';
import { buildScript, LEAD, ORDER } from '../src/script.ts';
import { initialState } from '../src/state.ts';

/** The script played in node at 10 samples a second: camera box and every state value. */
function samples(): Sample[] {
  const cues = JSON.parse(readFileSync(new URL('../public/bundles/s00/cues.json', import.meta.url), 'utf8')) as CueSheet;
  const s = initialState(), tl = buildScript(s, new CueBinder(cues, layoutClips(cues, ORDER, LEAD, 0.9).offsets)), out: Sample[] = [];
  for (let t = 0; t <= tl.duration() + 0.05; t += 0.1) {
    tl.seek(t);
    out.push({ t, cam: { x: s.camX, y: s.camY, w: s.camW, h: s.camH }, show: { ...s } as unknown as Record<string, number> });
  }
  return out;
}

test('while the camera holds, no shown label, caption or title block is cut, at every desktop size', () => {
  assert.deepEqual(heldFaults(samples(), WHOLE, SHOWN_BY), []);
});

test('no named shot cuts the title block, and the opening shot shows the whole sheet', () => {
  assert.deepEqual(framingFaults(SHOTS, { title: WHOLE.title }, DESKTOP), []);
  assert.deepEqual(framingFaults({ open: SHOTS.open }, { sheet: SHEET }, DESKTOP), []);
});

test('scale numerals (14 units) render at 11 px or more at 1920 in the shot the learner plays in', () => {
  assert.deepEqual(textFaults({ [REST]: SHOTS[REST] }, 14, 11), []);
});
