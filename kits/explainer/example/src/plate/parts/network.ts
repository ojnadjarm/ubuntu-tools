import * as THREE from 'three';
import type { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import { Ink, Z } from '../ink';
import { arcPts, bezierPts, circle, polyline, roundRectPts } from '../geom';
import { rng } from 'explainer-kit';
import type { Part } from './part';

const LAYERS = [3, 4, 4, 2];
const LX = [-600, -200, 200, 600];
const DY = 128, MW = 190, MH = 84;

/** Fig. 2: many small neurons wired layer to layer; wires carry dashed signal, dials turn as the network is tuned. */
export class NetworkFigure implements Part {
  readonly root = new THREE.Group();
  private flows: { mat: LineMaterial; phase: number }[] = [];
  private knobs: { g: THREE.Group; to: number }[] = [];
  private needles: { g: THREE.Group; from: number; to: number }[] = [];
  constructor(private ink: Ink, cy: number) {
    const r = rng(11), g = this.root;
    const mods = LAYERS.map((n, l) => Array.from({ length: n }, (_, i) => [LX[l], cy + ((n - 1) / 2 - i) * DY]));
    const outl: number[] = [], small: number[] = [];
    for (const [x, y] of mods.flat()) {
      const box = roundRectPts(x - MW / 2, y - MH / 2, x + MW / 2, y + MH / 2, 8, 4);
      g.add(ink.shape(box, ink.fill('paper'), Z.fill));
      outl.push(...polyline(box, true));
      for (let k = 0; k < 2; k++) {
        const kx = x - 62 + k * 44, kg = new THREE.Group();
        kg.position.set(kx, y, 0);
        kg.add(ink.disc(0, 0, 15, ink.fill('weight'), Z.part, 32));
        const p = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 11).translate(0, 7, 0), ink.fill('paper')); p.position.z = Z.top; kg.add(p);
        small.push(...circle(kx, y, 15, 32), ...circle(kx, y, 21, 40));
        g.add(kg); this.knobs.push({ g: kg, to: (r() * 2 - 1) * 2.2 });
      }
      const gx = x + 50, gy = y - 16;
      small.push(...polyline(arcPts(gx, gy, 32, 0, Math.PI, 32)), gx - 32, gy, gx + 32, gy);
      const ng = new THREE.Group(); ng.position.set(gx, gy, 0);
      ng.add(new THREE.Mesh(new THREE.PlaneGeometry(3, 27).translate(0, 13.5, Z.top), ink.fill('signal')));
      g.add(ng); this.needles.push({ g: ng, from: 1.3, to: 1.2 - r() * 2.4 });
    }
    g.add(ink.segs(outl, ink.line('ink', 'thin'), Z.line), ink.segs(small, ink.line('ink', 'hair'), Z.line));
    for (let l = 0; l < LAYERS.length - 1; l++) {
      const wires: number[] = [];
      for (const a of mods[l]) for (const b of mods[l + 1]) {
        const s = [a[0] + MW / 2, a[1]], e = [b[0] - MW / 2, b[1]];
        wires.push(...polyline(bezierPts(s, [s[0] + 90, s[1]], [e[0] - 90, e[1]], e, 24)));
      }
      g.add(ink.segs(wires, ink.line('inkSoft', 'hair'), Z.part));
      const mat = ink.line('signal', 1.8, { dash: [9, 9], own: true, opacity: 0 });
      g.add(ink.segs(wires, mat, Z.live));
      this.flows.push({ mat, phase: 0 });
    }
  }
  apply(net: number, tune: number, dt: number, run: boolean): void {
    this.root.visible = net > 1e-3;
    this.flows.forEach((f, l) => {
      const on = THREE.MathUtils.clamp(net * 4 - l * 0.8, 0, 1);
      f.mat.opacity = on * 0.9;
      if (run) f.phase += dt * 60 * on;
      f.mat.dashOffset = -f.phase;
    });
    this.knobs.forEach((k) => { k.g.rotation.z = -k.to * tune; });
    this.needles.forEach((n) => { n.g.rotation.z = n.from + (n.to - n.from) * tune; });
  }
}
