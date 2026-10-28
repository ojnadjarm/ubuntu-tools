"""Heads: FFBE-style anime head (bangs to the eye line, tall eyes, V chin) and beast heads (lion, falcon, bear)."""
import numpy as np
from core import V, pat, sphere, ellipsoid, cone, torus, inter, sub

EYE_ROWS_N = ['dkkkk', '.sbwk', '.bil.', '..ll.', '....r']
EYE_ROWS_F = ['kkkd', 'kwb.', '.li.', '.l..']
BANGS = ((V(-2.8, 4.2, 3.6), V(-4.4, -1.4, 4.8), 1.8), (V(-1.2, 4.6, 4.2), V(-1.9, -0.2, 6.0), 1.7),
         (V(0.6, 4.6, 4.2), V(0.3, -0.8, 6.2), 1.6), (V(2.4, 4.4, 3.8), V(2.9, 0.1, 5.8), 1.6),
         (V(3.8, 3.8, 3.0), V(4.8, -2.0, 4.2), 1.5))
SPIKES = ((V(-1.4, 5.6, 1.6), V(-3.8, 9.2, 2.6)), (V(1.0, 6.0, 0.6), V(2.6, 9.6, 0.4)), (V(-3.6, 4.8, 0.6), V(-6.8, 6.6, 1.2)))


def eyes(iris, lash='#160812', blush='#f2a090'):
    """Near (5x5) and far (4x4) eye stamps; iris = (dark, mid, light) hex."""
    c = {'k': lash, 'd': '#3a1a28', 'b': iris[0], 'i': iris[1], 'l': iris[2], 'w': '#ffffff', 's': '#f6eef0', 'r': blush}
    return pat(EYE_ROWS_N, c, 2, 1), pat(EYE_ROWS_F, c, 2, 1)


def anime_head(m, p, A, s):
    """Skin only on the lower head, cap cut at the brow, 5 bang cones, side locks, crown spikes, optional ponytail with rings."""
    H = A['head']; dark, light = s.get('hair_lines', ('#5e2012', '#ffe2a8'))
    m.add(sphere(H + V(0, 0.4, -0.4), 5.7), 'skin', 'head')
    m.add(cone(H + V(0, -0.6, 1.4), H + V(0, -5.3, 3.9), 4.5, 0.5), 'skin', 'head')

    def hair_tex(P, mt):
        mt = mt.copy(); q = P - H; a = np.arctan2(q[:, 0], q[:, 2] + 2)
        sv = np.sin(a * 7 + q[:, 1] * 0.3)
        mt[(sv > 0.9) & (q[:, 1] > 1.0)] = 'hair_s'
        mt[(np.abs(q[:, 1] - 4.2 + 0.9 * np.abs(np.sin(a * 5))) < 0.5) & (q[:, 2] > -1.0)] = 'hair_h'
        return mt

    def tail_tex(P, mt):
        mt = mt.copy(); sv = np.sin((P[:, 0] - H[0]) * 2.1 + (P[:, 2] - H[2]) * 0.6)
        mt[sv > 0.55] = 'hair_s'; return mt
    cap = ellipsoid(H + V(0, 1.9, -0.8), (6.4, 5.5, 6.3))
    m.add(inter(cap, lambda P: np.minimum(H[1] + 1.6 - P[:, 1], P[:, 2] - H[2] - 0.8)), 'hair', 'hair', hair_tex)
    for r0, t, w in s.get('bangs', BANGS):
        m.add(cone(H + r0, H + t, w, 0.3), 'hair', None, hair_tex)
        m.lines.append((H + r0 + V(0.5 * w, -1.0, 0.6), H + t + V(0.2, 0.6, 0.1), dark, 0.8))
        m.lines.append((H + r0 + V(-0.3 * w, -0.6, 0.7), H + r0 + (t - r0) * 0.45 + V(-0.2, 0, 0.5), light, 0.8))
    lock = s.get('locks', 5.6)
    for sd in (-1, 1):
        m.add(cone(H + V(5.0 * sd, 2.0, 1.6), H + V(5.4 * sd, -lock, 2.8), 1.7, 0.35), 'hair', None, hair_tex)
    for r0, t in s.get('spikes', SPIKES):
        m.add(cone(H + r0, H + t, 1.6, 0.25), 'hair', None, hair_tex)
    if s.get('ponytail', False):
        tl = p['tail']
        c0 = H + V(0, 4.6, -4.8)
        c1 = H + V(0, 6.6, -8.4) + tl * 0.3
        c2 = H + V(0.3, 3.6, -11.8) + tl * 0.7
        c3 = H + V(0.6, -2.8, -13.2) + tl * 1.2
        c4 = H + V(0.9, -9.2, -12.4) + tl * 1.7
        m.add(torus(c0, 1.8, 0.8, sy=1.4), 'gold', None)
        m.add(torus(c0 + (c1 - c0) * 0.35, 1.9, 0.5), 'gold', None)
        for a_, b_, r0, r1 in ((c0, c1, 1.8, 2.6), (c1, c2, 2.6, 2.6), (c2, c3, 2.6, 2.0), (c3, c4, 2.0, 0.6)):
            m.add(cone(a_, b_, r0, r1), 'hair', 'tail', tail_tex)
            m.lines.append((a_ + V(0.5, 1.2, 0), b_ + V(0.5, 0.8, 0), s.get('tail_line', '#ffd08a'), 1.0))
    en, ef = eyes(s.get('iris', ('#173a8c', '#2f7ee6', '#8fd8ff')))
    for sd in (-1, 1):
        m.stamps.append((H + V(2.1 * sd, -0.4, 5.6), en if sd > 0 else ef, V(0.2 * sd, 0, 1)))
    m.stamps.append((H + V(0.9, -3.2, 4.4), pat(['ab'], {'a': '#a4483e', 'b': '#d8826a'}), V(0, 0, 1)))


BEAST_EYE = ['kkk', 'wik', 'iik']


def beast_eyes(m, H, off, iris, glow=0.0, size='n'):
    """Two beast eyes as stamps (amber or spectral), the far one narrower."""
    c = {'k': '#120a10', 'w': '#ffffff', 'i': iris}
    for sd in (-1, 1):
        rows = BEAST_EYE if sd > 0 else ['kk', 'ik']
        m.stamps.append((H + V(off[0] * sd, off[1], off[2]), pat(rows, c, 1, 1), V(0.3 * sd, 0, 1)))
        if glow:
            m.dots.append((H + V(off[0] * sd, off[1] - 0.4, off[2] + 0.4), iris, glow, 3))


def lion_head(m, p, A, s):
    """Lion: broad muzzle with dark nose and fangs, round ears, amber eyes under a heavy brow, layered mane of locks around the face."""
    H = A['head']; mn = p.get('mane', V(0, 0, 0))
    m.add(sphere(H + V(0, 0.6, 0), 6.0), 'fur', 'head')
    m.add(ellipsoid(H + V(0, -2.2, 4.6), (4.0, 3.0, 3.4)), 'fur_l', 'head')
    m.add(ellipsoid(H + V(0, 2.2, 4.4), (4.8, 1.3, 2.0)), 'fur', 'head')
    m.add(ellipsoid(H + V(0, -0.6, 7.6), (1.6, 1.0, 1.0)), 'nose', None)
    m.add(ellipsoid(H + V(0, -4.8, 4.6), (2.4, 1.3, 2.2)), 'mouth', None)
    for sd in (-1, 1):
        m.lines.append((H + V(0.8 * sd, 2.6, 6.0), H + V(3.8 * sd, 3.4, 5.0), '#3a3034', 1.2))
    for sd in (-1, 1):
        m.add(cone(H + V(1.3 * sd, -3.8, 6.2), H + V(1.4 * sd, -6.2, 6.0), 0.55, 0.12), 'claw', None)
        m.add(sphere(H + V(4.8 * sd, 5.4, -0.6), 1.8), 'fur', None)
        m.add(sphere(H + V(4.8 * sd, 5.4, 0.0), 0.9), 'mouth', None)
    beast_eyes(m, H, (2.6, 1.0, 5.6), s.get('iris', '#f2b030'))
    rng = np.random.default_rng(s.get('seed', 7))
    for ring, (R, z, n, w) in enumerate(((6.4, -0.6, 14, 2.6), (7.8, -2.6, 16, 2.8), (6.6, -4.4, 10, 2.6))):
        for i in range(n):
            a = 2 * np.pi * (i + 0.5 * ring) / n
            if np.cos(a) < -0.85 and ring == 0:
                continue
            r0 = H + V(np.sin(a) * R * 0.55, np.cos(a) * R * 0.55 + 0.6, z)
            t = H + V(np.sin(a) * (R + 4.0), np.cos(a) * (R + 2.8) - 1.5, z - 2.0) + mn * (1 + ring) * 0.4 + V(*rng.normal(0, 0.5, 3))
            m.add(cone(r0, t, w, 0.4), 'mane', 'mane', lambda P, mt: np.where(np.sin(P[:, 0] * 2.6 + P[:, 1] * 1.4) > 0.6, 'mane_s', mt))
    m.group('mane', 1.0)


def falcon_head(m, p, A, s):
    """Falcon: feathered head with cheek stripe, hooked beak, a spectral glowing eye, under a deep hood with a gold rim."""
    H = A['head']
    m.add(ellipsoid(H + V(0, 0.4, 0.6), (5.0, 5.4, 5.6)), 'feather', 'head',
          lambda P, mt: np.where((P[:, 1] - H[1] < -1.0) & (P[:, 2] - H[2] > 1.4), 'feather_l', mt))
    m.add(cone(H + V(0, 0.4, 5.0), H + V(0, -1.2, 8.6), 2.0, 0.7), 'beak', 'beak')
    m.add(cone(H + V(0, -1.2, 8.6), H + V(0, -3.6, 8.2), 0.7, 0.2), 'beak_d', 'beak')
    m.add(cone(H + V(0, -1.6, 5.2), H + V(0, -2.4, 7.0), 1.0, 0.4), 'beak_d', 'beak')
    m.group('beak', 0.8)
    for sd in (-1, 1):
        m.lines.append((H + V(3.4 * sd, -0.6, 4.0), H + V(3.6 * sd, -4.0, 2.8), '#2a1a12', 1.2))
        m.lines.append((H + V(1.2 * sd, 3.0, 5.0), H + V(4.2 * sd, 2.2, 4.0), '#2a1a12', 1.2))
    beast_eyes(m, H, (2.8, 1.4, 4.8), s.get('iris', '#7dff6a'), glow=1.0)
    cut = ellipsoid(H + V(0, 0.2, 3.6), (5.8, 6.4, 6.2))
    hood = sub(ellipsoid(H + V(0, 1.4, -0.8), (7.6, 8.0, 7.8)), cut)
    m.add(hood, 'robe', None, lambda P, mt: np.where(cut(P) < 0.9, 'trim', mt))
    m.add(cone(H + V(0, 6.4, -4.4), H + V(0, 3.6, -10.0) + p.get('tail', V(0, 0, 0)) * 0.6, 3.2, 0.8), 'robe', None)


def bear_head(m, p, A, s):
    """Bear: big round head, pale muzzle with a black nose, small round ears, beady eyes, a scar over one brow."""
    H = A['head']
    m.add(sphere(H + V(0, 0.6, 0), 7.2), 'fur', 'head',
          lambda P, mt: np.where(np.sin(P[:, 0] * 1.3 + P[:, 1] * 2.1) * np.sin(P[:, 1] * 1.7 - P[:, 2] * 1.1) > 0.6, 'fur_s', mt))
    m.add(ellipsoid(H + V(0, -2.0, 5.6), (3.8, 3.0, 3.8)), 'fur_l', 'head')
    m.add(ellipsoid(H + V(0, -0.6, 9.0), (1.8, 1.2, 1.1)), 'nose', None)
    m.add(ellipsoid(H + V(0, -4.0, 7.2), (2.0, 0.7, 1.4)), 'mouth', None)
    for sd in (-1, 1):
        m.add(sphere(H + V(5.4 * sd, 6.0, -0.6), 2.4), 'fur', 'head')
        m.add(sphere(H + V(5.6 * sd, 6.0, 0.6), 1.2), 'fur_l', None)
    beast_eyes(m, H, (3.0, 1.8, 6.2), s.get('iris', '#ffcf40'))
    m.lines.append((H + V(1.6, 4.4, 6.0), H + V(3.8, 1.2, 6.0), '#e8b0a0', 1.5))


HEAD = dict(anime=anime_head, lion=lion_head, falcon=falcon_head, bear=bear_head)
