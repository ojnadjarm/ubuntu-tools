/** One neuron with two inputs and no bias: pure, deterministic arithmetic. */
export type Vec2 = [number, number];
export interface NeuronObs { contrib: Vec2; sum: number; out: number; }

export const relu = (x: number): number => Math.max(0, x);

export function forward(w: Vec2, x: Vec2): NeuronObs {
  const contrib: Vec2 = [w[0] * x[0], w[1] * x[1]];
  const sum = contrib[0] + contrib[1];
  return { contrib, sum, out: relu(sum) };
}

export interface Example { x: Vec2; target: number; }

/** Total absolute miss over a set of examples (what the ember columns show). */
export function totalMiss(w: Vec2, ex: Example[]): number {
  return ex.reduce((a, e) => a + Math.abs(forward(w, e.x).out - e.target), 0);
}

/** Mean squared error gradient, the signal the tuner follows. */
export function gradient(w: Vec2, ex: Example[]): Vec2 {
  const g: Vec2 = [0, 0];
  for (const e of ex) {
    const o = forward(w, e.x);
    if (o.sum <= 0) continue;
    const d = (2 * (o.out - e.target)) / ex.length;
    g[0] += d * e.x[0]; g[1] += d * e.x[1];
  }
  return g;
}
