import * as THREE from 'three';
import { Ink, Z, circle, rect, note, type Part } from 'cutaway-kit';

const MAX = 8, PITCH = 34, R = 10;

/** Punch-card click tally: `budget` holes in a ruled strip, one punched per click spent. */
export class Tally implements Part {
  readonly root = new THREE.Group();
  private holes: THREE.Object3D[] = [];
  private punched: THREE.Mesh[] = [];
  private last = '';
  constructor(ink: Ink, x: number, y: number) {
    this.root.add(note(ink, 'CLICKS', x, y + 36, { size: 14 }));
    this.root.add(ink.segs(rect(x - 14, y - 22, x + MAX * PITCH - 6, y + 22), ink.line('ink', 'thin'), Z.line));
    for (let i = 0; i < MAX; i++) {
      const cx = x + 12 + i * PITCH;
      const h = ink.segs(circle(cx, y, R, 32), ink.line('ink', 'thin'), Z.line);
      const p = ink.disc(cx, y, R - 1.5, ink.fill('ink'), Z.part, 32);
      this.holes.push(h); this.punched.push(p); this.root.add(h, p);
    }
    this.set(0, 0, 0);
  }
  set(on: number, budget: number, used: number): void {
    const key = `${on > 0.5}|${budget}|${Math.round(used)}`;
    if (key === this.last) return;
    this.last = key;
    this.root.visible = on > 0.5;
    this.holes.forEach((h, i) => { h.visible = i < budget; });
    this.punched.forEach((p, i) => { p.visible = i < budget && i < Math.round(used); });
  }
}
