/* The static office as one mesh: furniture models and code-built surfaces merged into one buffer, lit per vertex on the CPU (sky, sun, lamps, contact shadow). */
const ss = (a, b, x) => { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

export function batch(kit, pal) {
  const P = [], N = [], A = [], G = [], I = [], feet = [], stack = [];
  let T = { x: 0, y: 0, z: 0, r: 0, c: 1, s: 0 };
  const vert = (x, y, z, nx, ny, nz, col, g = 0) => { const { c, s } = T; P.push(T.x + x * c + z * s, T.y + y, T.z - x * s + z * c); N.push(nx * c + nz * s, ny, -nx * s + nz * c); A.push(col[0], col[1], col[2]); G.push(g); return P.length / 3 - 1; };
  const B = {
    feet,
    push({ x = 0, y = 0, z = 0, r = 0 } = {}) { stack.push(T); const { c, s } = T, R = T.r + r; T = { x: T.x + x * c + z * s, y: T.y + y, z: T.z - x * s + z * c, r: R, c: Math.cos(R), s: Math.sin(R) }; },
    pop() { T = stack.pop(); },
    at(x = 0, y = 0, z = 0) { const { c, s } = T; return { x: T.x + x * c + z * s, y: T.y + y, z: T.z - x * s + z * c, r: T.r }; },
    /* A kit model standing on (x, y, z), turned r; s scales it (number or [x, y, z]); tint and glow are keyed by material name. */
    model(name, { x = 0, y = 0, z = 0, r = 0, s = 1, tint, glow, foot = true } = {}) {
      const m = kit.models[name], o = P.length / 3, c = Math.cos(r), sn = Math.sin(r), [sx, sy, sz] = Array.isArray(s) ? s : [s, s, s];
      for (let i = 0; i < m.m.length; i++) {
        const k = kit.mats[m.m[i]], px = m.p[i * 3] * sx, pz = m.p[i * 3 + 2] * sz, nx = m.n[i * 3] / 127, nz = m.n[i * 3 + 2] / 127;
        vert(x + px * c + pz * sn, y + m.p[i * 3 + 1] * sy, z - px * sn + pz * c, nx * c + nz * sn, m.n[i * 3 + 1] / 127, -nx * sn + nz * c, tint?.[k] || pal[k] || pal._defaultMat, glow?.[k] || 0);
      }
      for (const i of m.i) I.push(o + i);
      if (foot && m.s[1] * sy > 0.08) B.foot(x, y, z, m.s[0] * sx / 2, m.s[2] * sz / 2, r);
      return m.s;
    },
    foot(x, y, z, hx, hz, r = 0) { const w = B.at(x, y, z); feet.push({ x: w.x, y: w.y, z: w.z, hx, hz, c: Math.cos(w.r + r), s: Math.sin(w.r + r) }); },
    /* A sheet of nu × nv cells from origin o along u and v, facing u × v; col is a colour or col(i, j); stagger shifts odd rows half a cell; sub splits a cell along u. */
    cells(o, u, v, nu, nv, col, { glow = 0, stagger = false, sub = 1 } = {}) {
      const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]], l = Math.hypot(...n), f = typeof col === "function";
      for (let j = 0; j < nv; j++) for (let i = stagger && j % 2 ? -1 : 0; i < nu; i++) {
        const off = stagger && j % 2 ? 0.5 : 0, a0 = Math.max(0, (i + off) / nu), a1 = Math.min(1, (i + 1 + off) / nu), c = f ? col(i, j) : col;
        if (a1 <= a0) continue;
        let prev = null;
        for (let k = 0; k <= sub; k++) {
          const a = a0 + ((a1 - a0) * k) / sub, row = [j / nv, (j + 1) / nv].map((b) => vert(o[0] + u[0] * a + v[0] * b, o[1] + u[1] * a + v[1] * b, o[2] + u[2] * a + v[2] * b, n[0] / l, n[1] / l, n[2] / l, c, glow));
          if (prev) I.push(prev[0], row[0], row[1], prev[0], row[1], prev[1]);
          prev = row;
        }
      }
    },
    /* A box standing on y, centred on (x, z). */
    box(x, y, z, w, h, d, col, { r = 0, glow = 0, foot = false } = {}) {
      B.push({ x, y, z, r });
      const a = w / 2, b = d / 2;
      B.cells([-a, h, -b], [0, 0, d], [w, 0, 0], 1, 1, col, { glow });
      B.cells([-a, 0, b], [w, 0, 0], [0, h, 0], 1, 1, col, { glow }); B.cells([a, 0, -b], [-w, 0, 0], [0, h, 0], 1, 1, col, { glow });
      B.cells([a, 0, b], [0, 0, -d], [0, h, 0], 1, 1, col, { glow }); B.cells([-a, 0, -b], [0, 0, d], [0, h, 0], 1, 1, col, { glow });
      if (foot) B.foot(0, 0, 0, a, b);
      B.pop();
    },
    /* A cone frustum on y: radius r0 at the foot, r1 at the top. */
    cyl(x, y, z, r0, r1, h, col, { seg = 14, glow = 0, foot = false } = {}) {
      const k = Math.hypot(h, r0 - r1), c0 = vert(x, y + h, z, 0, 1, 0, col, glow), ring = [];
      for (let i = 0; i <= seg; i++) {
        const a = (i / seg) * Math.PI * 2, s = Math.sin(a), c = Math.cos(a);
        ring.push([vert(x + r0 * s, y, z + r0 * c, s * h / k, (r0 - r1) / k, c * h / k, col, glow), vert(x + r1 * s, y + h, z + r1 * c, s * h / k, (r0 - r1) / k, c * h / k, col, glow), vert(x + r1 * s, y + h, z + r1 * c, 0, 1, 0, col, glow)]);
        if (i) { const p = ring[i - 1], q = ring[i]; I.push(p[0], q[0], q[1], p[0], q[1], p[1], c0, p[2], q[2]); }
      }
      if (foot) B.foot(x, y, z, r0, r0);
    },
    /* A flat ring of polar cells on y, from radius r0 to r1 over the arc [a0, a1]. */
    ring(x, y, z, r0, r1, a0, a1, na, nr, col, glow = 0) {
      const f = typeof col === "function";
      for (let j = 0; j < nr; j++) for (let i = 0; i < na; i++) {
        const c = f ? col(i, j) : col, q = [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]].map(([ii, jj]) => { const a = a0 + ((a1 - a0) * ii) / na, r = r0 + ((r1 - r0) * jj) / nr; return vert(x + r * Math.sin(a), y, z + r * Math.cos(a), 0, 1, 0, c, glow); });
        I.push(q[0], q[2], q[1], q[0], q[3], q[2]);
      }
    },
    /* Freezes the geometry; bake(env, lamps, glows) then returns the lit colour buffer. */
    finish() {
      const n = P.length / 3, pos = new Float32Array(P), ao = new Float32Array(n).fill(1), col = new Float32Array(n * 3), sum = new Float32Array(n * 3);
      for (let i = 0; i < n; i++) {
        if (N[i * 3 + 1] < 0.9) continue;
        const x = pos[i * 3], y = pos[i * 3 + 1], z = pos[i * 3 + 2];
        for (const f of feet) {
          if (Math.abs(y - f.y) > 0.05) continue;
          const dx = x - f.x, dz = z - f.z;
          if (Math.abs(dx) + Math.abs(dz) > f.hx + f.hz + 0.6) continue;
          const lx = Math.abs(dx * f.c - dz * f.s) - f.hx, lz = Math.abs(dx * f.s + dz * f.c) - f.hz, d = Math.hypot(Math.max(lx, 0), Math.max(lz, 0));
          ao[i] = Math.min(ao[i], 0.58 + 0.42 * ss(0, 0.3, d));
        }
      }
      let lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
      for (let i = 0; i < n * 3; i++) { lo[i % 3] = Math.min(lo[i % 3], pos[i]); hi[i % 3] = Math.max(hi[i % 3], pos[i]); }
      return {
        position: pos, color: col, index: n > 65535 ? new Uint32Array(I) : new Uint16Array(I), lo, hi,
        bake(env, lamps, glows) {
          sum.fill(0);
          for (const L of lamps) {
            const R = L.r, cut = (2.6 * R) ** 2;
            for (let i = 0; i < n; i++) {
              const dx = L.x - pos[i * 3], dz = L.z - pos[i * 3 + 2];
              if (dx * dx + dz * dz > cut) continue;
              const dy = L.y - pos[i * 3 + 1], d2 = dx * dx + dy * dy + dz * dz, d = Math.sqrt(d2) || 1e-3, ndl = (N[i * 3] * dx + N[i * 3 + 1] * dy + N[i * 3 + 2] * dz) / d;
              const w = (L.i * (0.3 + 0.7 * Math.max(ndl, 0))) / (1 + d2 / (R * R)) ** 2;
              sum[i * 3] += L.col[0] * w; sum[i * 3 + 1] += L.col[1] * w; sum[i * 3 + 2] += L.col[2] * w;
            }
          }
          const { sky, ground, sun, dir } = env;
          for (let i = 0; i < n; i++) {
            const h = N[i * 3 + 1] * 0.5 + 0.5, ndl = Math.max(0, N[i * 3] * dir[0] + N[i * 3 + 1] * dir[1] + N[i * 3 + 2] * dir[2]), g = G[i] && glows[G[i]];
            for (let k = 0; k < 3; k++) {
              let c = A[i * 3 + k] * ((ground[k] + (sky[k] - ground[k]) * h + sun[k] * ndl) * ao[i] + sum[i * 3 + k]);
              if (g) c = c * (1 - g[3]) + g[k] * g[3];
              c = Math.max(0, c); col[i * 3 + k] = c < 0.7 ? c : 0.7 + 0.3 * (1 - Math.exp(-(c - 0.7) / 0.3));
            }
          }
          return col;
        },
        /* Light on a point facing up, for the creatures. */
        lightAt(env, lamps, x, y, z) {
          const out = [0, 1, 2].map((k) => env.sky[k] * 0.75 + env.ground[k] * 0.25 + env.sun[k] * 0.6);
          for (const L of lamps) { const d2 = (L.x - x) ** 2 + (L.y - y) ** 2 + (L.z - z) ** 2, w = (L.i * 0.7) / (1 + d2 / (L.r * L.r)) ** 2; for (let k = 0; k < 3; k++) out[k] += L.col[k] * w; }
          return out;
        },
      };
    },
  };
  return B;
}
