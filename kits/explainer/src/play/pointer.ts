/** Screen pixels ↔ world units; the style's view implements it. */
export interface Projector { toWorld(px: number, py: number): [number, number]; toScreen(x: number, y: number): [number, number] }

/** Something the pointer can grab: hit test in world units, drag in screen pixels. */
export interface Grabbable { enabled: boolean; hits(wx: number, wy: number): boolean; down(px: number, py: number): void; move(px: number, py: number): void; up(): void }

/** Movement (px) before a press on a grabbable counts as a grab; a shorter press is a tap. */
export const SLOP = { mouse: 6, touch: 10 };

interface Press { id: number; g: Grabbable | null; x: number; y: number; lx: number; ly: number; slop: number; grabbed: boolean; panning: boolean; fine: boolean }

/** Drag on bare paper (no grabbable under the press) slides the zoomed drawing; `can()` is false at 1×. */
export interface Panner { can(): boolean; by(dx: number, dy: number): void }

/** Routes pointer input on the canvas: a drag past the slop grabs the enabled grabbable under it; a short press is a tap; a free mouse move is a hover. It sets no cursor. */
export class PointerRouter<G extends Grabbable> {
  private press: Press | null = null;
  /** Bare-paper drags pan through this when it allows it (zoomed); else they stay taps. */
  pan: Panner | null = null;
  onGrab: (g: G) => void = () => undefined;
  onActivity: () => void = () => undefined;
  /** A press that did not move past the slop: screen px, world units, the grabbable under it (if any), and whether a mouse made it. */
  onTap: (px: number, py: number, wx: number, wy: number, g: G | null, fine: boolean) => void = () => undefined;
  /** The pointer moved with no button held (screen px), or left the canvas (null). */
  onHover: (px: number | null, py: number | null) => void = () => undefined;
  private el: HTMLElement; private proj: Projector; private items: G[];
  constructor(el: HTMLElement, proj: Projector, items: G[]) {
    this.el = el; this.proj = proj; this.items = items;
    el.style.touchAction = 'none';
    el.addEventListener('pointerdown', (e) => this.down(e));
    el.addEventListener('pointermove', (e) => this.move(e));
    el.addEventListener('pointerup', (e) => this.up(e));
    el.addEventListener('pointercancel', (e) => { if (e.pointerId === this.press?.id) this.up(null); });
    el.addEventListener('pointerleave', () => { if (!this.press) this.onHover(null, null); });
  }
  private px(e: PointerEvent): [number, number] { const r = this.el.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; }
  private pick(px: number, py: number): G | null {
    const [wx, wy] = this.proj.toWorld(px, py);
    return this.items.find((g) => g.enabled && g.hits(wx, wy)) ?? null;
  }
  private down(e: PointerEvent): void {
    if (this.press) return;
    const [x, y] = this.px(e);
    this.press = { id: e.pointerId, g: this.pick(x, y), x, y, lx: x, ly: y, slop: e.pointerType === 'mouse' ? SLOP.mouse : SLOP.touch, grabbed: false, panning: false, fine: e.pointerType === 'mouse' };
    this.el.setPointerCapture?.(e.pointerId);
  }
  private move(e: PointerEvent): void {
    const [x, y] = this.px(e), p = this.press;
    if (!p) { if (e.pointerType === 'mouse') this.onHover(x, y); return; }
    if (e.pointerId !== p.id) return;
    if (!p.g) {
      if (!p.panning && this.pan?.can() && Math.hypot(x - p.x, y - p.y) >= p.slop) p.panning = true;
      if (p.panning) { this.pan!.by(x - p.lx, y - p.ly); this.onActivity(); }
      p.lx = x; p.ly = y;
      return;
    }
    if (!p.grabbed) {
      if (Math.hypot(x - p.x, y - p.y) < p.slop) return;
      p.grabbed = true;
      p.g.down(p.x, p.y); this.onGrab(p.g as G);
    }
    p.g.move(x, y); this.onActivity();
  }
  /** Drop the press without a tap (a pinch took over): a grabbed hand is let go where it is. */
  cancel(): void { this.up(null); }
  private up(e: PointerEvent | null): void {
    const p = this.press;
    if (!p || (e && e.pointerId !== p.id)) return;
    this.press = null;
    if (p.panning) return;
    if (p.grabbed) { p.g!.up(); this.onActivity(); return; }
    if (!e) return;
    const [x, y] = this.px(e), [wx, wy] = this.proj.toWorld(x, y);
    this.onTap(x, y, wx, wy, p.g as G | null, p.fine);
    this.onActivity();
  }
}
