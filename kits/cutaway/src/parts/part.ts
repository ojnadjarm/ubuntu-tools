import * as THREE from 'three';
import { Ink, Z } from '../ink';
import { circle, hatch } from '../geom';
import { HATCH } from '../tokens';

/** One drawn component of a plate (Composite leaf): it owns its meshes and reads plain numbers. */
export interface Part { readonly root: THREE.Group }

export const clamp01 = (x: number): number => Math.min(1, Math.max(0, x));

/** Ring inside test for hatching annuli. */
export const inRing = (cx: number, cy: number, r0: number, r1: number) => (x: number, y: number): boolean => {
  const d = Math.hypot(x - cx, y - cy); return d >= r0 && d <= r1;
};
/** Rotation (radians, CCW, 0 = up) to a unit direction. */
export const dir = (a: number): [number, number] => [-Math.sin(a), Math.cos(a)];

/** Drafting centre mark: four short strokes outside a circle. */
export function centreMark(cx: number, cy: number, r0: number, r1: number): number[] {
  return [cx - r1, cy, cx - r0, cy, cx + r0, cy, cx + r1, cy, cx, cy - r1, cx, cy - r0, cx, cy + r0, cx, cy + r1];
}

/** Round housing in section: paper disc, hatched bezel ring between r0 and r1, two outlines. */
export function housing(ink: Ink, g: THREE.Group, cx: number, cy: number, r0: number, r1: number): void {
  g.add(ink.disc(cx, cy, r1, ink.fill('paper'), Z.fill, 96));
  g.add(ink.segs(hatch(inRing(cx, cy, r0, r1), [cx - r1, cy - r1, cx + r1, cy + r1], HATCH.dense), ink.line('hatch', 'hair'), Z.hatch));
  g.add(ink.segs(circle(cx, cy, r1, 128), ink.line('ink', 'med'), Z.line));
  g.add(ink.segs(circle(cx, cy, r0, 128), ink.line('ink', 'hair'), Z.line));
}
