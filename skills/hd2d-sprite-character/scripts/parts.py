"""Shared SDF helpers for HD-2D characters: texture bands, overlapping lames, flat and curved blades."""
import numpy as np
from core import V, ellipsoid, sub

RIVET = '#fffbe8'


def unit(v):
    v = np.asarray(v, float); return v / max(np.linalg.norm(v), 1e-9)


def bands(c, d, offs, w, mat='gold'):
    """Texture: mat where the offset along direction d from c is within w of one of offs."""
    d = unit(d)

    def t(P, mt):
        mt = mt.copy(); q = (P - c) @ d
        for o in offs:
            mt[np.abs(q - o) < w] = mat
        return mt
    return t


def lame(c, rad, rt, cut=0.8):
    """Curved plate: an ellipsoid shell hollowed from behind and above, so stacked lames overlap like scales."""
    return sub(ellipsoid(c, rad, rot=rt), ellipsoid(c + rt.T @ V(0, cut * rad[1], -0.7 * rad[2]), (rad[0] * 1.08, rad[1] * 1.1, rad[2] * 0.95), rot=rt))


def blade(base, d, perp, L, w, t, curve=0.0):
    """Flat double-edged blade along d: diamond section, slight taper, a point over the last 6 units; curve bends it toward perp."""
    n = np.cross(d, perp)

    def f(P):
        q = P - base; u = q @ d
        xs = q @ perp - curve * (np.clip(u, 0, L) / L) ** 2 * L * 0.25
        x = np.abs(xs); z = np.abs(q @ n)
        wu = w * np.clip(np.minimum(1 - 0.2 * u / L, (L - u) / 6.0), 0.02, None)
        return np.maximum(np.maximum((x / wu + z / t - 1) * np.minimum(wu, t) * 0.8, -u), u - L)
    return f


def blade_tex(bs, sd, perp, L, w, curve=0.0, fuller=18.0):
    """Blade texture: dark fuller down the middle, light edges."""
    def t(P, mt):
        mt = mt.copy(); q = P - bs; u = q @ sd
        x = np.abs(q @ perp - curve * (np.clip(u, 0, L) / L) ** 2 * L * 0.25)
        wu = w * np.clip(np.minimum(1 - 0.2 * u / L, (L - u) / 6.0), 0.02, None)
        mt[(x < 0.3 * wu) & (u > 1.2) & (u < fuller)] = 'blade_f'
        mt[x > 0.72 * wu] = 'blade_e'
        return mt
    return t
