/** Flat 2D drawing primitives: every function returns segment lists [x1, y1, x2, y2, …] in drawing units. */
export type Segs = number[];

export function polyline(pts: number[], closed = false): Segs {
  const out: Segs = [], n = pts.length / 2;
  for (let i = 0; i < n - 1; i++) out.push(pts[2 * i], pts[2 * i + 1], pts[2 * i + 2], pts[2 * i + 3]);
  if (closed && n > 2) out.push(pts[2 * n - 2], pts[2 * n - 1], pts[0], pts[1]);
  return out;
}
export function arcPts(cx: number, cy: number, r: number, a0: number, a1: number, n = 64): number[] {
  const p: number[] = [];
  for (let i = 0; i <= n; i++) { const a = a0 + ((a1 - a0) * i) / n; p.push(cx + Math.cos(a) * r, cy + Math.sin(a) * r); }
  return p;
}
export const circle = (cx: number, cy: number, r: number, n = 96): Segs => polyline(arcPts(cx, cy, r, 0, Math.PI * 2, n));
export const rect = (x0: number, y0: number, x1: number, y1: number): Segs => polyline([x0, y0, x1, y0, x1, y1, x0, y1], true);

/** Rounded rectangle outline as points (for fills and break-line perturbation). */
export function roundRectPts(x0: number, y0: number, x1: number, y1: number, r: number, per = 10): number[] {
  const p: number[] = [];
  const c = [[x1 - r, y1 - r, 0], [x0 + r, y1 - r, 1], [x0 + r, y0 + r, 2], [x1 - r, y0 + r, 3]];
  for (const [cx, cy, q] of c) p.push(...arcPts(cx, cy, r, (q * Math.PI) / 2, ((q + 1) * Math.PI) / 2, per));
  return p;
}

/** Section hatching: parallel lines at `angle`, `gap` apart, kept wherever `inside` holds (sampled, so any shape works). */
export function hatch(inside: (x: number, y: number) => boolean, box: [number, number, number, number], gap: number, angle = Math.PI / 4, step = 0.8): Segs {
  const [x0, y0, x1, y1] = box, dx = Math.cos(angle), dy = Math.sin(angle), nx = -dy, ny = dx;
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, R = Math.hypot(x1 - x0, y1 - y0) / 2;
  const out: Segs = [];
  for (let o = -R; o <= R; o += gap) {
    let run: number[] | null = null;
    for (let t = -R; t <= R + step; t += step) {
      const x = cx + nx * o + dx * t, y = cy + ny * o + dy * t;
      const on = x >= x0 && x <= x1 && y >= y0 && y <= y1 && inside(x, y);
      if (on && !run) run = [x, y];
      if (!on && run) { out.push(run[0], run[1], x - dx * step, y - dy * step); run = null; }
    }
  }
  return out;
}

/** Even-odd point-in-polygon test. */
export function inPoly(pts: number[], x: number, y: number): boolean {
  let c = false;
  for (let i = 0, j = pts.length - 2; i < pts.length; j = i, i += 2) {
    const xi = pts[i], yi = pts[i + 1], xj = pts[j], yj = pts[j + 1];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
}

/** Cubic Bézier sampled into points. */
export function bezierPts(p0: number[], p1: number[], p2: number[], p3: number[], n = 32): number[] {
  const out: number[] = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n, u = 1 - t, a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
    out.push(a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]);
  }
  return out;
}

/** Polyline truncated to fraction f of its length (for lines that draw themselves on). */
export function partial(pts: number[], f: number): number[] {
  if (f >= 1) return pts;
  let total = 0; const seg: number[] = [];
  for (let i = 0; i < pts.length - 2; i += 2) { const l = Math.hypot(pts[i + 2] - pts[i], pts[i + 3] - pts[i + 1]); seg.push(l); total += l; }
  let left = Math.max(0, f) * total; const out = [pts[0], pts[1]];
  for (let k = 0; k < seg.length; k++) {
    const i = 2 * k;
    if (left >= seg[k]) { out.push(pts[i + 2], pts[i + 3]); left -= seg[k]; continue; }
    const u = seg[k] ? left / seg[k] : 0;
    out.push(pts[i] + (pts[i + 2] - pts[i]) * u, pts[i + 1] + (pts[i + 3] - pts[i + 1]) * u);
    break;
  }
  return out;
}

/** Section hatching clipped exactly to closed polygons by the even-odd rule (a band = outer + inner outline). */
export function hatchPolys(polys: number[][], box: [number, number, number, number], gap: number, angle = Math.PI / 4): Segs {
  const [x0, y0, x1, y1] = box, dx = Math.cos(angle), dy = Math.sin(angle), nx = -dy, ny = dx;
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, R = Math.hypot(x1 - x0, y1 - y0) / 2, out: Segs = [];
  for (let o = -R; o <= R; o += gap) {
    const px = cx + nx * o, py = cy + ny * o, ts: number[] = [];
    for (const p of polys) for (let i = 0, j = p.length - 2; i < p.length; j = i, i += 2) {
      const ax = p[j] - px, ay = p[j + 1] - py, bx = p[i] - px, by = p[i + 1] - py;
      const sa = ax * nx + ay * ny, sb = bx * nx + by * ny;
      if ((sa > 0) === (sb > 0)) continue;
      const u = sa / (sa - sb);
      ts.push((ax + (bx - ax) * u) * dx + (ay + (by - ay) * u) * dy);
    }
    ts.sort((a, b) => a - b);
    for (let k = 0; k + 1 < ts.length; k += 2) out.push(px + dx * ts[k], py + dy * ts[k], px + dx * ts[k + 1], py + dy * ts[k + 1]);
  }
  return out;
}
