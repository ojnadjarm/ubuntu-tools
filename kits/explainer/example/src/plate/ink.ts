import * as THREE from 'three';
import { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/addons/lines/LineSegmentsGeometry.js';
import { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import type { Theme, ColorRole } from './theme';
import type { Segs } from './geom';

export type Weight = 'hair' | 'thin' | 'med' | 'bold' | number;
/** Draw layers (z): later layers cover earlier ones. */
export const Z = { back: 0, shade: 0.5, fill: 1, hatch: 1.5, part: 2, live: 3, line: 4, top: 5, focus: 6, callout: 8, text: 9, veil: 20 };
export const FONT = { label: '"Plex Cond"', mono: '"Plex Mono"', serif: '"Caslon"' };

interface LineEntry { mat: LineMaterial; role: ColorRole; w: Weight }
type Draw = (g: CanvasRenderingContext2D, t: Theme) => void;

/** Text drawn on a canvas in drawing units and rasterised at on-screen resolution. */
export class TextPlate {
  readonly mesh: THREE.Mesh;
  readonly mat: THREE.MeshBasicMaterial;
  private canvas = document.createElement('canvas');
  private tex: THREE.CanvasTexture;
  constructor(readonly w: number, readonly h: number, public draw: Draw, ax = 0, ay = 0) {
    this.tex = new THREE.CanvasTexture(this.canvas);
    this.tex.colorSpace = THREE.SRGBColorSpace;
    this.tex.anisotropy = 4;
    this.mat = new THREE.MeshBasicMaterial({ map: this.tex, transparent: true, depthWrite: false });
    const geo = new THREE.PlaneGeometry(w, h).translate(w / 2 - ax * w, h / 2 - ay * h, 0);
    this.mesh = new THREE.Mesh(geo, this.mat);
  }
  redraw(k: number, t: Theme): void {
    const c = this.canvas, cw = Math.min(4096, Math.ceil(this.w * k)), ch = Math.min(4096, Math.ceil(this.h * k));
    if (c.width !== cw || c.height !== ch) { c.width = cw; c.height = ch; this.tex.dispose(); }
    const g = c.getContext('2d')!;
    g.setTransform(cw / this.w, 0, 0, ch / this.h, 0, 0);
    g.clearRect(0, 0, this.w, this.h);
    this.draw(g, t);
    this.tex.needsUpdate = true;
  }
}

/** The look's single owner (Flyweight registry): shared materials per role, line/fill/text factories, and `paint`. */
export class Ink {
  private lines: LineEntry[] = [];
  private lineCache = new Map<string, LineMaterial>();
  private fills: { mat: THREE.MeshBasicMaterial; role: ColorRole }[] = [];
  private fillCache = new Map<string, THREE.MeshBasicMaterial>();
  private texts: TextPlate[] = [];
  px = 1;
  k = 2;
  constructor(public theme: Theme) {}

  width(w: Weight): number { return typeof w === 'number' ? w : this.theme[w]; }

  /** Line material in drawing-unit width; shared per role and weight unless `own`. */
  line(role: ColorRole, w: Weight, o: { dash?: [number, number]; own?: boolean; opacity?: number } = {}): LineMaterial {
    const key = `${role}|${w}`;
    if (!o.own && !o.dash && this.lineCache.has(key)) return this.lineCache.get(key)!;
    const mat = new LineMaterial({ color: this.theme[role], linewidth: 1, transparent: o.opacity !== undefined, opacity: o.opacity ?? 1, depthWrite: o.opacity === undefined });
    if (o.dash) { mat.dashed = true; mat.dashSize = o.dash[0]; mat.gapSize = o.dash[1]; }
    this.lines.push({ mat, role, w });
    mat.linewidth = this.width(w) * this.px;
    if (!o.own && !o.dash) this.lineCache.set(key, mat);
    return mat;
  }
  /** Change a line's weight later (live quantities). */
  weigh(mat: LineMaterial, w: number): void {
    const e = this.lines.find((x) => x.mat === mat); if (!e) return;
    e.w = w; mat.linewidth = w * this.px;
  }
  fill(role: ColorRole, o: { own?: boolean; opacity?: number } = {}): THREE.MeshBasicMaterial {
    if (!o.own && this.fillCache.has(role)) return this.fillCache.get(role)!;
    const mat = new THREE.MeshBasicMaterial({ color: this.theme[role], transparent: o.opacity !== undefined, opacity: o.opacity ?? 1, depthWrite: o.opacity === undefined });
    this.fills.push({ mat, role });
    if (!o.own) this.fillCache.set(role, mat);
    return mat;
  }

  segs(s: Segs, mat: LineMaterial, z: number): LineSegments2 {
    const l = new LineSegments2(new LineSegmentsGeometry(), mat);
    this.setSegs(l, s);
    l.position.z = z;
    return l;
  }
  setSegs(l: LineSegments2, s: Segs): void {
    const p = new Float32Array((s.length / 2) * 3);
    for (let i = 0, j = 0; i < s.length; i += 2, j += 3) { p[j] = s[i]; p[j + 1] = s[i + 1]; }
    l.geometry.setPositions(p);
    l.visible = s.length >= 4;
    if ((l.material as LineMaterial).dashed) l.computeLineDistances();
  }
  shape(pts: number[], mat: THREE.Material, z: number): THREE.Mesh {
    const sh = new THREE.Shape();
    sh.moveTo(pts[0], pts[1]);
    for (let i = 2; i < pts.length; i += 2) sh.lineTo(pts[i], pts[i + 1]);
    const m = new THREE.Mesh(new THREE.ShapeGeometry(sh), mat);
    m.position.z = z;
    return m;
  }
  disc(cx: number, cy: number, r: number, mat: THREE.Material, z: number, seg = 64): THREE.Mesh {
    const m = new THREE.Mesh(new THREE.CircleGeometry(r, seg), mat);
    m.position.set(cx, cy, z);
    return m;
  }
  text(w: number, h: number, draw: Draw, ax = 0, ay = 0): TextPlate {
    const t = new TextPlate(w, h, draw, ax, ay);
    this.texts.push(t);
    t.redraw(this.k, this.theme);
    return t;
  }

  /** Screen px per drawing unit changed (zoom or resize): re-weigh every line. */
  setPx(px: number): void {
    if (Math.abs(px - this.px) < 1e-4) return;
    this.px = px;
    for (const e of this.lines) e.mat.linewidth = this.width(e.w) * px;
  }
  /** Re-rasterise all text at k device px per unit. */
  raster(k: number): void { this.k = k; for (const t of this.texts) t.redraw(k, this.theme); }
  /** Apply a theme in place: colours, weights, text; nothing is rebuilt. */
  paint(t: Theme): void {
    this.theme = t;
    for (const e of this.lines) { e.mat.color.set(t[e.role]); e.mat.linewidth = this.width(e.w) * this.px; }
    for (const f of this.fills) f.mat.color.set(t[f.role]);
    for (const x of this.texts) x.redraw(this.k, t);
  }
}
