import * as THREE from 'three';
import type { Ink } from './ink';
import { frameView, DEFAULT_INSET, type Box, type Inset } from './framing';

/** Space kept under page chrome over the stage, in px. */
const CHROME_GAP = 12;
/** How far down the stage visible page chrome marked `data-stage-top` (a section head) reaches, plus the gap; 0 when there is none. */
function chromeBottom(el: HTMLElement): number {
  if (typeof document === 'undefined') return 0;
  const top = el.getBoundingClientRect().top;
  let y = 0;
  for (const c of document.querySelectorAll<HTMLElement>('[data-stage-top]')) if (!c.hidden && c.offsetHeight) y = Math.max(y, c.getBoundingClientRect().bottom - top + CHROME_GAP);
  return y;
}
/** The stage's insets: `top` reads the larger of what the unit sets and the chrome over the stage, so a shot never sits under a section head. */
class ChromeInset implements Inset {
  bottom: number;
  private base: number; private el: HTMLElement;
  constructor(el: HTMLElement, i: Inset) { this.el = el; this.base = i.top; this.bottom = i.bottom; }
  get top(): number { return Math.max(this.base, chromeBottom(this.el)); }
  set top(v: number) { this.base = v; }
}

/** Renderer + orthographic camera: frames a shot box of drawing units into the free part of the viewport and draws on demand. */
export class Stage {
  readonly renderer: THREE.WebGLRenderer;
  readonly scene = new THREE.Scene();
  readonly camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 100);
  /** Screen px per drawing unit and the camera centre, from the last `frame`. */
  s = 1; cx = 0; cy = 0;
  W = 1; H = 1;
  private shots: Box[] = [];

  readonly inset: Inset;

  constructor(readonly el: HTMLElement, private ink: Ink, inset: Inset = DEFAULT_INSET) {
    this.inset = new ChromeInset(el, inset);
    this.renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(2, devicePixelRatio));
    this.renderer.setClearColor(ink.theme.paper);
    el.appendChild(this.renderer.domElement);
    this.camera.position.z = 50;
    this.scene.add(this.camera);
  }

  /** The framings the plate will use; text is rasterised for the tightest one. */
  setShots(shots: Box[]): void { this.shots = shots; }

  resize(): void {
    this.W = Math.max(1, this.el.clientWidth); this.H = Math.max(1, this.el.clientHeight);
    this.renderer.setSize(this.W, this.H, false);
    const k = Math.max(1, ...this.shots.map((b) => frameView(b, this.W, this.H, this.inset).s)) * this.renderer.getPixelRatio();
    this.ink.raster(Math.min(6, k));
  }

  /** Frame box b (drawing units) into the viewport minus the chrome insets (the top one clears a section head). */
  frame(b: Box): void {
    const f = frameView(b, this.W, this.H, this.inset), c = this.camera;
    this.s = f.s; this.cx = f.cx; this.cy = f.cy;
    [c.left, c.bottom, c.right, c.top] = f.view;
    c.updateProjectionMatrix();
    this.ink.setPx(f.s);
  }
  /** Put the camera at an exact look (the learner's zoom); text is re-rasterised, in half steps, once it is drawn finer than its raster. */
  look(s: number, cx: number, cy: number): void {
    const c = this.camera, hw = this.W / (2 * s), hh = this.H / (2 * s);
    this.s = s; this.cx = cx; this.cy = cy;
    [c.left, c.bottom, c.right, c.top] = [cx - hw, cy - hh, cx + hw, cy + hh];
    c.updateProjectionMatrix();
    this.ink.setPx(s);
    const k = s * this.renderer.getPixelRatio();
    if (k > this.ink.k + 0.05 && this.ink.k < 6) this.ink.raster(Math.min(6, Math.ceil(k * 2) / 2));
  }
  /** Visible width and height in drawing units. */
  span(): [number, number] { return [this.W / this.s, this.H / this.s]; }
  toScreen(x: number, y: number): [number, number] { return [(x - this.cx) * this.s + this.W / 2, this.H / 2 - (y - this.cy) * this.s]; }
  toWorld(px: number, py: number): [number, number] { return [(px - this.W / 2) / this.s + this.cx, (this.H / 2 - py) / this.s + this.cy]; }
  render(): void { this.renderer.render(this.scene, this.camera); }
}
