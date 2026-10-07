import * as THREE from 'three';
import { Ink, Z, FONT } from '../ink';
import { circle, hatchPolys, polyline, rect, roundRectPts } from '../geom';
import type { Part } from './part';

/** Push each point of a closed outline inward by a smooth irregular amount: a freehand break line. */
function breakLine(pts: number[], depth: number): number[] {
  const n = pts.length / 2, out: number[] = [];
  let s = 0;
  for (let i = 0; i < n; i++) {
    const p = (i - 1 + n) % n, q = (i + 1) % n;
    const tx = pts[2 * q] - pts[2 * p], ty = pts[2 * q + 1] - pts[2 * p + 1], l = Math.hypot(tx, ty) || 1;
    if (i > 0) s += Math.hypot(pts[2 * i] - pts[2 * i - 2], pts[2 * i + 1] - pts[2 * i - 1]);
    const w = depth + 7 * Math.sin(s * 0.021) + 4.5 * Math.sin(s * 0.057 + 1.3) + 2.2 * Math.sin(s * 0.19 + 0.4);
    out.push(pts[2 * i] - (ty / l) * w, pts[2 * i + 1] + (tx / l) * w);
  }
  return out;
}
/** Resample a closed outline to points about `step` apart (so the break line can wobble along straight edges). */
function resample(pts: number[], step: number): number[] {
  const out: number[] = [], n = pts.length / 2;
  for (let i = 0; i < n; i++) {
    const x0 = pts[2 * i], y0 = pts[2 * i + 1], x1 = pts[(2 * i + 2) % pts.length], y1 = pts[(2 * i + 3) % pts.length];
    const k = Math.max(1, Math.round(Math.hypot(x1 - x0, y1 - y0) / step));
    for (let j = 0; j < k; j++) out.push(x0 + ((x1 - x0) * j) / k, y0 + ((y1 - y0) * j) / k);
  }
  return out;
}

/** The instrument casing with its front cover cut away along a break line; the cut shell is hatched and riveted. */
export class Casing implements Part {
  readonly root = new THREE.Group();
  constructor(ink: Ink, w: number, h: number, centreLines: number[]) {
    const g = this.root, x0 = -w / 2, x1 = w / 2, y0 = -h / 2, y1 = h / 2;
    const outer = roundRectPts(x0, y0, x1, y1, 30, 10);
    const win = breakLine(resample(roundRectPts(x0 + 30, y0 + 30, x1 - 30, y1 - 30, 18, 8), 6), 6);
    g.add(ink.shape(outer, ink.fill('paper'), Z.back));
    g.add(ink.shape(win, ink.fill('paperShade'), Z.shade));
    g.add(ink.segs(hatchPolys([outer, win], [x0, y0, x1, y1], 6.5), ink.line('hatch', 'hair'), Z.hatch));
    g.add(ink.segs(polyline(outer, true), ink.line('ink', 'bold'), Z.line));
    g.add(ink.segs(polyline(roundRectPts(x0 + 7, y0 + 7, x1 - 7, y1 - 7, 24, 10), true), ink.line('ink', 'hair'), Z.line));
    g.add(ink.segs(polyline(win, true), ink.line('ink', 'med'), Z.line));
    const riv: number[] = [];
    const rp = roundRectPts(x0 + 16, y0 + 16, x1 - 16, y1 - 16, 16, 6), per: number[] = [];
    for (let i = 0; i < rp.length; i += 2) per.push(rp[i], rp[i + 1]);
    let acc = 0;
    for (let i = 2; i < per.length; i += 2) {
      acc += Math.hypot(per[i] - per[i - 2], per[i + 1] - per[i - 1]);
      if (acc >= 92) { acc = 0; riv.push(...circle(per[i], per[i + 1], 3.6, 16)); }
    }
    g.add(ink.segs(riv, ink.line('ink', 'thin'), Z.line));
    g.add(ink.segs(centreLines, ink.line('inkSoft', 'hair', { dash: [30, 6] }), Z.shade + 0.1));
  }
}

/** The drawing sheet: double border, zone marks, title block and figure captions. */
export class Sheet implements Part {
  readonly root = new THREE.Group();
  constructor(ink: Ink, box: [number, number, number, number], legend: string[]) {
    const g = this.root, [x0, y0, x1, y1] = box, m = 16;
    g.add(ink.segs(rect(x0, y0, x1, y1), ink.line('ink', 'med'), Z.line));
    g.add(ink.segs(rect(x0 + m, y0 + m, x1 - m, y1 - m), ink.line('ink', 'hair'), Z.line));
    const zt: number[] = [], cols = 8, rows = 6;
    for (let i = 1; i < cols; i++) { const x = x0 + ((x1 - x0) * i) / cols; zt.push(x, y0, x, y0 + m, x, y1, x, y1 - m); }
    for (let i = 1; i < rows; i++) { const y = y0 + ((y1 - y0) * i) / rows; zt.push(x0, y, x0 + m, y, x1, y, x1 - m, y); }
    g.add(ink.segs(zt, ink.line('ink', 'hair'), Z.line));
    const zone = (s: string, x: number, y: number) => {
      const t = ink.text(20, 16, (c, th) => { c.fillStyle = th.inkSoft; c.font = `500 11px ${FONT.mono}`; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(s, 10, 8); }, 0.5, 0.5);
      t.mesh.position.set(x, y, Z.text); g.add(t.mesh);
    };
    for (let i = 0; i < cols; i++) { const x = x0 + ((x1 - x0) * (i + 0.5)) / cols; zone(String(cols - i), x, y0 + m / 2); zone(String(cols - i), x, y1 - m / 2); }
    for (let i = 0; i < rows; i++) { const y = y0 + ((y1 - y0) * (i + 0.5)) / rows; zone('ABCDEF'[i], x0 + m / 2, y); zone('ABCDEF'[i], x1 - m / 2, y); }
    const bw = 560, bh = 176, bx = x1 - m - bw, by = y0 + m;
    g.add(ink.shape([bx, by, bx + bw, by, bx + bw, by + bh, bx, by + bh], ink.fill('paper'), Z.fill));
    g.add(ink.segs(rect(bx, by, bx + bw, by + bh), ink.line('ink', 'thin'), Z.line));
    const t = ink.text(bw, bh, (c, th) => {
      c.strokeStyle = th.ink; c.lineWidth = 1;
      c.beginPath(); c.moveTo(0, 40); c.lineTo(bw, 40); c.moveTo(0, 112); c.lineTo(bw, 112); c.moveTo(380, 40); c.lineTo(380, 112); c.stroke();
      c.textBaseline = 'alphabetic';
      c.fillStyle = th.inkSoft; c.font = `italic 400 17px ${FONT.serif}`; c.fillText('Plate I.', 16, 27);
      c.font = `500 12px ${FONT.mono}`; c.textAlign = 'right'; c.fillText('INSTRUMENT 01 \u00b7 SECTION A\u2013A', bw - 16, 26);
      c.textAlign = 'left'; c.fillText('SCALE 1 : 1', 396, 68); c.fillText('SHEET 1 OF 4', 396, 92);
      c.fillStyle = th.ink; c.font = `600 36px ${FONT.label}`; c.letterSpacing = '4px'; c.fillText('THE NEURON', 16, 92);
      c.letterSpacing = '0px'; c.font = `400 15px ${FONT.label}`;
      legend.forEach((s, i) => c.fillText(`${i + 1}  ${s}`, 16 + (i % 3) * 184, 138 + Math.floor(i / 3) * 24));
    }, 0, 0);
    t.mesh.position.set(bx, by, Z.text);
    g.add(t.mesh);
  }
}

/** Figure caption in the plate's serif italic. */
export function caption(ink: Ink, text: string, x: number, y: number): THREE.Mesh {
  const t = ink.text(420, 30, (c, th) => { c.fillStyle = th.inkSoft; c.font = `italic 400 19px ${FONT.serif}`; c.textBaseline = 'middle'; c.fillText(text, 0, 15); }, 0, 0.5);
  t.mesh.position.set(x, y, Z.text);
  return t.mesh;
}

/** Disc of radius 3 whose vertex alpha rises from 0 inside r = 0.35 to 1 at r = 1 (smooth, no texture banding). */
function washGeometry(): THREE.BufferGeometry {
  const radii = [0, 0.35, 0.5, 0.65, 0.8, 1, 3], seg = 72, pos: number[] = [], col: number[] = [], idx: number[] = [];
  radii.forEach((r) => {
    const a = THREE.MathUtils.smoothstep(r, 0.35, 1);
    for (let i = 0; i < seg; i++) { const t = (i / seg) * Math.PI * 2; pos.push(Math.cos(t) * r, Math.sin(t) * r, 0); col.push(1, 1, 1, a); }
  });
  for (let k = 0; k < radii.length - 1; k++) for (let i = 0; i < seg; i++) {
    const a = k * seg + i, b = k * seg + ((i + 1) % seg), c = a + seg, d = b + seg;
    idx.push(a, c, b, b, c, d);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 4));
  g.setIndex(idx);
  return g;
}

/** The narrator's pointer: the sheet darkens slightly away from the part being named, like paper under a desk lamp. */
export class FocusLamp implements Part {
  readonly root = new THREE.Group();
  private mat: THREE.MeshBasicMaterial;
  private mesh: THREE.Mesh;
  constructor(ink: Ink) {
    this.mat = ink.fill('vignette', { own: true, opacity: 0 });
    this.mat.vertexColors = true;
    this.mesh = new THREE.Mesh(washGeometry(), this.mat);
    this.mesh.position.z = Z.focus;
    this.root.add(this.mesh);
  }
  set(x: number, y: number, on: number, span: number): void {
    this.mesh.position.set(x, y, Z.focus);
    this.mesh.scale.setScalar(span * 0.6);
    this.mat.opacity = 0.11 * on;
  }
}

/** Paper veil over everything: the plate emerges from blank paper as exposure goes 0 → 1. */
export class Veil implements Part {
  readonly root = new THREE.Group();
  private mat: THREE.MeshBasicMaterial;
  private mesh: THREE.Mesh;
  constructor(ink: Ink) {
    this.mat = ink.fill('paper', { own: true, opacity: 1 });
    this.mesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), this.mat);
    this.root.add(this.mesh);
  }
  set(x: number, y: number, w: number, h: number, exposure: number): void {
    this.mesh.position.set(x, y, Z.veil);
    this.mesh.scale.set(w * 3, h * 3, 1);
    this.mat.opacity = 1 - exposure;
    this.mesh.visible = exposure < 0.999;
  }
}
