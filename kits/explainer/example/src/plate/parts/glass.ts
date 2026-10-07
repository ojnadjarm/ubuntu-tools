import * as THREE from 'three';
import type { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import type { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { Ink, Z, FONT } from '../ink';
import { hatch, polyline, rect } from '../geom';
import type { Part } from './part';

const WALL = 5;

/** Bolted flange in section: outline plus dense hatching. */
export function flange(ink: Ink, g: THREE.Group, x0: number, y0: number, x1: number, y1: number): void {
  g.add(ink.shape([x0, y0, x1, y0, x1, y1, x0, y1], ink.fill('paper'), Z.part));
  g.add(ink.segs(hatch(() => true, [x0, y0, x1, y1], 3.4), ink.line('hatch', 'hair'), Z.part + 0.1));
  g.add(ink.segs(rect(x0, y0, x1, y1), ink.line('ink', 'thin'), Z.line));
}

/** Horizontal glass tube in section holding an input as a length of blue liquid, on a 0–3 scale. */
export class Tube implements Part {
  readonly root = new THREE.Group();
  private liquid: THREE.Mesh;
  private meniscus: LineSegments2;
  private inner: number;
  constructor(ink: Ink, cx: number, cy: number, readonly len: number, readonly r: number, readonly max = 3) {
    const x0 = cx - len / 2, x1 = cx + len / 2, ri = r - WALL;
    this.inner = len - 4;
    const g = this.root;
    g.add(ink.shape([x0, cy - ri, x1, cy - ri, x1, cy + ri, x0, cy + ri], ink.fill('glass'), Z.fill));
    this.liquid = new THREE.Mesh(new THREE.PlaneGeometry(1, 2 * ri).translate(0.5, 0, 0), ink.fill('signal'));
    this.liquid.position.set(x0 + 2, cy, Z.live);
    this.meniscus = ink.segs([0, -ri, 0, ri], ink.line('ink', 'thin'), Z.line);
    this.meniscus.position.y = cy;
    const band = (y: number) => hatch(() => true, [x0, y, x1, y + WALL], 3.2);
    g.add(this.liquid, this.meniscus);
    g.add(ink.segs([...band(cy + ri), ...band(cy - r)], ink.line('hatch', 'hair'), Z.hatch));
    g.add(ink.segs([x0, cy + r, x1, cy + r, x0, cy - r, x1, cy - r], ink.line('ink', 'med'), Z.line));
    g.add(ink.segs([x0, cy + ri, x1, cy + ri, x0, cy - ri, x1, cy - ri], ink.line('ink', 'hair'), Z.line));
    g.add(ink.segs([x0 + 16, cy + ri - 5, x0 + len * 0.52, cy + ri - 5], ink.line('glass', 'thin'), Z.top));
    flange(ink, g, x0 - 16, cy - r - 9, x0 + 2, cy + r + 9);
    flange(ink, g, x1 - 2, cy - r - 9, x1 + 16, cy + r + 9);
    const sy = cy - r - 16, tk: number[] = [x0 + 2, sy, x1 - 2, sy];
    for (let i = 0; i <= max * 4; i++) { const x = x0 + 2 + (this.inner * i) / (max * 4), m = i % 4 === 0; tk.push(x, sy, x, sy - (m ? 10 : 5)); }
    g.add(ink.segs(tk, ink.line('ink', 'hair'), Z.line));
    const t = ink.text(len + 20, 22, (c, th) => {
      c.fillStyle = th.inkSoft; c.font = `500 14px ${FONT.mono}`; c.textAlign = 'center'; c.textBaseline = 'middle';
      for (let i = 0; i <= max; i++) c.fillText(String(i), 12 + (this.inner * i) / max, 11);
    }, 0, 0.5);
    t.mesh.position.set(x0 - 10, sy - 22, Z.text);
    g.add(t.mesh);
  }
  set(v: number): void {
    const w = Math.max(0.001, (this.inner * v) / this.max);
    this.liquid.scale.x = w;
    this.meniscus.position.x = this.liquid.position.x + w;
    this.meniscus.visible = v > 0.02;
  }
}

/** Vertical glass chamber: the blue level above the dashed zero line is the sum. */
export class Chamber implements Part {
  readonly root = new THREE.Group();
  private liquid: THREE.Mesh;
  private meniscus: LineSegments2;
  private y0: number; private h: number;
  constructor(ink: Ink, cx: number, cy: number, readonly hw: number, height: number, readonly range = 4.5) {
    const x0 = cx - hw, x1 = cx + hw, y0 = cy - height / 2, y1 = cy + height / 2, xi0 = x0 + WALL, xi1 = x1 - WALL;
    this.y0 = y0 + 2; this.h = height - 4;
    const g = this.root;
    g.add(ink.shape([xi0, y0, xi1, y0, xi1, y1, xi0, y1], ink.fill('glass'), Z.fill));
    this.liquid = new THREE.Mesh(new THREE.PlaneGeometry(xi1 - xi0, 1).translate(0, 0.5, 0), ink.fill('signal'));
    this.liquid.position.set(cx, this.y0, Z.live);
    this.meniscus = ink.segs([xi0, 0, xi1, 0], ink.line('ink', 'thin'), Z.line);
    g.add(this.liquid, this.meniscus);
    const band = (x: number) => hatch(() => true, [x, y0, x + WALL, y1], 3.2);
    g.add(ink.segs([...band(x0), ...band(xi1)], ink.line('hatch', 'hair'), Z.hatch));
    g.add(ink.segs([x0, y0, x0, y1, x1, y0, x1, y1], ink.line('ink', 'med'), Z.line));
    g.add(ink.segs([xi0, y0, xi0, y1, xi1, y0, xi1, y1], ink.line('ink', 'hair'), Z.line));
    g.add(ink.segs([cx - hw * 0.35, y0 + 18, cx - hw * 0.35, y1 - 30], ink.line('glass', 'thin'), Z.top));
    flange(ink, g, x0 - 12, y1 - 2, x1 + 12, y1 + 16);
    flange(ink, g, x0 - 12, y0 - 16, x1 + 12, y0 + 2);
    g.add(ink.segs([xi0, cy, xi1, cy], ink.line('ink', 'thin', { dash: [6, 4] }), Z.top));
    const tk: number[] = [];
    for (let v = -4; v <= 4; v++) { const y = this.levelY(v), m = v % 2 === 0; tk.push(x1 + 2, y, x1 + (m ? 14 : 8), y); }
    g.add(ink.segs(tk, ink.line('ink', 'hair'), Z.line));
    const t = ink.text(40, height, (c, th) => {
      c.fillStyle = th.inkSoft; c.font = `500 13px ${FONT.mono}`; c.textBaseline = 'middle';
      for (const v of [-4, -2, 0, 2, 4]) c.fillText(v > 0 ? `+${v}` : v < 0 ? `−${-v}` : '0', 2, y1 - this.levelY(v));
    }, 0, 0);
    t.mesh.position.set(x1 + 18, y0, Z.text);
    g.add(t.mesh);
  }
  private levelY(sum: number): number { return this.y0 + THREE.MathUtils.clamp(0.5 + sum / (2 * this.range), 0.005, 1) * this.h; }
  set(sum: number, on: number): void {
    const y = this.levelY(sum * on);
    this.liquid.scale.y = Math.max(0.001, y - this.y0);
    this.meniscus.position.y = y;
  }
}

/** Offset a polyline sideways by d (mitred joints). */
function offset(pts: number[], d: number): number[] {
  const n = pts.length / 2, out: number[] = [];
  for (let i = 0; i < n; i++) {
    const a = Math.max(0, i - 1), b = Math.min(n - 1, i + 1);
    let nx = 0, ny = 0;
    for (const [p, q] of [[a, i], [i, b]]) {
      if (p === q) continue;
      const dx = pts[2 * q] - pts[2 * p], dy = pts[2 * q + 1] - pts[2 * p + 1], l = Math.hypot(dx, dy) || 1;
      nx += -dy / l; ny += dx / l;
    }
    const l = Math.hypot(nx, ny) || 1, cos = i > 0 && i < n - 1 ? Math.max(0.5, l / 2) : 1;
    out.push(pts[2 * i] + (nx / l) * (d / cos), pts[2 * i + 1] + (ny / l) * (d / cos));
  }
  return out;
}

/** Pipe in section: two ink walls and a dashed blue core whose weight is the flow and whose dashes run with its sign. */
export class Pipe implements Part {
  readonly root = new THREE.Group();
  private core: LineSegments2;
  private mat: LineMaterial;
  private phase = 0;
  constructor(private ink: Ink, pts: number[], r = 7) {
    const g = this.root;
    g.add(ink.segs([...polyline(offset(pts, r)), ...polyline(offset(pts, -r))], ink.line('ink', 'thin'), Z.part));
    this.mat = ink.line('signal', 2, { dash: [11, 7], own: true });
    this.core = ink.segs(polyline(pts), this.mat, Z.live);
    g.add(this.core);
  }
  update(flow: number, dt: number, gain: number, run: boolean): void {
    const a = Math.min(3, Math.abs(flow) * gain);
    this.core.visible = a > 0.03;
    this.ink.weigh(this.mat, 1.2 + 2.2 * Math.min(1.6, a));
    if (run) this.phase += dt * Math.sign(flow) * Math.min(2.2, 0.6 + Math.abs(flow) * 0.5) * 38;
    this.mat.dashOffset = -this.phase;
  }
}
