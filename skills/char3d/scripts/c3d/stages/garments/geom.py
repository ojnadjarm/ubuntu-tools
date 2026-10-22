"""Quad sheets: lofted grids, Catmull-Rom resampling, accumulation into one UV-mapped quad mesh."""
import math
from dataclasses import dataclass

import bmesh
import numpy as np

from ... import bpyutil as bu
from .base import TAU, unit


@dataclass
class Sheet:
    """Quad grid lofted around a spine: rows along it, columns around it (closed) or across it (open)."""
    P: np.ndarray
    closed: bool = True
    th: np.ndarray = None
    C: np.ndarray = None
    Ta: np.ndarray = None
    Tb: np.ndarray = None
    rad: np.ndarray = None
    ref: np.ndarray = None
    N: np.ndarray = None
    flip: bool = False
    keep: np.ndarray = None

    def update_normals(self):
        P = self.P
        dr = np.gradient(P, axis=0)
        dc = (np.roll(P, -1, 1) - np.roll(P, 1, 1)) / 2 if self.closed else np.gradient(P, axis=1)
        n = unit(np.cross(dr, dc))
        ref = self.ref if self.ref is not None else P - self.C[:, None]
        self.flip = float(np.sum(n * ref)) < 0
        self.N = -n if self.flip else n
        return self

    def active(self):
        """Vertices used by at least one kept face."""
        if self.keep is None:
            return np.ones(self.P.shape[:2], bool)
        R, C = self.P.shape[:2]
        k = self.keep
        act = np.zeros((R, C), bool)
        cols = k.shape[1]
        jn = (np.arange(cols) + 1) % C
        for di, js in ((0, slice(0, cols)), (1, slice(0, cols)), (0, jn), (1, jn)):
            act[di:R - 1 + di, js] |= k
        return act

    @property
    def s(self):
        """Arc length (m) down the rows, averaged over the columns."""
        return np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(self.P, axis=0), axis=-1).mean(1))])

    def ray(self, along, th):
        """Spine point and outward direction for a surface coordinate (arc length along the rows, angle)."""
        i = np.interp(along, self.s, np.arange(len(self.P)))
        lo = int(min(i, len(self.P) - 2))
        f = i - lo
        mix = lambda a: a[lo] * (1 - f) + a[lo + 1] * f  # noqa: E731
        d = math.cos(th) * mix(self.Ta) + math.sin(th) * mix(self.Tb)
        return mix(self.C), d / np.linalg.norm(d), float(mix(self.rad))


def loft(C, up, rx, ry, cols, closed=True, th=None, off=None, side=(1.0, 0.0, 0.0)):
    """Rings around a spine: C + rx cos(th) Ta + ry sin(th) Tb + off along the ring's radial direction."""
    C = np.asarray(C, float)
    R = len(C)
    T = unit(np.broadcast_to(np.asarray(up, float), C.shape).copy())
    side = np.asarray(side, float)
    Ta = unit(side - (T @ side)[:, None] * T)
    Tb = np.cross(T, Ta)
    if th is None:
        th = math.pi / 2 + np.linspace(0, TAU, cols, endpoint=not closed)
    th = np.broadcast_to(th, (R, cols)).copy()
    rx, ry = np.broadcast_to(rx, (R,)).astype(float), np.broadcast_to(ry, (R,)).astype(float)
    c, s = np.cos(th)[..., None], np.sin(th)[..., None]
    P = C[:, None] + rx[:, None, None] * c * Ta[:, None] + ry[:, None, None] * s * Tb[:, None]
    if off is not None:
        P += off[..., None] * unit(c * Ta[:, None] + s * Tb[:, None])
    return Sheet(P, closed, th, C, Ta, Tb, (rx + ry) / 2)


def resample(points, n):
    """Catmull-Rom through the points, then n samples evenly spaced by arc length."""
    p = np.asarray(points, float)
    q = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
    t = np.linspace(0, 1, 24, endpoint=False)[:, None]
    dense = []
    for i in range(1, len(q) - 2):
        a, b, c, d = q[i - 1], q[i], q[i + 1], q[i + 2]
        dense.append(0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t ** 2 + (3 * b - a - 3 * c + d) * t ** 3))
    dense = np.vstack(dense + [p[-1:]])
    acc = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(dense, axis=0), axis=1))])
    u = np.linspace(0, acc[-1], n)
    return np.stack([np.interp(u, acc, dense[:, k]) for k in range(dense.shape[1])], 1), acc[-1]


def superellipse(a, hw, hd, k=4.0):
    """Points of a rounded rectangle (half width hw, half depth hd) at angles a."""
    c, s = np.cos(a), np.sin(a)
    return hw * np.sign(c) * np.abs(c) ** (2 / k), hd * np.sign(s) * np.abs(s) ** (2 / k)


class Geo:
    """Sheets and caps accumulated into one quad mesh with per-loop UVs."""

    def __init__(self):
        self.V, self.F, self.UV, self.n = [], [], [], 0

    def sheet(self, sh):
        """Add the sheet's kept quads; returns its (rows, cols) grid of mesh vertex ids, -1 where culled."""
        R, C = sh.P.shape[:2]
        idx = np.arange(R * C).reshape(R, C)
        cols = C if sh.closed else C - 1
        u, v = np.linspace(0, 1, cols + 1), np.linspace(0, 1, R)
        i, j = np.meshgrid(np.arange(R - 1), np.arange(cols), indexing='ij')
        jn = (j + 1) % C
        F = np.stack([idx[i, j], idx[i + 1, j], idx[i + 1, jn], idx[i, jn]], -1).reshape(-1, 4)
        UV = np.stack([np.stack(x, -1) for x in ((u[j], v[i]), (u[j], v[i + 1]), (u[j + 1], v[i + 1]), (u[j + 1], v[i]))],
                      -2).reshape(-1, 4, 2)
        if sh.flip:
            F, UV = F[:, ::-1], UV[:, ::-1]
        V, grid = sh.P.reshape(-1, 3), idx
        if sh.keep is not None:
            F, UV = F[sh.keep.ravel()], UV[sh.keep.ravel()]
            used = np.unique(F)
            remap = np.full(len(V), -1)
            remap[used] = np.arange(len(used))
            V, F, grid = V[used], remap[F], remap.reshape(R, C)
        base = self.n
        self._add(V, F, UV)
        return np.where(grid >= 0, grid + base, -1)

    def cap(self, ring, out):
        """Close a ring of vertex ids (even count) with a ladder of quads facing `out`; no new vertices."""
        K = len(ring)
        P = np.array([self.V[k] for k in ring])
        F = np.array([(ring[i], ring[i + 1], ring[K - 2 - i], ring[K - 1 - i]) for i in range(K // 2 - 1)])
        if np.cross(P, np.roll(P, -1, 0)).sum(0) @ out < 0:
            F = F[:, ::-1]
        a = unit(np.cross(out, [0.31, 0.53, 0.79]))
        b = np.cross(out, a)
        pos = {k: (p @ a, p @ b) for k, p in zip(ring, P)}
        uv = np.array([[pos[k] for k in f] for f in F])
        uv = (uv - uv.reshape(-1, 2).min(0)) / max(np.ptp(uv.reshape(-1, 2), 0).max(), 1e-9)
        self.F.extend(F.tolist())
        self.UV.append(uv.reshape(-1, 2))

    def _add(self, V, F, UV):
        self.V.extend(V.tolist())
        self.F.extend((F + self.n).tolist())
        self.UV.append(UV.reshape(-1, 2))
        self.n += len(V)

    def build(self, name, thick, merge=False):
        ob = bu.mesh_object(name, self.V, self.F)
        ob.data.uv_layers.new(name='UVMap').data.foreach_set('uv', np.concatenate(self.UV).astype(np.float32).ravel())
        if merge:
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
            bm.to_mesh(ob.data)
            bm.free()
        ob.data.shade_smooth()
        if thick:
            m = ob.modifiers.new('solidify', 'SOLIDIFY')
            m.thickness, m.offset, m.use_even_offset = thick, 1.0, True
        return ob


def smooth(D, closed, n):
    for _ in range(n):
        rows = np.pad(D, ((1, 1), (0, 0), (0, 0)), mode='edge')
        if closed:
            left, right = np.roll(D, 1, 1), np.roll(D, -1, 1)
        else:
            cols = np.pad(D, ((0, 0), (1, 1), (0, 0)), mode='edge')
            left, right = cols[:, :-2], cols[:, 2:]
        D = (2 * D + rows[:-2] + rows[2:] + left + right) / 6
    return D
