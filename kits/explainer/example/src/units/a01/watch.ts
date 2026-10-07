import { Timeline, type CueBinder } from 'explainer-kit';
import { ANCHORS } from './layout';
import type { A01State } from './state';

type ShotVars = Pick<A01State, 'camX' | 'camY' | 'camW' | 'camH'>;
const shot = (camX: number, camY: number, camW: number, camH: number): ShotVars => ({ camX, camY, camW, camH });

/** Named framings as boxes in drawing units, fitted to any viewport. */
export const SHOTS = {
  open: shot(0, 15, 2300, 2670),
  full: shot(-35, -45, 1700, 900),
  left: shot(-440, 0, 900, 560),
  dials: shot(-230, 0, 1000, 760),
  right: shot(330, 0, 960, 620),
  gauge: shot(540, 0, 800, 760),
  wall: shot(0, 355, 2000, 1720),
  drive: shot(-20, -45, 1660, 900),
};

export const WATCH_ORDER = ['w1', 'w2', 'w3', 'w4'];
export const LEAD = 3.4, GAP = 0.9;

/** The narrated Watch beat: every visual event is placed on a spoken word (state = f(t)). */
export function buildWatch(s: A01State, cue: CueBinder): Timeline {
  const tl = new Timeline();
  const lamp = (a: keyof typeof ANCHORS, t: number, d = 0.8) => tl.to(s, { lampX: ANCHORS[a].x, lampY: ANCHORS[a].y, duration: d }, t - 0.3);
  const cam = (v: ShotVars, t: number, d = 1.8) => tl.to(s, { ...v, duration: d }, t - 0.4);
  const engrave = (k: keyof A01State, t: number, d = 0.9) => tl.to(s, { [k]: 1, duration: d, ease: 'none' }, t);

  tl.set(s, { ...SHOTS.open, lampOn: 0, exposure: 0, x1: 0, x2: 0, w1: 0, w2: 0, flowOn: 0, chamberOn: 0, markOn: 0, markGlow: 0, net: 0, tuneWall: 0, lblInput: 0, lblWeight: 0, lblOutput: 0, lblTarget: 0, lblNeuron: 0, lblNetwork: 0, cTubes: 0, cDials: 0, cChamber: 0, cValve: 0, cGauge: 0, lampX: ANCHORS.machine.x, lampY: ANCHORS.machine.y }, 0);
  tl.to(s, { exposure: 1, duration: 2.2, ease: 'power1.out' }, 0);
  tl.to(s, { ...SHOTS.full, duration: 3.6, ease: 'power3.inOut' }, 0.1);
  tl.to(s, { lampOn: 1, duration: 0.9, ease: 'power1.in' }, 1.6);

  const w1 = (m: string) => cue.at('w1', m);
  lamp('machine', w1('machine'));
  cam(SHOTS.left, w1('tubes'), 2.0); lamp('tubes', w1('tubes')); engrave('cTubes', w1('tubes'), 0.7);
  tl.to(s, { x1: 2, x2: 1, duration: 1.6, ease: 'power2.out' }, w1('tubes') + 0.6);
  engrave('lblInput', w1('input'));
  lamp('vial1', w1('x1'), 0.6); lamp('vial2', w1('x2'), 0.6);

  const w2 = (m: string) => cue.at('w2', m);
  cam(SHOTS.dials, w2('dials')); lamp('dials', w2('dials')); engrave('cDials', w2('dials'), 0.7);
  tl.to(s, { flowOn: 1, duration: 1.2 }, w2('dials'));
  lamp('dial1', w2('w1up'), 0.6); tl.to(s, { hiDial1: 1, duration: 0.4 }, w2('w1up') - 0.1);
  tl.to(s, { w1: 1.5, duration: 1.6, ease: 'power1.inOut' }, w2('w1up') + 0.35);
  tl.to(s, { hiDial1: 0, duration: 0.5 }, w2('w2down') - 0.3);
  lamp('dial2', w2('w2down'), 0.6); tl.to(s, { hiDial2: 1, duration: 0.4 }, w2('w2down') - 0.1);
  tl.to(s, { w2: -1, duration: 1.5, ease: 'power1.inOut' }, w2('w2down') + 1.0);
  tl.to(s, { hiDial2: 0, duration: 0.5 }, w2('weight'));
  lamp('dials', w2('weight')); engrave('lblWeight', w2('weight'));

  const w3 = (m: string) => cue.at('w3', m);
  cam(SHOTS.right, w3('chamber')); lamp('chamber', w3('chamber')); engrave('cChamber', w3('chamber'), 0.7);
  tl.to(s, { chamberOn: 1, duration: 1.8, ease: 'power2.out' }, w3('chamber') + 0.4);
  lamp('valve', w3('valve')); engrave('cValve', w3('valve'), 0.7);
  tl.to(s, { w1: -0.5, duration: 1.3 }, w3('valve') + 1.3);
  cam(SHOTS.gauge, w3('gauge'), 1.6); lamp('gauge', w3('gauge')); engrave('cGauge', w3('gauge'), 0.7);
  tl.to(s, { w1: 1.5, duration: 1.4 }, w3('gauge') - 0.2);
  engrave('lblOutput', w3('output'));
  tl.to(s, { markOn: 1, markGlow: 1, duration: 0.5, ease: 'back.out(2)' }, w3('target') - 0.25);
  lamp('mark', w3('target'), 0.6); engrave('lblTarget', w3('target'), 0.7);
  tl.to(s, { markGlow: 0.25, duration: 1.2 }, w3('target') + 2.2);

  const w4 = (m: string) => cue.at('w4', m);
  cam(SHOTS.full, w4('recap'), 1.6);
  lamp('tubes', cue.word('w4', 'inputs'), 0.45); lamp('dials', cue.word('w4', 'weights'), 0.45);
  lamp('chamber', cue.word('w4', 'sum'), 0.45); lamp('valve', cue.word('w4', 'valve'), 0.45); lamp('gauge', cue.word('w4', 'output'), 0.45);
  lamp('machine', w4('neuron'), 0.8); engrave('lblNeuron', w4('neuron'), 1.1);
  cam(SHOTS.wall, w4('pull'), 3.2);
  tl.to(s, { net: 0.55, duration: 3.0, ease: 'power1.inOut' }, w4('pull') + 0.6);
  tl.to(s, { net: 1, duration: 1.4 }, w4('network'));
  engrave('lblNetwork', w4('network'), 1.3);
  tl.to(s, { tuneWall: 1, duration: 4.5, ease: 'none' }, w4('tuned'));
  cam(SHOTS.drive, cue.end('w4') - 0.8, 2.6);
  tl.to(s, { net: 0.12, duration: 2.4 }, cue.end('w4') - 0.6);
  tl.to(s, { w1: 0, w2: 0, duration: 1.4 }, cue.end('w4') - 0.4);
  lamp('dial1', cue.end('w4'), 1.0);
  tl.end(cue.end('w4') + 2.2);
  tl.mark('end', cue.end('w4') + 0.2);
  return tl;
}

/** The plate as the Watch beat leaves it (for jumping straight to a later beat). */
export function afterWatch(): Partial<A01State> {
  const d = ANCHORS.dial1;
  return {
    ...SHOTS.drive, exposure: 1, lampOn: 1, flowOn: 1, chamberOn: 1, markOn: 1, markGlow: 0.25, x1: 2, x2: 1, w1: 0, w2: 0,
    lblInput: 1, lblWeight: 1, lblOutput: 1, lblTarget: 1, lblNeuron: 1, lblNetwork: 1, cTubes: 1, cDials: 1, cChamber: 1, cValve: 1, cGauge: 1,
    net: 0.12, tuneWall: 1, lampX: d.x, lampY: d.y,
  };
}
