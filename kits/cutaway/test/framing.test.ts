import { test } from 'node:test';
import assert from 'node:assert/strict';
import { frameView, cuts, framingFaults, heldFaults, fitShot, textFaults, titleRect, DESKTOP } from '../src/framing.ts';

test('frameView fits the shot between the chrome insets', () => {
  const { s, view } = frameView({ x: 0, y: 0, w: 1000, h: 500 }, 1920, 1080, { top: 28, bottom: 164 });
  assert.equal(s, Math.min(1920 / 1000, 888 / 500));
  assert.ok(Math.abs((view[2] - view[0]) * s - 1920) < 1e-6);
});

test('cuts is true only for an object that is partly on screen', () => {
  assert.equal(cuts([0, 0, 10, 10], [8, 8, 12, 12]), true);
  assert.equal(cuts([0, 0, 10, 10], [2, 2, 4, 4]), false);
  assert.equal(cuts([0, 0, 10, 10], [20, 20, 30, 30]), false);
});

test('T71 neuron wall shot: the old sheet cut the title block at 2560, the fixed sheet does not', () => {
  const wall = { wall: { x: 0, y: 355, w: 2000, h: 1720 } };
  const title = (y0: number) => titleRect([-1100, y0, 1100, 1330]);
  assert.ok(framingFaults(wall, { title: title(-900) }, [[2560, 1440]]).length === 1);
  assert.deepEqual(framingFaults(wall, { title: title(-1300) }, DESKTOP), []);
});

test('textFaults flags a shot whose scale numerals fall under the legible size', () => {
  const shots = { tight: { x: 0, y: 0, w: 1400, h: 700 }, wide: { x: 0, y: 0, w: 2200, h: 2400 } };
  assert.deepEqual(textFaults(shots, 14, 11).map((f) => f.split(' ')[0]), ['wide']);
});

test('heldFaults reports a shown label cut by a held camera, and ignores hidden labels and moving cameras', () => {
  const cam = { x: 0, y: 0, w: 1000, h: 600 }, moving = { x: 50, y: 0, w: 1000, h: 600 };
  const whole = { edge: [600, 0, 800, 40] as [number, number, number, number] };
  const at = (t: number, c: typeof cam, lbl: number) => ({ t, cam: c, show: { lbl, exposure: 1 } });
  assert.equal(heldFaults([at(0, cam, 0), at(0.1, cam, 0)], whole, { edge: 'lbl' }, [[1920, 1080]]).length, 0);
  assert.equal(heldFaults([at(0, cam, 1), at(0.1, moving, 1)], whole, { edge: 'lbl' }, [[1920, 1080]]).length, 0);
  assert.equal(heldFaults([at(0, cam, 1), at(0.1, cam, 1)], whole, { edge: 'lbl' }, [[1920, 1080]]).length, 1);
});

test('fitShot moves a shot that cuts a label to the nearest box that holds it whole', () => {
  const whole = { lbl: [600, -20, 740, 20] as [number, number, number, number] };
  const b = { x: 0, y: 0, w: 1000, h: 600 };
  assert.ok(framingFaults({ b }, whole, [[1920, 1080]]).length > 0);
  const n = fitShot(b, whole, ['lbl'], [[1920, 1080]]);
  assert.ok(n && framingFaults({ n }, whole, [[1920, 1080]]).length === 0 && frameView(n, 1920, 1080).view[2] >= 740);
});

test('a signed title block grows upward by the signature strip; an unsigned one keeps its size', () => {
  const sheet: [number, number, number, number] = [-900, -1000, 900, 600];
  assert.deepEqual(titleRect(sheet), [324, -984, 884, -808]);
  assert.deepEqual(titleRect(sheet, true), [324, -984, 884, -768]);
});
