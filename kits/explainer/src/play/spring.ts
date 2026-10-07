const H = 1 / 120;

/** A damped spring on one axis at a fixed 120 Hz step: a knob's weight, or a needle that lags and settles on its value. */
export class Spring {
  a = 0; v = 0; private t = 0; private k = 0; private d = 0;
  private min: number; private max: number;
  constructor(min = -Infinity, max = Infinity) { this.min = min; this.max = max; }
  /** Pull toward `t` with stiffness `k` and damping `d` (per unit inertia). */
  drive(t: number, k: number, d: number): void { this.t = t; this.k = k; this.d = d; }
  set(a: number): void { this.a = a; this.v = 0; this.t = a; }
  step(dt: number): void {
    const n = Math.ceil(dt / H), h = dt / n;
    for (let i = 0; i < n; i++) { this.v += (this.k * (this.t - this.a) - this.d * this.v) * h; this.a = Math.min(this.max, Math.max(this.min, this.a + this.v * h)); }
  }
  resting(eps = 1e-4): boolean { return Math.abs(this.v) < eps && Math.abs(this.a - this.t) < eps; }
}
