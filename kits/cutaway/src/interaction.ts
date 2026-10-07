import type { Stage } from './stage';
import type { Dial } from './parts/instruments';

const clamp = (x: number, a: number, b: number): number => Math.min(b, Math.max(a, x));
const K_DRAG = 1300, D_DRAG = 90, K_REST = 600, D_REST = 26, H = 1 / 120;

/** A damped spring on one hinge at a fixed 120 Hz step: the knob has weight and settles into detents. */
export class Spring {
  a = 0; v = 0; private t = 0; private k = 0; private d = 0;
  drive(t: number, k: number, d: number): void { this.t = t; this.k = k; this.d = d; }
  set(a: number): void { this.a = a; this.v = 0; this.t = a; }
  step(dt: number): void {
    const n = Math.ceil(dt / H), h = dt / n;
    for (let i = 0; i < n; i++) { this.v += (this.k * (this.t - this.a) - this.d * this.v) * h; this.a += this.v * h; }
  }
}

/** Turns a Dial by dragging around its centre (or by keys); it settles into the scale's detents through a spring. */
export class DialHand {
  enabled = true;
  grabbed = false;
  readonly spring = new Spring();
  onDetent: (value: number) => void = () => undefined;
  private target = 0; private last: [number, number] = [0, 0]; private centre: [number, number] = [0, 0]; private detent = NaN;
  private lo: number; private hi: number;

  constructor(readonly dial: Dial, private stage: Stage, v = dial.scale.origin) {
    this.lo = Math.min(dial.angle(dial.scale.min), dial.angle(dial.scale.max));
    this.hi = Math.max(dial.angle(dial.scale.min), dial.angle(dial.scale.max));
    this.place(v);
  }
  hits(wx: number, wy: number): boolean { return Math.hypot(wx - this.dial.cx, wy - this.dial.cy) <= this.dial.r + 10; }
  down(px: number, py: number): void { this.grabbed = true; this.target = this.spring.a; this.last = [px, py]; this.centre = this.stage.toScreen(this.dial.cx, this.dial.cy); }
  move(px: number, py: number): void {
    const rx = this.last[0] - this.centre[0], ry = -(this.last[1] - this.centre[1]);
    const dx = px - this.last[0], dy = -(py - this.last[1]);
    this.target = clamp(this.target + (rx * dy - ry * dx) / Math.max(rx * rx + ry * ry, 24 * 24), this.lo, this.hi);
    this.last = [px, py];
  }
  up(): void { this.grabbed = false; this.target = this.dial.angle(this.value()); }
  /** Keyboard path: n detents up (positive) or down. */
  turn(n: number): void { const s = this.dial.scale; this.target = this.dial.angle(clamp(this.value() + n * s.step, s.min, s.max)); }
  /** Detent value nearest to where the knob physically is. */
  value(): number { const s = this.dial.scale; return clamp(s.min + Math.round((this.dial.value(this.spring.a) - s.min) / s.step) * s.step, s.min, s.max); }
  settled(): boolean { return !this.grabbed && Math.abs(this.spring.v) < 0.05 && Math.abs(this.spring.a - this.dial.angle(this.value())) < 0.02; }
  place(v: number): void { this.spring.set(this.dial.angle(v)); this.target = this.spring.a; this.detent = v; }
  /** Step the spring; returns the continuous value for drawing (the knob moves smoothly between detents). */
  update(dt: number): number {
    if (this.grabbed) {
      const s = this.dial.scale, raw = this.dial.value(this.target);
      const nearest = this.dial.angle(clamp(s.min + Math.round((raw - s.min) / s.step) * s.step, s.min, s.max));
      this.spring.drive(this.target + (nearest - this.target) * 0.45, K_DRAG, D_DRAG);
    } else this.spring.drive(this.target, K_REST, D_REST);
    this.spring.step(dt);
    const v = this.value();
    if (v !== this.detent) { this.detent = v; this.onDetent(v); }
    return this.dial.value(this.spring.a);
  }
}

/** Routes pointer events on the canvas to the enabled dial under the pointer. */
export class PointerRouter {
  private active: DialHand | null = null;
  onActivity: () => void = () => undefined;
  constructor(private el: HTMLElement, private stage: Stage, private hands: DialHand[]) {
    el.style.touchAction = 'none';
    el.addEventListener('pointerdown', (e) => this.down(e));
    el.addEventListener('pointermove', (e) => this.move(e));
    const up = (): void => { this.active?.up(); this.active = null; this.el.style.cursor = ''; this.onActivity(); };
    el.addEventListener('pointerup', up); el.addEventListener('pointercancel', up);
  }
  private px(e: PointerEvent): [number, number] { const r = this.el.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; }
  private pick(e: PointerEvent): DialHand | null {
    const [wx, wy] = this.stage.toWorld(...this.px(e));
    return this.hands.find((d) => d.enabled && d.hits(wx, wy)) ?? null;
  }
  private down(e: PointerEvent): void {
    const d = this.pick(e); if (!d) return;
    this.el.setPointerCapture(e.pointerId);
    this.active = d; this.el.style.cursor = 'grabbing'; d.down(...this.px(e)); this.onActivity();
  }
  private move(e: PointerEvent): void {
    if (this.active) { this.active.move(...this.px(e)); this.onActivity(); return; }
    if (e.pointerType === 'mouse') this.el.style.cursor = this.pick(e) ? 'grab' : '';
  }
}
