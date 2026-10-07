import type { Explained, View } from '../../src/unit/ports';
import type { LabelMode } from '../../src/unit/beats';
import type { Item } from '../../src/place/place';
import { DetentHand } from '../../src/play/hand';
import type { Projector } from '../../src/play/pointer';
import { Zoom } from '../../src/play/zoom';

type Box = { x: number; y: number; w: number; h: number };
/** The Cutaway stage as the view needs it (structural: cutaway-kit's `Stage` or a plate's own copy). */
export interface CutawayStage {
  readonly el: HTMLElement;
  readonly renderer: { domElement: HTMLElement; compile(scene: unknown, camera: unknown): unknown };
  readonly scene: unknown; readonly camera: unknown;
  /** Stage size in CSS px and px per drawing unit (screen-constant parts size themselves with these). */
  readonly W: number; readonly H: number; readonly s: number;
  cx: number; cy: number;
  frame(b: Box): void; span(): [number, number]; render(): void; resize(): void;
  /** Put the camera at an exact look (the learner's zoom over the framed shot); without it the view does not zoom. */
  look?(s: number, cx: number, cy: number): void;
  toScreen(x: number, y: number): [number, number]; toWorld(px: number, py: number): [number, number];
}
/** A plate: draws a state; the focus lamp, exposure veil and the callout note are optional. */
export interface CutawayFigure<S> {
  apply(s: S, dt: number, run: boolean): void;
  /** After the shot is framed, before the render: size screen-constant parts (the callout note) to the stage. */
  frame?(stage: CutawayStage): void;
  /** Draw the callout (dot, leader, note) or clear it; `light` outlines one part (its number is hovered). */
  explain?(c: Explained | null): void;
  light?(part: string | null): void;
  /** Named leader labels, or numbers only: in `numbered` no named label is drawn, whatever the state says. */
  labels?(mode: LabelMode): void;
  /** What is drawn now, in drawing units (tests check the layout rules on it). */
  layout?(): Item[];
  /** What of the drawn note is under screen point (px, py). */
  noteAt?(px: number, py: number, stage: CutawayStage): 'hear' | 'close' | 'inside' | null;
  lamp?: { set(x: number, y: number, on: number, span: number): void };
  veil?: { set(cx: number, cy: number, w: number, h: number, exposure: number): void };
}
/** The state keys every Cutaway plate carries: the shot box, the focus lamp and the exposure. */
export interface CutawayState { camX: number; camY: number; camW: number; camH: number; lampX: number; lampY: number; lampOn: number; exposure: number }

export const CAMERA_KEYS = ['camX', 'camY', 'camW', 'camH'] as const;
const UNITS = { camX: 0.5, camY: 0.5, camW: 0.5, camH: 0.5, lampX: 0.5, lampY: 0.5 };
/** Director easing for Cutaway: the camera eases slower and snaps under reduced motion; camera and lamp (drawing units) land within 0.5. */
export const cutawayEasing = { rates: { camX: 1.5, camY: 1.5, camW: 1.5, camH: 1.5 }, eps: UNITS, snap: [...CAMERA_KEYS] };

/** A cutaway-kit `Dial` as the hand needs it (structural). */
export interface CutawayDial { cx: number; cy: number; r: number; scale: { min: number; max: number; step: number }; angle(v: number): number; value(a: number): number }
/** A detent hand on a cutaway-kit Dial: grab radius `r + pad`, spring overshoot capped at `limit` radians. */
export function dialHand(dial: CutawayDial, proj: Projector, limit = 2.4, pad = 10): DetentHand {
  const { min, max, step } = dial.scale;
  return new DetentHand({ cx: dial.cx, cy: dial.cy, r: dial.r + pad, min, max, step, angle: (v) => dial.angle(v), value: (a) => dial.value(a) }, proj, limit);
}

/** Cutaway style adapter: state → plate parts → shot → lamp and veil → one render. */
export class CutawayView<S extends CutawayState> implements View<S> {
  readonly el: HTMLElement; readonly canvas: HTMLElement;
  /** The learner's zoom: kept across chapters, applied over every shot. */
  readonly zoom?: Zoom;
  private stage: CutawayStage; private fig: CutawayFigure<S>;
  constructor(stage: CutawayStage, fig: CutawayFigure<S>) { this.stage = stage; this.fig = fig; this.el = stage.el; this.canvas = stage.renderer.domElement; if (stage.look) this.zoom = new Zoom(); }
  draw(s: S, dt: number, run: boolean): void {
    const st = this.stage;
    this.fig.apply(s, dt, run);
    st.frame({ x: s.camX, y: s.camY, w: s.camW, h: s.camH });
    if (this.zoom) {
      const [fx, fy] = st.toScreen(s.camX, s.camY), [l, t] = st.toScreen(s.camX - s.camW / 2, s.camY + s.camH / 2), [r, b] = st.toScreen(s.camX + s.camW / 2, s.camY - s.camH / 2);
      this.zoom.focus = [fx / st.W, fy / st.H]; this.zoom.shot = [l / st.W, t / st.H, r / st.W, b / st.H];
    }
    if (this.zoom?.on) { const l = this.zoom.look(st, st.W, st.H); st.look!(l.s, l.cx, l.cy); }
    const [sw, sh] = st.span();
    this.fig.lamp?.set(s.lampX, s.lampY, s.lampOn, Math.max(sw, sh));
    this.fig.veil?.set(st.cx, st.cy, sw, sh, s.exposure);
    this.fig.frame?.(st);
    st.render();
  }
  explain(c: Explained | null): void { this.fig.explain?.(c); }
  light(part: string | null): void { this.fig.light?.(part); }
  labels(mode: LabelMode): void { this.fig.labels?.(mode); }
  layout(): Item[] { return this.fig.layout?.() ?? []; }
  noteAt(px: number, py: number): 'hear' | 'close' | 'inside' | null { return this.fig.noteAt?.(px, py, this.stage) ?? null; }
  resize(): void { this.stage.resize(); }
  prepare(): void { this.stage.renderer.compile(this.stage.scene, this.stage.camera); }
  toWorld(px: number, py: number): [number, number] { return this.stage.toWorld(px, py); }
  toScreen(x: number, y: number): [number, number] { return this.stage.toScreen(x, y); }
}
