import { labelRect, titleRect, type Box, type Rect } from 'cutaway-kit/framing';

/** Plate II geometry in drawing units (y up): input row on top, bias row below, sum column and gauge on the right. */
export const ROW: [number, number] = [110, -110];
export const L = {
  tubeX: -500, tubeLen: 220, tubeR: 25,
  dialX: -170, dialR: 104, knobR: 44,
  colX: 170, colHW: 40, colH: 340,
  gaugeX: 480, gaugeR: 118,
  caseW: 1360, caseH: 520,
  tallyX: -560, tallyY: -340,
};
export const SHEET: Rect = [-1100, -1180, 1100, 560];
/** The casing: the look gate (tools/shot.mjs) measures inside it. */
export const CASING: Rect = [-L.caseW / 2, -L.caseH / 2, L.caseW / 2, L.caseH / 2];

/** Every label on the plate: the plate draws them from here and the framing test keeps each one whole or out of every held shot. */
/** `align` 0 = starts at `at`, 1 = ends at `at`; `show` names the state key that draws the label in (absent = always on the sheet). */
const TL = L.tubeX - L.tubeLen / 2 - 16;
export const LABELS = {
  input: { at: [TL - 98, 330], text: 'INPUT', align: 1, size: 26, show: 'lblInput' },
  weight: { at: [-12, 330], text: 'WEIGHT', align: 0, size: 26, show: 'lblWeight' },
  bias: { at: [-12, -330], text: 'BIAS', align: 0, size: 26, show: 'lblBias' },
  output: { at: [L.gaugeX + 48, -330], text: 'OUTPUT', align: 0, size: 26, show: 'lblOutput' },
  target: { at: [L.gaugeX + 118, 330], text: 'TARGET', align: 0, size: 26, show: 'lblTarget' },
  name: { at: [0, -430 - 34 * 1.05], text: 'NEURON WITH BIAS', align: 0.5, size: 34, show: 'lblName' },
  fig1: { at: [-L.caseW / 2, -520], text: 'Fig. 1.', align: 0, size: 19 },
} as const;

/** Objects a held camera must show whole or not at all, and the state key that shows each one (framing `heldFaults`). */
export const WHOLE: Record<string, Rect> = {
  title: titleRect(SHEET),
  ...Object.fromEntries(Object.entries(LABELS).map(([k, l]) => [k, labelRect(l.at[0], l.at[1], l.text, l.size, l.align)])),
};
export const SHOWN_BY: Record<string, string> = Object.fromEntries(Object.entries(LABELS).flatMap(([k, l]) => ('show' in l ? [[k, l.show]] : [])));

/** Named framings; `drive` is where the learner plays (it holds the click tally too). */
export const SHOTS: Record<string, Box> = {
  open: { x: 0, y: -310, w: 2300, h: 1840 },
  full: { x: -20, y: -30, w: 1720, h: 920 },
  top: { x: -330, y: 60, w: 980, h: 640 },
  bias: { x: -330, y: -110, w: 1029, h: 672 },
  right: { x: 330, y: 0, w: 960, h: 680 },
  drive: { x: -20, y: -50, w: 1760, h: 980 },
};

/** Points the focus lamp can look at. */
export const ANCHORS: Record<string, [number, number]> = {
  machine: [0, 0], tube: [L.tubeX, ROW[0]], source: [L.tubeX, ROW[1]],
  dialW: [L.dialX, ROW[0]], dialB: [L.dialX, ROW[1]], column: [L.colX, 0],
  gauge: [L.gaugeX, 0], mark: [L.gaugeX, L.gaugeR], tally: [L.tallyX + 140, L.tallyY],
};

/** A drawn part a tap can open: the term it carries, its outline in discs [cx, cy, r] and boxes [x0, y0, x1, y1], and the dot its callout starts on. */
export interface SpotSpec { term: string; discs?: [number, number, number][]; boxes?: [number, number, number, number][]; dot: [number, number] }
const tube = (y: number): [number, number, number, number] => [L.tubeX - L.tubeLen / 2 - 16, y - L.tubeR - 8, L.tubeX + L.tubeLen / 2 + 16, y + L.tubeR + 8];
/** Tap targets, first match wins; the bias dial comes before the source so a callout on `bias` points at the dial. */
export const SPOTS: Record<string, SpotSpec> = {
  tube: { term: 'input', boxes: [tube(ROW[0])], dot: [L.tubeX - 60, ROW[0] + L.tubeR] },
  dialW: { term: 'weight', discs: [[L.dialX, ROW[0], L.dialR]], dot: [L.dialX, ROW[0] + L.dialR] },
  dialB: { term: 'bias', discs: [[L.dialX, ROW[1], L.dialR]], dot: [L.dialX, ROW[1] - L.dialR] },
  source: { term: 'bias', boxes: [tube(ROW[1])], dot: [L.tubeX - 60, ROW[1] - L.tubeR] },
  gauge: { term: 'output', discs: [[L.gaugeX, 0, L.gaugeR]], dot: [L.gaugeX - L.gaugeR * 0.71, L.gaugeR * 0.71] },
};
