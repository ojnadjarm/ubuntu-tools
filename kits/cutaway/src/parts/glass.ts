import * as THREE from 'three';
import type { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { Ink, Z } from '../ink';
import { hatch } from '../geom';
import { FONT, HATCH, type ColorRole } from '../tokens';
import { flange } from './section';
import type { Part } from './part';

const WALL = 5;
const signed = (v: number): string => (v > 0 ? `+${v}` : v < 0 ? `−${-v}` : '0');

/** Horizontal glass tube in section: a filled length of liquid in a primary from `min`, flanged ends, an engraved scale below. */
export class Tube implements Part {
  readonly root = new THREE.Group();
  private liquid: THREE.Mesh;
  private meniscus: LineSegments2;
  private inner: number;
  private x0: number;
  constructor(ink: Ink, cx: number, cy: number, readonly len: number, readonly r: number, readonly max = 3, role: ColorRole = 'blue', readonly min = 0, labelStep = 1) {
    const x0 = cx - len / 2, x1 = cx + len / 2, ri = r - WALL, g = this.root;
    this.inner = len - 4; this.x0 = x0 + 2;
    g.add(ink.shape([x0, cy - ri, x1, cy - ri, x1, cy + ri, x0, cy + ri], ink.fill('glass'), Z.fill));
    this.liquid = new THREE.Mesh(new THREE.PlaneGeometry(1, 2 * ri).translate(0.5, 0, 0), ink.fill(role));
    this.liquid.position.set(this.x0, cy, Z.live);
    this.meniscus = ink.segs([0, -ri, 0, ri], ink.line('ink', 'thin'), Z.line);
    this.meniscus.position.y = cy;
    const band = (y: number) => hatch(() => true, [x0, y, x1, y + WALL], HATCH.band);
    g.add(this.liquid, this.meniscus);
    g.add(ink.segs([...band(cy + ri), ...band(cy - r)], ink.line('hatch', 'hair'), Z.hatch));
    g.add(ink.segs([x0, cy + r, x1, cy + r, x0, cy - r, x1, cy - r], ink.line('ink', 'med'), Z.line));
    g.add(ink.segs([x0, cy + ri, x1, cy + ri, x0, cy - ri, x1, cy - ri], ink.line('ink', 'hair'), Z.line));
    g.add(ink.segs([x0 + 16, cy + ri - 5, x0 + len * 0.52, cy + ri - 5], ink.line('glass', 'thin'), Z.top));
    flange(ink, g, x0 - 16, cy - r - 9, x0 + 2, cy + r + 9);
    flange(ink, g, x1 - 2, cy - r - 9, x1 + 16, cy + r + 9);
    const sy = cy - r - 16, span = max - min, tk: number[] = [x0 + 2, sy, x1 - 2, sy];
    for (let i = 0; i <= span * 4; i++) { const x = this.x0 + (this.inner * i) / (span * 4), m = i % 4 === 0; tk.push(x, sy, x, sy - (m ? 10 : 5)); }
    g.add(ink.segs(tk, ink.line('ink', 'hair'), Z.line));
    const t = ink.text(len + 40, 22, (c, th) => {
      c.fillStyle = th.inkSoft; c.font = `500 14px ${FONT.mono}`; c.textAlign = 'center'; c.textBaseline = 'middle';
      for (let v = min; v <= max + 1e-6; v += labelStep) c.fillText(min < 0 ? signed(v) : String(v), 22 + (this.inner * (v - min)) / span, 11);
    }, 0, 0.5);
    t.mesh.position.set(x0 - 20, sy - 22, Z.text);
    g.add(t.mesh);
  }
  /** Liquid from `min` to v. */
  set(v: number): void { this.fill(this.min, v); }
  /** Liquid between a and b (a stroke or an interval on the scale). */
  fill(a: number, b: number): void {
    const u = (x: number): number => (this.inner * (THREE.MathUtils.clamp(x, this.min, this.max) - this.min)) / (this.max - this.min);
    const lo = Math.min(u(a), u(b)), w = Math.max(0.001, Math.abs(u(b) - u(a)));
    this.liquid.position.x = this.x0 + lo; this.liquid.scale.x = w;
    this.meniscus.position.x = this.x0 + u(b);
    this.liquid.visible = this.meniscus.visible = w > 0.5;
  }
}

/** Vertical glass column in section: the liquid level in a primary stands at the value; a dashed line marks `origin`. */
export class Column implements Part {
  readonly root = new THREE.Group();
  private liquid: THREE.Mesh;
  private meniscus: LineSegments2;
  private y0: number; private h: number; private origin: number;
  constructor(ink: Ink, cx: number, cy: number, readonly hw: number, height: number, readonly min = -4.5, readonly max = 4.5, role: ColorRole = 'blue',
    o: { origin?: number; labels?: number[]; minor?: number; format?: (v: number) => string } = {}) {
    const x0 = cx - hw, x1 = cx + hw, y0 = cy - height / 2, y1 = cy + height / 2, xi0 = x0 + WALL, xi1 = x1 - WALL, g = this.root;
    this.y0 = y0 + 2; this.h = height - 4;
    const origin = this.origin = o.origin ?? THREE.MathUtils.clamp(0, min, max), fmt = o.format ?? (min < 0 ? signed : String);
    g.add(ink.shape([xi0, y0, xi1, y0, xi1, y1, xi0, y1], ink.fill('glass'), Z.fill));
    this.liquid = new THREE.Mesh(new THREE.PlaneGeometry(xi1 - xi0, 1).translate(0, 0.5, 0), ink.fill(role));
    this.liquid.position.set(cx, this.y0, Z.live);
    this.meniscus = ink.segs([xi0, 0, xi1, 0], ink.line('ink', 'thin'), Z.line);
    g.add(this.liquid, this.meniscus);
    const band = (x: number) => hatch(() => true, [x, y0, x + WALL, y1], HATCH.band);
    g.add(ink.segs([...band(x0), ...band(xi1)], ink.line('hatch', 'hair'), Z.hatch));
    g.add(ink.segs([x0, y0, x0, y1, x1, y0, x1, y1], ink.line('ink', 'med'), Z.line));
    g.add(ink.segs([xi0, y0, xi0, y1, xi1, y0, xi1, y1], ink.line('ink', 'hair'), Z.line));
    g.add(ink.segs([cx - hw * 0.35, y0 + 18, cx - hw * 0.35, y1 - 30], ink.line('glass', 'thin'), Z.top));
    flange(ink, g, x0 - 12, y1 - 2, x1 + 12, y1 + 16);
    flange(ink, g, x0 - 12, y0 - 16, x1 + 12, y0 + 2);
    if (origin > min) g.add(ink.segs([xi0, this.levelY(origin), xi1, this.levelY(origin)], ink.line('ink', 'thin', { dash: [6, 4] }), Z.top));
    const minor = o.minor ?? 1, tk: number[] = [];
    const labels = o.labels ?? Array.from({ length: Math.floor(max) - Math.ceil(min) + 1 }, (_, i) => Math.ceil(min) + i).filter((v) => min >= 0 || v % 2 === 0);
    for (let v = Math.ceil(min / minor) * minor; v <= max + 1e-6; v += minor) {
      const y = this.levelY(v), m = labels.some((l) => Math.abs(l - v) < 1e-6);
      tk.push(x1 + 2, y, x1 + (m ? 14 : 8), y);
    }
    g.add(ink.segs(tk, ink.line('ink', 'hair'), Z.line));
    const pad = 12, t = ink.text(44, height + 2 * pad, (c, th) => {
      c.fillStyle = th.inkSoft; c.font = `500 14px ${FONT.mono}`; c.textBaseline = 'middle';
      for (const v of labels) c.fillText(fmt(v), 2, pad + y1 - this.levelY(v));
    }, 0, 0);
    t.mesh.position.set(x1 + 18, y0 - pad, Z.text);
    g.add(t.mesh);
  }
  /** Drawing-unit height of a value on this column (for projection lines to it). */
  levelY(v: number): number { return this.y0 + THREE.MathUtils.clamp((v - this.min) / (this.max - this.min), 0.005, 1) * this.h; }
  /** Level at v; `on` scales it from the origin (0 = level at the origin). */
  set(v: number, on = 1): void {
    const y = this.levelY(this.origin + (v - this.origin) * on);
    this.liquid.scale.y = Math.max(0.001, y - this.y0);
    this.meniscus.position.y = y;
  }
}
