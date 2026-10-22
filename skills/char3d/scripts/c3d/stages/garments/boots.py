"""Boots: sole, raised heel, welt, upper shrink-wrapped on the foot and leg, turned-down cuff."""
import math

import numpy as np
from mathutils import Vector

from .base import CLEAR, TAU, Z, Built, smoothstep, unit
from .geom import Sheet, smooth


def build_boots(g, env, body, below):
    """Boot per foot: sole with a raised heel, welt, upper shrink-wrapped on the foot and leg, turned-down cuff; one quad shell."""
    p, s = g.get('params', {}), env.s
    cuff, sole, heel = p.get('cuff_m', 0.12) * s, p.get('sole_m', 0.014) * s, p.get('heel_m', 0.03) * s
    welt, clear, K = 0.006 * s, CLEAR['boots'] * s, 24
    side0 = g.get('attach', 'foot.L').rsplit('.', 1)[-1]
    sheets, caps, info = {}, [], {}
    for side in (('L', 'R') if p.get('pair', True) else (side0,)):
        ank, toe = env.lm[f'foot.{side}'], env.lm[f'toe.{side}']
        fwd = unit((toe - ank) * [1, 1, 0])
        back = math.atan2(-fwd[1], -fwd[0])
        a = back + (np.arange(K) + 0.5) * TAU / K
        dirs = np.stack([np.cos(a), np.sin(a), np.zeros(K)], 1)
        heelness = smoothstep(-0.1, 0.5, dirs @ -fwd)
        wall = sole + (heel - sole) * heelness
        top = ank[2] + cuff
        foot_c = ank * [1, 1, 0] + fwd * 0.075 * s
        leg_c = ank * [1, 1, 0] - fwd * 0.005 * s
        tau = np.linspace(0, 1, 13) ** 1.6
        rows = []
        for tk in tau:
            ring = []
            for j in range(K):
                z = wall[j] + (top - wall[j]) * tk
                c = foot_c + (leg_c - foot_c) * smoothstep(0.03 * s, 0.11 * s, z) + Z * z
                r0 = 0.17 * s
                hit = body.bvh.ray_cast(Vector(c + dirs[j] * r0), Vector(-dirs[j]), r0)[0]
                r = (r0 - (Vector(c + dirs[j] * r0) - hit).length) if hit is not None else 0.04 * s
                ring.append((c, max(r, 0.035 * s)))
            rows.append(ring)
        cen = np.array([[c for c, _ in ring] for ring in rows])
        rad = np.array([[r for _, r in ring] for ring in rows])
        rad = np.maximum(smooth(rad[..., None], True, 2)[..., 0], rad) + clear
        upper = cen + rad[..., None] * dirs[None]
        lip = upper[-1] + dirs * 0.006 * s + Z * 0.006 * s
        fold = upper[-1] + dirs * 0.012 * s - Z * 0.01 * s
        hem = upper[-1] + dirs * 0.017 * s - Z * 0.05 * s
        out_lo = upper[0] * [1, 1, 0] + dirs * welt
        out_hi = out_lo + Z * wall[:, None]
        welt_in = upper[0] + dirs * 0.002 * s
        P = np.stack([out_lo, out_hi, welt_in, *upper, lip, fold, hem])
        P[0, :, 2] = 0.0
        sh = Sheet(P, True, np.broadcast_to(a, (len(P), K)).copy(), C=P.mean(1),
                   Ta=np.broadcast_to([1.0, 0, 0], (len(P), 3)), Tb=np.broadcast_to([0, 1.0, 0], (len(P), 3)), rad=np.full(len(P), 0.05))
        sh.ref = np.broadcast_to(dirs, P.shape).copy()
        sheets[side] = sh.update_normals()
        caps.append((side, 'first_row', -Z))
        info = {'boot_heel_m': round(float(heel), 4), 'boot_sole_m': round(float(sole), 4), 'boot_cuff_m': round(float(cuff), 4)}
    return Built(sheets, caps=caps, split=True, fitted=False, info=info)
