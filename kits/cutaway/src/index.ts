/** cutaway-kit: the T71 Cutaway plate look as reusable tokens, parts and a flat three.js renderer. */
export { THEME, HATCH, TYPE, FONT, loadFonts, type Theme, type ColorRole } from './tokens';
export { Ink, TextPlate, Z, type Weight } from './ink';
export * from './geom';
export { frameView, cuts, framingFaults, heldFaults, textFaults, labelRect, titleRect, TITLE, DESKTOP, DEFAULT_INSET, type Box, type Inset, type Rect, type Sample } from './framing';
export { Stage } from './stage';
export { OnDemand, stateKey } from './loop';
export { AudioClock, ManualClock, PerfClock, Timeline, CueBinder, Narration, layoutClips, type Clock, type CueSheet, type Clip, type Word } from './motion';
export { DialHand, PointerRouter, Spring } from './interaction';
export { clamp01, inRing, dir, centreMark, housing, type Part } from './parts/part';
export { Callout, Balloon, Dimension, DetailLink, typed } from './parts/callout';
export { SectionCut, flange, hatchFill } from './parts/section';
export { Sheet, TitleBlock, caption, FocusLamp, Veil, type TitleSpec } from './parts/sheet';
export { Dial, Gauge, Valve, Pipe, WEIGHT_SCALE, type DialScale } from './parts/instruments';
export { Tube, Column } from './parts/glass';
export { Scale, GraphPaper, note } from './parts/scale';
export { Shell, type ShellText } from './shell';
export { Captions, type UnitSpec } from './captions';
