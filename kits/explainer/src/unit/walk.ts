/** One step of a scripted walk: wait `gap` seconds, then act (turn a dial one click, type a row, move the lamp). */
export interface WalkStep { gap: number; run(): void }

/** A scripted sequence driven by frame time (no timers): a hint that works the case, a dial turning its drawn clicks. */
export class Walk {
  private steps: WalkStep[];
  private i = 0;
  private t = 0;
  constructor(steps: WalkStep[]) { this.steps = steps; }
  /** Advance by dt; returns true once every step has run. */
  update(dt: number): boolean {
    this.t += dt;
    while (this.i < this.steps.length && this.t >= this.steps[this.i].gap) { this.t -= this.steps[this.i].gap; this.steps[this.i++].run(); }
    return this.done();
  }
  done(): boolean { return this.i >= this.steps.length; }
  /** Run every step left at once (reduced motion, a skip). */
  finish(): void { while (this.i < this.steps.length) this.steps[this.i++].run(); }
}
