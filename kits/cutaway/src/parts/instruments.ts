import * as THREE from 'three';
import type { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import type { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { Ink, Z } from '../ink';
import { arcPts, circle, offset, polyline } from '../geom';
import { FONT, type ColorRole } from '../tokens';
import { centreMark, dir, housing, type Part } from './part';

/** A dial's engraved scale: range, detent step, which values carry numerals, and the value its arc grows from. */
export interface DialScale { min: number; max: number; step: number; labels: number[]; origin: number; format: (v: number) => string }

const signed = (v: number): string => (v > 0 ? `+${v}` : v < 0 ? `−${-v}` : '0');
export const WEIGHT_SCALE: DialScale = { min: -3, max: 3, step: 0.5, labels: [-3, -2, -1, 0, 1, 2, 3], origin: 0, format: signed };
const SWEEP = (135 * Math.PI) / 180;

/** Knob over an engraved scale; the coloured arc from `origin` is the value. Radii follow r (the neuron dial is r = 104). */
export class Dial implements Part {
  readonly root = new THREE.Group();
  private knob = new THREE.Group();
  private arc: LineSegments2;
  private ringMat: LineMaterial;
  private ring: LineSegments2;
  private last = NaN;
  constructor(private ink: Ink, readonly cx: number, readonly cy: number, readonly r: number, kr: number,
    readonly scale: DialScale = WEIGHT_SCALE, role: ColorRole = 'red') {
    const g = this.root, f = r / 104, { min, max, step } = scale;
    housing(ink, g, cx, cy, r - 9 * f, r);
    const tk: number[] = [], mj: number[] = [];
    for (let v = min; v <= max + 1e-6; v += step) {
      const [dx, dy] = dir(this.angle(v)), major = scale.labels.some((l) => Math.abs(l - v) < 1e-6);
      (major ? mj : tk).push(cx + dx * (major ? 56 : 62) * f, cy + dy * (major ? 56 : 62) * f, cx + dx * 70 * f, cy + dy * 70 * f);
    }
    g.add(ink.segs(tk, ink.line('ink', 'hair'), Z.line), ink.segs(mj, ink.line('ink', 'thin'), Z.line));
    g.add(ink.segs(polyline(arcPts(cx, cy, 70 * f, Math.PI / 2 - SWEEP, Math.PI / 2 + SWEEP, 96)), ink.line('ink', 'hair'), Z.line));
    const t = ink.text(2 * r, 2 * r, (c, th) => {
      c.fillStyle = th.ink; c.font = `500 ${14 * f}px ${FONT.mono}`; c.textAlign = 'center'; c.textBaseline = 'middle';
      for (const v of scale.labels) { const [dx, dy] = dir(this.angle(v)); c.fillText(scale.format(v), r + dx * 83 * f, r - dy * 83 * f); }
    }, 0.5, 0.5);
    t.mesh.position.set(cx, cy, Z.text);
    g.add(t.mesh);
    this.arc = ink.segs([], ink.line(role, 5 * f), Z.live);
    g.add(this.arc);
    const k = this.knob;
    k.position.set(cx, cy, 0);
    k.add(ink.disc(0, 0, kr + 4, ink.fill('ink'), Z.part, 96), ink.disc(0, 0, kr, ink.fill(role), Z.part + 0.1, 96));
    const kn: number[] = [];
    for (let i = 0; i < 40; i++) { const a = (i / 40) * Math.PI * 2; kn.push(Math.cos(a) * (kr + 4), Math.sin(a) * (kr + 4), Math.cos(a) * (kr + 9), Math.sin(a) * (kr + 9)); }
    k.add(ink.segs(kn, ink.line('ink', 'thin'), Z.line));
    const ptr = new THREE.Mesh(new THREE.PlaneGeometry(6, kr - 12).translate(0, (kr - 12) / 2 + 8, 0), ink.fill('paper'));
    ptr.position.z = Z.top;
    k.add(ptr, ink.disc(0, 0, 6, ink.fill('ink'), Z.top + 0.1, 32));
    g.add(k);
    this.ringMat = ink.line(role, 'thin', { dash: [9, 7], own: true, opacity: 0 });
    this.ring = ink.segs(circle(cx, cy, r + 14, 128), this.ringMat, Z.focus);
    g.add(this.ring, ink.segs(centreMark(cx, cy, r + 4, r + 26), ink.line('inkSoft', 'hair'), Z.line));
  }
  /** Knob rotation (radians, CCW) for a value: min sits 135° left of top, max 135° right. */
  angle(v: number): number { const { min, max } = this.scale; return SWEEP - ((v - min) / (max - min)) * 2 * SWEEP; }
  value(a: number): number { const { min, max } = this.scale; return min + ((SWEEP - a) / (2 * SWEEP)) * (max - min); }
  /** v = value, hi = 0…1 dashed ring that says "this one" while the narrator names it. */
  set(v: number, hi = 0): void {
    this.knob.rotation.z = this.angle(v);
    if (v !== this.last) {
      this.last = v;
      const a0 = this.angle(this.scale.origin), a = this.angle(v);
      this.ink.setSegs(this.arc, Math.abs(a - a0) < 1e-3 ? [] : polyline(arcPts(this.cx, this.cy, 52 * (this.r / 104), Math.PI / 2 + a0, Math.PI / 2 + a, 48)));
    }
    this.ringMat.opacity = hi;
    this.ring.visible = hi > 0.01;
  }
}

const GSWEEP = (120 * Math.PI) / 180;

/** Round needle gauge min–max (signed when min < 0): needle and arc from zero in the output's primary, a yellow chevron for the target. */
export class Gauge implements Part {
  readonly root = new THREE.Group();
  private needle = new THREE.Group();
  private mark = new THREE.Group();
  private chev = new THREE.Group();
  private arc: LineSegments2;
  private glow: THREE.MeshBasicMaterial;
  private glowMesh: THREE.Mesh;
  private last = NaN;
  constructor(private ink: Ink, readonly cx: number, readonly cy: number, readonly r: number, readonly max = 5, role: ColorRole = 'blue', readonly min = 0) {
    const g = this.root;
    housing(ink, g, cx, cy, r, r + 12);
    const tk: number[] = [], mj: number[] = [];
    for (let i = Math.ceil(min * 5); i <= max * 5; i++) {
      const [dx, dy] = dir(this.angleOf(i / 5)), major = i % 5 === 0;
      (major ? mj : tk).push(cx + dx * (major ? r - 26 : r - 18), cy + dy * (major ? r - 26 : r - 18), cx + dx * (r - 8), cy + dy * (r - 8));
    }
    g.add(ink.segs(tk, ink.line('ink', 'hair'), Z.line), ink.segs(mj, ink.line('ink', 'thin'), Z.line));
    g.add(ink.segs(polyline(arcPts(cx, cy, r - 8, Math.PI / 2 - GSWEEP, Math.PI / 2 + GSWEEP, 96)), ink.line('ink', 'hair'), Z.line));
    const t = ink.text(2 * r, 2 * r, (c, th) => {
      c.fillStyle = th.ink; c.font = `500 17px ${FONT.mono}`; c.textAlign = 'center'; c.textBaseline = 'middle';
      for (let v = Math.ceil(min); v <= max; v++) { const [dx, dy] = dir(this.angleOf(v)); c.fillText(v < 0 ? `−${-v}` : min < 0 && v > 0 ? `+${v}` : String(v), r + dx * (r - 44), r - dy * (r - 44)); }
    }, 0.5, 0.5);
    t.mesh.position.set(cx, cy, Z.text);
    g.add(t.mesh);
    this.arc = ink.segs([], ink.line(role, 5), Z.live);
    g.add(this.arc);
    this.glow = ink.fill('yellow', { own: true, opacity: 0 });
    this.glowMesh = new THREE.Mesh(new THREE.RingGeometry(r + 16, r + 40, 48, 1, Math.PI / 2 - 0.2, 0.4), this.glow);
    this.glowMesh.position.set(cx, cy, Z.fill + 0.2);
    g.add(this.glowMesh);
    const m = this.mark;
    m.position.set(cx, cy, 0);
    this.chev.position.y = r + 26;
    this.chev.add(ink.shape([-13, 12, 13, 12, 0, -12], ink.fill('yellow'), Z.top));
    this.chev.add(ink.segs(polyline([-13, 12, 13, 12, 0, -12], true), ink.line('ink', 'thin'), Z.top + 0.1));
    m.add(this.chev);
    g.add(m);
    const n = this.needle;
    n.position.set(cx, cy, 0);
    n.add(ink.shape([-6, -16, 6, -16, 1.6, r - 12, -1.6, r - 12], ink.fill(role), Z.top));
    n.add(ink.disc(0, 0, 11, ink.fill('ink'), Z.top + 0.1, 40), ink.disc(0, 0, 3.5, ink.fill('paper'), Z.top + 0.2, 20));
    g.add(n, ink.segs(centreMark(cx, cy, r + 16, r + 30), ink.line('inkSoft', 'hair'), Z.line));
  }
  angleOf(v: number): number { return GSWEEP - ((THREE.MathUtils.clamp(v, this.min, this.max) - this.min) / (this.max - this.min)) * 2 * GSWEEP; }
  set(v: number): void {
    this.needle.rotation.z = this.angleOf(v);
    const q = Math.round(v * 200) / 200;
    if (q !== this.last) {
      this.last = q;
      const a0 = Math.PI / 2 + this.angleOf(THREE.MathUtils.clamp(0, this.min, this.max)), a1 = Math.PI / 2 + this.angleOf(v);
      this.ink.setSegs(this.arc, Math.abs(a1 - a0) < 1e-3 ? [] : polyline(arcPts(this.cx, this.cy, this.r - 4, a0, a1, 64)));
    }
  }
  /** Target chevron at v; show scales it in, glow is the "brass mark" halo. */
  setTarget(v: number, show: number, glow: number): void {
    this.mark.rotation.z = this.angleOf(v);
    this.chev.scale.setScalar(Math.max(0.001, show));
    this.mark.visible = show > 0.001;
    this.glowMesh.rotation.z = this.angleOf(v);
    this.glow.opacity = 0.55 * glow * Math.min(1, show);
  }
}

/** Butterfly valve in section with the one-way symbol above it: flap along the pipe = open, across = shut. */
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
  /** 0 = shut, 1 = open. */
  set(open: number): void { this.flap.rotation.z = (1 - open) * (Math.PI / 2); }
}

/** Pipe in section: two ink walls and a dashed core whose weight is the flow and whose dashes run with its sign. */
export class Pipe implements Part {
  readonly root = new THREE.Group();
  private core: LineSegments2;
  private mat: LineMaterial;
  private phase = 0;
  constructor(private ink: Ink, pts: number[], r = 7, role: ColorRole = 'blue') {
    const g = this.root;
    g.add(ink.segs([...polyline(offset(pts, r)), ...polyline(offset(pts, -r))], ink.line('ink', 'thin'), Z.part));
    this.mat = ink.line(role, 2, { dash: [11, 7], own: true });
    this.core = ink.segs(polyline(pts), this.mat, Z.live);
    g.add(this.core);
  }
  /** `run` advances the dashes (only while something is moving, so idle frames stay at zero). */
  update(flow: number, dt: number, gain: number, run: boolean): void {
    const a = Math.min(3, Math.abs(flow) * gain);
    this.core.visible = a > 0.03;
    this.ink.weigh(this.mat, 1.2 + 2.2 * Math.min(1.6, a));
    if (run) this.phase += dt * Math.sign(flow) * Math.min(2.2, 0.6 + Math.abs(flow) * 0.5) * 38;
    this.mat.dashOffset = -this.phase;
  }
}
