"""4D bodies as boundary tetrahedra, and their exact 3D cross-section by a hyperplane (numpy only).

Copied from fourd/film (T2015); one change (B1): a body keeps its recipe, `parts`, for the seeds of atelier.four."""
from collections import namedtuple

import numpy as np

# A swept 3D mesh: faces F (m,3) as given, n points a key, K keys; point i of key k is P[p0 + k*n + i], and tet j
# (0..2) of face f between keys k and k+1 is T[t0 + (3*k + j)*m + f] (corners from the face's sorted points).
Part = namedtuple("Part", "F n K p0 t0")


class Body:
    """A 4D solid's boundary: points P (V,4), tets T (M,4), an outward hint N (M,4) per tet, per-point attrs, and the
    recipe it was swept from (parts; empty for a body made of bare tets)."""

    def __init__(self, P, T, N, attrs=None, parts=()):
        self.P = np.asarray(P, np.float64)
        self.N = np.asarray(N, np.float64)
        self.T = np.asarray(T, np.int64)
        self.attrs = {k: np.asarray(v, np.float64) for k, v in (attrs or {}).items()}
        self.parts = list(parts)


def loft(keys, ws, F, attrs=None, caps=False):
    """Loft a 3D mesh along w: keys (K,N,3) are its vertices at each w of ws; caps close star-shaped ends."""
    keys = np.asarray(keys, np.float64)
    ws = np.asarray(ws, np.float64)
    F = np.asarray(F, np.int64)
    K, n, _ = keys.shape
    P = np.concatenate([keys, np.broadcast_to(ws[:, None, None], (K, n, 1))], axis=2).reshape(K * n, 4)
    fn = np.stack([np.cross(keys[k][F[:, 1]] - keys[k][F[:, 0]], keys[k][F[:, 2]] - keys[k][F[:, 0]]) for k in range(K)])
    S = np.sort(F, axis=1)
    a, b, c = S[:, 0], S[:, 1], S[:, 2]
    T, N = [], []
    for k in range(K - 1):
        lo, hi = k * n, (k + 1) * n
        T += [np.stack([a + lo, b + lo, c + lo, c + hi], 1),
              np.stack([a + lo, b + lo, b + hi, c + hi], 1),
              np.stack([a + lo, a + hi, b + hi, c + hi], 1)]
        N += [np.column_stack([fn[k] + fn[k + 1], np.zeros(len(F))])] * 3  # a key shrunk to a line adds nothing
    A = {}
    for name, v in (attrs or {}).items():
        v = np.asarray(v, np.float64)
        A[name] = np.tile(v, (K, 1)) if v.ndim == 2 else v.reshape(K * n, -1)
    if caps:
        extra_p = []
        for k, sgn in ((0, -1.0), (K - 1, 1.0)):
            ci = len(P) + len(extra_p)
            extra_p.append(np.append(keys[k].mean(0), ws[k]))
            T.append(np.column_stack([F + k * n, np.full(len(F), ci)]))
            N.append(np.tile([0, 0, 0, sgn], (len(F), 1)))
            for name in A:
                A[name] = np.vstack([A[name], A[name][k * n:(k + 1) * n].mean(0)])
        P = np.vstack([P, extra_p])
    return Body(P, np.vstack(T), np.vstack(N), A, [Part(F, n, K, 0, 0)])


def frames4(path):
    """Three unit vectors across a 4D path at each point, carried along it without twist."""
    path = np.asarray(path, np.float64)
    t = np.gradient(path, axis=0)
    t /= np.linalg.norm(t, axis=1, keepdims=True)
    out = np.zeros((len(path), 3, 4))
    basis = [np.eye(4)[i] for i in np.argsort(np.abs(t[0]))[:3]]
    cur = basis
    for i in range(len(path)):
        f = []
        for v in cur:
            v = v - t[i] * (v @ t[i])
            for u in f:
                v = v - u * (v @ u)
            f.append(v / np.linalg.norm(v))
        out[i] = cur = f
    return out


def tube(path, radii, sphere_v, sphere_f, attrs=None, squash=None):
    """A 4D tube: a sphere of radius radii[i] across the path at each point (radius 0 closes an end)."""
    path = np.asarray(path, np.float64)
    radii = np.asarray(radii, np.float64)
    Fr = frames4(path)
    S, n = len(path), len(sphere_v)
    sv = sphere_v if squash is None else sphere_v[None] * squash[:, None, :]
    dirs = np.einsum("...nk,skd->snd", sv, Fr) if squash is None else np.einsum("snk,skd->snd", sv, Fr)
    P = (path[:, None, :] + radii[:, None, None] * dirs).reshape(S * n, 4)
    R = dirs.reshape(S * n, 4)
    Fs = np.sort(np.asarray(sphere_f, np.int64), axis=1)
    a, b, c = Fs[:, 0], Fs[:, 1], Fs[:, 2]
    T = []
    for k in range(S - 1):
        lo, hi = k * n, (k + 1) * n
        T += [np.stack([a + lo, b + lo, c + lo, c + hi], 1),
              np.stack([a + lo, b + lo, b + hi, c + hi], 1),
              np.stack([a + lo, a + hi, b + hi, c + hi], 1)]
    A = {k: np.asarray(v, np.float64).reshape(S * n, -1) for k, v in (attrs or {}).items()}
    T = np.vstack(T)
    return Body(P, T, R[T].sum(1), A, [Part(np.asarray(sphere_f, np.int64), n, S, 0, 0)])


def merge(bodies):
    """One body from many (attrs must match)."""
    off, toff, T, parts = 0, 0, [], []
    for b in bodies:
        T.append(b.T + off)
        parts += [p._replace(p0=p.p0 + off, t0=p.t0 + toff) for p in b.parts]
        off += len(b.P)
        toff += len(b.T)
    names = bodies[0].attrs.keys()
    return Body(np.vstack([b.P for b in bodies]), np.vstack(T), np.vstack([b.N for b in bodies]),
                {k: np.vstack([b.attrs[k] for b in bodies]) for k in names}, parts)


class Slice:
    """A 3D slice of 4D space: origin o, in-slice axes E (3,4), normal n."""

    def __init__(self, w=0.0, angle=0.0, axis=0, pivot=(0.0, 0.0, 0.0)):
        """The slice w = const, turned by angle (rad) from the given space axis into w about the pivot."""
        c, s = np.cos(angle), np.sin(angle)
        E = np.eye(4)[:3].copy()
        E[axis] = 0
        E[axis, axis], E[axis, 3] = c, s
        n = np.zeros(4)
        n[axis], n[3] = -s, c
        self.E, self.n = E, n
        self.o = np.array([pivot[0], pivot[1], pivot[2], w], np.float64)
        self.pivot = np.asarray(pivot, np.float64)

    def to3(self, P):
        return (P - self.o) @ self.E.T + self.pivot


_TRI = {1: ((0, 1), (0, 2), (0, 3)), 3: ((3, 0), (3, 1), (3, 2))}
_QUAD = ((0, 2), (0, 3), (1, 3), (1, 2))


def cut(body, sl, eps=1e-10):
    """Cross-section of a body: verts (n,3), triangles (m,3) facing outward, attrs at the verts."""
    d = (body.P - sl.o) @ sl.n
    pos = d >= 0
    dt = pos[body.T]
    cnt = dt.sum(1)
    live = (cnt > 0) & (cnt < 4)
    T, dt, cnt, Nt = body.T[live], dt[live], cnt[live], body.N[live] @ sl.E.T
    order = np.argsort(~dt, axis=1, kind="stable")  # the positive corners first
    T = np.take_along_axis(T, order, 1)
    ea, eb, tri, hint = [], [], [], []
    base = 0
    for c in (1, 3):
        Tc = T[cnt == c]
        if len(Tc):
            for i, j in _TRI[c]:
                ea.append(Tc[:, i]); eb.append(Tc[:, j])
            k = np.arange(len(Tc))
            tri.append(base + np.stack([k, k + len(Tc), k + 2 * len(Tc)], 1))
            hint.append(Nt[cnt == c])
            base += 3 * len(Tc)
    Tc = T[cnt == 2]
    if len(Tc):
        for i, j in _QUAD:
            ea.append(Tc[:, i]); eb.append(Tc[:, j])
        k, m = np.arange(len(Tc)), len(Tc)
        tri.append(base + np.stack([k, k + m, k + 2 * m], 1))
        tri.append(base + np.stack([k, k + 2 * m, k + 3 * m], 1))
        hint += [Nt[cnt == 2]] * 2
    if not tri:
        return np.zeros((0, 3)), np.zeros((0, 3), np.int64), {k: np.zeros((0, v.shape[1])) for k, v in body.attrs.items()}
    ea, eb, tri, hint = np.concatenate(ea), np.concatenate(eb), np.vstack(tri), np.vstack(hint)
    lo, hi = np.minimum(ea, eb), np.maximum(ea, eb)
    key, inv = np.unique(lo * len(body.P) + hi, return_inverse=True)
    lo, hi = key // len(body.P), key % len(body.P)
    t = (d[lo] / (d[lo] - d[hi]))[:, None]
    V = sl.to3(body.P[lo] * (1 - t) + body.P[hi] * t)
    tri = inv[tri]
    fn = np.cross(V[tri[:, 1]] - V[tri[:, 0]], V[tri[:, 2]] - V[tri[:, 0]])
    keep = np.einsum("ij,ij->i", fn, fn) > eps * eps
    tri, fn = tri[keep], fn[keep]
    flip = np.einsum("ij,ij->i", fn, hint[keep]) < 0
    tri[flip] = tri[flip][:, ::-1]
    return V, tri, {k: v[lo] * (1 - t) + v[hi] * t for k, v in body.attrs.items()}


def volume(V, F):
    """Signed volume of a closed triangle mesh."""
    return float(np.einsum("ij,ij->i", V[F[:, 0]], np.cross(V[F[:, 1]], V[F[:, 2]])).sum() / 6.0)


def closed(V, F, tol=1e-9):
    """True when, points welded, every edge is shared by exactly two triangles, once each way."""
    _, w = np.unique(np.round(V / tol).astype(np.int64), axis=0, return_inverse=True)
    F = w.reshape(-1)[F]
    F = F[(F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 2] != F[:, 0])]
    e = np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    k, n = np.unique(e[:, 0] * (F.max() + 1) + e[:, 1], return_counts=True)
    r = np.unique(e[:, 1] * (F.max() + 1) + e[:, 0])
    return bool((n == 1).all() and np.array_equal(k, r))


def box(lo, hi):
    """A box as 8 verts and 12 outward triangles."""
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    V = np.array([[x, y, z] for z in (0, 1) for y in (0, 1) for x in (0, 1)], float) * (hi - lo) + lo
    F = np.array([[0, 2, 1], [1, 2, 3], [4, 5, 6], [5, 7, 6], [0, 1, 4], [1, 5, 4],
                  [2, 6, 3], [3, 6, 7], [0, 4, 2], [2, 4, 6], [1, 3, 5], [3, 7, 5]])
    return V, F


def icosphere(n):
    t = (1 + 5 ** 0.5) / 2
    V = np.array([[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t],
                  [0, -1, -t], [0, 1, -t], [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]], float)
    F = np.array([[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
                  [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5],
                  [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]])
    V /= np.linalg.norm(V, axis=1, keepdims=True)
    for _ in range(n):
        m = {}
        def mid(a, b):
            nonlocal V
            k = (min(a, b), max(a, b))
            if k not in m:
                p = V[a] + V[b]
                V = np.vstack([V, p / np.linalg.norm(p)])
                m[k] = len(V) - 1
            return m[k]
        F2 = []
        for a, b, c in F:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            F2 += [[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]]
        F = np.array(F2)
    return V, F
