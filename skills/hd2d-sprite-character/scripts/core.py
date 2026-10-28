"""SDF sprite renderer: ortho sphere-tracing to palette-ramp pixel art, normal map and emissive mask."""
import numpy as np

RT = np.array([1.0, 0.0, 0.0])


def set_pitch(deg):
    """Camera tilt below horizontal: 22 for sprites, lower for portraits."""
    global DV, UP
    p = np.radians(deg)
    DV = np.array([0.0, -np.sin(p), -np.cos(p)])
    UP = np.array([0.0, np.cos(p), -np.sin(p)])


set_pitch(22.0)
LIGHT = np.array([-0.55, 0.8, 0.5]); LIGHT = LIGHT / np.linalg.norm(LIGHT)


def hexrgb(h):
    h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def V(*a):
    return np.array(a, dtype=float)


def length(v):
    return np.sqrt((v * v).sum(-1))


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h), h


# ---- primitives: each returns a function P(N,3) -> d(N)
def sphere(c, r):
    c = V(*c)
    return lambda P: length(P - c) - r


def ellipsoid(c, rad, rot=None):
    c = V(*c); rad = V(*rad)
    def f(P):
        q = P - c
        if rot is not None: q = q @ rot
        q0 = q / rad; k0 = length(q0); k1 = length(q0 / rad)
        return k0 * (k0 - 1) / np.maximum(k1, 1e-6)
    return f


def cone(a, b, r1, r2):
    """Round cone between points a,b with radii r1,r2 (iq)."""
    a = V(*a); b = V(*b); ba = b - a; l2 = ba @ ba; rr = r1 - r2; a2 = l2 - rr * rr; il2 = 1.0 / l2
    def f(P):
        pa = P - a; y = pa @ ba; z = y - l2
        x2v = pa * l2 - np.outer(y, ba); x2 = (x2v * x2v).sum(-1)
        y2 = y * y * l2; z2 = z * z * l2; k = np.sign(rr) * rr * rr * x2
        d3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + y * rr) * il2 - r1
        d1 = np.sqrt(x2 + z2) * il2 - r2
        d2 = np.sqrt(x2 + y2) * il2 - r1
        return np.where(np.sign(z) * a2 * z2 > k, d1, np.where(np.sign(y) * a2 * y2 < k, d2, d3))
    return f


def box(c, half, rot=None, r=0.0):
    c = V(*c); half = V(*half)
    def f(P):
        q = P - c
        if rot is not None: q = q @ rot
        q = np.abs(q) - half + r
        return length(np.maximum(q, 0)) + np.minimum(q.max(-1), 0) - r
    return f


def torus(c, R, r, rot=None, sy=1.0):
    c = V(*c)
    def f(P):
        q = P - c
        if rot is not None: q = q @ rot
        qx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - R
        return np.sqrt(qx ** 2 + (q[:, 1] / sy) ** 2) - r
    return f


def octa(c, s, sy=1.0, rot=None):
    c = V(*c)
    def f(P):
        q = P - c
        if rot is not None: q = q @ rot
        q = np.abs(q); q[:, 1] /= sy
        return (q.sum(-1) - s) * 0.57735 * min(1.0, sy)
    return f


def warp(fn, w):
    """Domain warp: w(P)->offset subtracted before evaluation."""
    return lambda P: fn(P - w(P))


def sub(a, b):
    return lambda P: np.maximum(a(P), -b(P))


def inter(a, b):
    return lambda P: np.maximum(a(P), b(P))


def rot_y(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_x(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_z(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def frame_to(axis_dir):
    """Rotation whose local y maps to axis_dir (for q = (P-c) @ R)."""
    y = axis_dir / np.linalg.norm(axis_dir)
    t = np.array([0, 0, 1.0]) if abs(y[2]) < 0.9 else np.array([1.0, 0, 0])
    x = np.cross(y, t); x /= np.linalg.norm(x); z = np.cross(x, y)
    return np.stack([x, y, z], 1)


class Prim:
    def __init__(self, fn, mat, group=None, tex=None):
        self.fn, self.mat, self.group, self.tex = fn, mat, group, tex


class Model:
    """Prims + smooth groups + overlays (lines, stamps, particles) in character-local space."""
    def __init__(self):
        self.prims, self.k, self.lines, self.stamps, self.dots = [], {}, [], [], []
        self.sel = set()

    def add(self, fn, mat, group=None, tex=None):
        self.prims.append(Prim(fn, mat, group, tex)); return self

    def group(self, name, k):
        self.k[name] = k

    def eval(self, P):
        best = np.full(len(P), 1e9); idx = np.full(len(P), -1)
        gd = {}
        for i, p in enumerate(self.prims):
            d = p.fn(P)
            if p.group is None:
                m = d < best; best = np.where(m, d, best); idx = np.where(m, i, idx)
            elif p.group not in gd:
                gd[p.group] = [d, np.full(len(P), i)]
            else:
                g = gd[p.group]; nd, h = smin(d, g[0], self.k[p.group])
                g[1] = np.where(h > 0.5, i, g[1]); g[0] = nd
        for d, gi in gd.values():
            m = d < best; best = np.where(m, d, best); idx = np.where(m, gi, idx)
        return best, idx


CULL = True


def _trace(model, O, dv, act, eps, steps):
    n = len(O); t = np.zeros(n); hit = np.zeros(n, bool); dmin = np.full(n, 1e9)
    for _ in range(steps):
        ia = np.nonzero(act)[0]
        if len(ia) == 0: break
        P = O[ia] + np.outer(t[ia], dv)
        d, _ = model.eval(P)
        dmin[ia] = np.minimum(dmin[ia], d)
        t[ia] += d * 0.8
        h = d < eps; hit[ia[h]] = True
        out = t[ia] > 330
        act[ia[h | out]] = False
    return t, hit, dmin


def march(model, W, H, ss, pivot, scale, yaw, steps=110):
    """Sphere-trace W*H*ss*ss rays; with CULL a 1-ray-per-pixel pass first skips pixels no ray comes near."""
    R = rot_y(-yaw)
    dv = R @ DV
    up = R @ UP; rt = R @ RT
    eps = 0.04 / scale + 0.02

    def origins(k):
        xs = ((np.arange(W * k) + 0.5) / k - pivot[0]) / scale
        ys = (pivot[1] - (np.arange(H * k) + 0.5) / k) / scale
        SX, SY = np.meshgrid(xs, ys)
        return np.outer(SX.ravel(), rt) + np.outer(SY.ravel(), up) - 160 * dv
    O = origins(ss); n = len(O)
    act = np.ones(n, bool)
    if CULL and ss > 1:
        _, h1, dmin = _trace(model, origins(1), dv, np.ones(W * H, bool), eps, steps)
        near = (h1 | (dmin < 2.0 / scale + 0.6)).reshape(H, W)
        near = near | _nb(near, 1, 0, False) | _nb(near, -1, 0, False) | _nb(near, 0, 1, False) | _nb(near, 0, -1, False)
        act = np.repeat(np.repeat(near, ss, 0), ss, 1).ravel()
    t, hit, _ = _trace(model, O, dv, act, eps, steps)
    P = O + np.outer(t, dv)
    return P, t, hit, R, dv


def render(model, mats, W, H, pivot, scale=1.0, yaw=0.0, ss=3, outline=True, cleanup=True):
    """Return dict: rgba (H,W,4) uint8, normal (H,W,4), emis (H,W) float, depth, idx map, mat map."""
    P, t, hit, R, dv = march(model, W, H, ss, pivot, scale, yaw)
    n = len(t); hi = np.nonzero(hit)[0]
    Ph = P[hi]
    d0, pid = model.eval(Ph)
    mat = np.array([model.prims[i].mat for i in pid], dtype=object)
    for i in np.unique(pid):
        pr = model.prims[i]
        if pr.tex is not None:
            sel = pid == i
            mat[sel] = pr.tex(Ph[sel], mat[sel])
    e = 0.12
    k = np.array([[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]], float)
    nrm = np.zeros_like(Ph)
    for kk in k:
        nrm += kk * model.eval(Ph + kk * e)[0][:, None]
    nrm /= np.maximum(length(nrm)[:, None], 1e-6)
    ao = np.ones(len(hi))
    for i, hstep in enumerate((1.0, 2.5, 4.5)):
        dd, _ = model.eval(Ph + nrm * hstep)
        ao -= np.clip(hstep - dd, 0, None) / hstep * 0.25 / (i + 1) ** 0.5
    ao = np.clip(ao, 0.35, 1)
    # world-space vectors (undo yaw): local = R @ world -> world = R.T @ local
    nw = nrm @ R
    dw = DV
    lam = nw @ LIGHT
    refl = dw - 2 * (nw @ dw)[:, None] * nw
    ndv = -(nw @ dw)
    names = sorted(set(mat))
    mid = {m: i for i, m in enumerate(names)}
    mi = np.array([mid[m] for m in mat])
    val = np.zeros(len(hi))
    for m in names:
        s = mi == mid[m]; kind = mats[m].get('kind', 'cloth')
        L = lam[s]; a = ao[s]
        if kind == 'metal':
            r = refl[s]
            env = np.where(r[:, 1] > 0.12, 0.62 + 0.3 * r[:, 1], np.where(r[:, 1] > -0.25, 0.22, 0.34))
            spec = np.clip(r @ LIGHT, 0, 1) ** 18
            v = 0.15 + 0.35 * np.clip((L + 0.3) / 1.3, 0, 1) + 0.45 * env * a + 0.6 * spec
            v *= a ** 0.7
        elif kind == 'emis':
            v = 0.55 + 0.45 * np.clip(ndv[s] * 0.6 + L * 0.5, 0, 1)
        elif kind == 'skin':
            a = 1 - (1 - a) * mats[m].get('ao', 1.0)
            v = 0.1 + 0.9 * np.clip((L + 0.55) / 1.45, 0, 1) ** 1.2 * a ** 1.2
        else:
            w = mats[m].get('wrap', 0.3)
            v = 0.06 + 0.94 * np.clip((L + w) / (1 + w), 0, 1) ** mats[m].get('gamma', 1.25) * a ** 1.6
        val[s] = v
    # per-pixel resolve
    WS, HS = W * ss, H * ss
    full_m = np.full(n, -1); full_m[hi] = mi
    fm = full_m.reshape(H, ss, W, ss).transpose(0, 2, 1, 3).reshape(H, W, ss * ss)
    cov = (fm >= 0).sum(-1)
    nm = len(names)
    counts = np.stack([(fm == j).sum(-1) for j in range(nm)], -1) if nm else np.zeros((H, W, 1))
    pm = counts.argmax(-1)
    opaque = cov >= int(np.ceil(ss * ss * 0.45))

    def resolve(arr):
        full = np.zeros((n,) + arr.shape[1:]); full[hi] = arr
        f = full.reshape((H, ss, W, ss) + arr.shape[1:]).swapaxes(1, 2).reshape((H, W, ss * ss) + arr.shape[1:])
        sel = (fm == pm[..., None]).astype(float)
        if arr.ndim == 2: sel = sel[..., None]
        return (f * sel).sum(2) / np.maximum(sel.sum(2), 1)
    pv = resolve(val); pn = resolve(nw); pdep = resolve(t[hi]); plam = resolve(lam)
    pl = resolve(Ph)
    pn /= np.maximum(length(pn)[..., None], 1e-6)
    pdep[~opaque] = 1e9
    # quantize
    idx = np.zeros((H, W), int); nsteps = np.zeros((H, W), int)
    for j, m in enumerate(names):
        s = (pm == j) & opaque
        ns = len(mats[m]['ramp']); nsteps[s] = ns
        bias = mats[m].get('bias', 0.0)
        idx[s] = np.clip(np.floor(pv[s] * ns + bias), 0, ns - 1).astype(int)
    if cleanup:
        for _ in range(2):
            idx = _clean(idx, pm, opaque)
    if outline:
        idx = _contours(idx, pm, opaque, pdep, plam)
    sel = [j for j, m in enumerate(names) if m in getattr(model, 'sel', ())]
    if sel:
        idx, pm, opaque = _selout(idx, pm, opaque, pdep, sel)
    out = dict(idx=idx, pm=pm, names=names, opaque=opaque, depth=pdep, normal=pn, local=pl, lam=plam,
               W=W, H=H, pivot=pivot, scale=scale, yaw=yaw, R=R, selmask=np.isin(pm, sel) & opaque)
    rgba = np.zeros((H, W, 4), np.uint8); emis = np.zeros((H, W))
    for j, m in enumerate(names):
        s = (pm == j) & opaque
        ramp = np.array([hexrgb(c) for c in mats[m]['ramp']])
        rgba[s, :3] = ramp[np.clip(idx[s], 0, len(ramp) - 1)]
        rgba[s, 3] = 255
        if mats[m].get('kind') == 'emis' or 'glow' in mats[m]: emis[s] = mats[m].get('glow', 1.0)
    out['rgba'] = rgba; out['emis'] = emis
    return out


def _nb(a, dy, dx, fill):
    r = np.full_like(a, fill)
    H, W = a.shape
    ys = slice(max(dy, 0), H + min(dy, 0)); yd = slice(max(-dy, 0), H + min(-dy, 0))
    xs = slice(max(dx, 0), W + min(dx, 0)); xd = slice(max(-dx, 0), W + min(-dx, 0))
    r[yd, xd] = a[ys, xs]
    return r


def _clean(idx, pm, op):
    """Remove orphan pixels: a pixel unlike all 4 neighbours that agree among themselves."""
    key = np.where(op, pm * 100 + idx, -1)
    nb = [_nb(key, dy, dx, -2) for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1))]
    same = (nb[0] == nb[1]) & (nb[1] == nb[2]) & (nb[2] == nb[3])
    fix = op & same & (nb[0] != key) & (nb[0] >= 0) & (nb[0] // 100 == pm)
    idx = idx.copy(); idx[fix] = nb[0][fix] % 100
    return idx


def _selout(idx, pm, op, dep, sel):
    """Hand materials: orphans adopt a neighbour, edges on the shadow side take the darkest step."""
    idx, pm, op = idx.copy(), pm.copy(), op.copy()
    isel = np.isin(pm, sel) & op
    nbs = [(dy, dx) for dy, dx in ((1, 0), (0, 1), (-1, 0), (0, -1))]
    same = sum(((_nb(pm, dy, dx, -1) == pm) & _nb(op, dy, dx, False)).astype(int) for dy, dx in nbs)
    orphan = isel & (same == 0)
    for y, x in zip(*np.nonzero(orphan)):
        for dy, dx in nbs:
            yy, xx = y + dy, x + dx
            if 0 <= yy < idx.shape[0] and 0 <= xx < idx.shape[1] and op[yy, xx] and pm[yy, xx] not in sel:
                pm[y, x], idx[y, x] = pm[yy, xx], idx[yy, xx]; break
        else:
            op[y, x] = False
    isel = np.isin(pm, sel) & op
    for dy, dx in nbs:
        npm = _nb(pm, dy, dx, -1); nop = _nb(op, dy, dx, False)
        diff = isel & (~nop | (npm != pm))
        if (dy, dx) in ((1, 0), (0, 1)):
            idx[diff] = 0
    return idx, pm, op


def _contours(idx, pm, op, dep, lam):
    idx = idx.copy()
    # silhouette: shadow side (right/down neighbour empty or lam<0.15) gets darkest step
    edge_sh = np.zeros_like(op); edge_lit = np.zeros_like(op)
    for dy, dx in ((1, 0), (0, 1), (-1, 0), (0, -1)):
        e = op & ~_nb(op, dy, dx, False)
        if (dy, dx) in ((1, 0), (0, 1)):
            edge_sh |= e
        else:
            edge_lit |= e
    edge_sh &= ~(edge_lit & (lam > 0.35))
    idx[edge_sh] = 0
    lit = edge_lit & ~edge_sh
    idx[lit] = np.maximum(idx[lit] - 1, 1)
    # inner contours where a near surface overlaps a far one: the far pixel takes a cast-shadow step
    for dy, dx in ((-1, 0), (0, -1), (1, 0), (0, 1)):
        nd = _nb(dep, dy, dx, 1e9)
        far = op & ~edge_sh & (dep - nd > 3.0)
        k = 2 if (dy, dx) in ((-1, 0), (0, -1)) else 1
        idx[far] = np.maximum(idx[far] - k, 0)
    return idx


def project(pt, R, pivot, scale):
    """Local point -> (px, py, depth)."""
    w = R.T @ np.asarray(pt, float)
    sx, sy = w @ RT, w @ UP
    dep = w @ DV + 160
    return pivot[0] + sx * scale, pivot[1] - sy * scale, dep


def overlay(out, model, pal):
    """Draw lines, stamps and dots (local 3D) onto rgba with a depth test; hand pixels hide overlays behind them."""
    rgba = out['rgba']; R = out['R']; pv = out['pivot']; sc = out['scale']; dep = out['depth']; H, W = out['H'], out['W']
    sm = out.get('selmask')
    def put(x, y, d, col, tol=2.5, emis=0.0):
        x, y = int(np.floor(x)), int(np.floor(y))
        if 0 <= x < W and 0 <= y < H and d <= dep[y, x] + tol and not (sm is not None and sm[y, x] and d > dep[y, x] - 0.5):
            rgba[y, x, :3] = hexrgb(col); rgba[y, x, 3] = 255
            if emis: out['emis'][y, x] = max(out['emis'][y, x], emis)
    for a, b, col, *rest in model.lines:
        tol = rest[0] if rest else 2.5
        x0, y0, d0 = project(a, R, pv, sc); x1, y1, d1 = project(b, R, pv, sc)
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 1.5) + 1
        for i in range(n + 1):
            f = i / n
            put(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, d0 + (d1 - d0) * f, col, tol)
    for pt, pattern, facing, *rest in model.stamps:
        if facing is not None and (R.T @ np.asarray(facing, float)) @ DV > -0.15:
            continue
        x, y, d = project(pt, R, pv, sc)
        mirror = rest[0] if rest else False
        for (dx, dy), col in pattern.items():
            put(x + (-dx if mirror else dx), y + dy, d, col, 4.0)
    for pt, col, e, *rest in model.dots:
        x, y, d = project(pt, R, pv, sc)
        tol = rest[0] if rest else 1e9
        put(x, y, d, col, tol, e)


def normal_map(out):
    """OpenGL (y-up) tangent-space normal map in screen space."""
    n = out['normal']
    nx = n @ RT; ny = n @ UP; nz = -(n @ DV)
    rgb = np.stack([nx, ny, nz], -1) * 0.5 + 0.5
    a = out['rgba'][..., 3]
    img = np.zeros(n.shape[:2] + (4,), np.uint8)
    img[..., :3] = np.clip(rgb * 255, 0, 255).astype(np.uint8)
    img[..., 3] = a
    flat = (a > 0) & ~out['opaque']
    img[flat, :3] = (128, 128, 255)
    return img


def pat(rows, cmap, ox=0, oy=0):
    """ASCII rows -> stamp pattern {(dx,dy): hex}; '.' is empty; origin (ox,oy)."""
    out = {}
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != '.':
                out[(x - ox, y - oy)] = cmap[ch]
    return out
