import { WatchBeat, GuidedPlay, Exercise, EndBeat, DetentHand, all, settled, handAt, type Beat, type Control, type Director, type GuidedStep, type Hotspot, type Projector, type Round, type UnitDef } from 'explainer-kit';
import { dialHand } from 'explainer-kit/cutaway';
import type { Dial } from 'cutaway-kit';
import { initialState, type A02State } from './state';
import { buildWatch, WATCH_ORDER, LEAD, GAP } from './watch';
import { ANCHORS, SHOTS, SPOTS } from './layout';
import { LIVE } from './live';
import { output } from '../../sim/bias';

type D = Director<A02State>;
const cam = (k: keyof typeof SHOTS): Partial<A02State> => ({ camX: SHOTS[k].x, camY: SHOTS[k].y, camW: SHOTS[k].w, camH: SHOTS[k].h });

/** Unit A02 for the engine: its state, the narrated watch and the live numbers. */
export const A02: UnitDef<A02State> = { initial: initialState, watch: { order: WATCH_ORDER, lead: LEAD, gap: GAP, build: buildWatch }, live: LIVE };

/** Every drawn part a tap can open, from the layout's outlines (first match wins). */
export const HOTSPOTS: Hotspot[] = Object.entries(SPOTS).map(([part, sp]) => ({
  part, term: sp.term, dot: sp.dot,
  hits: (x, y) => !!sp.discs?.some(([cx, cy, r]) => Math.hypot(x - cx, y - cy) <= r) || !!sp.boxes?.some(([a, b, c, e]) => x >= a && x <= c && y >= b && y <= e),
}));

/** Hand 0 turns the weight dial, hand 1 the bias dial; each lights its own dashed ring. */
export const controls = (dials: [Dial, Dial], p: Projector): Control<A02State>[] => dials.map((dl, i) => ({
  hand: dialHand(dl, p),
  key: i ? 'b' : 'w', glow: i ? 'hiB' : 'hiW',
}));

const lampTo = (d: D, name: string): void => { const [x, y] = ANCHORS[name]; Object.assign(d.goal, { lampX: x, lampY: y }); d.wake(); };
const reading = (d: D, x: number): number => output(d.hands[0].value(), x, d.hands[1].value());
const onTarget = (d: D, x: number, t: number): boolean => Math.abs(reading(d, x) - t) < 1e-6;

const DRIVE: GuidedStep<A02State>[] = [
  { hand: 0, ask: 'd1', ok: 'd1ok', done: all(handAt(0, 1), settled), enter: (d) => lampTo(d, 'dialW'), after: (d) => lampTo(d, 'gauge') },
  { hand: 1, ask: 'd2', ok: 'd2ok', hint: 'd2hint', done: all<A02State>((d) => onTarget(d, 0, 1.5), settled),
    enter: (d) => lampTo(d, 'dialB'), after: (d) => { lampTo(d, 'mark'); d.goal.markGlow = 1; } },
];

/** A click-budget round: input x, mark t, at most `budget` detents of rest-to-rest movement across both dials (spring overshoot is free). */
function round(id: string, x: number, t: number, budget: number): Round<A02State> {
  let last = [0, 0];
  const spent = (d: D): number => d.s.clicks;
  return {
    ask: id, pass: id + 'ok', fail: id + 'miss', hints: [id + 'hint'], hands: [0, 1],
    setup: (d) => {
      Object.assign(d.goal, { x, target: t, markGlow: 0.25 });
      d.controls.forEach((c) => { c.hand.place(0); d.s[c.key] = 0; });
      last = [0, 0]; d.s.clicks = 0; d.s.budget = budget;
      lampTo(d, 'dialW');
    },
    update: (d) => d.hands.forEach((h, i) => {
      const v = h.value();
      if (h.settled() && v !== last[i]) { d.s.clicks += Math.round(Math.abs(v - last[i]) / (h instanceof DetentHand ? h.g.step : 1)); last[i] = v; }
    }),
    verdict: (d) => {
      if (onTarget(d, x, t) && settled(d)) return true;
      if (spent(d) > budget || (spent(d) === budget && settled(d))) return false;
      return null;
    },
  };
}

const ROUNDS: Round<A02State>[] = [round('r1', 2, 3, 6), round('r2', 1, -2, 4)];

/** Watch → drive (two spoken steps) → click-budget puzzle (two rounds) → end card. */
export const beats = (d: D): Record<string, Beat> => ({
  watch: new WatchBeat(d, { next: 'drive', exitGoal: (s) => ({ ...cam('drive'), lampX: s.lampX, lampY: s.lampY }) }),
  drive: new GuidedPlay(d, 'drive', DRIVE, { next: 'ex', enter: (x) => Object.assign(x.goal, { ...cam('drive'), lampOn: 1, exposure: 1, markOn: 1, markGlow: 0.25, x: 0, src: 1, target: 1.5 }) }),
  ex: new Exercise(d, 'ex', ROUNDS, { next: 'end', label: 'Puzzle', cta: 'Finish',
    enter: (x) => Object.assign(x.goal, { ...cam('drive'), tallyOn: 1 }), exit: (x) => { delete x.goal.tallyOn; x.s.tallyOn = 0; } }),
  end: new EndBeat(d, 'Next: many neurons'),
});
