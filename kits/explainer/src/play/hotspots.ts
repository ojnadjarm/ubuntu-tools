/** A part of the drawing that answers "what is this?": hit test in world units, the term it shows, the dot its callout leader starts on. */
export interface Hotspot { part: string; term: string; hits(wx: number, wy: number): boolean; dot: [number, number] }

/** A round hotspot (a dial, a gauge); the dot defaults to the top of the rim. */
export const disc = (part: string, term: string, cx: number, cy: number, r: number, dot: [number, number] = [cx, cy + r]): Hotspot =>
  ({ part, term, dot, hits: (x, y) => Math.hypot(x - cx, y - cy) <= r });
/** A box hotspot (a tube, a chamber, a figure); the dot defaults to the top edge's centre. */
export const box = (part: string, term: string, x0: number, y0: number, x1: number, y1: number, dot: [number, number] = [(x0 + x1) / 2, Math.max(y0, y1)]): Hotspot =>
  ({ part, term, dot, hits: (x, y) => x >= Math.min(x0, x1) && x <= Math.max(x0, x1) && y >= Math.min(y0, y1) && y <= Math.max(y0, y1) });

/** Answers which part is under a point (first listed wins, so list small parts before the large ones around them). */
export class HotspotRouter {
  readonly spots: Hotspot[];
  constructor(spots: Hotspot[]) { this.spots = spots; }
  peek(wx: number, wy: number): Hotspot | null { return this.spots.find((h) => h.hits(wx, wy)) ?? null; }
  part(id: string): Hotspot | undefined { return this.spots.find((h) => h.part === id); }
  byTerm(term: string): Hotspot | undefined { return this.spots.find((h) => h.term === term); }
}
