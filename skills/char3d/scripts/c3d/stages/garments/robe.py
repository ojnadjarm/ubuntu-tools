"""Cloth garments: robe (cinched, bloused, folds fanning to a full hem, open front, bell sleeves) and the shoulder mantle."""
import math

import numpy as np

from .base import FRONT, TAU, Z, Built, arms, fold_field, seg_dist, smoothstep, unit
from .geom import Sheet, loft, resample


def row_heights(ztop, zbot, step, zw, s):
    """Row z values from the collar down to the hem, twice as dense around the waist so the cinch and blouse read."""
    zs = np.concatenate([np.linspace(ztop, zbot, max(12, int((ztop - zbot) / step) + 1)),
                         np.arange(zw + 0.11 * s, zw - 0.08 * s, -step / 2)])
    zs = np.sort(zs[(zs <= ztop) & (zs >= zbot)])[::-1]
    keep = np.concatenate([[True], -np.diff(zs) > step / 4])
    return zs[keep]


def sleeve(sh, hand, s, p, rng):
    """Bell sleeve from the shoulder to the wrist, folds widening to the cuff, underside hung to `sleeve_length_m`; pinned in the drape."""
    d = unit(hand - sh)
    a = sh - d * 0.01 * s
    top = np.linalg.norm(hand - a) - 0.01 * s
    bot = max(top, p.get('sleeve_length_m', 0.0) * s)
    bell = p.get('sleeve_bell_m', 0.1) * s
    rows, cols = max(10, int(bot / 0.045)), 24
    u = np.linspace(0, 1, rows)
    th = math.pi / 2 + np.linspace(0, TAU, cols, endpoint=False)
    sl = loft(a + np.outer(u * top, d), d, 1.0, 1.0, cols, th=th, side=(0, 1, 0))
    e = unit(sl.P - sl.C[:, None])
    down = unit(-Z - (-Z @ d) * d)
    hang = np.clip(e[0] @ down, 0, 1) ** 1.5
    r = 0.075 * s + (bell - 0.075 * s) * u[:, None] ** 1.6
    r = r * (1 + 0.22 * fold_field(np.broadcast_to(th, (rows, cols)), u, 5, rng, drift=0.8) * u[:, None] ** 1.3)
    sl.P = a + (u * top)[:, None, None] * d + r[..., None] * e - Z * ((bot - top) * hang[None] * u[:, None] ** 3)[..., None]
    sl.C = a + np.outer(u * top, d)
    sl.rad = r.mean(1)
    return sl, np.ones((rows, cols))


def build_robe(g, env, body, below):
    """Robe cinched at the belt and bloused above it, irregular gathers merging into deep folds at the hem."""
    p, s = g.get('params', {}), env.s
    rng = np.random.default_rng(p.get('seed', 7))
    hips, zw = env.lm['hips'], env.waist
    outer = bool(p.get('sleeves') or p.get('sleeve_bell_m'))
    dense, _ = resample([(r * s, z) for r, z in g['profile']], 400)
    z = row_heights(dense[0, 1], dense[-1, 1], 0.045 if outer else 0.06, zw, s)
    rx = np.interp(-z, -dense[:, 1], dense[:, 0])
    rx = rx * (1 - p.get('cinch', 0.0) * np.exp(-((z - zw) / (0.03 * s)) ** 2))
    rx = rx + p.get('blouse_m', 0.0) * s * np.exp(-((z - zw - 0.06 * s) / (0.035 * s)) ** 2)
    R, cols = len(z), (72 if outer else 32)
    u = np.clip((zw - z) / (zw - z[-1]), 0, 1)
    v = np.clip((z - zw) / (0.2 * s), 0, 1)
    t = np.linspace(0, 1, R)
    ry = rx * (0.82 + 0.18 * t)
    C = np.stack([np.full(R, hips[0]), np.full(R, hips[1] - 0.02 * s), z], 1)
    opening = p.get('front_opening_m', 0.0)
    w = opening * (0.6 + 1.6 * t)
    if opening:
        gap = w / ry
        th = FRONT + gap[:, None] / 2 + (TAU - gap[:, None]) * np.linspace(0, 1, cols)[None]
    else:
        th = np.broadcast_to(math.pi / 2 + np.linspace(0, TAU, cols, endpoint=False), (R, cols))
    depth, gather = p.get('fold_depth_m', 0.008) * s, p.get('gather_depth_m', 0.0) * s
    nf = int(p.get('folds', 6))
    main = fold_field(th, u, nf, rng, drift=0.35) + 0.45 * fold_field(th, u, 2 * nf + 3, rng, drift=0.2, width=(0.3, 0.5))
    main = main / np.abs(main).max() * (smoothstep(0.0, 0.12, u) * (0.2 + 0.8 * u ** 0.8))[:, None]
    gathers = fold_field(th, u, int(p.get('gathers', 12)), rng, drift=0.08, width=(0.42, 0.55))
    fade = np.where(z < zw, smoothstep(0.0, 0.02, u) * np.exp(-u / 0.2), 0.6 * np.exp(-v / 0.35) * (v > 0))
    off = depth * main + gather * gathers * fade[:, None]
    torso = loft(C, Z, rx, ry, cols, closed=not opening, th=th, off=off)
    torso.P[..., 2] += 0.6 * depth * main * smoothstep(0.8, 1.0, u)[:, None]
    sheets = {'body': torso}
    holes = np.zeros(torso.P.shape[:2], bool)
    for sh, hand in arms(env):
        holes |= (seg_dist(torso.P, sh, hand + unit(hand - sh) * 0.15 * s) < 0.065 * s) & (torso.P[..., 2] > zw + 0.12 * s)
    if holes.any():
        cols_f = cols if torso.closed else cols - 1
        jn = (np.arange(cols_f) + 1) % cols
        q = holes[:-1, :cols_f] | holes[1:, :cols_f]
        torso.keep = ~(q | (holes[:-1, jn] | holes[1:, jn]))
    pins = {'body': smoothstep(hips[2] - 0.1 * s, zw, torso.P[..., 2])}
    if outer:
        for (sh, hand), side in zip(arms(env), 'LR'):
            sheets[f'sleeve.{side}'], pins[f'sleeve.{side}'] = sleeve(sh, hand, s, p, rng)
    edges = {'hem': [('body', 'last_row')], 'collar': [('body', 'first_row')],
             'front': [('body', 'first_col'), ('body', 'last_col')] if opening else [],
             'cuffs': [(k, 'last_row') for k in sheets if k.startswith('sleeve')]}
    return Built(sheets, edges, borders(torso, g, env, C, opening), pins=pins, joins=[('body', k) for k in sheets if k != 'body'],
                 info={'sleeves': sum(k.startswith('sleeve') for k in sheets)})


def borders(torso, g, env, C, opening):
    """Embroidery bands inside the trim: up each front edge and round the hem, meeting at the corners."""
    s = env.s
    tw, hw = g.get('trim', {}).get('width_m', 0.03) * s, 0.024 * s
    s_hem = torso.s[-1]
    s_waist = float(np.interp(-env.waist, -C[:, 2], torso.s))
    edge = lambda a: opening * (0.6 + 1.6 * a / s_hem) / 2 + tw + 0.01 * s + hw  # noqa: E731
    al_hem = s_hem - tw - 0.01 * s - hw
    r_hem = float(np.interp(al_hem, torso.s, torso.rad))
    g0 = edge(al_hem) - hw if opening else 0.0
    hem = dict(sheet='body', target='self', th0=FRONT, length=TAU * r_hem - 2 * g0, half=hw,
               at=lambda x, y: (al_hem - y, g0 + x))
    bands = {'hem_band': [hem]}
    if opening:
        a0, a1 = s_waist + 0.07 * s, al_hem - hw
        bands['front_border'] = [dict(sheet='body', target='self', th0=FRONT, length=a1 - a0, half=hw,
                                      at=lambda x, y, sg=sg: (a0 + x, sg * (edge(a0 + x) + y))) for sg in (1, -1)]
    return bands


def build_mantle(g, env, body, below):
    """Shoulder cape: collar pinned, front and back points longer than the sides, irregular folds settled by the drape."""
    s, neck = env.s, env.lm['neck']
    rng = np.random.default_rng(g.get('params', {}).get('seed', 11))
    shz = neck[2] - 0.1 * s
    prof = g.get('profile') or [(0.1, neck[2] - 0.025 * s), (0.19, shz + 0.03 * s), (0.26, shz - 0.08 * s), (0.28, shz - 0.17 * s)]
    pr, _ = resample([(r * s, z) for r, z in prof], 12)
    R, cols = len(pr), 48
    t = np.linspace(0, 1, R)
    th = math.pi / 2 + np.linspace(0, TAU, cols, endpoint=False)
    point = 1 + 0.45 * np.abs(np.cos(th - FRONT)) ** 3
    z0 = pr[0, 1]
    zz = z0 + (pr[:, 1] - z0)[:, None] * point[None]
    off = 0.016 * s * smoothstep(0.35, 1, t)[:, None] * fold_field(np.broadcast_to(th, (R, cols)), t, 9, rng, drift=0.4)
    rr = np.interp(-np.minimum(zz, z0), -pr[:, 1], pr[:, 0], right=pr[-1, 0] * 1.05)
    P = np.empty((R, cols, 3))
    P[..., 0] = neck[0] + (rr + off) * np.cos(th)[None]
    P[..., 1] = neck[1] - 0.01 * s + (rr + off) * (0.72 + 0.1 * t[:, None]) * np.sin(th)[None]
    P[..., 2] = zz
    C = np.stack([np.full(R, neck[0]), np.full(R, neck[1] - 0.01 * s), pr[:, 1]], 1)
    sh = Sheet(P, True, np.broadcast_to(th, (R, cols)).copy(), C, np.broadcast_to([1.0, 0, 0], (R, 3)).copy(),
               np.broadcast_to([0, 1.0, 0], (R, 3)).copy(), pr[:, 0])
    pins = {'body': 1 - smoothstep(0.1, 0.45, np.broadcast_to(t[:, None], (R, cols)))}
    return Built({'body': sh}, {'hem': [('body', 'last_row')], 'collar': [('body', 'first_row')]}, pins=pins)
