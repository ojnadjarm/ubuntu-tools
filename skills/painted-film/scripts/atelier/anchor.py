"""Seeds tied to surface points: stable ids, level-of-detail octaves, stroke direction (ARCHITECTURE.md 5, rules 1, 2, 5)."""
import numpy as np

from .scene import Seeds

NEAR = 0.1  # m: the reference's near clip; nearer seeds are not placed
MIN_FACING = 0.05  # cosine floor of the facing, so grazing surfaces keep a finite level
U64 = np.uint64


def mix(*parts):
    """splitmix64 of the parts (ints or uint64 arrays), wrapping on purpose: a stable hash, no frame in it."""
    h = U64(0x243F6A8885A308D3)
    with np.errstate(over="ignore"):
        for p in parts:
            h = (h ^ np.asarray(p).astype(U64)) + U64(0x9E3779B97F4A7C15)
            h = (h ^ (h >> U64(30))) * U64(0xBF58476D1CE4E5B9)
            h = (h ^ (h >> U64(27))) * U64(0x94D049BB133111EB)
            h = h ^ (h >> U64(31))
    return h


def unit(h):
    """A hash -> uniform float in [0, 1)."""
    return (np.asarray(h, U64) >> U64(11)).astype(np.float64) * 2.0 ** -53


def split(V, F, max_edge):
    """Longest-edge halving until no edge is longer than max_edge: parent face of each piece and its corners'
    barycentrics in the parent (s, 3, 3)."""
    parent = np.arange(len(F))
    B = np.tile(np.eye(3), (len(F), 1, 1))
    tri = V[F]
    while True:
        Q = B @ tri[parent]
        L = np.linalg.norm(Q[:, [1, 2, 0]] - Q, axis=2)
        big = L.max(1) > max_edge
        if not big.any():
            return parent, B
        k = L[big].argmax(1)
        Bb, n = B[big], big.sum()
        r = np.arange(n)
        c0, c1, c2 = Bb[r, k], Bb[r, (k + 1) % 3], Bb[r, (k + 2) % 3]
        mid = 0.5 * (c0 + c1)
        parent = np.concatenate([parent[~big], parent[big], parent[big]])
        B = np.concatenate([B[~big], np.stack([c0, mid, c2], 1), np.stack([mid, c1, c2], 1)])


def _tangent_rule(N, direction):
    """Unit tangent per face from the material's rule: "course" (level, along the courses), "down" (down the
    slope) or a world vector, each projected on the face; faces where it vanishes take the world x."""
    if isinstance(direction, str):
        up = np.array([0.0, 0.0, 1.0])
        v = np.cross(up, N) if direction == "course" else -up - (N @ -up)[:, None] * N
        if direction not in ("course", "down"):
            raise ValueError("unknown direction rule %r" % direction)
    else:
        d = np.asarray(direction, float)
        v = d - (N @ d)[:, None] * N
    x = np.array([1.0, 0.0, 0.0]) - N[:, :1] * N
    v = np.where((np.linalg.norm(v, axis=1) < 0.3)[:, None], x, v)
    return v / np.maximum(np.linalg.norm(v, axis=1), 1e-12)[:, None]


def _normals(tri):
    e1, e2 = tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]
    n = np.cross(e1, e2)
    return e1, e2, n / np.maximum(np.linalg.norm(n, axis=1), 1e-12)[:, None]


def level(P, N, cam, px_per_stroke, rho0):
    """Octave level L at each point: log4 of the seed density the view needs (one seed per px_per_stroke^2 of
    screen) over rho0. Also the view depth."""
    d = P - cam.pos
    z = -(d @ cam.R[:, 2])
    dist = np.linalg.norm(d, axis=1)
    f = cam.lens_mm / cam.sensor_mm * cam.size[0]
    facing = np.maximum(np.abs((N * d).sum(1)) / np.maximum(dist, 1e-12), MIN_FACING)
    with np.errstate(divide="ignore", invalid="ignore"):
        need = f * f * facing / (np.maximum(z, NEAR) * np.maximum(dist, NEAR) * px_per_stroke ** 2)
    return 0.5 * np.log2(need / rho0), z


def _cull(Q, cam, px_per_stroke, rho0):
    """Triangles (k, 3, 3) whose bounding sphere can be in view, and the highest level a point of each can need."""
    c = Q.mean(1)
    R = np.linalg.norm(Q - c[:, None], axis=2).max(1)
    cc = (c - cam.pos) @ cam.R
    W, H = cam.size
    f = cam.lens_mm / cam.sensor_mm * W
    keep = -cc[:, 2] + R > NEAR
    for axis, half in ((0, W / 2 + W / 8), (1, H / 2 + W / 8)):  # side planes, margin W/8 px
        for s in (1.0, -1.0):
            keep &= (s * f * cc[:, axis] + half * cc[:, 2]) / np.hypot(f, half) <= R
    lo = np.maximum(np.linalg.norm(c - cam.pos, axis=1) - R, NEAR)
    corner = np.hypot(f, 0.5 * np.hypot(W, H)) / f  # 1 / cos of the view's widest angle
    return keep, 0.5 * np.log2(f * f * corner / (lo * lo * px_per_stroke ** 2) / rho0)


class SeedBank:
    """Seeds on a 3D surface of fixed topology. Octave j holds rho0 * 4^j seeds per m2 (of the rest surface); a
    seed is (piece, octave, index) and everything about it comes from its id, never from the frame."""

    def __init__(self, V, F, material, ident, direction, rho0, seed, octaves=8, max_edge=0.5):
        V, F = np.asarray(V, np.float64), np.asarray(F, np.int64)
        self.F, self.rho0, self.octaves, self.material = F, float(rho0), int(octaves), int(material)
        self.seed = int(seed) & 0xFFFFFFFFFFFFFFFF
        ident = np.asarray(ident)
        self.ident = (ident[F[:, 0]] if ident.ndim else np.full(len(F), ident)).astype(np.int32)
        self.parent, self.B = split(V, F, max_edge)
        Q = self.B @ V[F][self.parent]
        self.area = 0.5 * np.linalg.norm(np.cross(Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0]), axis=1)
        e1, e2, N = _normals(V[F])
        T = _tangent_rule(N, direction)
        g11, g12, g22 = (e1 * e1).sum(1), (e1 * e2).sum(1), (e2 * e2).sum(1)
        r1, r2 = (e1 * T).sum(1), (e2 * T).sum(1)
        det = g11 * g22 - g12 * g12
        ok = np.abs(det) > 1e-18
        det = np.where(ok, det, 1.0)
        self.ab = np.where(ok[:, None], np.column_stack([(g22 * r1 - g12 * r2) / det, (g11 * r2 - g12 * r1) / det]), 0.0)

    def _visible_pieces(self, V_now, cam, px_per_stroke):
        """Pieces that can be in view and their highest possible level: faces culled first, then their pieces."""
        tri = V_now[self.F]
        keep, _ = _cull(tri, cam, px_per_stroke, self.rho0)
        idx = np.nonzero(keep[self.parent])[0]
        keep, top = _cull(self.B[idx] @ tri[self.parent[idx]], cam, px_per_stroke, self.rho0)
        return idx[keep], top[keep]

    def place(self, V_now, cam, px_per_stroke) -> Seeds:
        """The seeds the view can need, at their places on the surface V_now (same topology as at construction)."""
        V_now = np.asarray(V_now, np.float64)
        pieces, top = self._visible_pieces(V_now, cam, px_per_stroke)
        W, H = cam.size
        m = W / 8
        out = []
        for j in range(self.octaves):
            sel = pieces[top >= j - 1]
            if not len(sel):
                break
            n = np.floor(self.area[sel] * self.rho0 * 4.0 ** j + unit(mix(self.seed, sel, j, 0xC0))).astype(np.int64)
            rep = np.repeat(sel, n)
            if not len(rep):
                continue
            idx = np.arange(len(rep)) - np.repeat(np.cumsum(n) - n, n)
            ids = mix(self.seed, rep, j, idx)
            u, v = unit(mix(ids, 1)), unit(mix(ids, 2))
            flip = u + v > 1
            u, v = np.where(flip, 1 - u, u), np.where(flip, 1 - v, v)
            bary = (1 - u - v)[:, None] * self.B[rep, 0] + u[:, None] * self.B[rep, 1] + v[:, None] * self.B[rep, 2]
            face = self.parent[rep]
            tri = V_now[self.F[face]]
            P = np.einsum("kc,kcd->kd", bary, tri)
            e1, e2, N = _normals(tri)
            T = self.ab[face, :1] * e1 + self.ab[face, 1:] * e2
            T /= np.maximum(np.linalg.norm(T, axis=1), 1e-12)[:, None]
            L, z = level(P, N, cam, px_per_stroke, self.rho0)
            op = np.ones(len(P)) if j == 0 else np.clip(L - j + 1, 0.0, 1.0)
            xy, _ = cam.project(P)
            ok = (z > NEAR) & (op > 0) & (xy[:, 0] > -m) & (xy[:, 0] < W + m) & (xy[:, 1] > -m) & (xy[:, 1] < H + m)
            out.append((ids[ok], P[ok], N[ok], T[ok], np.full(ok.sum(), j), self.ident[face[ok]], op[ok],
                        px_per_stroke * 2.0 ** (L[ok] - j)))
        return _seeds(out, self.material)


def _seeds(parts, material):
    if not parts:
        parts = [(np.zeros(0, U64), *(np.zeros((0, 3)),) * 3, np.zeros(0), np.zeros(0), np.zeros(0), np.zeros(0))]
    ids, P, N, T, octv, ident, op, px = (np.concatenate(c) for c in zip(*parts))
    k = len(ids)
    return Seeds(ids.astype(U64), P, N, T, octv.astype(np.uint8), np.full(k, material, np.int16), ident.astype(np.int32),
                 np.zeros(k, np.uint8), np.zeros(k, np.float32), np.zeros(k, np.float32), np.zeros(k, np.uint8),
                 op.astype(np.float32), px.astype(np.float32))


def concat(seeds):
    """One Seeds of several (a scene's banks together)."""
    return Seeds(*(np.concatenate([getattr(s, k) for s in seeds]) for k in Seeds.__dataclass_fields__))
