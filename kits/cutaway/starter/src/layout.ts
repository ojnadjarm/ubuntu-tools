import { labelRect, titleRect, type Box, type Rect } from 'cutaway-kit/framing.ts';

/** Plate geometry in drawing units (y up); pure data, so the framing test runs in node. */
export const L = { caseW: 1000, caseH: 440, dialX: -280, dialR: 104, knobR: 44, gaugeX: 260, gaugeR: 118, meterX: -20 };

/** The casing (the look gate measures inside it) and the sheet, which sits low enough that no resting shot reaches its title block. */
export const CASING: Rect = [-L.caseW / 2, -L.caseH / 2, L.caseW / 2, L.caseH / 2];
export const SHEET: Rect = [-900, -1000, 900, 600];

/** Every label on the plate: the plate draws them from here and the framing test keeps each one whole or out of every shot. */
/** `show` names the state key that draws the label in (absent = always on the sheet). */
export const LABELS = {
  rate: { at: [-112, 300], text: 'RATE', align: 0, size: 26, show: 'lblRate' },
  flow: { at: [28, -300], text: 'FLOW', align: 0, size: 26, show: 'lblFlow' },
  target: { at: [L.gaugeX + 118, 300], text: 'TARGET', align: 0, size: 26, show: 'lblTarget' },
  name: { at: [0, -380 - 34 * 1.05], text: 'REGULATOR', align: 0.5, size: 34, show: 'lblName' },
  fig1: { at: [-L.caseW / 2, -470], text: 'Fig. 1.', align: 0, size: 19 },
} as const;

/** Objects a held camera must show whole or not at all, and the state key that shows each one (see framing `heldFaults`). */
export const WHOLE: Record<string, Rect> = {
  title: titleRect(SHEET, true),
  ...Object.fromEntries(Object.entries(LABELS).map(([k, l]) => [k, labelRect(l.at[0], l.at[1], l.text, l.size, l.align)])),
};
export const SHOWN_BY: Record<string, string> = Object.fromEntries(Object.entries(LABELS).flatMap(([k, l]) => ('show' in l ? [[k, l.show]] : [])));

/** Named framings; the timeline tweens the camera between them. `full` is where the learner plays. */
export const SHOTS: Record<string, Box> = {
  open: { x: 0, y: -200, w: 1900, h: 1640 },
  full: { x: 0, y: -20, w: 1300, h: 820 },
  dial: { x: -280, y: 30, w: 700, h: 600 },
  gauge: { x: 260, y: 60, w: 720, h: 640 },
};
/** The shot the learner plays in: its scale numerals must stay legible. */
export const REST = 'full';

/** Points the focus lamp can look at. */
export const ANCHORS: Record<string, [number, number]> = { casing: [0, 0], dial: [L.dialX, 0], pipe: [0, 0], gauge: [L.gaugeX, 0], mark: [L.gaugeX, L.gaugeR] };
