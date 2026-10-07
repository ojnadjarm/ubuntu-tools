import * as THREE from 'three';
import type { Ink } from './ink';

export interface Box { x: number; y: number; w: number; h: number }

/** Renderer + orthographic camera: frames a box of drawing units into the free part of the viewport and draws on demand. */
export class Stage {
  readonly renderer: THREE.WebGLRenderer;
  readonly scene = new THREE.Scene();
  readonly camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 100);
  /** Screen px per drawing unit and the camera centre, from the last `frame`. */
  s = 1; cx = 0; cy = 0;
  W = 1; H = 1;
  private inset = { top: 28, bottom: 164 };
  private shots: Box[] = [];

  constructor(readonly el: HTMLElement, private ink: Ink) {
    this.renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(2, devicePixelRatio));
    this.renderer.setClearColor(ink.theme.paper);
    el.appendChild(this.renderer.domElement);
    this.camera.position.z = 50;
    this.scene.add(this.camera);
  }

  /** The framings the unit will use; text is rasterised for the tightest one. */
  setShots(shots: Box[]): void { this.shots = shots; }

  resize(): void {
    this.W = Math.max(1, this.el.clientWidth); this.H = Math.max(1, this.el.clientHeight);
    this.renderer.setSize(this.W, this.H, false);
    const k = Math.max(1, ...this.shots.map((b) => this.fit(b))) * this.renderer.getPixelRatio();
    this.ink.raster(Math.min(6, k));
  }

  private fit(b: Box): number { return Math.min(this.W / b.w, (this.H - this.inset.top - this.inset.bottom) / b.h); }

  /** Frame box b (drawing units) into the viewport minus the chrome insets. */
  frame(b: Box): void {
    const s = this.fit(b), uc = this.inset.top + (this.H - this.inset.top - this.inset.bottom) / 2;
    this.s = s; this.cx = b.x; this.cy = b.y + (uc - this.H / 2) / s;
    const hw = this.W / (2 * s), hh = this.H / (2 * s), c = this.camera;
    c.left = this.cx - hw; c.right = this.cx + hw; c.top = this.cy + hh; c.bottom = this.cy - hh;
    c.updateProjectionMatrix();
    this.ink.setPx(s);
  }
  /** Visible width and height in drawing units. */
  span(): [number, number] { return [this.W / this.s, this.H / this.s]; }
  toScreen(x: number, y: number): [number, number] { return [(x - this.cx) * this.s + this.W / 2, this.H / 2 - (y - this.cy) * this.s]; }
  toWorld(px: number, py: number): [number, number] { return [(px - this.W / 2) / this.s + this.cx, (this.H / 2 - py) / this.s + this.cy]; }
  render(): void { this.renderer.render(this.scene, this.camera); }
}
