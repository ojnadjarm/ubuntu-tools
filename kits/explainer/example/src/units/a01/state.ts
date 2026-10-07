/** Every animatable quantity of the A01 plate: the timeline tweens these, parts read them (state = f(t)). */
export interface A01State {
  x1: number; x2: number; w1: number; w2: number; target: number;
  flowOn: number; chamberOn: number; markOn: number; markGlow: number; hiDial1: number; hiDial2: number;
  lblInput: number; lblWeight: number; lblOutput: number; lblTarget: number; lblNeuron: number; lblNetwork: number;
  cTubes: number; cDials: number; cChamber: number; cValve: number; cGauge: number;
  lampX: number; lampY: number; lampOn: number;
  camX: number; camY: number; camW: number; camH: number;
  net: number; tuneWall: number; exposure: number;
}

export function initialState(): A01State {
  return {
    x1: 2, x2: 1, w1: 0, w2: 0, target: 2.5,
    flowOn: 0, chamberOn: 0, markOn: 0, markGlow: 0, hiDial1: 0, hiDial2: 0,
    lblInput: 0, lblWeight: 0, lblOutput: 0, lblTarget: 0, lblNeuron: 0, lblNetwork: 0,
    cTubes: 0, cDials: 0, cChamber: 0, cValve: 0, cGauge: 0,
    lampX: 0, lampY: 0, lampOn: 0,
    camX: 0, camY: 150, camW: 2800, camH: 1700,
    net: 0, tuneWall: 0, exposure: 0,
  };
}
