"""Hand model (FFBE/Octopath read): a fist wrapped round the handle with knuckle lines and a thumb on top, or a palm with
separate fingers; the wrist always continues the forearm. Knuckle and finger seams use 'hand_d' (same ramp, darker)."""
import numpy as np
from core import V, box, cone, sphere, ellipsoid

# finger curl per joint (radians toward the palm), finger spread (radians) and thumb (t, d, n) direction per free-hand state
GRIPS = {
    'open':    dict(c1=0.15, c2=0.15, spread=0.22, thumb=(0.9, 0.55, 0.2)),
    'relaxed': dict(c1=0.55, c2=0.75, spread=0.10, thumb=(0.45, 0.85, 0.45)),
    'claw':    dict(c1=0.45, c2=0.95, spread=0.26, thumb=(0.9, 0.45, 0.5)),
}
PALM, FIN, HW = 2.3, 2.3, 1.7     # palm length, finger length, palm half-width (units, size 1)
VIEW = V(0.56, 0.3, 0.78)         # toward the camera in sprite space at the party yaw -0.6: thumbs and palms face it


def _unit(v):
    v = np.asarray(v, float); return v / max(np.linalg.norm(v), 1e-9)


def _seam(c, a, fw, n0, cut, thumb=None):
    """Texture: dark seams between three knuckle bands (two seams read at 6 px; three turn to a checker) along a (from c) where (P-c).n0 > cut, and a ring round the thumb."""
    def t(P, mt):
        q = P - c; u = (q @ a) / fw; f = u - np.round(u)
        mt = mt.copy()
        mt[(np.abs(f) < 0.12) & (u > 0.5) & (u < 2.5) & ((q @ n0) > cut)] = 'hand_d'
        if thumb is not None:
            a0, b0, r = thumb; ab = b0 - a0; h = np.clip(((P - a0) @ ab) / (ab @ ab), 0, 1)
            mt[np.linalg.norm(P - a0 - h[:, None] * ab, axis=1) < r] = 'hand_d'
        return mt
    return t


def _wrap(m, el, g, side, a, s, rod, grp, knuckle, claw):
    """Fist round a handle at g along a: knuckle bands, back of the hand toward the elbow, thumb over the index finger."""
    fa = _unit(g - np.asarray(el, float))
    b = fa - (fa @ a) * a
    b = _unit(b) if np.linalg.norm(b) > 0.25 else _unit(np.cross(a, V(0, 0, 1)))
    t = _unit(np.cross(a, b))
    if t @ VIEW < 0:
        t = -t
    fw = 0.78 * s; L = 2.0 * fw; R = rod + 0.72 * s
    c = g + b * 0.25 * s
    rot = np.stack([t, a, b], 1)
    tb = g - b * (rod + 1.1 * s) + t * (R * 0.8) + a * (L * 0.5)
    tt = g + b * (0.3 * s) + t * (R + 0.1 * s) + a * (L * 0.8)
    m.add(box(c, (R, L, R + 0.15 * s), rot, 0.85 * s), 'hand', grp, _seam(g - a * L, a, 2 * L / 3, b, -0.3 * s, (tb, tt, 0.9 * s)))
    m.add(box(g - b * (rod + 0.9 * s) + a * 0.2 * s, (R * 0.85, L * 0.9, 0.85 * s), rot, 0.6 * s), 'hand', grp)
    if knuckle:
        m.add(box(g - b * (rod + 1.3 * s) + t * 0.55 * s, (0.45 * s, L * 0.95, 0.5 * s), rot, 0.3 * s), knuckle, None)
    m.add(cone(tb, tt, 0.7 * s, 0.55 * s), 'hand', None)
    if claw:
        for i in range(4):
            k = g + a * (L - fw * (i + 0.5)) + b * (R + 0.2 * s) + t * 0.5 * s
            m.add(cone(k, k + t * 0.9 * s - b * 0.3 * s, 0.35 * s, 0.08 * s), claw, None)
    return g - b * (rod + 2.4 * s) - a * 0.2 * s


def _free(m, el, hand, side, grip, palm, point, s, grp, claw):
    """Palm and four separate fingers (open, relaxed, claw) or a closed fist (fist) at the end of the forearm."""
    fa = _unit(np.asarray(hand, float) - np.asarray(el, float))
    d = _unit(fa + (0 if point is None else 1.4) * _unit(point if point is not None else fa))
    n = V(-side, 0, -1.0) if palm is None else _unit(palm)
    n = n - (n @ d) * d
    n = _unit(n) if np.linalg.norm(n) > 0.2 else _unit(np.cross(d, V(0, 0, 1)) * -side)
    t = _unit(side * np.cross(n, d))
    if grip == 'fist':
        return _wrap(m, el, hand + d * 0.6 * s, side, t, s, 0.25 * s, grp, None, claw)
    g = GRIPS[grip]; wr = np.asarray(hand, float) - d * 0.4 * s
    rot = np.stack([t, d, n], 1)
    m.add(box(wr + d * PALM * 0.5 * s, (HW * s, PALM * 0.5 * s, 0.7 * s), rot, 0.55 * s), 'hand', grp)
    k0 = wr + d * PALM * s
    for i, u in enumerate((-1.5, -0.5, 0.5, 1.5)):
        sp = g['spread'] * u; L = FIN * s * (0.85 if abs(u) > 1 else 1.0)
        base = k0 + t * (u * 0.82 * s) - n * 0.1 * s
        d0 = _unit(d * np.cos(sp) + t * np.sin(sp))
        f1 = _unit(d0 * np.cos(g['c1']) + n * np.sin(g['c1']))
        f2 = _unit(d0 * np.cos(g['c1'] + g['c2']) + n * np.sin(g['c1'] + g['c2']))
        j = base + f1 * L * 0.5; tip = j + f2 * L * 0.5
        side_dark = (lambda b0: lambda P, mt: np.where(((P - b0) @ t) < -0.3 * s, 'hand_d', mt))(base)
        m.add(cone(base, j, 0.5 * s, 0.45 * s), 'hand', None, side_dark)
        m.add(cone(j, tip, 0.45 * s, 0.36 * s), 'hand', None, side_dark)
        if claw:
            m.add(cone(tip, tip + f2 * 0.9 * s + n * 0.4 * s, 0.32 * s, 0.06 * s), claw, None)
    tb = wr + d * 0.6 * s + t * (HW * s * 0.9)
    th = _unit(t * g['thumb'][0] + d * g['thumb'][1] + n * g['thumb'][2])
    m.add(cone(tb, tb + th * 2.1 * s, 0.62 * s, 0.45 * s), 'hand', None,
          lambda P, mt: np.where(((P - tb) @ n) > 0.35 * s, 'hand_d', mt))
    return wr - d * 0.6 * s


def add_hand(m, el, hand, side, grip='relaxed', palm=None, axis=None, size=1.0, mat='hand', reach=0.8, cuff=None, point=None,
             rod=0.85, knuckle=None, claw=None):
    """Add one hand to Model m. el = elbow, hand = free-hand point or grip point on a prop (axis = handle direction).
    Returns the wrist: end the forearm there so it flows straight into the hand.

    grip: open / relaxed / claw (separate fingers) or fist; with an axis the fist wraps a handle of radius rod.
    cuff = (material, radius) band over the wrist; knuckle = gauntlet plate material over the knuckles;
    claw = material of claw tips on each finger; point = finger direction hint (wrist bends toward it).
    """
    s = size; grp = 'hand%d' % side; m.group(grp, 0.35 * s)
    hand = np.asarray(hand, float)
    if axis is not None:
        wr = _wrap(m, el, hand, side, _unit(axis), s, rod, grp, knuckle, claw)
    else:
        wr = _free(m, el, hand, side, grip, palm, point, s, grp, claw)
    fa = _unit(wr - np.asarray(el, float))
    m.add(sphere(wr + fa * 0.6 * s, 0.95 * s), 'hand', grp)
    if cuff:
        m.add(cone(wr - fa * 0.9 * s, wr - fa * 0.1 * s, cuff[1], cuff[1] * 0.95), cuff[0])
    return wr - fa * 0.4 * s


def add_paw(m, el, hand, side, s=1.6, palm=None, fur='fur', pad='fur_l', claw='claw'):
    """Raised bear paw at hand, fingers up: fur mitt, pale palm pad facing palm (default forward), four toe pads split by seams, hooked claws."""
    hand = np.asarray(hand, float)
    d = _unit(V(0, 2.0, 0) + _unit(hand - np.asarray(el, float)) * 0.6)
    n = _unit(V(-0.3 * side, 0.1, 1.0) if palm is None else palm); n = _unit(n - (n @ d) * d)
    t = _unit(np.cross(d, n))
    grp = 'paw%d' % side; m.group(grp, 0.5 * s)
    rot = np.stack([t, d, n], 1)
    m.add(box(hand, (1.9 * s, 1.6 * s, 1.1 * s), rot, 1.0 * s), fur, grp)
    m.add(ellipsoid(hand + n * 1.15 * s - d * 0.3 * s, (1.35 * s, 1.0 * s, 0.45 * s), rot=rot), pad, None)
    for i, u in enumerate((-1.5, -0.5, 0.5, 1.5)):
        c = hand + d * (1.8 * s - 0.3 * s * abs(u)) + t * (u * 0.98 * s) + n * 0.3 * s
        m.add(sphere(c, 0.66 * s), fur, grp, (lambda c0: lambda P, mt: np.where(((P - c0) @ t) < -0.4 * s, 'fur_s', mt))(c))
        m.add(sphere(c + n * 0.62 * s, 0.36 * s), pad, None)
        k = c + d * 0.5 * s + n * 0.3 * s
        m.add(cone(k, k + d * 1.1 * s + n * 0.4 * s, 0.36 * s, 0.24 * s), claw, None)
        m.add(cone(k + d * 1.1 * s + n * 0.4 * s, k + d * 1.5 * s + n * 1.3 * s, 0.24 * s, 0.05 * s), claw, None)
    return hand - d * 1.6 * s
