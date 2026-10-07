/** A drawn outline in drawing units: a disc, an axis-aligned box, or a segment (a leader, a pipe) with a half width. */
export type Shape =
  | { k: 'disc'; x: number; y: number; r: number }
  | { k: 'box'; x0: number; y0: number; x1: number; y1: number }
  | { k: 'seg'; x0: number; y0: number; x1: number; y1: number; w?: number };

export const discOf = (x: number, y: number, r: number): Shape => ({ k: 'disc', x, y, r });
export const boxOf = (x0: number, y0: number, x1: number, y1: number): Shape => ({ k: 'box', x0: Math.min(x0, x1), y0: Math.min(y0, y1), x1: Math.max(x0, x1), y1: Math.max(y0, y1) });
export const segOf = (x0: number, y0: number, x1: number, y1: number, w = 0): Shape => ({ k: 'seg', x0, y0, x1, y1, w });
/** A box of half size (hw, hh) round (x, y). */
export const around = (x: number, y: number, hw: number, hh: number): Shape => boxOf(x - hw, y - hh, x + hw, y + hh);

type Seg = Extract<Shape, { k: 'seg' }>;
type Box = Extract<Shape, { k: 'box' }>;

const ptBox = (x: number, y: number, b: Box): number => Math.hypot(Math.max(b.x0 - x, 0, x - b.x1), Math.max(b.y0 - y, 0, y - b.y1));
function ptSeg(x: number, y: number, s: Seg): number {
  const dx = s.x1 - s.x0, dy = s.y1 - s.y0, l2 = dx * dx + dy * dy;
  const t = l2 ? Math.max(0, Math.min(1, ((x - s.x0) * dx + (y - s.y0) * dy) / l2)) : 0;
  return Math.hypot(x - s.x0 - t * dx, y - s.y0 - t * dy);
}
/** Liang–Barsky: does segment s pass through box b? */
function segCrossesBox(s: Seg, b: Box): boolean {
  let t0 = 0, t1 = 1;
  const dx = s.x1 - s.x0, dy = s.y1 - s.y0;
  for (const [p, q] of [[-dx, s.x0 - b.x0], [dx, b.x1 - s.x0], [-dy, s.y0 - b.y0], [dy, b.y1 - s.y0]]) {
    if (p === 0) { if (q < 0) return false; continue; }
    const t = q / p;
    if (p < 0) { if (t > t1) return false; if (t > t0) t0 = t; } else { if (t < t0) return false; if (t < t1) t1 = t; }
  }
  return true;
}
const cross = (ax: number, ay: number, bx: number, by: number): number => ax * by - ay * bx;
function segsCross(a: Seg, b: Seg): boolean {
  const d1 = cross(a.x1 - a.x0, a.y1 - a.y0, b.x0 - a.x0, b.y0 - a.y0), d2 = cross(a.x1 - a.x0, a.y1 - a.y0, b.x1 - a.x0, b.y1 - a.y0);
  const d3 = cross(b.x1 - b.x0, b.y1 - b.y0, a.x0 - b.x0, a.y0 - b.y0), d4 = cross(b.x1 - b.x0, b.y1 - b.y0, a.x1 - b.x0, a.y1 - b.y0);
  return d1 * d2 < 0 && d3 * d4 < 0;
}
function segBox(s: Seg, b: Box): number {
  if (segCrossesBox(s, b)) return 0;
  const corners = [[b.x0, b.y0], [b.x1, b.y0], [b.x1, b.y1], [b.x0, b.y1]];
  return Math.min(ptBox(s.x0, s.y0, b), ptBox(s.x1, s.y1, b), ...corners.map(([x, y]) => ptSeg(x, y, s)));
}
function segSeg(a: Seg, b: Seg): number {
  if (segsCross(a, b)) return 0;
  return Math.min(ptSeg(a.x0, a.y0, b), ptSeg(a.x1, a.y1, b), ptSeg(b.x0, b.y0, a), ptSeg(b.x1, b.y1, a));
}

/** Clear distance between two outlines (0 when they touch or overlap); a segment's half width counts as part of it. */
export function dist(a: Shape, b: Shape): number {
  if (a.k === 'seg' || b.k === 'seg') {
    const [s, o] = (a.k === 'seg' ? [a, b] : [b, a]) as [Seg, Shape];
    const d = o.k === 'disc' ? ptSeg(o.x, o.y, s) - o.r : o.k === 'box' ? segBox(s, o) : segSeg(s, o) - (o.w ?? 0);
    return Math.max(0, d - (s.w ?? 0));
  }
  if (a.k === 'disc' && b.k === 'disc') return Math.max(0, Math.hypot(a.x - b.x, a.y - b.y) - a.r - b.r);
  if (a.k === 'box' && b.k === 'box') return Math.hypot(Math.max(0, a.x0 - b.x1, b.x0 - a.x1), Math.max(0, a.y0 - b.y1, b.y0 - a.y1));
  const [c, x] = (a.k === 'disc' ? [a, b] : [b, a]) as [Extract<Shape, { k: 'disc' }>, Box];
  return Math.max(0, ptBox(c.x, c.y, x) - c.r);
}
/** The two outlines come closer than `gap` (0: they touch or overlap). */
export const overlaps = (a: Shape, b: Shape, gap = 0): boolean => (gap > 0 ? dist(a, b) < gap : dist(a, b) === 0);
/** A leader (a segment) comes within `gap` of a shape. */
export const segHits = (seg: Shape, shape: Shape, gap = 0): boolean => overlaps(seg, shape, gap);

/** Centre of a shape. */
export const centre = (s: Shape): [number, number] => (s.k === 'disc' ? [s.x, s.y] : [(s.x0 + s.x1) / 2, (s.y0 + s.y1) / 2]);
/** Where the ray from the shape's centre toward (tx, ty) leaves its outline: a leader's end on its part's edge. */
export function edgePoint(s: Shape, [tx, ty]: [number, number]): [number, number] {
  const [cx, cy] = centre(s), dx = tx - cx, dy = ty - cy, l = Math.hypot(dx, dy) || 1;
  if (s.k === 'disc') return [cx + (dx / l) * s.r, cy + (dy / l) * s.r];
  if (s.k === 'seg') return [cx, cy];
  const hx = (s.x1 - s.x0) / 2, hy = (s.y1 - s.y0) / 2, k = Math.min(dx ? hx / Math.abs(dx) : Infinity, dy ? hy / Math.abs(dy) : Infinity);
  return [cx + dx * k, cy + dy * k];
}
/** Is point (x, y) inside the shape? */
export const contains = (s: Shape, x: number, y: number): boolean =>
  s.k === 'disc' ? Math.hypot(x - s.x, y - s.y) <= s.r : s.k === 'box' ? x >= s.x0 && x <= s.x1 && y >= s.y0 && y <= s.y1 : false;
/** Is shape `a` wholly inside box-or-disc `c`? */
export function within(a: Shape, c: Shape): boolean {
  const pts: [number, number][] = a.k === 'disc' ? [[a.x - a.r, a.y], [a.x + a.r, a.y], [a.x, a.y - a.r], [a.x, a.y + a.r]]
    : a.k === 'box' ? [[a.x0, a.y0], [a.x1, a.y0], [a.x1, a.y1], [a.x0, a.y1]] : [[a.x0, a.y0], [a.x1, a.y1]];
  return pts.every(([x, y]) => contains(c, x, y));
}
/** Map a shape through a point transform with a uniform scale (drawing units → screen px, y flipped). */
export function mapShape(s: Shape, f: (x: number, y: number) => [number, number], k: number): Shape {
  if (s.k === 'disc') { const [x, y] = f(s.x, s.y); return discOf(x, y, s.r * k); }
  const [x0, y0] = f(s.x0, s.y0), [x1, y1] = f(s.x1, s.y1);
  return s.k === 'box' ? boxOf(x0, y0, x1, y1) : segOf(x0, y0, x1, y1, (s.w ?? 0) * k);
}
