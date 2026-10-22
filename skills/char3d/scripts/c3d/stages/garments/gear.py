"""Belt and sash band with a buckle, and the leather pouch hung from it."""
import math

import numpy as np

from .base import FRONT, TAU, Z, Built, smoothstep, unit
from .geom import Sheet, loft, resample, smooth, superellipse


def build_band(g, env, body, below):
    s, p = env.s, g.get('params', {})
    z = env.waist
    hips = env.lm['hips']
    rows, cols, half = 5, 48, p.get('width_m', 0.07) * s / 2
    C = np.stack([np.full(rows, hips[0]), np.full(rows, hips[1] - 0.02 * s), np.linspace(z + half, z - half, rows)], 1)
    sh = loft(C, Z, 0.1, 0.1, cols)
    r = np.zeros((rows, cols))
    for i in range(rows):
        for j in range(cols):
            d = unit(sh.P[i, j] - sh.C[i])
            hits = [(below or body).ray_in(sh.C[i], d)]
            r[i, j] = max([np.linalg.norm((hp - sh.C[i])[:2]) for hp, _ in filter(None, hits)] + [0.1])
    r = smooth(r.max(0)[None, :, None], True, 4)[0, :, 0] + 0.004
    bulge = 0.003 * np.sin(np.linspace(0, math.pi, rows))
    sh = loft(C, Z, 0.0, 0.0, cols, off=r[None] + bulge[:, None])
    sh.rad = np.full(rows, r.mean())
    mat = p.get('buckle_material', g['material'])
    return Built({'body': sh}, {'hem': [('body', 'last_row')], 'band': [('body', 'first_row')]},
                 pieces=lambda b, own: [('buckle', buckle(b.sheets['body'], own, env), mat, 0)])


def buckle(sash, surf, env):
    """Rounded-rectangle frame with a prong on the front of the band; ([sheets], [(sheet index, row side)])."""
    o, d, _ = sash.ray(sash.s[-1] / 2, FRONT)
    hit = surf.ray_in(o, d)
    if hit is None:
        return [], []
    c, n = hit[0] + hit[1] * 0.006 * env.s, hit[1]
    up = unit(Z - (Z @ n) * n)
    rt = np.cross(up, n)
    a = np.linspace(0, TAU, 33)
    hw, hh = 0.04 * env.s, 0.032 * env.s
    x, y = superellipse(a, hw, hh)
    spine = c + x[:, None] * rt + y[:, None] * up
    tang = np.gradient(spine, axis=0)
    tang[0] = tang[-1] = spine[1] - spine[-2]
    frame = loft(spine, tang, 0.006 * env.s, 0.006 * env.s, 8, side=n)
    line = c + np.outer(np.linspace(-hw + 0.0075 * env.s, 0.25 * hw, 4), rt) + n * 0.003 * env.s
    prong = loft(line, rt, 0.0025 * env.s, 0.0025 * env.s, 8, side=n)
    return [frame.update_normals(), prong.update_normals()], [(1, 'first_row', -rt), (1, 'last_row', rt)]


def build_pouch(g, env, body, below):
    """Leather pouch hung from the belt behind one hip (`angle_deg` from the side): rounded body, flap, stud; outside the layers."""
    p, s = g.get('params', {}), env.s
    sgn = 1 if p.get('side', 'L') == 'L' else -1
    w, dp, h = (np.array(p.get('size_m', [0.12, 0.05, 0.14]), float) * s)
    ang = (0.0 if sgn > 0 else math.pi) + sgn * math.radians(p.get('angle_deg', 35))
    out = np.array([math.cos(ang), math.sin(ang), 0.0])
    lat = np.cross(Z, out)
    hips = env.lm['hips']
    axis = np.array([hips[0], hips[1], 0.0])
    top = env.waist - 0.01 * s
    zs = np.linspace(top, top - h, 5)
    surf = below or body
    need = []
    for z in zs:
        dist = 0.0
        for x in (-w / 2, 0, w / 2):
            o = axis + lat * x + Z * z
            hit = surf.ray_in(o, out, 0.42 * s)
            hit_b = body.ray_in(o, out, 0.42 * s)
            for hp in filter(None, (hit, hit_b)):
                dist = max(dist, (hp[0] - o) @ out)
        need.append(dist + 0.008 * s + dp / 2)
    need = np.array(need)
    b = (need[-1] - need[0]) / (zs[-1] - zs[0])
    a = float((need - b * zs).max())
    ez = unit(Z + b * out)
    ctr = axis + out * (a + b * (top - h / 2)) + Z * (top - h / 2)
    ey = unit(out - (out @ ez) * ez)
    rows, cols = 10, 24
    u = np.linspace(0, 1, rows)
    ang_r = np.linspace(0, TAU, cols, endpoint=False) + math.pi + math.pi / cols
    scale = (0.9 + 0.1 * smoothstep(0.0, 0.2, u)) * (1 - 0.45 * smoothstep(0.7, 1.0, u) ** 2)
    scale[-1] = 0.3
    x, y = superellipse(ang_r, w / 2, dp / 2, 3.5)
    zrow = h / 2 - h * u
    zrow[-1] += 0.02 * h
    P = ctr + zrow[:, None, None] * ez + scale[:, None, None] * (x[None, :, None] * lat + y[None, :, None] * ey)
    C = ctr + zrow[:, None] * ez
    bag = Sheet(P, True, C=C, Ta=np.broadcast_to(lat, (rows, 3)), Tb=np.broadcast_to(ey, (rows, 3)), rad=np.full(rows, w / 2))
    fr, fc = 6, 11
    xs = np.linspace(-w / 2, w / 2, fc) * 1.04
    tongue = 0.45 * h * (0.7 + 0.3 * np.cos(math.pi * xs / w))
    F = np.empty((fr, fc, 3))
    lift = 0.004 * s
    for k, xk in enumerate(xs):
        dk = dp / 2 * (1 - np.clip(abs(xk) / (w / 2), 0, 1) ** 3.5) ** (1 / 3.5)
        path = [(-0.6 * dk, h / 2 + lift), (0.3 * dk, h / 2 + lift * 1.6), (0.9 * dk + lift, h / 2 - 0.04 * h),
                (dk + 1.5 * lift, h / 2 - tongue[k] * 0.6), (dk + 1.2 * lift, h / 2 - tongue[k])]
        pts, _ = resample(path, fr)
        F[:, k] = ctr + xk * lat + pts[:, :1] * ey + pts[:, 1:] * ez
    flap = Sheet(F, False, ref=np.broadcast_to(ez + ey, (fr, fc, 3)))
    tip = ctr + ey * (dp / 2 + 2.2 * lift) + ez * (h / 2 - 0.85 * tongue[fc // 2])
    stud = loft(tip + np.outer([0, 0.002, 0.004, 0.0055], ey * s), ey, np.array([0.007, 0.007, 0.005, 0.002]) * s,
                np.array([0.007, 0.007, 0.005, 0.002]) * s, 8, side=lat)
    mat = p.get('stud_material') or ('gold' if 'gold' in env.materials else g['material'])
    pieces = lambda b, own: [('flap', ([flap.update_normals()], []), g['material'], 0.003 * s),  # noqa: E731
                             ('stud', ([stud.update_normals()], [(0, 'first_row', -ey), (0, 'last_row', ey)]), mat, 0)]
    return Built({'body': bag.update_normals()}, caps=[('body', 'first_row', ez), ('body', 'last_row', -ez)],
                 pieces=pieces, fitted=False)
