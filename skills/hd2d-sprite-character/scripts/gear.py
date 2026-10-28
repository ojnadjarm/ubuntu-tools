"""Gear: cape anchored under the pauldrons, two-handed glowing sword, scimitar, staff with gem, round shield, spell orb."""
import numpy as np
from core import V, sphere, ellipsoid, cone, torus, box, octa, inter, frame_to
from parts import bands, blade, blade_tex, unit


def cape(m, p, A, s):
    """Cape born 3 units under the neck and clipped flat at neck-1.4 (hidden by gorget and pauldrons), lining, gold hem, clasps."""
    neck, b, cr = A['neck'], A['b'], A['cr']
    cp = p['cape']; top = neck[1] - 1.4; L = s.get('length', 1.0)

    def cape_w(P):
        k = np.clip((neck[1] - P[:, 1]) / 26, 0, 1) ** 1.5
        return np.stack([cp[0] * k, 0 * k, cp[2] * k], 1)
    hem = (5.0 + b * 0.3) * L
    capec = inter(cone(neck + V(0, -3.0, -2.6), V(0, 6 + b * 0.3, -6.4 - cr), 6.6, 12.0),
                  lambda P: np.maximum(np.maximum(P[:, 2] - (-1.6 - 0.04 * (neck[1] - P[:, 1])), P[:, 1] - top), hem - P[:, 1]
                                       + 0.9 * np.sin(np.arctan2(P[:, 0], -P[:, 2] - 4) * 7 + p['fold'])))

    def cape_f(P):
        q = P - cape_w(P); a = np.arctan2(q[:, 0], -q[:, 2]); k = np.clip((top - q[:, 1]) / 26, 0, 1)
        return capec(q) - 0.75 * k * np.sin(a * 6 + p['fold']) - 0.3 * k * np.sin(a * 11 - p['fold'])

    def cape_tex(P, mt):
        mt = mt.copy(); q = P - cape_w(P); edge = -1.6 - 0.04 * (neck[1] - q[:, 1])
        inner = q[:, 2] > edge - 0.3
        trim = ((q[:, 2] > edge - 1.5) & ~inner) | (q[:, 1] < hem + 2.4 + 0.9 * np.sin(np.arctan2(q[:, 0], -q[:, 2] - 4) * 7 + p['fold']))
        mt[trim] = 'trim'; mt[inner] = 'cape_in'
        return mt
    m.add(cape_f, 'cape', None, cape_tex)
    for sd in (-1, 1):
        m.add(octa(neck + V(4.4 * sd, -2.6, 0.4), 1.1), 'gold', None)
        m.add(sphere(neck + V(4.4 * sd, -2.6, 0.9), 0.6), 'gem', None)


def grips(p, w):
    """Hand targets {side: (point, grip, axis)} for the weapon spec: two-handed hilts, else main hand +1 and off hand -1."""
    sd = unit(p['sword']); hilt = p['hilt'] + V(0, p['b'] * 0.6, 0)
    if w.get('hands', 1) == 2:
        return {-1: (hilt + sd * w.get('front', 0.0), 'grip', sd), 1: (hilt - sd * w.get('back', 4.9), 'grip', sd)}
    out = {1: (hilt + sd * w.get('front', 0.0), 'grip', sd)}
    off = p.get('off')
    if off is not None:
        out[-1] = (off + V(0, p['b'] * 0.6, 0), p.get('off_grip', 'open'), None)
    return out


def sword(m, p, A, w):
    """Longsword (hands 1 or 2, grip length): leather grip with gold wraps, pommel gem, quillons, flat blade with fuller, runes and a glow line."""
    sd = unit(p['sword']); hilt = p['hilt'] + V(0, A['b'] * 0.6, 0); L = w.get('length', 26.0); G = w.get('grip', 9.0)
    m.add(cone(hilt - sd * G, hilt + sd * 2.0, 0.85, 0.85), 'leather', None,
          bands(hilt, sd, tuple(np.arange(1.6, -G, -1.4)), 0.22, 'dgold'))
    m.add(octa(hilt - sd * (G + 0.8), 1.5), 'gold', None)
    m.add(sphere(hilt - sd * (G + 0.8), 0.9), 'gem', None)
    perp = unit(np.cross(sd, V(0, 0, 1)))
    for s in (-1, 1):
        m.add(cone(hilt + sd * 2.4, hilt + sd * 2.2 + perp * 3.6 * s, 0.95, 0.5), 'gold', None)
        m.add(sphere(hilt + sd * 2.0 + perp * 3.9 * s, 0.75), 'gold', None)
    m.add(ellipsoid(hilt + sd * 2.6, (1.4, 1.4, 1.0)), 'gold', None)
    m.add(sphere(hilt + sd * 2.6 + V(0, 0, 0.8), 0.7), 'gem', None)
    bs = hilt + sd * 3.0
    m.add(blade(bs, sd, perp, L, 2.1, 0.7), 'blade', None, blade_tex(bs, sd, perp, L, 2.1))
    m.add(box(bs + sd * 0.8, (2.3, 0.8, 0.8), rot=frame_to(sd)), 'dgold', None)
    for u in ((5.0, 9.0, 13.0) if w.get('rune', '#8fd0ff') else ()):
        m.dots.append((bs + sd * u + V(0, 0, 0.8), w.get('rune', '#8fd0ff'), w.get('rune_glow', 0.5), 1.5))
    m.lines.append((bs + sd * 1.0 + perp * 1.7 + V(0, 0, 0.5), bs + sd * (L - 4.5) + perp * 1.0 + V(0, 0, 0.4), w.get('edge', '#cfe6ff'), 1.2))


def scimitar(m, p, A, w):
    """One-handed shamshir: gold knuckle cross, wrapped grip, broad curved blade with a light edge."""
    sd = unit(p['sword']); hilt = p['hilt'] + V(0, A['b'] * 0.6, 0); L = w.get('length', 20.0)
    perp = unit(np.cross(sd, V(0, 0, 1)) * w.get('edge_side', 1))
    m.add(cone(hilt - sd * 2.4, hilt + sd * 1.6, 0.8, 0.8), 'leather', None, bands(hilt, sd, (-1.6, 0.0), 0.22, 'dgold'))
    m.add(sphere(hilt - sd * 2.8, 1.0), 'gold', None)
    m.add(cone(hilt + sd * 2.0 - perp * 2.6, hilt + sd * 2.0 + perp * 2.6, 0.8, 0.8), 'gold', None)
    bs = hilt + sd * 2.4
    m.add(blade(bs, sd, perp, L, 1.9, 0.6, curve=w.get('curve', 1.0)), 'blade', None, blade_tex(bs, sd, perp, L, 1.9, w.get('curve', 1.0), 0))


def staff(m, p, A, w):
    """Staff held in the main hand: shaft with gold bands, crook head cradling an emissive gem."""
    sd = unit(p['sword']); hilt = p['hilt'] + V(0, A['b'] * 0.6, 0)
    top = hilt + sd * w.get('up', 18.0); bot = hilt - sd * w.get('down', 22.0)
    m.add(cone(bot, top, 0.8, 0.95), 'wood', None, bands(hilt, sd, (-12.0, 8.0, 14.0), 0.35, 'gold'))
    m.add(torus(top + sd * 2.6, 2.4, 0.55, rot=frame_to(V(0, 0, 1))), 'gold', None)
    for s in (-1, 1):
        m.add(cone(top + V(1.6 * s, 3.4, 0), top + V(1.0 * s, 7.0, 0.2), 0.5, 0.15), 'gold', None)
    m.add(octa(top + sd * 2.8, 1.6, sy=1.6), 'gem_e', None)
    m.dots.append((top + sd * 3.6 + V(0, 0, 1.2), '#f2fff0', 1.0, 4))


def shield(m, p, A, w):
    """Round buckler on the off hand facing p['shield_dir']: chrome face, gold rim, spokes and boss."""
    c = p['off'] + V(0, A['b'] * 0.6, 0) + unit(p['shield_dir']) * 1.6; d = unit(p['shield_dir']); R = w.get('r', 7.0)
    rot = frame_to(d)
    def spokes(P, mt):
        q = P - c; r = np.sqrt((q @ rot[:, 0]) ** 2 + (q @ rot[:, 2]) ** 2); a = np.arctan2(q @ rot[:, 0], q @ rot[:, 2])
        mt = mt.copy(); mt[(np.abs((a + np.pi / 8) % (np.pi / 4) - np.pi / 8) * r < 0.45) & (r > 1.8)] = 'gold'
        return mt
    m.add(inter(sphere(c - d * (R * 1.6), R * 1.75), lambda P: -((P - c) @ d) - 0.2), 'steel', None, spokes)
    m.add(torus(c - d * 0.2, R - 0.3, 0.7, rot=rot), 'gold', None)
    m.add(sphere(c + d * 0.4, 1.6), 'gold', None)
    m.add(sphere(c + d * 1.4, 0.7), 'gem', None)


def orb(m, p, A, w):
    """Spell orb floating over the open off hand, with orbiting sparks."""
    c = p['off'] + V(0, A['b'] * 0.6 + 3.4, 1.0)
    m.add(sphere(c, w.get('r', 1.8)), 'gem_e', None)
    m.dots.append((c + V(-0.5, 0.6, 1.8), '#ffffff', 1.0, 9))
    ph = p.get('ph', 0.0)
    for i in range(3):
        a = 6.283 * (ph + i / 3)
        m.dots.append((c + V(3.4 * np.cos(a), 1.2 * np.sin(2 * a), 3.4 * np.sin(a)), w.get('spark', '#b8ffb0'), 1.0, 9))


WEAPON = dict(sword=sword, scimitar=scimitar, staff=staff)
OFFHAND = dict(shield=shield, orb=orb)
