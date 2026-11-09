/* Primitive meshes, 4×4 maths and the baker that merges every part of a creature into one buffer with a bone index per vertex. */
const TAU = Math.PI * 2, cache = new Map();
const memo = (k, make) => { if (!cache.has(k)) cache.set(k, wind(make())); return cache.get(k); };

/* Turns every triangle to face along its vertex normals. */
function wind(m) {
  const { P, N, I } = m;
  for (let i = 0; i < I.length; i += 3) {
    const a = I[i] * 3, b = I[i + 1] * 3, c = I[i + 2] * 3;
    const ux = P[b] - P[a], uy = P[b + 1] - P[a + 1], uz = P[b + 2] - P[a + 2], vx = P[c] - P[a], vy = P[c + 1] - P[a + 1], vz = P[c + 2] - P[a + 2];
    const d = (uy * vz - uz * vy) * (N[a] + N[b] + N[c]) + (uz * vx - ux * vz) * (N[a + 1] + N[b + 1] + N[c + 1]) + (ux * vy - uy * vx) * (N[a + 2] + N[b + 2] + N[c + 2]);
    if (d < 0) { const t = I[i + 1]; I[i + 1] = I[i + 2]; I[i + 2] = t; }
  }
  return m;
}
function join(...ms) {
  const P = [], N = [], I = [];
  for (const m of ms) { const o = P.length / 3; P.push(...m.P); N.push(...m.N); for (const i of m.I) I.push(i + o); }
  return { P, N, I };
}
/* Revolves profile rows [r, y, nr, ny] round Y over the arc [t0, t0 + tl]; x = r sin t, z = r cos t. */
function lathe(prof, n, t0 = 0, tl = TAU) {
  const P = [], N = [], I = [], rows = prof.length;
  for (let j = 0; j <= n; j++) {
    const t = t0 + (j / n) * tl, s = Math.sin(t), c = Math.cos(t);
    for (const [r, y, nr, ny] of prof) { P.push(r * s, y, r * c); N.push(nr * s, ny, nr * c); }
  }
  for (let j = 0; j < n; j++) for (let i = 0; i < rows - 1; i++) { const a = j * rows + i, b = a + rows; I.push(a, a + 1, b, a + 1, b + 1, b); }
  return { P, N, I };
}
const arc = (n, a0, a1, r, y0) => Array.from({ length: n + 1 }, (_, i) => { const a = a0 + ((a1 - a0) * i) / n; return [r * Math.sin(a), y0 + r * Math.cos(a), Math.sin(a), Math.cos(a)]; });

export const sphere = (w = 20, h = 12) => memo(`s${w}/${h}`, () => lathe(arc(h, 0, Math.PI, 1, 0), w));
export const G = {
  get sph() { return sphere(20, 12); },
  get lo() { return sphere(10, 6); },
  get dome() { return memo("dome", () => lathe(arc(5, 0, Math.PI / 2, 1, 0), 14)); },
  get cone() { return cyl(0, 1, 1, 10); },
  get cone4() { return cyl(0, 1, 1, 4); },
  get box() {
    return memo("box", () => {
      const P = [], N = [], I = [];
      for (let ax = 0; ax < 3; ax++) for (const d of [-1, 1]) {
        const o = P.length / 3, u = (ax + 1) % 3, v = (ax + 2) % 3;
        for (const [a, b] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) { const p = [0, 0, 0], n = [0, 0, 0]; p[ax] = d * 0.5; p[u] = a * 0.5; p[v] = b * 0.5; n[ax] = d; P.push(...p); N.push(...n); }
        I.push(o, o + 1, o + 2, o, o + 2, o + 3);
      }
      return { P, N, I };
    });
  },
};
export const capsule = (r, len, seg = 8) => memo(`cap${r}/${len}/${seg}`, () => lathe([...arc(3, 0, Math.PI / 2, r, len / 2), ...arc(3, Math.PI / 2, Math.PI, r, -len / 2)], seg));
export function cyl(rt, rb, h, n, open = false, t0 = 0, tl = TAU) {
  return memo(`cyl${rt}/${rb}/${h}/${n}/${open}/${t0}/${tl}`, () => {
    const sl = (rb - rt) / h, k = Math.hypot(1, sl), side = lathe([[rt, h / 2, 1 / k, sl / k], [rb, -h / 2, 1 / k, sl / k]], n, t0, tl);
    if (open) return side;
    return join(side, lathe([[0, h / 2, 0, 1], [rt, h / 2, 0, 1]], n, t0, tl), lathe([[rb, -h / 2, 0, -1], [0, -h / 2, 0, -1]], n, t0, tl));
  });
}
/* A torus in the XY plane round Z, swept over `sweep` radians from +X. */
export function torus(R, tube, rs, ts, sweep = TAU) {
  return memo(`tor${R}/${tube}/${rs}/${ts}/${sweep}`, () => {
    const P = [], N = [], I = [];
    for (let j = 0; j <= rs; j++) for (let i = 0; i <= ts; i++) {
      const u = (i / ts) * sweep, v = (j / rs) * TAU, cu = Math.cos(u), su = Math.sin(u), cv = Math.cos(v), sv = Math.sin(v);
      P.push((R + tube * cv) * cu, (R + tube * cv) * su, tube * sv); N.push(cv * cu, cv * su, sv);
    }
    for (let j = 1; j <= rs; j++) for (let i = 1; i <= ts; i++) { const a = (ts + 1) * j + i - 1, b = (ts + 1) * (j - 1) + i - 1, c = b + 1, d = a + 1; I.push(a, b, d, b, c, d); }
    return { P, N, I };
  });
}

/* Column-major TRS matrix, rotation as XYZ Euler angles. */
export function compose(out, p, r, s) {
  const a = Math.cos(r[0]), b = Math.sin(r[0]), c = Math.cos(r[1]), d = Math.sin(r[1]), e = Math.cos(r[2]), f = Math.sin(r[2]);
  out[0] = c * e * s[0]; out[1] = (a * f + b * e * d) * s[0]; out[2] = (b * f - a * e * d) * s[0]; out[3] = 0;
  out[4] = -c * f * s[1]; out[5] = (a * e - b * f * d) * s[1]; out[6] = (b * e + a * f * d) * s[1]; out[7] = 0;
  out[8] = d * s[2]; out[9] = -b * c * s[2]; out[10] = a * c * s[2]; out[11] = 0;
  out[12] = p[0]; out[13] = p[1]; out[14] = p[2]; out[15] = 1;
  return out;
}
/* out = a · b for affine matrices; out may start at offset o of a larger array. */
export function mul(out, a, b, o = 0) {
  for (let c = 0; c < 4; c++) {
    const x = b[c * 4], y = b[c * 4 + 1], z = b[c * 4 + 2], w = c === 3 ? 1 : 0;
    out[o + c * 4] = a[0] * x + a[4] * y + a[8] * z + a[12] * w;
    out[o + c * 4 + 1] = a[1] * x + a[5] * y + a[9] * z + a[13] * w;
    out[o + c * 4 + 2] = a[2] * x + a[6] * y + a[10] * z + a[14] * w;
    out[o + c * 4 + 3] = w;
  }
  return out;
}
export const IDENT = compose(new Float32Array(16), [0, 0, 0], [0, 0, 0], [1, 1, 1]);
const v3 = (s) => (Array.isArray(s) ? s : [s, s, s]);

/* A transform node; a bone when it moves at run time, else folded into its parts at bake time. */
class Node {
  constructor(parent, p, r, s, bone) { this.parent = parent; this.p = [...p]; this.r = [...r]; this.s = [...v3(s)]; this.vis = true; this.bone = bone; this.pre = null; this.world = new Float32Array(16); }
}

/* The rig of one creature: group() and part() build it, pose(out, root) writes one matrix per bone, mesh() gives the merged buffers. */
export function rig(maxBones) {
  const bones = [], pos = [], nor = [], col = [], shd = [], par = [], out = [], idx = [], tmp = new Float32Array(16), loc = new Float32Array(16);
  /* Matrix from node n's space up to its nearest bone, and that bone. */
  function up(n) {
    let m = IDENT, b = n;
    while (b && b.bone < 0) { m = mul(new Float32Array(16), compose(new Float32Array(16), b.p, b.r, b.s), m); b = b.parent; }
    return [m, b];
  }
  function node(parent, { p = [0, 0, 0], r = [0, 0, 0], s = 1 } = {}, bone) {
    const n = new Node(parent, p, r, s, -1);
    if (bone) {
      if (bones.length >= maxBones) throw new Error("familiars: too many bones");
      const [m, b] = parent ? up(parent) : [IDENT, null];
      n.pre = m; n.parent = b; n.bone = bones.length; bones.push(n);
    }
    return n;
  }
  const R = {
    bones,
    /* A moving group (a bone) or, with fixed, a static one. */
    group: (parent, p, fixed) => node(parent, { p }, !fixed),
    /* One primitive under parent: o.p, o.r, o.s place it, o.outline inks it, o.bone makes it a moving part. */
    part(parent, g, m, o = {}) {
      const n = node(parent, o, !!o.bone), [M, b] = up(n), o0 = pos.length / 3, { P, N } = g;
      const c0 = [M[5] * M[10] - M[6] * M[9], M[6] * M[8] - M[4] * M[10], M[4] * M[9] - M[5] * M[8]], c1 = [M[9] * M[2] - M[10] * M[1], M[10] * M[0] - M[8] * M[2], M[8] * M[1] - M[9] * M[0]], c2 = [M[1] * M[6] - M[2] * M[5], M[2] * M[4] - M[0] * M[6], M[0] * M[5] - M[1] * M[4]];
      for (let i = 0; i < P.length; i += 3) {
        const x = P[i], y = P[i + 1], z = P[i + 2], nx = N[i], ny = N[i + 1], nz = N[i + 2];
        pos.push(M[0] * x + M[4] * y + M[8] * z + M[12], M[1] * x + M[5] * y + M[9] * z + M[13], M[2] * x + M[6] * y + M[10] * z + M[14]);
        const a = c0[0] * nx + c1[0] * ny + c2[0] * nz, bb = c0[1] * nx + c1[1] * ny + c2[1] * nz, c = c0[2] * nx + c1[2] * ny + c2[2] * nz, l = Math.hypot(a, bb, c) || 1;
        nor.push(a / l, bb / l, c / l); col.push(...m.col); shd.push(...m.shade); par.push(b.bone, m.rim, m.em, m.flag); out.push(o.outline ? 1 : 0);
      }
      for (const i of g.I) idx.push(i + o0);
      return n;
    },
    /* Writes root · world of every bone into out (16 floats each); a hidden bone and its children collapse to zero. */
    pose(dst, root) {
      for (const b of bones) {
        const pw = b.parent ? b.parent.world : root, off = b.bone * 16;
        b.hid = !b.vis || (b.parent && b.parent.hid);
        if (b.hid) { dst.fill(0, off, off + 16); continue; }
        compose(loc, b.p, b.r, b.s);
        mul(b.world, pw, b.pre === IDENT ? loc : mul(tmp, b.pre, loc));
        dst.set(b.world, off);
      }
    },
    mesh: () => ({ position: new Float32Array(pos), normal: new Float32Array(nor), aCol: new Float32Array(col), aShade: new Float32Array(shd), aP: new Float32Array(par), aO: new Float32Array(out), index: pos.length / 3 > 65535 ? new Uint32Array(idx) : new Uint16Array(idx) }),
  };
  return R;
}
