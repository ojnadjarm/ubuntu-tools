import { Timeline, CueBinder } from 'cutaway-kit/motion.ts';
import { SHOTS, ANCHORS } from './layout.ts';
import type { PlateState } from './state.ts';

export const LEAD = 2.6, ORDER = ['s1'];
const cam = (k: keyof typeof SHOTS) => ({ camX: SHOTS[k].x, camY: SHOTS[k].y, camW: SHOTS[k].w, camH: SHOTS[k].h });

/** The narrated plate: every visual event sits on a spoken word (state = f(t)). */
export function buildScript(s: PlateState, cue: CueBinder): Timeline {
  const tl = new Timeline();
  const lamp = (a: string, t: number, d = 0.8) => tl.to(s, { lampX: ANCHORS[a][0], lampY: ANCHORS[a][1], duration: d }, t - 0.3);
  const move = (k: keyof typeof SHOTS, t: number, d = 1.8) => tl.to(s, { ...cam(k), duration: d }, t - 0.4);
  const engrave = (k: keyof PlateState, t: number, d = 0.9) => tl.to(s, { [k]: 1, duration: d, ease: 'none' }, t);
  const at = (m: string) => cue.at('s1', m);

  tl.set(s, { ...cam('open'), exposure: 0, lampOn: 0, rate: 0, flowOn: 0, markOn: 0 }, 0);
  tl.to(s, { exposure: 1, duration: 2.0, ease: 'power1.out' }, 0);
  tl.to(s, { ...cam('full'), duration: 3.0, ease: 'power3.inOut' }, 0.1);
  tl.to(s, { lampOn: 1, duration: 0.9, ease: 'power1.in' }, 1.4);
  lamp('casing', at('casing'));
  move('dial', at('dial')); lamp('dial', at('dial')); engrave('cDial', at('dial'), 0.7);
  tl.to(s, { hiDial: 1, duration: 0.4 }, at('dial'));
  engrave('lblRate', at('rate'));
  tl.to(s, { rate: 2.5, duration: 1.6, ease: 'power1.inOut' }, at('rate') + 0.3);
  tl.to(s, { hiDial: 0, duration: 0.5 }, at('pipe') - 0.3);
  move('full', at('pipe'), 1.6); lamp('pipe', at('pipe')); engrave('cPipe', at('pipe'), 0.7);
  tl.to(s, { flowOn: 1, duration: 1.2 }, at('pipe'));
  engrave('lblFlow', at('flow'));
  move('gauge', at('gauge'), 1.6); lamp('gauge', at('gauge')); engrave('cGauge', at('gauge'), 0.7);
  tl.to(s, { markOn: 1, markGlow: 1, duration: 0.5, ease: 'back.out(2)' }, at('target') - 0.25);
  lamp('mark', at('target'), 0.6); engrave('lblTarget', at('target'), 0.7);
  tl.to(s, { markGlow: 0.25, duration: 1.2 }, at('target') + 2.0);
  move('full', cue.end('s1') - 0.2, 2.2); lamp('dial', cue.end('s1'));
  engrave('lblName', cue.end('s1') + 0.4, 1.1);
  return tl.end(cue.end('s1') + 2.4);
}
