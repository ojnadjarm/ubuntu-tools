import { WatchBeat, GuidedPlay, EndBeat, DetentHand, all, settled, handAt, type Beat, type Control, type Director, type GuidedStep, type Projector, type Spec, type UnitDef } from 'explainer-kit';
import { initialState, type A01State } from './state';
import { buildWatch, WATCH_ORDER, LEAD, GAP, SHOTS } from './watch';
import { ANCHORS, ROW, L } from './layout';
import { forward } from '../../sim/neuron';
import { DIAL_MIN, DIAL_MAX, DIAL_STEP, valueToAngle, angleToValue } from '../../plate/parts/meters';

type D = Director<A01State>;

/** Unit A01 for the engine: its state and the narrated watch. */
export const A01: UnitDef<A01State> = { initial: initialState, watch: { order: WATCH_ORDER, lead: LEAD, gap: GAP, build: buildWatch } };

/** The two weight dials: hand i drives w1/w2 and lights hiDial1/hiDial2. */
export const controls = (p: Projector): Control<A01State>[] => ROW.map((y, i) => ({
  hand: new DetentHand({ cx: L.dialX, cy: y, r: L.dialR + 10, min: DIAL_MIN, max: DIAL_MAX, step: DIAL_STEP, angle: valueToAngle, value: angleToValue }, p, 2.4),
  key: i ? 'w2' : 'w1', glow: i ? 'hiDial2' : 'hiDial1',
}));

/** Focus lamp to a named anchor (the voice's pointer). */
const lampTo = (d: D, name: string): void => { const p = ANCHORS[name] ?? ANCHORS.machine; Object.assign(d.goal, { lampX: p.x, lampY: p.y }); d.wake(); };
const outputOnTarget: Spec<A01State> = (d) => Math.abs(forward([d.hands[0].value(), d.hands[1].value()], [d.s.x1, d.s.x2]).out - d.s.target) < 0.01;

const DRIVE: GuidedStep<A01State>[] = [
  { hand: 0, ask: 'd1', ok: 'd1ok', done: all(handAt(0, 1), settled), enter: (d) => lampTo(d, 'dial1'), after: (d) => lampTo(d, 'gauge') },
  { hand: 1, ask: 'd2', ok: 'd2ok', done: all(outputOnTarget, settled), enter: (d) => lampTo(d, 'dial2'), after: (d) => { lampTo(d, 'mark'); d.goal.markGlow = 1; } },
];

/** Watch → drive (two spoken steps) → end card. */
export const beats = (d: D): Record<string, Beat> => ({
  watch: new WatchBeat(d, { next: 'drive', exitGoal: (s) => ({ ...SHOTS.drive, lampX: s.lampX, lampY: s.lampY }) }),
  drive: new GuidedPlay(d, 'drive', DRIVE, { next: 'end', enter: (x) => Object.assign(x.goal, { ...SHOTS.drive, lampOn: 1, exposure: 1, markOn: 1, markGlow: 0.25 }) }),
  end: new EndBeat(d, 'Next: race the tuner', (x) => lampTo(x, 'mark')),
});
