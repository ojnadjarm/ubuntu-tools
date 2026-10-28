"""Hand model: palm, two-segment fingers and thumb per grip state, aligned to the forearm; returns the wrist point."""
import numpy as np
from core import V, box, cone

# curl of the proximal and distal finger segments (radians toward the palm) and thumb tip in (t, d, n) per state
GRIPS = {
    'open':    dict(c1=0.12, c2=0.10, thumb=(0.75, 0.70, 0.15)),
    'relaxed': dict(c1=0.55, c2=0.75, thumb=(0.30, 0.85, 0.45)),
    'hook':    dict(c1=0.35, c2=1.55, thumb=(0.20, 0.80, 0.55)),
    'fist':    dict(c1=1.45, c2=1.60, thumb=(-0.45, 0.55, 0.80)),
    'grip':    dict(c1=1.35, c2=1.55, thumb=(-0.35, 0.60, 0.80)),
}
PALM, F1, F2, HW = 2.5, 1.45, 1.25, 1.75     # palm length, finger segment lengths, palm half-width (units, size 1)


def _unit(v):
    v = np.asarray(v, float); return v / max(np.linalg.norm(v), 1e-9)


def hand_frame(d, side, palm=None, axis=None):
    """Orthonormal (t, d, n): fingers d, palm normal n, thumb side t = side * n x d (right hand side -1)."""
    d = _unit(d)
    if axis is not None:
        t = _unit(axis); d2 = d - (d @ t) * t
        d = _unit(d2) if np.linalg.norm(d2) > 0.2 else _unit(np.cross(t, V(side, 0, 0.3)))
        return t, d, _unit(side * np.cross(d, t))
    n = V(-side, 0, -1.0) if palm is None else _unit(palm)
    n = n - (n @ d) * d
    n = _unit(n) if np.linalg.norm(n) > 0.2 else _unit(np.cross(d, V(0, 0, 1)) * -side)
    return _unit(side * np.cross(n, d)), d, n


def add_hand(m, el, hand, side, grip='relaxed', palm=None, axis=None, size=1.0, mat='hand', reach=0.8, cuff=None, point=None):
    """Add one hand to Model m. el = elbow, hand = old hand point (free hands) or grip point on a prop (axis given).
    Returns the forearm end: end the sleeve/forearm cone there so its round tip does not swallow the palm.

    cuff = (material, radius): a short band over the wrist that separates sleeve and hand by value.
    point = finger direction hint: the wrist bends toward it (wave: up), the forearm keeps its pose.
    """
    hand = np.asarray(hand, float); s = size
    fa = _unit(hand - np.asarray(el, float))
    t, d, n = hand_frame(fa if point is None else fa + 2.0 * _unit(point), side, palm, axis)
    g = GRIPS['grip' if axis is not None and grip == 'relaxed' else grip]
    if axis is not None:
        wr = hand - d * (1.8 * s) - n * (0.85 * s)
    else:
        wr = hand - d * reach * s
    R = lambda a, b, c: np.stack([a, b, c], 1)
    grp = 'hand%d' % side; m.group(grp, 0.3 * s)
    pc = wr + d * (PALM * 0.5 * s) + n * 0.05 * s
    m.add(box(pc, (HW * s, PALM * 0.5 * s, 0.78 * s), R(t, d, n), 0.5 * s), mat, grp)
    k = wr + d * PALM * s
    f1 = np.cos(g['c1']) * d + np.sin(g['c1']) * n
    a2 = g['c1'] + g['c2']; f2 = np.cos(a2) * d + np.sin(a2) * n
    for f, L, k0 in ((f1, F1, k), (f2, F2, k + f1 * F1 * s)):
        nn = _unit(np.cross(t, f))
        m.add(box(k0 + f * (L * 0.5 * s), ((HW - 0.1) * s, L * 0.5 * s + 0.2 * s, 0.68 * s), R(t, f, nn), 0.5 * s), mat, grp)
    tb = wr + d * 0.7 * s + t * 1.35 * s + n * 0.4 * s
    tt = tb + (t * g['thumb'][0] + d * g['thumb'][1] + n * g['thumb'][2]) * 1.85 * s
    m.add(cone(tb, tt, 0.85 * s, 0.72 * s), mat, grp)
    end = wr - fa * 1.1 * s
    if cuff:
        m.add(cone(end + fa * 0.2 * s, end + fa * 0.75 * s, cuff[1], cuff[1]), cuff[0])
    return end
