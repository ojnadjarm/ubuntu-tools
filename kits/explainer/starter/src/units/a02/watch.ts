import { Timeline, type CueBinder } from 'explainer-kit';
import { ANCHORS, SHOTS } from './layout';
import type { A02State } from './state';

type Cam = Pick<A02State, 'camX' | 'camY' | 'camW' | 'camH'>;
const cam = (k: keyof typeof SHOTS): Cam => ({ camX: SHOTS[k].x, camY: SHOTS[k].y, camW: SHOTS[k].w, camH: SHOTS[k].h });

export const WATCH_ORDER = ['w1', 'w2', 'w3', 'w4'];
export const LEAD = 3.2, GAP = 0.9;

/** The narrated watch: every visual event sits on a spoken word (state = f(t)). */
export function buildWatch(s: A02State, cue: CueBinder): Timeline {
  const tl = new Timeline();
  const lamp = (a: string, t: number, d = 0.8) => tl.to(s, { lampX: ANCHORS[a][0], lampY: ANCHORS[a][1], duration: d }, t - 0.3);
  const move = (k: keyof typeof SHOTS, t: number, d = 1.8) => tl.to(s, { ...cam(k), duration: d }, t - 0.4);
  const engrave = (k: keyof A02State, t: number, d = 0.9) => tl.to(s, { [k]: 1, duration: d, ease: 'none' }, t);

  tl.set(s, { ...cam('open'), exposure: 0, lampOn: 0, lampX: 0, lampY: 0, x: 0, src: 0, w: 0, b: 0, target: 1.5, flowOn: 0, colOn: 0, markOn: 0, markGlow: 0 }, 0);
  tl.to(s, { exposure: 1, duration: 2.2, ease: 'power1.out' }, 0);
  tl.to(s, { ...cam('full'), duration: 3.4, ease: 'power3.inOut' }, 0.1);
  tl.to(s, { lampOn: 1, duration: 0.9, ease: 'power1.in' }, 1.6);

  const w1 = (m: string) => cue.at('w1', m);
  lamp('machine', w1('machine'));
  move('top', w1('input')); lamp('tube', w1('input')); engrave('cIn', w1('input'), 0.7); engrave('lblInput', w1('input') + 0.3);
  tl.to(s, { x: 2, duration: 1.4, ease: 'power2.out' }, w1('input') + 0.2);
  tl.to(s, { flowOn: 1, duration: 1.0 }, w1('input') + 0.6);
  lamp('dialW', w1('weight'), 0.6); engrave('cW', w1('weight'), 0.7); engrave('lblWeight', w1('weight') + 0.2);
  tl.to(s, { hiW: 1, duration: 0.4 }, w1('weight') - 0.1);
  tl.to(s, { w: 1, duration: 1.2, ease: 'power1.inOut' }, w1('weight') + 0.4);
  tl.to(s, { hiW: 0, duration: 0.5 }, w1('gauge') - 0.2);
  move('right', w1('gauge'), 1.6); lamp('gauge', w1('gauge')); engrave('cCol', w1('gauge') - 0.3, 0.7); engrave('cGauge', w1('gauge'), 0.7);
  tl.to(s, { colOn: 1, duration: 1.4, ease: 'power2.out' }, w1('gauge') - 0.2);
  engrave('lblOutput', w1('gauge') + 0.6);

  const w2 = (m: string) => cue.at('w2', m);
  move('full', w2('empty'), 1.6); lamp('tube', w2('empty'));
  tl.to(s, { x: 0, duration: 1.6, ease: 'power2.inOut' }, w2('empty') + 0.3);
  lamp('dialW', w2('zero'), 0.6); tl.to(s, { hiW: 1, duration: 0.4 }, w2('zero'));
  tl.to(s, { w: 2.5, duration: 1.2, ease: 'power1.inOut' }, w2('stuck') + 0.2);
  tl.to(s, { w: -2, duration: 1.6, ease: 'power1.inOut' }, w2('stuck') + 1.5);
  lamp('gauge', w2('stuck') + 2.2, 0.7);
  tl.to(s, { w: 0.5, duration: 1.0, ease: 'power1.inOut' }, w2('stuck') + 3.2);
  tl.to(s, { hiW: 0, duration: 0.5 }, cue.end('w2'));

  const w3 = (m: string) => cue.at('w3', m);
  move('bias', w3('source')); lamp('source', w3('source')); engrave('cSrc', w3('source'), 0.7);
  tl.to(s, { src: 1, duration: 1.2, ease: 'power2.out' }, w3('full'));
  lamp('dialB', w3('bias'), 0.6); engrave('cB', w3('bias') - 0.3, 0.7); engrave('lblBias', w3('bias'));
  tl.to(s, { hiB: 1, duration: 0.4 }, w3('bias') - 0.1);
  tl.to(s, { b: 1, duration: 1.2, ease: 'power1.inOut' }, w3('bias') + 0.5);
  move('full', w3('shift'), 1.6); lamp('gauge', w3('shift'));
  tl.to(s, { b: 2, duration: 1.2, ease: 'power1.inOut' }, w3('shift') + 0.3);
  tl.to(s, { hiB: 0, duration: 0.5 }, w3('always') - 0.3);
  lamp('tube', w3('always'), 0.6);
  tl.to(s, { x: 2, duration: 1.2, ease: 'power1.inOut' }, w3('always') + 0.2);
  lamp('gauge', w3('always') + 1.4, 0.6);

  const w4 = (m: string) => cue.at('w4', m);
  lamp('dialW', w4('recap'), 0.5); tl.to(s, { hiW: 1, duration: 0.3 }, w4('recap'));
  tl.to(s, { w: -0.5, duration: 1.0, ease: 'power1.inOut' }, w4('recap') + 0.3);
  tl.to(s, { hiW: 0, duration: 0.3 }, w4('recap2') - 0.1);
  lamp('dialB', w4('recap2'), 0.5); tl.to(s, { hiB: 1, duration: 0.3 }, w4('recap2'));
  tl.to(s, { b: -1, duration: 1.0, ease: 'power1.inOut' }, w4('recap2') + 0.3);
  tl.to(s, { hiB: 0, duration: 0.3 }, w4('mark') - 0.1);
  tl.to(s, { markOn: 1, markGlow: 1, duration: 0.5, ease: 'back.out(2)' }, w4('mark') - 0.25);
  tl.to(s, { w: 1, b: -0.5, duration: 1.2, ease: 'power1.inOut' }, w4('mark') + 0.2);
  lamp('mark', w4('mark'), 0.6); engrave('lblTarget', w4('mark'), 0.7);
  tl.to(s, { markGlow: 0.25, duration: 1.2 }, w4('mark') + 2.0);
  const e = cue.end('w4');
  move('drive', e - 0.4, 2.4); engrave('lblName', e - 0.2, 1.1);
  tl.to(s, { x: 0, w: 0, b: 0, duration: 1.4 }, e);
  lamp('dialW', e + 0.4, 1.0);
  tl.mark('end', e + 0.2);
  tl.end(e + 2.2);
  return tl;
}

/** The plate as the watch leaves it (for `?beat=` jumps). */
export function afterWatch(): Partial<A02State> {
  return {
    ...cam('drive'), exposure: 1, lampOn: 1, lampX: ANCHORS.dialW[0], lampY: ANCHORS.dialW[1],
    x: 0, src: 1, w: 0, b: 0, target: 1.5, flowOn: 1, colOn: 1, markOn: 1, markGlow: 0.25,
    lblInput: 1, lblWeight: 1, lblBias: 1, lblOutput: 1, lblTarget: 1, lblName: 1, cIn: 1, cW: 1, cSrc: 1, cB: 1, cCol: 1, cGauge: 1,
  };
}
