/* The Switchboard's materials and the two shapes the batch lacks: a rod between two points and an upright arc. */
export const TIMBER = [0.2, 0.13, 0.085], STONE = [0.25, 0.27, 0.28], BRASS = [0.66, 0.5, 0.21], BRONZE = [0.33, 0.25, 0.12], BOTTLE = [0.05, 0.2, 0.14], PAPER = [0.84, 0.8, 0.68], MOON = [0.42, 0.56, 0.7];

/* A rod t thick from a to b: two crossed ribbons seen from every side. */
export function rod(B, a, b, t, col, glow = 0) {
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], l = Math.hypot(...u) || 1e-6, f = Math.hypot(u[0], u[2]);
  const s = f < 1e-6 ? [1, 0, 0] : [u[2] / f, 0, -u[0] / f], n = [(u[1] * s[2] - u[2] * s[1]) / l, (u[2] * s[0] - u[0] * s[2]) / l, (u[0] * s[1] - u[1] * s[0]) / l];
  for (const d of [s, n]) {
    const w = d.map((x) => x * t), o = a.map((x, i) => x - w[i] / 2);
    B.cells(o, u, w, 1, 1, col, { glow }); B.cells(o.map((x, i) => x + w[i]), u, w.map((x) => -x), 1, 1, col, { glow });
  }
}

/* An upright arc of n faces round (x, z) from angle a0 to a1 (0 = +z), y0 to y1; inward turns the faces to the centre; col is a colour or col(i). */
export function arc(B, x, z, r, y0, y1, a0, a1, n, col, { inward = false, glow = 0 } = {}) {
  const at = (i) => { const a = a0 + ((a1 - a0) * i) / n; return [x + r * Math.sin(a), z + r * Math.cos(a)]; };
  for (let i = 0; i < n; i++) {
    const [p, q] = inward ? [at(i + 1), at(i)] : [at(i), at(i + 1)];
    B.cells([p[0], y0, p[1]], [q[0] - p[0], 0, q[1] - p[1]], [0, y1 - y0, 0], 1, 1, typeof col === "function" ? col(i) : col, { glow });
  }
}
