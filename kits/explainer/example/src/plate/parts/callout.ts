import * as THREE from 'three';
import type { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { Ink, Z, FONT, type TextPlate } from '../ink';
import { circle, partial, polyline } from '../geom';
import type { ColorRole } from '../theme';
import type { Part } from './part';

const clamp01 = (x: number): number => Math.min(1, Math.max(0, x));

/** Typed label: draws the first n characters of `text` (n follows the draw-on progress). */
function typed(ink: Ink, text: string, size: number, role: ColorRole, ax: number, font = FONT.label, weight = 600): { plate: TextPlate; show: (f: number) => void } {
  let n = -1;
  const w = text.length * size * 0.72 + 12, h = size * 1.5;
  const plate = ink.text(w, h, (c, th) => {
    c.fillStyle = th[role]; c.font = `${weight} ${size}px ${font}`; c.textBaseline = 'middle';
    c.letterSpacing = `${(size * 0.08).toFixed(1)}px`;
    c.textAlign = ax === 0 ? 'left' : ax === 1 ? 'right' : 'center';
    c.fillText(text.slice(0, Math.max(0, n)), ax * w, h / 2 + size * 0.04);
  }, ax, 0.5);
  const show = (f: number): void => {
    const m = Math.round(text.length * clamp01(f));
    if (m === n) return;
    n = m; plate.redraw(ink.k, ink.theme); plate.mesh.visible = m > 0;
  };
  return { plate, show };
}

/** Leader-line callout: dots on the part, legs that draw themselves on, then the label types in at the spoken word. */
export class Callout implements Part {
  readonly root = new THREE.Group();
  private lines: LineSegments2[] = [];
  private dots: THREE.Mesh[] = [];
  private label: ReturnType<typeof typed>;
  private last = -1;
  constructor(private ink: Ink, private legs: number[][], at: [number, number], text: string, o: { align?: 'left' | 'right' | 'center'; role?: ColorRole; size?: number; dot?: boolean } = {}) {
    const ax = o.align === 'right' ? 1 : o.align === 'center' ? 0.5 : 0;
    for (const leg of legs) {
      const l = ink.segs([], ink.line('ink', 'thin'), Z.callout); this.lines.push(l); this.root.add(l);
      if (o.dot !== false) { const d = ink.disc(leg[0], leg[1], 3.6, ink.fill('ink'), Z.callout + 0.1, 20); this.dots.push(d); this.root.add(d); }
    }
    this.label = typed(ink, text, o.size ?? 24, o.role ?? 'ink', ax);
    this.label.plate.mesh.position.set(at[0], at[1], Z.text);
    this.root.add(this.label.plate.mesh);
    this.set(0);
  }
  set(p: number): void {
    if (p === this.last) return;
    this.last = p;
    this.root.visible = p > 0.001;
    const f = clamp01(p / 0.55);
    this.legs.forEach((leg, i) => this.ink.setSegs(this.lines[i], polyline(partial(leg, f))));
    this.dots.forEach((d) => d.scale.setScalar(Math.max(0.001, clamp01(p * 6))));
    this.label.show((p - 0.45) / 0.5);
  }
}

/** Numbered balloon (patent style) on a short leader. */
export class Balloon implements Part {
  readonly root = new THREE.Group();
  private leg: LineSegments2;
  private head = new THREE.Group();
  private last = -1;
  constructor(private ink: Ink, private pts: number[], n: number, private r = 15) {
    const [x, y] = pts.slice(-2);
    this.leg = ink.segs([], ink.line('ink', 'hair'), Z.callout);
    this.head.position.set(x, y, 0);
    this.head.add(ink.disc(0, 0, r, ink.fill('paper'), Z.callout + 0.1, 40), ink.segs(circle(0, 0, r, 48), ink.line('ink', 'thin'), Z.callout + 0.2));
    const t = ink.text(2 * r, 2 * r, (c, th) => { c.fillStyle = th.ink; c.font = `500 17px ${FONT.serif}`; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(String(n), r, r + 1); }, 0.5, 0.5);
    t.mesh.position.z = Z.text;
    this.head.add(t.mesh);
    this.root.add(this.leg, this.head);
    this.set(0);
  }
  set(p: number): void {
    if (p === this.last) return;
    this.last = p;
    this.root.visible = p > 0.001;
    const lead = this.pts.slice(0, -2).concat(this.shorten());
    this.ink.setSegs(this.leg, polyline(partial(lead, clamp01(p / 0.6))));
    const s = clamp01((p - 0.5) / 0.35);
    this.head.scale.setScalar(Math.max(0.001, s < 1 ? s * (1.15 - 0.15 * s) : 1));
  }
  private shorten(): number[] {
    const n = this.pts.length, x = this.pts[n - 2], y = this.pts[n - 1], px = this.pts[n - 4], py = this.pts[n - 3], l = Math.hypot(x - px, y - py) || 1;
    return [x - ((x - px) / l) * this.r, y - ((y - py) / l) * this.r];
  }
}

/** Dimension line with arrowheads and extension lines; it draws outward from its centre, then the name types in below. */
export class Dimension implements Part {
  readonly root = new THREE.Group();
  private legs: LineSegments2[];
  private ext: LineSegments2;
  private heads: THREE.Mesh[];
  private label: ReturnType<typeof typed>;
  private last = -1;
  constructor(private ink: Ink, private x0: number, private x1: number, private y: number, private from: number, text: string, size = 30, below = true) {
    const mat = ink.line('ink', 'thin');
    this.legs = [ink.segs([], mat, Z.callout), ink.segs([], mat, Z.callout)];
    this.ext = ink.segs([], ink.line('ink', 'hair'), Z.callout);
    const a = 16, b = 5.5;
    this.heads = [ink.shape([x0, y, x0 + a, y + b, x0 + a, y - b], ink.fill('ink'), Z.callout), ink.shape([x1, y, x1 - a, y + b, x1 - a, y - b], ink.fill('ink'), Z.callout)];
    this.label = typed(ink, text, size, 'ink', 0.5);
    this.label.plate.mesh.position.set((x0 + x1) / 2, y + (below ? -1 : 1) * size * 1.05, Z.text);
    this.root.add(...this.legs, this.ext, ...this.heads, this.label.plate.mesh);
    this.set(0);
  }
  set(p: number): void {
    if (p === this.last) return;
    this.last = p;
    this.root.visible = p > 0.001;
    const f = clamp01(p / 0.55), c = (this.x0 + this.x1) / 2, y = this.y;
    this.ink.setSegs(this.legs[0], [c, y, c + (this.x0 - c) * f, y]);
    this.ink.setSegs(this.legs[1], [c, y, c + (this.x1 - c) * f, y]);
    const e = clamp01((p - 0.35) / 0.3), s = Math.sign(y - this.from), y0 = this.from + s * 8;
    this.ink.setSegs(this.ext, e <= 0 ? [] : [this.x0, y0, this.x0, y0 + (y + s * 14 - y0) * e, this.x1, y0, this.x1, y0 + (y + s * 14 - y0) * e]);
    this.heads.forEach((h) => { h.visible = f >= 1; });
    this.label.show((p - 0.45) / 0.5);
  }
}

/** Detail reference: a dash circle around one small neuron of Fig. 2, linked to Fig. 1 by a leader and a lettered tag at each end. */
export class DetailLink implements Part {
  readonly root = new THREE.Group();
  private ring: LineSegments2;
  private leg: LineSegments2;
  private tags: THREE.Group[] = [];
  private ringPts: number[];
  private last = -1;
  constructor(private ink: Ink, cx: number, cy: number, r: number, private legPts: number[], letter = 'A') {
    this.ringPts = [];
    for (let i = 0; i <= 96; i++) { const a = Math.PI * 1.25 - (i / 96) * Math.PI * 2; this.ringPts.push(cx + Math.cos(a) * r, cy + Math.sin(a) * r); }
    this.ring = ink.segs([], ink.line('ink', 'thin', { dash: [18, 5] }), Z.callout);
    this.leg = ink.segs([], ink.line('ink', 'hair'), Z.callout);
    this.root.add(this.ring, this.leg);
    const n = legPts.length;
    for (const [x, y] of [[this.ringPts[0], this.ringPts[1]], [legPts[n - 2], legPts[n - 1]]]) {
      const g = new THREE.Group(); g.position.set(x, y, 0);
      g.add(ink.disc(0, 0, 16, ink.fill('ink'), Z.callout + 0.2, 40));
      const t = ink.text(32, 32, (c, th) => { c.fillStyle = th.paper; c.font = `600 19px ${FONT.label}`; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(letter, 16, 17); }, 0.5, 0.5);
      t.mesh.position.z = Z.text; g.add(t.mesh);
      this.tags.push(g); this.root.add(g);
    }
    this.set(0);
  }
  set(p: number): void {
    if (p === this.last) return;
    this.last = p;
    this.root.visible = p > 0.001;
    this.ink.setSegs(this.ring, polyline(partial(this.ringPts, clamp01(p / 0.5))));
    this.ink.setSegs(this.leg, polyline(partial(this.legPts, clamp01((p - 0.4) / 0.45))));
    this.tags[0].scale.setScalar(Math.max(0.001, clamp01(p * 5)));
    this.tags[1].scale.setScalar(Math.max(0.001, clamp01((p - 0.8) * 5)));
  }
}
