import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { framingFaults, heldFaults, textFaults, titleRect, DESKTOP, type Sample } from 'cutaway-kit/framing';
import { CueBinder, layoutClips, type CueSheet } from 'explainer-kit';
import { SHEET, SHOTS, WHOLE, SHOWN_BY } from '../src/units/a02/layout';
import { buildWatch, WATCH_ORDER, LEAD, GAP } from '../src/units/a02/watch';
import { initialState } from '../src/units/a02/state';

const BUNDLE = new URL('../public/bundles/a02/cues.json', import.meta.url);
const PLAY = 'drive';

/** The narrated watch played in node at 10 samples a second: camera box and every state value. */
function samples(): Sample[] {
  const cues = JSON.parse(readFileSync(BUNDLE, 'utf8')) as CueSheet;
  const s = initialState(), tl = buildWatch(s, new CueBinder(cues, layoutClips(cues, WATCH_ORDER, LEAD, GAP).offsets)), out: Sample[] = [];
  for (let t = 0; t <= tl.duration() + 0.05; t += 0.1) {
    tl.seek(t);
    out.push({ t, cam: { x: s.camX, y: s.camY, w: s.camW, h: s.camH }, show: { ...s } as unknown as Record<string, number> });
  }
  return out;
}

test('while the camera holds, no shown label or title block is cut, at every desktop size', () => {
  assert.deepEqual(heldFaults(samples(), WHOLE, SHOWN_BY), []);
});

test('no named shot cuts the title block, and the opening shot shows the whole sheet', () => {
  assert.deepEqual(framingFaults(SHOTS, { title: titleRect(SHEET) }, DESKTOP), []);
  assert.deepEqual(framingFaults({ open: SHOTS.open }, { sheet: SHEET }, DESKTOP), []);
});

test('the play shot holds every label whole, and scale numerals (14 units) render at 11 px or more at 1920', () => {
  assert.deepEqual(framingFaults({ [PLAY]: SHOTS[PLAY] }, WHOLE, DESKTOP), []);
  assert.deepEqual(textFaults({ [PLAY]: SHOTS[PLAY] }, 14, 11), []);
});
