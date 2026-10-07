/** Zoom range and the levels the buttons and keys step through. */
export const ZOOM = { min: 1, max: 3, steps: [1, 1.5, 2, 2.5, 3] };

/** A camera look: px per drawing unit and the centre, in drawing units. */
export interface Look { s: number; cx: number; cy: number }

const clamp = (x: number, a: number, b: number): number => Math.min(b, Math.max(a, x));

/**
 * The learner's zoom over the framed shot (pure, no DOM): screen point p = z·q + u·size, where q is where the 1× frame puts it.
 * `u` (fractions of the stage) stays in [b·(1 − z), a·(1 − z)] for the shot's span a…b on each axis, so the zoomed view never leaves
 * the shot the 1× frame shows between the chrome, and a pan brings each of its edges to the edge of the clear paper.
 */
export class Zoom {
  z = 1; ux = 0; uy = 0;
  /** Stage fraction the buttons and keys zoom about: the view sets it to the shot's centre (the middle of the paper between the chrome). */
  focus: [number, number] = [0.5, 0.5];
  /** Where the 1× frame puts the shot, as stage fractions [left, top, right, bottom]; the view sets it each frame. */
  shot: [number, number, number, number] = [0, 0, 1, 1];
  get on(): boolean { return this.z > 1.0001; }
  /** Zoom to `z` keeping the stage fraction (fx, fy) over the same drawing point. */
  at(z: number, fx = 0.5, fy = 0.5): void {
    const n = clamp(z, ZOOM.min, ZOOM.max), qx = (fx - this.ux) / this.z, qy = (fy - this.uy) / this.z;
    this.z = n; this.ux = fx - n * qx; this.uy = fy - n * qy;
    this.bound();
  }
  /** Multiply the zoom by `k` about (fx, fy): the wheel and the pinch. */
  by(k: number, fx = 0.5, fy = 0.5): void { this.at(this.z * k, fx, fy); }
  /** The next level up (+1) or down (−1) from the buttons and keys. */
  step(dir: 1 | -1, fx = this.focus[0], fy = this.focus[1]): void {
    const s = ZOOM.steps, z = dir > 0 ? s.find((v) => v > this.z + 1e-3) ?? ZOOM.max : [...s].reverse().find((v) => v < this.z - 1e-3) ?? ZOOM.min;
    this.at(z, fx, fy);
  }
  /** Slide the zoomed drawing by (dx, dy) stage fractions. */
  pan(dx: number, dy: number): void { this.ux += dx; this.uy += dy; this.bound(); }
  reset(): void { this.z = 1; this.ux = 0; this.uy = 0; }
  private bound(): void {
    const k = 1 - this.z, span = (a: number, b: number): [number, number] => { const lo = clamp(a, 0, 1), hi = clamp(b, 0, 1); return lo < hi ? [lo, hi] : [0, 1]; };
    const [l, r] = span(this.shot[0], this.shot[2]), [t, b] = span(this.shot[1], this.shot[3]);
    this.ux = clamp(this.ux, r * k, l * k) + 0; this.uy = clamp(this.uy, b * k, t * k) + 0;
  }
  /** The zoomed look from the 1× look `l` on a W × H stage (y up in drawing units, down on screen). */
  look(l: Look, W: number, H: number): Look {
    const s = l.s * this.z, tx = this.ux * W, ty = this.uy * H;
    return { s, cx: l.cx + (W / 2 - (this.z * W) / 2 - tx) / s, cy: l.cy + ((this.z * H) / 2 + ty - H / 2) / s };
  }
}
