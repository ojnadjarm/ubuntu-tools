/** Every animatable quantity of the plate: the timeline tweens these, parts read them (state = f(t)). */
export interface PlateState {
  exposure: number; lampOn: number; lampX: number; lampY: number;
  camX: number; camY: number; camW: number; camH: number;
  rate: number; flowOn: number; hiDial: number; markOn: number; markGlow: number;
  lblRate: number; lblFlow: number; lblTarget: number; lblName: number; cDial: number; cPipe: number; cGauge: number;
}

export function initialState(): PlateState {
  return {
    exposure: 0, lampOn: 0, lampX: 0, lampY: 0, camX: 0, camY: 0, camW: 1300, camH: 820,
    rate: 0, flowOn: 0, hiDial: 0, markOn: 0, markGlow: 0,
    lblRate: 0, lblFlow: 0, lblTarget: 0, lblName: 0, cDial: 0, cPipe: 0, cGauge: 0,
  };
}
