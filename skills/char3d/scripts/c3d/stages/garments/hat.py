"""Hat: a felt crown with a worn crease, dents and a drooping tip over a floppy brim with a rolled edge."""
import math

import numpy as np

from .base import FRONT, TAU, Z, Built, fold_field, smoothstep, unit, wrap
from .geom import loft

HAT_GAP = 0.016
BRIM_GAP = 0.008


def band_seat(body, base, side, gap):
    """Band ring seated on the skull: (centre xy, radius along `side`, radius across) of the skin slice at the band
    height plus `gap` (hair and felt), so the hat rests on the head instead of floating; None without a skull slice."""
    if body is None:
        return None
    V = np.asarray(body.V)
    sl = V[(np.abs(V[:, 2] - base[2]) < 0.006) & (np.linalg.norm(V[:, :2] - base[:2], axis=1) < 0.16)]
    if len(sl) < 16:
        return None
    a, b = side[:2] / np.linalg.norm(side[:2]), np.array([-side[1], side[0]]) / np.linalg.norm(side[:2])
    pa, pb = sl[:, :2] @ a, sl[:, :2] @ b
    c = a * (pa.min() + pa.max()) / 2 + b * (pb.min() + pb.max()) / 2
    return c, np.ptp(pa) / 2 + gap, np.ptp(pb) / 2 + gap


def seat_ring(ring, bth, rr, gap):
    """Brim rows (xy offsets from the band centre) grown from the crown's base ring plus `gap` out to the rolled edge, so
    the brim meets the crown wall instead of passing through it."""
    d = np.stack([np.cos(bth), 0.94 * np.sin(bth)], 1)
    a = np.arctan2(d[:, 1], d[:, 0])
    ang = np.arctan2(ring[:, 1], ring[:, 0])
    o = np.argsort(ang)
    rho = np.interp(a, ang[o], np.hypot(ring[:, 0], ring[:, 1])[o], period=TAU) + gap
    outer = rr[-3] * np.linalg.norm(d, axis=1)
    f = ((rr - rr[0]) / (rr[-3] - rr[0]))[:, None]
    r = rho[None] + (outer - rho)[None] * f
    return r[..., None] * (d / np.linalg.norm(d, axis=1, keepdims=True))[None]


def build_hat(g, env, body, below):
    """Felt hat whose overall height is solved to `height_m`; crease, dents and droop read as years of wear."""
    p, s = g.get('params', {}), env.s
    rng = np.random.default_rng(p.get('seed', 5))
    H = p.get('height_m', 0.45)
    R0, Rb = p.get('base_radius_m', 0.13) * s, p.get('brim_radius_m', 0.24) * s
    tilt, bend = math.radians(p.get('brim_tilt_deg', 0)), math.radians(p.get('tip_bend_deg', 45))
    crease, droop, uc = math.radians(p.get('crease_deg', 0)), p.get('droop', 0.0), p.get('crease_at', 0.42)
    head, eye = env.lm['head'], env.lm['eye.L']
    base = np.array([head[0], head[1] - 0.015 * s, eye[2] + 0.055 * s])
    bdir = unit(np.array([0.45, 0.89, 0.0]))
    side = np.cross(Z, bdir)
    seat = band_seat(body, base, side, HAT_GAP * s)
    ratio0 = 0.92
    if seat:
        base[:2], R0, ratio0 = seat[0], seat[1], seat[2] / seat[1]
    ca, sa = math.cos(-tilt), math.sin(-tilt)
    rot = np.array([[1, 0, 0], [0, ca, -sa], [0, sa, ca]])
    rows, cols = 26, 32
    u = np.linspace(0, 1, rows)
    phi = (bend * smoothstep(0.2, 1.0, u) + crease * smoothstep(uc - 0.015, uc + 0.015, u)
           + droop * math.pi / 2 * smoothstep(uc, uc + 0.25, u) - math.radians(7) * smoothstep(0.05, uc, u))
    yaw = math.radians(35) * smoothstep(uc, 1.0, u)
    turn = np.cos(yaw)[:, None] * bdir + np.sin(yaw)[:, None] * side
    T = np.cos(phi)[:, None] * Z + np.sin(phi)[:, None] * turn
    th = np.linspace(0, TAU, cols, endpoint=False)
    inner = np.clip(-np.sin(th), 0, None)[None]
    near = np.exp(-((u - uc) / 0.04) ** 2)[:, None]
    ripple = np.exp(-((u - uc) / 0.1) ** 2)[:, None] * np.sin(TAU * (u - uc) / 0.06)[:, None]
    outer = np.clip(np.sin(th), 0, None)[None]
    k = min(1.0, crease / math.radians(12))
    worn = 1 - (0.5 * near + 0.3 * ripple) * k * inner ** 2 + 0.1 * near * k * outer ** 2
    for uk, tk, ak in zip(rng.uniform(0.12, 0.8, 4), rng.uniform(0, TAU, 4), (0.3, 0.24, 0.18, 0.14)):
        worn = worn - ak * np.exp(-((u[:, None] - uk) / 0.09) ** 2 - (wrap(th[None] - tk) / 0.6) ** 2)
    worn = worn * (1 + 0.12 * fold_field(np.broadcast_to(th, (rows, cols)), u, 5, rng, drift=1.5))
    belly = 1 + 0.07 * np.exp(-((u - 0.14) / 0.1) ** 2)
    bth = math.pi / 2 + np.linspace(0, TAU, 48, endpoint=False)
    lump = fold_field(np.broadcast_to(bth, (1, 48)), [0.0], 5, rng)[0]

    def tilted(sh):
        for k in ('P', 'C'):
            setattr(sh, k, (getattr(sh, k) - base) @ rot.T + base)
        sh.Ta, sh.Tb = sh.Ta @ rot.T, sh.Tb @ rot.T
        if sh.ref is not None:
            sh.ref = sh.ref @ rot.T
        return sh

    def make(L):
        C = base + np.vstack([[0, 0, 0], np.cumsum((T[1:] + T[:-1]) / 2 * L / (rows - 1), 0)])
        r = R0 * (1 - u) ** 0.6 * belly + 0.003
        crown = loft(C, T, r, (ratio0 - 0.15 * smoothstep(uc, uc + 0.1, u)) * r, cols, th=th, off=r[:, None] * (worn - 1),
                     side=side)
        rr = np.concatenate([np.linspace(R0 - 0.012 * s, Rb, 8), [Rb + 0.007 * s, Rb + 0.006 * s]])
        q = np.clip((rr - R0) / (Rb - R0), 0, 1)
        brim = loft(base - Z * (0.025 * s * q ** 2)[:, None], Z, rr, rr * 0.94, 48, th=bth)
        brim.P[..., :2] = base[:2] + seat_ring(crown.P[0] - base, bth, rr, BRIM_GAP * s)
        updown = 0.55 + 0.45 * np.cos(2 * (bth - FRONT))
        curl = np.exp(-(wrap(bth - FRONT - 2.3) / 0.6) ** 2)
        sag = droop * 0.07 * updown - 0.018 * (1 - updown) + 0.035 * lump + 0.006 * np.sin(2 * bth + 1.1) - 0.05 * curl
        brim.P[..., 2] -= s * q[:, None] ** 1.5 * sag[None]
        brim.P[-2:, :, 2] -= np.array([0.006, 0.016])[:, None] * s
        brim.ref = Z
        return tilted(crown), tilted(brim)

    def height(L):
        zs = np.concatenate([sh.P[..., 2].ravel() for sh in make(L)])
        return zs.max() - zs.min()

    lo, hi = 0.05, 3.0
    for _ in range(40):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if height(mid) < H else (lo, mid)
    crown, brim = make((lo + hi) / 2)
    return Built({'crown': crown, 'brim': brim}, {'band': [('crown', 'first_row')], 'rim': [('brim', 'last_row')]},
                 caps=[('crown', 'last_row', T[-1] @ rot.T)],
                 info={'hat_crease_deg': round(math.degrees(crease), 1), 'hat_droop': droop,
                       'hat_tip_angle_deg': round(math.degrees(phi[-1]), 1)})
