import { Spring } from './spring';
import type { Grabbable, Projector } from './pointer';

const clamp = (x: number, a: number, b: number): number => Math.min(b, Math.max(a, x));
const K_DRAG = 1300, D_DRAG = 90, K_REST = 600, D_REST = 26;

/** A dial as the hand sees it: where it is, its detent scale, and the style's value ↔ angle mapping. */
export interface DialGeom { cx: number; cy: number; r: number; min: number; max: number; step: number; angle(v: number): number; value(a: number): number }

/** Anything the learner moves by pointer or keys (Strategy): a dial, a pencil on a scale, a part carried to a seat, a locked input. */
export interface Hand extends Grabbable {
  grabbed: boolean;
  /** Called when the value lands on a new step (a detent, a snap, a seat). */
  onDetent: (value: number) => void;
  /** Keyboard path: n steps up (positive) or down. */
  turn(n: number): void;
  /** Nearest allowed value to `v`. */
  snap(v: number): number;
  /** The value the hand is on now. */
  value(): number;
  settled(): boolean;
  /** Put the hand on `v` at once (a new case, a restored step); not a learner move. */
  place(v: number): void;
  /** Advance one frame; returns the value to draw (it may ease between steps). */
  update(dt: number): number;
}

/** Turns a dial by dragging around its centre (or by keys); it settles into detents through a spring. Drags closer than half the
 * on-screen radius (24 px at most) to the centre turn it less, so a small dial still turns a full sweep. */
export class DetentHand implements Hand {
  enabled = false;
  grabbed = false;
  readonly spring: Spring;
  onDetent: (value: number) => void = () => undefined;
  private target = 0; private goal: number | null = null; private last: [number, number] = [0, 0]; private centre: [number, number] = [0, 0]; private near = 24; private detent = 0;
  private lo: number; private hi: number;
  readonly g: DialGeom; private proj: Projector;

  constructor(g: DialGeom, proj: Projector, limit = Infinity) {
    this.g = g; this.proj = proj;
    this.lo = Math.min(g.angle(g.min), g.angle(g.max)); this.hi = Math.max(g.angle(g.min), g.angle(g.max));
    this.spring = new Spring(-limit, limit);
  }
  hits(wx: number, wy: number): boolean { return Math.hypot(wx - this.g.cx, wy - this.g.cy) <= this.g.r; }
  down(px: number, py: number): void { this.grabbed = true; this.goal = null; this.target = this.spring.a; this.last = [px, py]; this.centre = this.proj.toScreen(this.g.cx, this.g.cy);
    const e = this.proj.toScreen(this.g.cx + this.g.r, this.g.cy);
    this.near = Math.min(24, Math.hypot(e[0] - this.centre[0], e[1] - this.centre[1]) / 2);
  }
  move(px: number, py: number): void {
    const rx = this.last[0] - this.centre[0], ry = -(this.last[1] - this.centre[1]);
    const dx = px - this.last[0], dy = -(py - this.last[1]);
    this.target = clamp(this.target + (rx * dy - ry * dx) / Math.max(rx * rx + ry * ry, this.near * this.near), this.lo, this.hi);
    this.last = [px, py];
  }
  up(): void { this.grabbed = false; this.goal = null; this.target = this.g.angle(this.value()); }
  /** Keyboard path: n detents up (positive) or down, from the detent the last press aimed at (presses faster than the spring add up). */
  turn(n: number): void {
    this.goal = clamp((this.goal ?? this.value()) + n * this.g.step, this.g.min, this.g.max);
    this.target = this.g.angle(this.goal);
  }
  /** Nearest detent to `v`. */
  snap(v: number): number { return clamp(this.g.min + Math.round((v - this.g.min) / this.g.step) * this.g.step, this.g.min, this.g.max); }
  /** Detent value nearest to where the knob physically is. */
  value(): number { return this.snap(this.g.value(this.spring.a)); }
  settled(): boolean { return !this.grabbed && Math.abs(this.spring.v) < 0.05 && Math.abs(this.spring.a - this.g.angle(this.value())) < 0.02; }
  place(v: number): void { this.spring.set(this.g.angle(v)); this.target = this.spring.a; this.goal = null; this.detent = v; }
  /** Step the spring; returns the continuous value for drawing (the knob moves smoothly between detents). */
  update(dt: number): number {
    if (this.grabbed) {
      const nearest = this.g.angle(this.snap(this.g.value(this.target)));
      this.spring.drive(this.target + (nearest - this.target) * 0.45, K_DRAG, D_DRAG);
    } else this.spring.drive(this.target, K_REST, D_REST);
    this.spring.step(dt);
    const v = this.value();
    if (v !== this.detent) { this.detent = v; this.onDetent(v); }
    return this.g.value(this.spring.a);
  }
}
