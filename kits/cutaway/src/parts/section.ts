import * as THREE from 'three';
import { Ink, Z } from '../ink';
import { breakLine, circle, hatch, hatchPolys, polyline, rect, resample, roundRectPts } from '../geom';
import { HATCH } from '../tokens';
import type { Part } from './part';

/** Bolted flange in section: paper, dense hatching, thin outline. */
export function flange(ink: Ink, g: THREE.Group, x0: number, y0: number, x1: number, y1: number): void {
  g.add(ink.shape([x0, y0, x1, y0, x1, y1, x0, y1], ink.fill('paper'), Z.part));
  g.add(ink.segs(hatch(() => true, [x0, y0, x1, y1], HATCH.dense), ink.line('hatch', 'hair'), Z.part + 0.1));
  g.add(ink.segs(rect(x0, y0, x1, y1), ink.line('ink', 'thin'), Z.line));
}

/** Hatch a cut surface given as closed outlines (a band = outer + inner outline, even-odd). */
export function hatchFill(ink: Ink, polys: number[][], gap: number = HATCH.shell, z = Z.hatch): THREE.Object3D {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const p of polys) for (let i = 0; i < p.length; i += 2) { x0 = Math.min(x0, p[i]); x1 = Math.max(x1, p[i]); y0 = Math.min(y0, p[i + 1]); y1 = Math.max(y1, p[i + 1]); }
  return ink.segs(hatchPolys(polys, [x0, y0, x1, y1], gap), ink.line('hatch', 'hair'), z);
}

/** A casing centred at (cx, cy) with its front cover cut away along a break line: hatched shell, rivets, centre lines. */
export class SectionCut implements Part {
  readonly root = new THREE.Group();
  constructor(ink: Ink, w: number, h: number, centreLines: number[] = [], cx = 0, cy = 0) {
    const g = this.root, x0 = cx - w / 2, x1 = cx + w / 2, y0 = cy - h / 2, y1 = cy + h / 2;
    const outer = roundRectPts(x0, y0, x1, y1, 30, 10);
    const win = breakLine(resample(roundRectPts(x0 + 30, y0 + 30, x1 - 30, y1 - 30, 18, 8), 6), 6);
    g.add(ink.shape(outer, ink.fill('paper'), Z.back));
    g.add(ink.shape(win, ink.fill('paperShade'), Z.shade));
    g.add(hatchFill(ink, [outer, win]));
    g.add(ink.segs(polyline(outer, true), ink.line('ink', 'bold'), Z.line));
    g.add(ink.segs(polyline(roundRectPts(x0 + 7, y0 + 7, x1 - 7, y1 - 7, 24, 10), true), ink.line('ink', 'hair'), Z.line));
    g.add(ink.segs(polyline(win, true), ink.line('ink', 'med'), Z.line));
    const riv: number[] = [], per = roundRectPts(x0 + 16, y0 + 16, x1 - 16, y1 - 16, 16, 6);
    let acc = 0;
    for (let i = 2; i < per.length; i += 2) {
      acc += Math.hypot(per[i] - per[i - 2], per[i + 1] - per[i - 1]);
      if (acc >= 92) { acc = 0; riv.push(...circle(per[i], per[i + 1], 3.6, 16)); }
    }
    g.add(ink.segs(riv, ink.line('ink', 'thin'), Z.line));
    if (centreLines.length) g.add(ink.segs(centreLines, ink.line('inkSoft', 'hair', { dash: [30, 6] }), Z.shade + 0.1));
  }
}
