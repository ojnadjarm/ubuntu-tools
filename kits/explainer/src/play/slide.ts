import type { Hand } from './hand';
import type { Projector } from './pointer';

/** A pencil's track: where it can be picked up, the value under a world point, and its range and snap. */
export interface Track { hits(wx: number, wy: number): boolean; valueAt(wx: number, wy: number): number; min: number; max: number; step: number }

const EASE = 22;

/** A pencil slid along a scale by dragging (or by keys, one snap per press); the learner's own guess, never a goal. */
export class SlideHand implements Hand {
  enabled = false;
  grabbed = false;
  onDetent: (value: number) => void = () => undefined;
  private v = 0; private shown = 0; private said = 0;
  readonly track: Track; private proj: Projector;
  constructor(track: Track, proj: Projector) { this.track = track; this.proj = proj; }
  hits(wx: number, wy: number): boolean { return this.track.hits(wx, wy); }
  down(px: number, py: number): void { this.grabbed = true; this.move(px, py); }
  move(px: number, py: number): void { const [wx, wy] = this.proj.toWorld(px, py); this.v = this.snap(this.track.valueAt(wx, wy)); }
  up(): void { this.grabbed = false; }
  turn(n: number): void { this.v = this.snap(this.v + n * this.track.step); }
  snap(v: number): number {
    const { min, max, step } = this.track;
    return Number(Math.min(max, Math.max(min, min + Math.round((v - min) / step) * step)).toFixed(6));
  }
  value(): number { return this.v; }
  settled(): boolean { return !this.grabbed && Math.abs(this.shown - this.v) < 1e-3; }
  place(v: number): void { this.v = this.shown = this.said = this.snap(v); }
  update(dt: number): number {
    const k = 1 - Math.exp(-EASE * dt);
    this.shown = Math.abs(this.v - this.shown) < 1e-4 ? this.v : this.shown + (this.v - this.shown) * k;
    if (this.v !== this.said) { this.said = this.v; this.onDetent(this.v); }
    return this.shown;
  }
}
