import { SHOTS } from './layout';

/** Every visible quantity of Plate II: the timeline and the hands write these, the plate reads them (state = f(t)). */
export interface A02State {
  x: number; src: number; w: number; b: number; target: number;
  flowOn: number; colOn: number; markOn: number; markGlow: number; hiW: number; hiB: number;
  lblInput: number; lblWeight: number; lblBias: number; lblOutput: number; lblTarget: number; lblName: number;
  cIn: number; cW: number; cSrc: number; cB: number; cCol: number; cGauge: number;
  tallyOn: number; clicks: number; budget: number;
  lampX: number; lampY: number; lampOn: number;
  camX: number; camY: number; camW: number; camH: number; exposure: number;
}

const o = SHOTS.open;
export function initialState(): A02State {
  return {
    x: 0, src: 0, w: 0, b: 0, target: 1.5,
    flowOn: 0, colOn: 0, markOn: 0, markGlow: 0, hiW: 0, hiB: 0,
    lblInput: 0, lblWeight: 0, lblBias: 0, lblOutput: 0, lblTarget: 0, lblName: 0,
    cIn: 0, cW: 0, cSrc: 0, cB: 0, cCol: 0, cGauge: 0,
    tallyOn: 0, clicks: 0, budget: 0,
    lampX: 0, lampY: 0, lampOn: 0,
    camX: o.x, camY: o.y, camW: o.w, camH: o.h, exposure: 0,
  };
}
