import type { Projector } from './pointer';
import type { PartSpec } from '../content/types';

/** A numbered badge on the drawing: the only target that opens its part's callout. `at()` is its centre while drawn, else null. */
export interface Marker { n: number; part: string; term: string; r: number; at(): [number, number] | null }

/** Screen px: with touch a badge answers within this radius at least (a 44 px target, like a button), capped by its neighbours. */
export const MARKER_HIT = 22;
/** Screen px a mouse may sit outside a badge's drawn circle and still be on it. */
export const MARKER_SLACK = 2;

/** Finds the drawn marker under a screen point. A mouse (`fine`) must be on the drawn circle + 2 px; touch reaches max(r, 22 px), capped at half the distance to the nearest other drawn badge, so two badges never share a hit area. */
export class MarkerRouter {
  readonly list: Marker[];
  constructor(list: Marker[]) { this.list = list; }
  hit(px: number, py: number, proj: Projector, fine = true): Marker | null {
    const drawn = this.list.flatMap((m) => {
      const at = m.at(); if (!at) return [];
      const [sx, sy] = proj.toScreen(at[0], at[1]), [ex] = proj.toScreen(at[0] + m.r, at[1]);
      return [{ m, sx, sy, r: Math.abs(ex - sx) }];
    });
    let best: Marker | null = null, bd = Infinity;
    for (const b of drawn) {
      const d = Math.hypot(px - b.sx, py - b.sy);
      let reach = b.r + MARKER_SLACK;
      if (!fine) {
        const gap = Math.min(Infinity, ...drawn.filter((o) => o !== b).map((o) => Math.hypot(o.sx - b.sx, o.sy - b.sy)));
        reach = Math.max(reach, Math.min(MARKER_HIT, gap / 2));
      }
      if (d <= reach && d < bd) { best = b.m; bd = d; }
    }
    return best;
  }
}

/** One marker per numbered part of the script (`parts[].n`), opening the part's callout (else its term); `at(n)` is where badge n is drawn now. */
export const partMarkers = (parts: PartSpec[], at: (n: number) => [number, number] | null, r: number): Marker[] =>
  parts.filter((p) => p.n !== undefined).map((p) => ({ n: p.n!, part: p.id, term: p.callout ?? p.term, r, at: () => at(p.n!) }));
