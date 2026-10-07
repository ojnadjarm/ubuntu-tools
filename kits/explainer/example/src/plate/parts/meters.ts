import * as THREE from 'three';
import type { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import type { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { Ink, Z, FONT } from '../ink';
import { arcPts, circle, hatch, polyline } from '../geom';
import { inRing, dir, type Part } from './part';

export const DIAL_MIN = -3, DIAL_MAX = 3, DIAL_STEP = 0.5, DIAL_SWEEP = (135 * Math.PI) / 180;
export const valueToAngle = (v: number): number => (-v / DIAL_MAX) * DIAL_SWEEP;
export const angleToValue = (a: number): number => (-a / DIAL_SWEEP) * DIAL_MAX;
const signed = (v: number): string => (v > 0 ? `+${v}` : v < 0 ? `−${-v}` : '0');

/** Drafting centre mark: four short strokes outside a circle. */
function centreMark(cx: number, cy: number, r0: number, r1: number): number[] {
  return [cx - r1, cy, cx - r0, cy, cx + r0, cy, cx + r1, cy, cx, cy - r1, cx, cy - r0, cx, cy + r0, cx, cy + r1];
}

/** Sectioned housing: paper disc, hatched bezel ring, two outlines. */
function housing(ink: Ink, g: THREE.Group, cx: number, cy: number, r0: number, r1: number): void {
  g.add(ink.disc(cx, cy, r1, ink.fill('paper'), Z.fill, 96));
  g.add(ink.segs(hatch(inRing(cx, cy, r0, r1), [cx - r1, cy - r1, cx + r1, cy + r1], 3.4), ink.line('hatch', 'hair'), Z.hatch));
  g.add(ink.segs(circle(cx, cy, r1, 128), ink.line('ink', 'med'), Z.line));
  g.add(ink.segs(circle(cx, cy, r0, 128), ink.line('ink', 'hair'), Z.line));
}

/** A weight dial: red knob over an engraved −3…+3 scale; the red arc is the weight. */
export class Dial implements Part {
  readonly root = new THREE.Group();
  private knob = new THREE.Group();
  private arc: LineSegments2;
  private ring: LineSegments2;
  private ringMat: LineMaterial;
  private last = NaN;
  constructor(private ink: Ink, readonly cx: number, readonly cy: number, readonly r: number, readonly kr: number) {
    const g = this.root;
    housing(ink, g, cx, cy, r - 9, r);
    const tk: number[] = [], mj: number[] = [];
    for (let v = DIAL_MIN; v <= DIAL_MAX + 1e-6; v += DIAL_STEP) {
      const [dx, dy] = dir(valueToAngle(v)), major = Math.abs(v - Math.round(v)) < 1e-6;
      (major ? mj : tk).push(cx + dx * (major ? 56 : 62), cy + dy * (major ? 56 : 62), cx + dx * 70, cy + dy * 70);
    }
    g.add(ink.segs(tk, ink.line('ink', 'hair'), Z.line), ink.segs(mj, ink.line('ink', 'thin'), Z.line));
    g.add(ink.segs(polyline(arcPts(cx, cy, 70, Math.PI / 2 - DIAL_SWEEP, Math.PI / 2 + DIAL_SWEEP, 96)), ink.line('ink', 'hair'), Z.line));
    const t = ink.text(2 * r, 2 * r, (c, th) => {
      c.fillStyle = th.ink; c.font = `500 14px ${FONT.mono}`; c.textAlign = 'center'; c.textBaseline = 'middle';
      for (let v = DIAL_MIN; v <= DIAL_MAX; v++) { const [dx, dy] = dir(valueToAngle(v)); c.fillText(signed(v), r + dx * 83, r - dy * 83); }
    }, 0.5, 0.5);
    t.mesh.position.set(cx, cy, Z.text);
    g.add(t.mesh);
    this.arc = ink.segs([], ink.line('weight', 5), Z.live);
    g.add(this.arc);
    const k = this.knob;
    k.position.set(cx, cy, 0);
    k.add(ink.disc(0, 0, kr + 4, ink.fill('ink'), Z.part, 96), ink.disc(0, 0, kr, ink.fill('weight'), Z.part + 0.1, 96));
    const kn: number[] = [];
    for (let i = 0; i < 40; i++) { const a = (i / 40) * Math.PI * 2; kn.push(Math.cos(a) * (kr + 4), Math.sin(a) * (kr + 4), Math.cos(a) * (kr + 9), Math.sin(a) * (kr + 9)); }
    k.add(ink.segs(kn, ink.line('ink', 'thin'), Z.line));
    const ptr = new THREE.Mesh(new THREE.PlaneGeometry(6, kr - 12).translate(0, (kr - 12) / 2 + 8, 0), ink.fill('paper'));
    ptr.position.z = Z.top;
    k.add(ptr, ink.disc(0, 0, 6, ink.fill('ink'), Z.top + 0.1, 32));
    g.add(k);
    this.ringMat = ink.line('weight', 'thin', { dash: [9, 7], own: true, opacity: 0 });
    this.ring = ink.segs(circle(cx, cy, r + 14, 128), this.ringMat, Z.focus);
    g.add(this.ring, ink.segs(centreMark(cx, cy, r + 4, r + 26), ink.line('inkSoft', 'hair'), Z.line));
  }
  set(v: number, hi: number): void {
    this.knob.rotation.z = valueToAngle(v);
    if (v !== this.last) {
      this.last = v;
      const a = valueToAngle(v);
      this.ink.setSegs(this.arc, Math.abs(a) < 1e-3 ? [] : polyline(arcPts(this.cx, this.cy, 52, Math.PI / 2, Math.PI / 2 + a, 48)));
    }
    this.ringMat.opacity = hi;
    this.ring.visible = hi > 0.01;
  }
}

/** Butterfly valve in section with the one-way symbol: flap along the pipe = open, across = shut. */
export class Valve implements Part {
  readonly root = new THREE.Group();
  private flap = new THREE.Group();
  constructor(ink: Ink, cx: number, cy: number, r: number) {
    const g = this.root;
    housing(ink, g, cx, cy, r - 7, r);
    this.flap.position.set(cx, cy, 0);
    this.flap.add(ink.segs([-(r - 9), 0, r - 9, 0], ink.line('ink', 'bold'), Z.top), ink.disc(0, 0, 4.5, ink.fill('ink'), Z.top + 0.1, 24));
    g.add(this.flap);
    const sy = cy + r + 26;
    g.add(ink.shape([cx - 10, sy - 9, cx + 7, sy, cx - 10, sy + 9], ink.fill('ink'), Z.part));
    g.add(ink.segs([cx + 8, sy - 10, cx + 8, sy + 10, cx - 24, sy, cx + 22, sy], ink.line('ink', 'thin'), Z.line));
  }
  set(open: number): void { this.flap.rotation.z = (1 - open) * (Math.PI / 2); }
}

const SWEEP = (120 * Math.PI) / 180;

/** Round needle gauge 0–max: blue needle and arc are the output, the yellow chevron is the target. */
export class Gauge implements Part {
  readonly root = new THREE.Group();
  private needle = new THREE.Group();
  private mark = new THREE.Group();
  private chev = new THREE.Group();
  private arc: LineSegments2;
  private glow: THREE.MeshBasicMaterial;
  private glowMesh: THREE.Mesh;
  private last = NaN;
  constructor(private ink: Ink, readonly cx: number, readonly cy: number, readonly r: number, readonly max = 5) {
    const g = this.root;
    housing(ink, g, cx, cy, r, r + 12);
    const tk: number[] = [], mj: number[] = [];
    for (let i = 0; i <= max * 5; i++) {
      const [dx, dy] = dir(this.angleOf(i / 5)), major = i % 5 === 0;
      (major ? mj : tk).push(cx + dx * (major ? r - 26 : r - 18), cy + dy * (major ? r - 26 : r - 18), cx + dx * (r - 8), cy + dy * (r - 8));
    }
    g.add(ink.segs(tk, ink.line('ink', 'hair'), Z.line), ink.segs(mj, ink.line('ink', 'thin'), Z.line));
    g.add(ink.segs(polyline(arcPts(cx, cy, r - 8, Math.PI / 2 - SWEEP, Math.PI / 2 + SWEEP, 96)), ink.line('ink', 'hair'), Z.line));
    const t = ink.text(2 * r, 2 * r, (c, th) => {
      c.fillStyle = th.ink; c.font = `500 17px ${FONT.mono}`; c.textAlign = 'center'; c.textBaseline = 'middle';
      for (let v = 0; v <= max; v++) { const [dx, dy] = dir(this.angleOf(v)); c.fillText(String(v), r + dx * (r - 44), r - dy * (r - 44)); }
    }, 0.5, 0.5);
    t.mesh.position.set(cx, cy, Z.text);
    g.add(t.mesh);
    this.arc = ink.segs([], ink.line('signal', 5), Z.live);
    g.add(this.arc);
    this.glow = ink.fill('target', { own: true, opacity: 0 });
    this.glowMesh = new THREE.Mesh(new THREE.RingGeometry(r + 16, r + 40, 48, 1, Math.PI / 2 - 0.2, 0.4), this.glow);
    this.glowMesh.position.set(cx, cy, Z.fill + 0.2);
    g.add(this.glowMesh);
    const m = this.mark;
    m.position.set(cx, cy, 0);
    this.chev.position.y = r + 26;
    this.chev.add(ink.shape([-13, 12, 13, 12, 0, -12], ink.fill('target'), Z.top));
    this.chev.add(ink.segs(polyline([-13, 12, 13, 12, 0, -12], true), ink.line('ink', 'thin'), Z.top + 0.1));
    m.add(this.chev);
    g.add(m);
    const n = this.needle;
    n.position.set(cx, cy, 0);
    n.add(ink.shape([-6, -16, 6, -16, 1.6, r - 12, -1.6, r - 12], ink.fill('signal'), Z.top));
    n.add(ink.disc(0, 0, 11, ink.fill('ink'), Z.top + 0.1, 40), ink.disc(0, 0, 3.5, ink.fill('paper'), Z.top + 0.2, 20));
    g.add(n, ink.segs(centreMark(cx, cy, r + 16, r + 30), ink.line('inkSoft', 'hair'), Z.line));
  }
  angleOf(v: number): number { return SWEEP - (THREE.MathUtils.clamp(v, 0, this.max) / this.max) * 2 * SWEEP; }
  set(v: number): void {
    this.needle.rotation.z = this.angleOf(v);
    const q = Math.round(v * 200) / 200;
    if (q !== this.last) {
      this.last = q;
      const a0 = Math.PI / 2 + this.angleOf(0), a1 = Math.PI / 2 + this.angleOf(v);
      this.ink.setSegs(this.arc, Math.abs(a1 - a0) < 1e-3 ? [] : polyline(arcPts(this.cx, this.cy, this.r - 4, a0, a1, 64)));
    }
  }
  setTarget(v: number, show: number, glow: number): void {
    this.mark.rotation.z = this.angleOf(v);
    this.chev.scale.setScalar(Math.max(0.001, show));
    this.mark.visible = show > 0.001;
    this.glowMesh.rotation.z = this.angleOf(v);
    this.glow.opacity = 0.55 * glow * Math.min(1, show);
  }
}
