import type { Zoom } from '../play/zoom';
import type { Panner, PointerRouter, Grabbable } from '../play/pointer';

const svg = (d: string): string => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${d}"/></svg>`;
const ICON = {
  in: svg('M11 5h2v6h6v2h-6v6h-2v-6H5v-2h6z'),
  out: svg('M5 11h14v2H5z'),
  /** Four corner marks: the whole drawing. */
  fit: svg('M4 4h6v2H6v4H4zM14 4h6v6h-2V6h-4zM4 14h2v4h4v2H4zM18 14h2v6h-6v-2h4z'),
};
/** Wheel zoom per pixel of Ctrl+wheel delta (a trackpad pinch arrives as Ctrl+wheel). */
const WHEEL = 0.0025;
/** Zoom factor per mouse-wheel notch. */
const NOTCH = 1.2;

/** A mouse-wheel notch, not a trackpad scroll: a line or page delta (Firefox), or a vertical pixel delta whose legacy `wheelDeltaY` is whole notches of 120 (Chromium, Safari). */
export function wheelNotches(e: { deltaMode: number; deltaX: number; deltaY: number; wheelDeltaY?: number }): number {
  if (e.deltaMode === 1) return -e.deltaY / 3;
  if (e.deltaMode === 2) return -e.deltaY;
  const w = e.wheelDeltaY ?? 0;
  return e.deltaX === 0 && w !== 0 && w % 120 === 0 ? w / 120 : 0;
}

/**
 * The drawing's zoom control (Humble Object over `Zoom`): + / − / whole-drawing buttons, the mouse wheel, Ctrl+wheel and trackpad pinch about the pointer,
 * a two-finger pinch on touch, and bare-paper drags through the router's `pan`. Every change calls `changed`; nothing here touches a beat.
 */
export class ZoomControl {
  readonly el: HTMLElement;
  private touches = new Map<number, [number, number]>();
  private pinch: { d: number; z: number } | null = null;
  private router: { cancel(): void } | null = null;
  private zoom: Zoom; private canvas: HTMLElement; private changed: () => void;
  constructor(zoom: Zoom, canvas: HTMLElement, root: HTMLElement, changed: () => void) {
    this.zoom = zoom; this.canvas = canvas; this.changed = changed;
    const el = this.el = document.createElement('div');
    el.className = 'zoom'; el.setAttribute('role', 'group'); el.setAttribute('aria-label', 'Zoom the drawing');
    el.innerHTML = `<button class="btn icon" data-z="in" aria-label="Zoom in (+)">${ICON.in}</button>`
      + `<button class="btn icon" data-z="out" aria-label="Zoom out (−)">${ICON.out}</button>`
      + `<button class="btn icon" data-z="fit" aria-label="Whole drawing (0)">${ICON.fit}</button>`
      + '<span class="zoom-hint" aria-hidden="true">Scroll to zoom</span>';
    root.appendChild(el);
    el.addEventListener('click', (e) => {
      const b = (e.target as HTMLElement).closest('button'); if (!b) return;
      const k = b.dataset.z; if (k === 'in') this.step(1); else if (k === 'out') this.step(-1); else this.reset();
    });
    canvas.addEventListener('wheel', (e) => this.wheel(e), { passive: false });
    canvas.addEventListener('pointerdown', (e) => this.touch(e, true));
    canvas.addEventListener('pointermove', (e) => this.touch(e, false));
    for (const t of ['pointerup', 'pointercancel']) canvas.addEventListener(t, (e) => this.lift(e as PointerEvent));
    this.sync();
  }
  /** Bare-paper drags slide the drawing while zoomed, and a second finger turns the press into a pinch. */
  attach<G extends Grabbable>(router: PointerRouter<G>): void {
    const pan: Panner = { can: () => this.zoom.on, by: (dx, dy) => { this.zoom.pan(dx / this.w(), dy / this.h()); this.sync(); this.changed(); } };
    router.pan = pan;
    this.router = router;
  }
  step(dir: 1 | -1): void { this.zoom.step(dir); this.sync(); this.changed(); }
  reset(): void { this.zoom.reset(); this.sync(); this.changed(); }
  private w(): number { return Math.max(1, this.canvas.clientWidth); }
  private h(): number { return Math.max(1, this.canvas.clientHeight); }
  private at(cx: number, cy: number): [number, number] { const r = this.canvas.getBoundingClientRect(); return [(cx - r.left) / this.w(), (cy - r.top) / this.h()]; }
  private wheel(e: WheelEvent): void {
    const n = e.ctrlKey ? 0 : wheelNotches(e as WheelEvent & { wheelDeltaY?: number });
    if (!e.ctrlKey && !n) return;
    e.preventDefault();
    const dy = e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY;
    this.zoom.by(e.ctrlKey ? Math.exp(-dy * WHEEL) : NOTCH ** n, ...this.at(e.clientX, e.clientY));
    this.sync(); this.changed();
  }
  private touch(e: PointerEvent, down: boolean): void {
    if (e.pointerType !== 'touch' || (!down && !this.touches.has(e.pointerId))) return;
    this.touches.set(e.pointerId, [e.clientX, e.clientY]);
    if (this.touches.size < 2) return;
    const [a, b] = [...this.touches.values()], d = Math.max(1, Math.hypot(a[0] - b[0], a[1] - b[1]));
    if (!this.pinch) { this.router?.cancel(); this.pinch = { d, z: this.zoom.z }; return; }
    this.zoom.at(this.pinch.z * (d / this.pinch.d), ...this.at((a[0] + b[0]) / 2, (a[1] + b[1]) / 2));
    this.sync(); this.changed();
  }
  private lift(e: PointerEvent): void {
    this.touches.delete(e.pointerId);
    if (this.touches.size < 2) this.pinch = null;
  }
  /** Buttons at the ends of the range are disabled. */
  private sync(): void {
    const q = (k: string): HTMLButtonElement => this.el.querySelector(`[data-z="${k}"]`)!;
    q('in').disabled = this.zoom.z >= 3 - 1e-3; q('out').disabled = !this.zoom.on; q('fit').disabled = !this.zoom.on;
    this.el.dataset.zoomed = this.zoom.on ? 'true' : 'false';
  }
}
