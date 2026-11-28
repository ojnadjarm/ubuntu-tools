"""The 4D provider (B1): Scene4D cuts 4D bodies by the frame's slice; SeedBank4D ties each seed to a line through a
body and places it where the slice cuts that line (ARCHITECTURE.md 6). numpy only: runs in Blender too."""
import os
import sys
import time
import zlib

import numpy as np

from .. import diskcache
from ..anchor import (CREASE_COS, MARK, NEAR, _cull, _normals, _seeds, _tangent_rule, concat, creases, inside, level, mix,
                      split, unit)
from ..scene import Mesh, ident_of
from . import slicer

E4 = np.eye(4)
# The three nodes s = 0, beta_c, beta_b + beta_c start the three tets of a prism: [a0 b0 c0 c1], [a0 b0 b1 c1],
# [a0 a1 b1 c1]; at them the face's sorted corners (a, b, c) weigh on key k: a b c, a b, a; on key k+1: none, c, b c.
TET_C = np.array([[0, 1, 2, 2], [0, 1, 1, 2], [0, 0, 1, 2]])  # each tet's corners: which sorted corner,
TET_K = np.array([[0, 0, 0, 1], [0, 0, 1, 1], [0, 1, 1, 1]], bool)  # on key k (False) or k+1 (True)
CHUNK = 3_000_000  # line nodes evaluated at once
BLOCK = 65536  # seeds placed at once
EMERGE = 0.1  # how far (m along the slice's normal) the slice moves past a line's turn while its new strokes fade in
CREASE_RAMP = 0.1  # a crease's marks fade in as the cosine of its faces' angle falls from CREASE_COS + this to CREASE_COS - this


def _area(Q):
    """Areas of triangles (k, 3, d) in any dimension."""
    e1, e2 = Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0]
    g = (e1 * e1).sum(1) * (e2 * e2).sum(1) - (e1 * e2).sum(1) ** 2
    return 0.5 * np.sqrt(np.maximum(g, 0.0))


def _normal4(p):
    """Normal (k, 4) of the 3D hyperplane through four 4D points (k, 4, 4), unnormalised."""
    M = p[:, 1:] - p[:, :1]
    out = np.empty((len(p), 4))
    for i in range(4):
        out[:, i] = (-1) ** i * np.linalg.det(M[:, :, [j for j in range(4) if j != i]])
    return out


def _unit(v, fallback):
    n = np.linalg.norm(v, axis=1, keepdims=True)
    return np.where(n > 1e-12, v / np.maximum(n, 1e-300), fallback)


class SeedBank4D:
    """Seeds on a 4D body's recipe faces: a seed is (piece, octave, index) as in SeedBank, its barycentric place in
    its face is a line through the body along the sweep, and it lands where the slice cuts that line (one stroke per
    crossing; the n-th monotone run of the line across the slice adds n to the id)."""

    def __init__(self, body, material, ident, direction, rho0, seed, octaves=8, max_edge=0.5, mark_width=0.02):
        self.body, self.rho0, self.octaves, self.material = body, float(rho0), int(octaves), int(material)
        self.mark_width = float(mark_width)
        self.seed = int(seed) & 0xFFFFFFFFFFFFFFFF
        c0, perm, step, K, tet0, mp, rest = [], [], [], [], [], [], []
        P = body.P
        for p in body.parts:
            F = np.asarray(p.F, np.int64)
            m = len(F)
            c0.append(p.p0 + F)
            perm.append(np.argsort(F, axis=1, kind="stable"))
            step.append(np.full(m, p.n)), K.append(np.full(m, p.K)), mp.append(np.full(m, m))
            tet0.append(p.t0 + np.arange(m))
            keys = np.stack([P[p.p0 + k * p.n + F] for k in range(p.K)])  # (K, m, 3, 4)
            best = np.argmax(np.stack([_area(q) for q in keys]), axis=0)  # the face at its largest: its rest
            rest.append(keys[best, np.arange(m)])
        cat = lambda a, dt, shape: np.concatenate(a).astype(dt) if a else np.zeros(shape, dt)
        self.c0, self.perm = cat(c0, np.int64, (0, 3)), cat(perm, np.int64, (0, 3))
        self.step, self.K, self.tet0, self.m = (cat(a, np.int64, 0) for a in (step, K, tet0, mp))
        rest = cat(rest, np.float64, (0, 3, 4))
        ident = np.asarray(ident)
        self.ident = (ident[self.c0[:, 0]] if ident.ndim else np.full(len(self.c0), ident)).astype(np.int32)
        self.rest_area = _area(rest)
        self.parent, self.B = split(rest.reshape(-1, 4), np.arange(3 * len(rest)).reshape(-1, 3), max_edge)
        self.area = _area(self.B @ rest[self.parent])
        self.by_face = np.argsort(self.parent, kind="stable")
        self.first = np.searchsorted(self.parent[self.by_face], np.arange(len(rest) + 1))
        e1, e2, N = _normals(rest[..., :3])
        T = _tangent_rule(N, direction)
        g11, g12, g22 = (e1 * e1).sum(1), (e1 * e2).sum(1), (e2 * e2).sum(1)
        r1, r2 = (e1 * T).sum(1), (e2 * T).sum(1)
        det = g11 * g22 - g12 * g12
        ok = np.abs(det) > 1e-18
        det = np.where(ok, det, 1.0)
        self.ab = np.where(ok[:, None], np.column_stack([(g22 * r1 - g12 * r2) / det, (g11 * r2 - g12 * r1) / det]), 0.0)
        nseg = np.maximum(self.K - 1, 0)
        self.pface = np.repeat(np.arange(len(self.K)), nseg)
        self.pk = np.arange(len(self.pface)) - np.repeat(np.cumsum(nseg) - nseg, nseg)
        self.koff = np.cumsum(self.K) - self.K
        self.nkey = self._key_normals()
        self._crease_lines(max_edge)

    @classmethod
    def cached(cls, folder, body, *args):
        """cls(body, *args), read back from the disk cache folder when made before (folder None: made)."""
        made = []

        def make():
            made.append(cls(body, *args))
            return {k: v for k, v in vars(made[0]).items() if k != "body"}
        parts = [a for p in body.parts for a in (p.F, (p.n, p.K, p.p0, p.t0))]
        d = diskcache.get(folder, "bank4d_" + diskcache.key(body.P, body.T, body.N, *parts, *args, *_SOURCES), make)
        if made:
            return made[0]
        bank = cls.__new__(cls)
        bank.__dict__.update(d, body=body)
        return bank

    def _key_normals(self):
        """A 4D normal per face and key: the mean of the face's tets on either side of the key. Lerped along the
        sweep it turns smoothly where the cut's facets do not (level and stroke direction read it). Keeps each tet's
        unit normal (self.tn, indexed like body.N): a seed's normal reads it instead of solving its tet again."""
        out = np.zeros((int(self.K.sum()), 4))
        self.tn = np.zeros((len(self.body.T), 4))
        for a in range(0, len(self.pface), 200_000):
            f, k = self.pface[a:a + 200_000], self.pk[a:a + 200_000]
            lo = np.take_along_axis(self.c0[f], self.perm[f], 1) + (k * self.step[f])[:, None]
            hi = lo + self.step[f][:, None]
            for j in range(3):
                c = np.where(TET_K[j], hi[:, TET_C[j]], lo[:, TET_C[j]])
                m = _normal4(self.body.P[c])
                tet = self.tet0[f] + (3 * k + j) * self.m[f]
                m *= np.where((m * self.body.N[tet]).sum(1) < 0, -1.0, 1.0)[:, None]
                m = _unit(m, 0.0)
                self.tn[tet] = m
                np.add.at(out, self.koff[f] + k, m)
                np.add.at(out, self.koff[f] + k + 1, m)
        return _unit(out, 0.0)

    def _visible_pieces(self, d, sl, cam, px_per_stroke):
        """Pieces whose part of a prism the slice cuts can be in view, and the highest level a point of each needs."""
        lo = self.c0[self.pface] + (self.pk * self.step[self.pface])[:, None]
        hi = lo + self.step[self.pface][:, None]
        dd = np.concatenate([d[lo], d[hi]], 1)
        live = np.nonzero((dd.min(1) < 0) & (dd.max(1) >= 0))[0]
        Q = sl.to3(self.body.P[np.concatenate([lo[live], hi[live]], 1)])
        keep, _ = _cull(Q, cam, px_per_stroke, self.rho0)
        live = live[keep]
        f = self.pface[live]
        cnt = self.first[f + 1] - self.first[f]
        pr = np.repeat(live, cnt)
        piece = self.by_face[np.repeat(self.first[f], cnt) + np.arange(cnt.sum()) - np.repeat(np.cumsum(cnt) - cnt, cnt)]
        B = self.B[piece]
        q = np.concatenate([B @ self.body.P[lo[pr]], B @ self.body.P[hi[pr]]], 1)
        keep, top = _cull(sl.to3(q), cam, px_per_stroke, self.rho0)
        best = np.full(len(self.parent), -np.inf)
        np.maximum.at(best, piece[keep], top[keep])
        pieces = np.nonzero(best > -np.inf)[0]
        return pieces, best[pieces]

    def _crossings(self, face, beta, d):
        """Where each seed's line (face, barycentrics in the face's order) crosses the slice: seed row, key k,
        tet j (0..2), place s in [0, 1] between keys k and k+1, its run label, and its fade: how far past the turns that
        bound its run the slice is, over EMERGE (a pair of crossings born where the line touches the slice starts at 0)."""
        out = []
        for Kv in np.unique(self.K[face]):
            rows = np.nonzero(self.K[face] == Kv)[0]
            for a in range(0, len(rows), max(1, CHUNK // (3 * Kv))):
                r = rows[a:a + max(1, CHUNK // (3 * Kv))]
                f = face[r]
                bs = np.take_along_axis(beta[r], self.perm[f], 1)
                cs = np.take_along_axis(self.c0[f], self.perm[f], 1)
                dk = d[cs[:, None, :] + (np.arange(Kv)[None, :, None] * self.step[f][:, None, None])]  # (s, K, 3)
                lo, hi = bs[:, None, :] * dk[:, :-1], bs[:, None, :] * dk[:, 1:]  # the nodes' weights
                D = np.stack([(lo[..., 0] + lo[..., 1]) + lo[..., 2], (lo[..., 0] + lo[..., 1]) + hi[..., 2],
                              lo[..., 0] + (hi[..., 1] + hi[..., 2])], -1)
                seq = np.concatenate([D.reshape(len(r), -1), (bs * dk[:, -1]).sum(1)[:, None]], 1)
                neg = seq < 0
                slope = np.sign(np.diff(seq, axis=1))
                at = np.maximum.accumulate(np.where(slope != 0, np.arange(slope.shape[1]), 0), axis=1)
                slope = np.take_along_axis(slope, at, 1)
                runs = np.concatenate([np.zeros((len(r), 1), np.int64),
                                       np.cumsum((slope[:, 1:] != slope[:, :-1]) & (slope[:, :-1] != 0), 1)], 1)
                si, ji = np.nonzero(neg[:, :-1] != neg[:, 1:])
                nint = runs.shape[1]
                start = np.concatenate([np.ones((len(r), 1), bool), runs[:, 1:] != runs[:, :-1]], 1)
                first = np.maximum.accumulate(np.where(start, np.arange(nint), 0), axis=1)[si, ji]
                end = np.concatenate([runs[:, 1:] != runs[:, :-1], np.ones((len(r), 1), bool)], 1)
                last = np.minimum.accumulate(np.where(end, np.arange(nint), nint)[:, ::-1], axis=1)[:, ::-1][si, ji]
                depth = np.minimum(np.where(first > 0, np.abs(seq[si, first]), np.inf),
                                   np.where(last < nint - 1, np.abs(seq[si, last + 1]), np.inf))
                t = seq[si, ji] / (seq[si, ji] - seq[si, ji + 1])
                k, j = ji // 3, ji % 3
                nodes = np.column_stack([np.zeros(len(r)), bs[:, 2], bs[:, 1] + bs[:, 2], np.ones(len(r))])
                s = nodes[si, j] + t * (nodes[si, j + 1] - nodes[si, j])
                out.append((r[si], k, j, s, runs[si, ji], np.clip(depth / EMERGE, 0.0, 1.0)))
        if not out:
            z = np.zeros(0, np.int64)
            return z, z, z, np.zeros(0), z, np.zeros(0)
        row, k, j, s, run, fade = (np.concatenate(c) for c in zip(*out))
        o = np.lexsort((k * 3 + j, row))
        return row[o], k[o], j[o], s[o], run[o], fade[o]

    def _point(self, f, b, k, s):
        """The 4D point at place s between keys k and k+1 of the line (face f, barycentrics b), and the face's corners
        at both keys."""
        c_lo = self.c0[f] + (k * self.step[f])[:, None]
        c_hi = c_lo + self.step[f][:, None]
        bs = np.take_along_axis(b, self.perm[f], 1)
        lo_s = np.column_stack([bs[:, 1] + bs[:, 2], bs[:, 2], np.zeros(len(f))])
        mv = np.clip(s[:, None] - lo_s, 0.0, bs)
        sc_lo, sc_hi = np.take_along_axis(c_lo, self.perm[f], 1), np.take_along_axis(c_hi, self.perm[f], 1)
        P4 = self.body.P
        X = np.einsum("kv,kvd->kd", bs - mv, P4[sc_lo]) + np.einsum("kv,kvd->kd", mv, P4[sc_hi])
        return X, c_lo, c_hi

    def _crease_lines(self, max_edge):
        """The swept edges where two recipe faces meet at an angle at some key (ridges of the 4D body), cut into
        pieces no longer than max_edge at their longest: each crease (f1, f2), the corner of f1 it starts at, its
        end points at key 0, and its (edge, key) rows."""
        P, ef, kc, ev, rl, foff = self.body.P, [], [], [], [], 0
        for p in self.body.parts:
            F = np.asarray(p.F, np.int64)
            keys = np.stack([P[p.p0 + k * p.n:p.p0 + (k + 1) * p.n, :3] for k in range(p.K)])
            rest = int(np.argmax([_area(q[F]).sum() for q in keys]))
            e, f2, _ = creases(keys[rest], F, 2.0)  # every edge of two faces, welded at the rest key
            cos = np.stack([(n[f2[:, 0]] * n[f2[:, 1]]).sum(1) for n in (_normals(q[F])[2] for q in keys)])
            keep = cos.min(0) < CREASE_COS + CREASE_RAMP
            e, f2 = e[keep], f2[keep]
            kc.append(np.argmax(F[f2[:, 0]] == e[:, :1], axis=1))
            ef.append(f2 + foff)
            ev.append(p.p0 + e)
            rl.append(np.linalg.norm(keys[:, e[:, 1]] - keys[:, e[:, 0]], axis=2).max(0) if len(e) else np.zeros(0))
            foff += len(F)
        cat = lambda a, dt, shape: np.concatenate(a).astype(dt) if a else np.zeros(shape, dt)
        self.ef, self.ek, self.ev, rl = cat(ef, np.int64, (0, 2)), cat(kc, np.int64, 0), cat(ev, np.int64, (0, 2)), cat(rl, float, 0)
        n = np.maximum(np.ceil(rl / max_edge).astype(np.int64), 1)
        self.me = np.repeat(np.arange(len(n)), n)
        i = np.arange(len(self.me)) - np.repeat(np.cumsum(n) - n, n)
        self.ms = np.column_stack([i, i + 1]) / n[self.me, None]
        self.mr = 0.5 * rl[self.me] / n[self.me]  # a piece's half length at its longest
        self.mfirst = np.r_[0, np.cumsum(n)]
        nseg = np.maximum(self.K[self.ef[:, 0]] - 1, 0) if len(self.ef) else np.zeros(0, np.int64)
        self.qe = np.repeat(np.arange(len(nseg)), nseg)
        self.qk = np.arange(len(self.qe)) - np.repeat(np.cumsum(nseg) - nseg, nseg)

    def marks(self, sl, cam, px_per_stroke):
        """Mark seeds where the slice cuts the creases' lines (SeedBank's rules): octave j holds sqrt(rho0) * 2^j a metre
        of the crease at its longest; kind 1 on a convex crease (a lit edge), 2 on a concave one (a joint); a crease
        fades in as its faces turn to an angle, and a crossing born where its line touches the slice over EMERGE."""
        if not len(self.qe):
            return _seeds([], self.material)
        P4 = self.body.P
        d = (P4 - sl.o) @ sl.n
        W, H = cam.size
        fl, rho = cam.lens_mm / cam.sensor_mm * W, np.sqrt(self.rho0)
        step = self.step[self.ef[self.qe, 0]]
        a = self.ev[self.qe] + (self.qk * step)[:, None]
        dd = np.concatenate([d[a], d[a + step[:, None]]], 1)
        live = np.nonzero((dd.min(1) < 0) & (dd.max(1) >= 0))[0]
        e, k = self.qe[live], self.qk[live]
        cnt = self.mfirst[e + 1] - self.mfirst[e]
        row = np.repeat(np.arange(len(e)), cnt)
        piece = np.repeat(self.mfirst[e], cnt) + np.arange(cnt.sum()) - np.repeat(np.cumsum(cnt) - cnt, cnt)
        u = self.ms[piece]
        lo = a[live][row]
        hi = lo + step[live][row][:, None]
        Q = sl.to3(np.stack([(1 - u[:, i:i + 1]) * P4[c[:, 0]] + u[:, i:i + 1] * P4[c[:, 1]]
                             for c in (lo, hi) for i in (0, 1)], 1))
        keep, _ = _cull(Q, cam, px_per_stroke, self.rho0)
        c = Q.mean(1)
        R = np.linalg.norm(Q - c[:, None], axis=2).max(1)
        near = np.maximum(np.linalg.norm(c - cam.pos, axis=1) - R, NEAR)
        top = np.log2(fl * np.hypot(fl, 0.5 * np.hypot(W, H)) / fl / (near * px_per_stroke) / rho)
        best = np.full(len(self.me), -np.inf)
        np.maximum.at(best, piece[keep], top[keep])
        pieces = np.nonzero(best > -np.inf)[0]
        top = best[pieces]
        out = []
        for j in range(2 * self.octaves):
            sel = pieces[top >= j - 1]
            if not len(sel):
                break
            n = np.floor(2.0 * self.mr[sel] * rho * 2.0 ** j + unit(mix(self.seed, MARK, sel, j, 0xC0))).astype(np.int64)
            rep = np.repeat(sel, n)
            if not len(rep):
                continue
            ids = mix(self.seed, MARK, rep, j, np.arange(len(rep)) - np.repeat(np.cumsum(n) - n, n))
            e = self.me[rep]
            s = self.ms[rep, 0] + unit(mix(ids, 1)) * (self.ms[rep, 1] - self.ms[rep, 0])
            f1, kc = self.ef[e, 0], self.ek[e]
            beta = np.zeros((len(rep), 3))
            beta[np.arange(len(rep)), kc] = 1 - s
            beta[np.arange(len(rep)), (kc + 1) % 3] = s
            r, kk, _, sk, run, fade = self._crossings(f1, beta, d)
            if not len(r):
                continue
            e, f1, kc = e[r], f1[r], kc[r]
            ids = np.where(run == 0, ids[r], mix(ids[r], run))
            X, c_lo, c_hi = self._point(f1, beta[r], kk, sk)
            P = sl.to3(X)
            at_s = lambda f: sl.to3((1 - sk)[:, None, None] * P4[c_lo - self.c0[f1] + self.c0[f]]
                                    + sk[:, None, None] * P4[c_hi - self.c0[f1] + self.c0[f]])  # a face at s, its order
            t1, t2 = at_s(f1), at_s(self.ef[e, 1])
            N1, N2 = (_normals(t)[2] for t in (t1, t2))
            for Nf, f in ((N1, f1), (N2, self.ef[e, 1])):  # outward, by the hint of the face's first tet at key k
                Nf *= np.where((Nf * (self.body.N[self.tet0[f] + 3 * kk * self.m[f]] @ sl.E.T)).sum(1) < 0, -1.0, 1.0)[:, None]
            Ne = _unit(N1 + N2, N1)
            D = t1[np.arange(len(r)), (kc + 1) % 3] - t1[np.arange(len(r)), kc]
            Dl = np.linalg.norm(D, axis=1)
            convex = ((t2.mean(1) - t1.mean(1)) * N1).sum(1) < 0
            xy, z = cam.project(P)
            L = np.log2(fl / (np.maximum(z, NEAR) * px_per_stroke) / rho)
            view = _unit(cam.pos - P, 0.0)
            front = np.maximum((N1 * view).sum(1), (N2 * view).sum(1))
            angle = np.clip((CREASE_COS + CREASE_RAMP - (N1 * N2).sum(1)) / (2 * CREASE_RAMP), 0.0, 1.0)
            op = ((np.ones(len(P)) if j == 0 else np.clip(L - j + 1, 0.0, 1.0)) * np.clip((front + 0.05) / 0.2, 0.0, 1.0)
                  * angle * fade)
            ok = (z > NEAR) & (op > 0) & inside(xy, cam)
            out.append((ids[ok], P[ok], Ne[ok], D[ok] / np.maximum(Dl[ok], 1e-12)[:, None], np.full(ok.sum(), j),
                        self.ident[f1[ok]], op[ok], px_per_stroke * 2.0 ** (L[ok] - j), np.where(convex[ok], 1, 2),
                        np.full(ok.sum(), self.mark_width), Dl[ok]))
        return _seeds(out, self.material)

    def place(self, sl, cam, px_per_stroke):
        """The seeds the view can need, where the slice sl cuts their lines (same rules as SeedBank.place)."""
        P4 = self.body.P
        d = (P4 - sl.o) @ sl.n
        pieces, top = self._visible_pieces(d, sl, cam, px_per_stroke)
        out = []
        for jo in range(self.octaves):
            sel = pieces[top >= jo - 1]
            if not len(sel):
                break
            n = np.floor(self.area[sel] * self.rho0 * 4.0 ** jo + unit(mix(self.seed, sel, jo, 0xC0))).astype(np.int64)
            rep = np.repeat(sel, n)
            if not len(rep):
                continue
            idx = np.arange(len(rep)) - np.repeat(np.cumsum(n) - n, n)
            for b in range(0, len(rep), BLOCK):  # in blocks: the temporaries stay in the CPU's cache; the same numbers
                rb, ib = rep[b:b + BLOCK], idx[b:b + BLOCK]
                ids = mix(self.seed, rb, jo, ib)
                u = (unit(mix(self.seed, rb, jo, 1)) + ib * 0.7548776662466927) % 1.0  # SeedBank's even (R2) places
                v = (unit(mix(self.seed, rb, jo, 2)) + ib * 0.5698402909980532) % 1.0
                flip = u + v > 1
                u, v = np.where(flip, 1 - u, u), np.where(flip, 1 - v, v)
                beta = np.einsum("kc,kcd->kd", np.column_stack([1 - u - v, u, v]), self.B[rb])
                face = self.parent[rb]
                row, k, j, s, run, fade = self._crossings(face, beta, d)
                if not len(row):
                    continue
                f = face[row]
                ids = np.where(run == 0, ids[row], mix(ids[row], run))
                X, c_lo, c_hi = self._point(f, beta[row], k, s)
                P = sl.to3(X)
                tri = sl.to3((1 - s)[:, None, None] * P4[c_lo] + s[:, None, None] * P4[c_hi])  # the face at s, its order
                e1, e2 = tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]
                nf = np.cross(e1, e2)
                tet = self.tet0[f] + (3 * k + j) * self.m[f]
                hint = self.body.N[tet] @ sl.E.T
                N = self.tn[tet] @ sl.E.T
                N *= np.where((N * hint).sum(1) < 0, -1.0, 1.0)[:, None]
                N = _unit(N, _unit(nf, _unit(hint, np.array([0.0, 0.0, 1.0]))))
                key = self.koff[f] + k
                Ns = _unit(((1 - s)[:, None] * self.nkey[key] + s[:, None] * self.nkey[key + 1]) @ sl.E.T, N)
                Ns *= np.where((Ns * N).sum(1) < 0, -1.0, 1.0)[:, None]
                T = self.ab[f, :1] * e1 + self.ab[f, 1:] * e2
                T = _unit(T - (T * Ns).sum(1, keepdims=True) * Ns, _unit(np.cross(Ns, [0.31, 0.42, 0.85]), np.array([1.0, 0, 0])))
                g = np.maximum(0.5 * np.linalg.norm(nf, axis=1) / np.maximum(self.rest_area[f], 1e-300), 1e-12)
                L, z = level(P, Ns, cam, px_per_stroke, self.rho0 / g)  # the cut's own density: rho0 over its stretch
                op = (np.ones(len(P)) if jo == 0 else np.clip(L - jo + 1, 0.0, 1.0)) * fade
                xy, _ = cam.project(P)
                ok = (z > NEAR) & (op > 0) & inside(xy, cam)
                out.append((ids[ok], P[ok], N[ok], T[ok], np.full(ok.sum(), jo), self.ident[f[ok]], op[ok],
                            px_per_stroke * 2.0 ** (L[ok] - jo)))
        return _seeds(out, self.material)


_HERE = os.path.dirname(os.path.abspath(__file__))
_SOURCES = [open(os.path.join(_HERE, n), "rb").read() for n in ("__init__.py", os.path.join("..", "anchor.py"))]  # a bank's makers


class Scene4D:
    """A Scene of 4D bodies (name = material) cut by the slice slice_at(t), plus residents: a 3D Scene living in the
    slice, which also gives the camera, lights, events, materials and world. A body whose cut cannot change between
    two slices is not cut again."""
    rho0, octaves, direction = 0.25, 8, {}  # seed density of the coarsest octave (a m2), octaves, material -> rule
    fps, duration, materials, world = 24, 0.0, {}, {}
    log = True
    cache_dir = None  # where the seed banks are kept on disk (film sets <work>/cache); None: made in memory only

    def __init__(self, bodies, slice_at, residents=None):
        self.bodies, self.slice_at, self.residents = dict(bodies), slice_at, residents
        if residents is not None:
            self.fps, self.duration = residents.fps, residents.duration
            self.materials, self.world = residents.materials, residents.world
        self._wspan = {name: (b.P[:, 3].min(), b.P[:, 3].max()) if len(b.P) else (np.inf, -np.inf)
                       for name, b in self.bodies.items()}
        self._cache = {}
        self.cut_stats = (0, 0, 0.0)  # last meshes(): bodies cut, bodies cached, seconds

    def _key(self, name, sl):
        """What the cut depends on: the slice itself, or only the side when a slice w = const misses the body. (Between
        two keys that do not differ the surface holds, but the cut's points on the diagonals still slide.)"""
        lo, hi = self._wspan[name]
        if np.array_equal(sl.n, E4[3]) and np.array_equal(sl.E, E4[:3]) and not lo <= sl.o[3] <= hi:
            return ("out", bool(sl.o[3] > hi))
        return ("slice", sl.o.tobytes(), sl.n.tobytes(), sl.E.tobytes(), np.asarray(sl.pivot, float).tobytes())

    def _ident(self, name, attrs, n):
        rule = self.materials.get(name, {}).get("rule", 0)
        return ident_of(rule, np.rint(attrs["ident"][:, 0]).astype(np.int64) if "ident" in attrs else np.ones(n, np.int64))

    def meshes(self, t):
        t0, sl, cut, cached, out = time.time(), self.slice_at(t), 0, 0, []
        for name in sorted(self.bodies):
            key = self._key(name, sl)
            hit = self._cache.get(name)
            if hit is not None and hit[0] == key:
                out.append(hit[1])
                cached += 1
                continue
            V, F, A = slicer.cut(self.bodies[name], sl)
            attrs = {"ident": self._ident(name, A, len(V))}
            if "tone" in A:
                attrs["tone"] = A["tone"][:, 0].astype(np.float32)
            m = Mesh(name, V.astype(np.float32), F.astype(np.int32), name, attrs)
            self._cache[name] = (key, m)
            out.append(m)
            cut += 1
        self.cut_stats = (cut, cached, time.time() - t0)
        if self.log:
            print("CUT t=%.4f w=%.4f cut %d cached %d %.2fs" % (t, sl.o[3], cut, cached, self.cut_stats[2]),
                  file=sys.stderr, flush=True)
        return out + (self.residents.meshes(t) if self.residents is not None else [])

    def banks(self):
        """The bodies' seed banks, made once (read back from cache_dir when made before)."""
        if not hasattr(self, "_banks"):
            mats = sorted(self.materials)
            self._banks = {}
            for name, b in sorted(self.bodies.items()):
                if b.parts:
                    self._banks[name] = SeedBank4D.cached(self.cache_dir, b, mats.index(name) if name in mats else 0,
                                                          self._ident(name, b.attrs, len(b.P)), self.direction.get(name, "course"),
                                                          self.rho0, zlib.crc32(name.encode()), self.octaves)
        return self._banks

    def seeds(self, t, cam, px_per_stroke):
        """Seeds and marks of every body where the slice cuts their lines, and the residents' own."""
        sl = self.slice_at(t)
        parts = [p for bank in self.banks().values() for p in (bank.place(sl, cam, px_per_stroke), bank.marks(sl, cam, px_per_stroke))]
        if self.residents is not None:
            parts.append(self.residents.seeds(t, cam, px_per_stroke))
        return concat(parts)

    def camera(self, t):
        return self.residents.camera(t)

    def lights(self, t):
        return self.residents.lights(t) if self.residents is not None else []

    def events(self):
        return self.residents.events() if self.residents is not None else {}
