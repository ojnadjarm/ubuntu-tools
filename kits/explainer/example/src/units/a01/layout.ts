/** Plate geometry in drawing units (y up): Fig. 1 the neuron at the origin, Fig. 2 the network above it. */
export const ROW: [number, number] = [110, -110];
export const L = {
  tubeX: -468, tubeLen: 232, tubeR: 25,
  dialX: -172, dialR: 104, knobR: 44,
  chamberX: 176, chamberHW: 40, chamberH: 340,
  valveX: 318, valveR: 30,
  gaugeX: 500, gaugeR: 118,
  caseW: 1340, caseH: 520,
  netY: 820,
};

/** Named points the camera and the focus lamp can look at. */
export const ANCHORS: Record<string, { x: number; y: number }> = {
  machine: { x: 0, y: 0 },
  tubes: { x: L.tubeX, y: 0 }, vial1: { x: L.tubeX, y: ROW[0] }, vial2: { x: L.tubeX, y: ROW[1] },
  dials: { x: L.dialX, y: 0 }, dial1: { x: L.dialX, y: ROW[0] }, dial2: { x: L.dialX, y: ROW[1] },
  chamber: { x: L.chamberX, y: 0 }, valve: { x: L.valveX, y: 0 },
  gauge: { x: L.gaugeX, y: 0 }, mark: { x: L.gaugeX, y: L.gaugeR },
};
