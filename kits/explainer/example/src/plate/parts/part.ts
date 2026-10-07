import * as THREE from 'three';

/** One drawn component of the plate (Composite leaf): it owns its meshes and reads plain numbers. */
export interface Part { readonly root: THREE.Group }

/** Ring inside test for hatching annuli. */
export const inRing = (cx: number, cy: number, r0: number, r1: number) => (x: number, y: number): boolean => {
  const d = Math.hypot(x - cx, y - cy); return d >= r0 && d <= r1;
};
/** Rotation (radians, CCW, 0 = up) to a unit direction. */
export const dir = (a: number): [number, number] => [-Math.sin(a), Math.cos(a)];
