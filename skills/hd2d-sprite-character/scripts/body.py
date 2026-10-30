"""Bodies and arms per armour kind: plate knight, gladiator, robed caster, upright beast, kobold. Each returns the anchor dict A."""
import numpy as np
from core import V, sphere, ellipsoid, cone, torus, box, octa, inter, rot_z, rot_x
from rig import ik, yaw, TAU
from hands import add_hand, add_paw
from parts import RIVET, bands, lame, unit

UP = V(0, 1, 0)


def anchors(p, s):
    """Pelvis, chest, neck, head and shoulder points from the pose and the body spec (height factor h)."""
    h = s.get('height', 1.0); b = p['b']; ln = p['lean']; cr = p['crouch']
    A = dict(b=b, ln=ln, cr=cr, h=h)
    A['pel'] = V(0, 22 * h + b, -0.6 * cr)
    A['chest'] = V(0, 31 * h + b + 0.2 * p['chest'], 0.5 * ln)
    A['neck'] = V(0, 37.4 * h + b, 0.8 * ln)
    A['head'] = V(0, (44.5 + s.get('head_lift', 0.0)) * h + b, 0.9 * ln) + p['head']
    A['sh'] = {sd: V(0, 34.5 * h + b, 0.5 * ln) + yaw(V(7.6 * sd * s.get('width', 1.0), 0, 0), 0.25 * sd) for sd in (-1, 1)}
    return A


def legs(m, p, A, s, mat='steel', knee='gold', boot='steel', greave=True):
    """Two IK legs in plate (greave line, knee cop with wing, sabaton) or plain (greave=False)."""
    pel = A['pel']; h = A['h']
    for side, ft in ((-1, p['feet'][0]), (1, p['feet'][1])):
        hip = pel + V(3.4 * side, -1.6, 0)
        ank = ft + V(0, 2.4, 0)
        kn = ik(hip, ank, 9.6 * h, 9.4 * h, V(0.25 * side, 0.1, 1))
        th = unit(kn - hip); sn = unit(ank - kn)
        r = s.get('leg_r', 1.0)
        m.add(cone(hip, kn, 3.3 * r, 2.7 * r), mat, 'leg', bands(hip, th, (6.4,), 0.32) if greave else None)
        m.add(cone(kn, ank, 2.8 * r, 2.0 * r), boot, 'leg', bands(kn, sn, (2.6,), 0.3) if greave else None)
        if greave:
            m.lines.append((kn + sn * 2.8 + V(0, 0, 2.6), ank + V(0, 0.6, 2.0), '#eef6ff', 1.2))
        if knee:
            m.add(ellipsoid(kn + V(0, 0.3, 1.5), (2.3, 2.1, 1.3)), knee, None)
            m.add(ellipsoid(kn + V(1.7 * side, 0.3, 0.9), (1.0, 2.3, 0.5), rot=rot_z(-0.5 * side)), 'd' + knee, None)
            m.dots.append((kn + V(0, 0.4, 2.9), RIVET, 0.0, 1.5))
        if greave:
            m.add(ellipsoid(ft + V(0, 1.4, 1.2), (2.4, 1.6, 3.4)), boot, None, bands(ft, V(0, 0.35, 1), (1.3, 3.2), 0.3, 'dsteel'))
            m.add(cone(ft + V(0, 0.9, 3.6), ft + V(0, 0.6, 5.0), 1.3, 0.6), 'gold', None)
        else:
            m.add(ellipsoid(ft + V(0, 1.3, 1.0), (2.2, 1.5, 3.2)), boot, None, bands(ft, V(0, 1, 0), (2.4,), 0.3, 'leather'))


def plate_body(m, p, A, s):
    """Knight: plate legs, belt with buckle, faulds, tabard flap, lamed tassets, gold-rimmed breastplate with star, gorget."""
    pel, chest, neck = A['pel'], A['chest'], A['neck']
    legs(m, p, A, s)
    m.add(torus(pel + V(0, 1.2, 0.2), 5.9, 0.85), 'leather', None)
    m.add(box(pel + V(0, 1.2, 5.9), (1.3, 1.0, 0.45)), 'gold', None)
    m.dots.append((pel + V(-0.4, 1.6, 6.5), '#ffffff', 0.0, 1.5))
    fl = inter(cone(pel + V(0, 0.6, 0), pel + V(0, -5.2, 0.2), 6.4, 7.6), lambda P: (pel[1] - 5.6) - P[:, 1])
    m.add(fl, 'steel', None, bands(pel, UP, (-2.2, -5.0), 0.3, 'gold'))
    sw = 0.5 * p['fold']
    flap = inter(box(pel + V(0, -5.6, 5.6), (2.3, 5.0, 0.4), rot=rot_x(-0.15)),
                 lambda P: -(P[:, 1] - (pel[1] - 10.2 + 0.5 * np.cos((P[:, 0] - pel[0]) * 1.4 + sw))))
    m.add(flap, 'cape', None, lambda P, mt: np.where((P[:, 1] < pel[1] - 9.0) | (np.abs(P[:, 0] - pel[0]) > 1.7), 'trim', mt))
    for side in (-1, 1):
        for i, (dy, wx) in enumerate(((-2.0, 3.4), (-4.6, 3.1))):
            c = pel + V(5.0 * side, dy, 1.0 - 0.3 * i); rt = rot_z(0.35 * side) @ rot_x(-0.15)
            m.add(lame(c, (wx, 2.1, 1.0), rt), 'steel', None, bands(c, UP, (-1.5,), 0.36))
            m.dots.append((c + V(0, 0.7, 1.4), RIVET, 0.0, 1.5))

    def chest_tex(P, mt):
        mt = mt.copy(); q = P - chest
        rim = np.abs(np.sqrt((q[:, 0] / 6.6) ** 2 + ((q[:, 1] + 1) / 6.2) ** 2) - 0.88) < 0.06
        ridge = (np.abs(q[:, 0]) < 0.4) & (q[:, 1] < -2.6)
        swirl = (np.abs(np.sin(q[:, 0] * 1.1 + q[:, 1] * 0.7) - 0.85) < 0.07) & (np.abs(q[:, 0]) > 2.8) & (q[:, 1] > -2.5)
        mt[(rim | ridge | swirl) & (q[:, 2] > 1.5)] = 'gold'
        return mt
    m.add(ellipsoid(chest, (7.4, 7.2, 5.4)), 'steel', 'body', chest_tex)
    m.add(ellipsoid(pel + V(0, 4.2, 0.2), (6.0, 3.9, 4.4)), 'steel', 'body', bands(pel, UP, (3.1, 5.6), 0.3))
    if s.get('emblem'):
        m.stamps.append((chest + V(0, 0.3, 5.6), s['emblem'], V(0, 0, 1)))
    for sd in (-1, 1):
        m.dots.append((chest + V(3.6 * sd, 2.6, 4.6), RIVET, 0.0, 1.5))
        m.dots.append((chest + V(4.6 * sd, -1.4, 4.2), RIVET, 0.0, 1.5))
    m.add(cone(neck + V(0, -1.6, 0), neck + V(0, 0.6, 0.2), 3.9, 3.1), 'steel', None, bands(neck, UP, (-0.9,), 0.35))
    m.add(torus(neck + V(0, 0.8, 0.2), 3.1, 0.6), 'gold', None)


def gladiator_body(m, p, A, s):
    """Gladiator: furred torso under a cross harness with a gem buckle, studded belt, tattered layered kilt, plain legs with greaves."""
    pel, chest, neck = A['pel'], A['chest'], A['neck']
    legs(m, p, A, s, mat='fur', knee='gold', boot='leather', greave=False)
    for sd in (-1, 1):
        ft = p['feet'][0 if sd < 0 else 1]
        m.add(cone(ft + V(0, 3.2, 0.6), ft + V(0, 8.6, 1.4), 2.5, 2.7), 'steel', None, bands(ft, UP, (4.0, 7.2), 0.3, 'gold'))

    def kilt_tex(P, mt):
        mt = mt.copy(); a = np.arctan2(P[:, 0] - pel[0], P[:, 2] - pel[2])
        mt[np.sin(a * 9) > 0.75] = 'kilt_s'
        mt[P[:, 1] > pel[1] - 1.2] = 'leather'
        return mt
    sw = p['fold']
    kilt = inter(cone(pel + V(0, 0.8, 0), pel + V(0, -9.0, 0.6), 6.4, 8.6),
                 lambda P: (pel[1] - 8.6 + 1.1 * np.abs(np.sin(np.arctan2(P[:, 0], P[:, 2] - pel[2]) * 5 + sw))) - P[:, 1])
    m.add(kilt, 'kilt', None, kilt_tex)
    m.add(torus(pel + V(0, 1.4, 0.2), 6.2, 1.1), 'leather', None, bands(pel, V(1, 0, 0), (-4, -2, 0, 2, 4), 0.25, 'gold'))
    m.add(box(pel + V(0, 1.4, 6.6), (1.6, 1.3, 0.5)), 'gold', None)
    m.add(sphere(pel + V(0, 1.4, 7.0), 0.8), 'gem', None)
    m.add(ellipsoid(chest + V(0, 0.4, 0), (7.6, 7.6, 5.6)), 'fur', 'body',
          lambda P, mt: np.where((P[:, 2] - chest[2] > 2.0) & (np.abs(P[:, 0] - chest[0]) < 3.6) & (P[:, 1] < chest[1] + 2), 'fur_l', mt))
    m.add(ellipsoid(pel + V(0, 4.4, 0.2), (6.2, 4.2, 4.6)), 'fur', 'body')
    for sd in (-1, 1):
        a0 = chest + V(5.8 * sd, 5.4, 1.6); a1 = pel + V(-4.4 * sd, 3.0, 4.8)
        m.add(cone(a0, a1, 0.9, 0.9), 'leather', None)
        m.add(cone(a0 + V(0, 0, -6.0), a1 + V(0, 0, -9.0), 0.9, 0.9), 'leather', None)
    m.add(octa(chest + V(0, -0.6, 5.8), 1.5), 'gold', None)
    m.add(sphere(chest + V(0, -0.6, 6.4), 0.8), 'gem', None)
    m.add(cone(neck + V(0, -1.6, 0), neck + V(0, 0.6, 0.2), 3.9, 3.3), 'fur', None)


def robe_body(m, p, A, s):
    """Caster: floor-length robe flaring to a gold hem with folds, chest plate with an emblem, sash, high collar."""
    pel, chest, neck = A['pel'], A['chest'], A['neck']
    sw = p['fold']; hem = 0.6

    def robe(P):
        q = P - pel; a = np.arctan2(q[:, 0], q[:, 2])
        k = np.clip((pel[1] + 8 - P[:, 1]) / 30, 0, 1)
        d = cone(pel + V(0, 9, 0), V(0, hem, -1.2 + p['cape'][2] * 0.3), 6.6, 11.0)(P - np.stack([p['cape'][0] * k ** 2, 0 * k, 0 * k], 1))
        return np.maximum(d - 0.7 * k * np.sin(a * 7 + sw), hem - P[:, 1])

    def robe_tex(P, mt):
        mt = mt.copy(); a = np.arctan2(P[:, 0] - pel[0], P[:, 2] - pel[2])
        mt[P[:, 1] < hem + 2.0] = 'trim'
        mt[(np.abs(a) < 0.16) & (P[:, 1] < pel[1] + 4)] = 'robe_in'
        mt[(np.abs(np.abs(a) - 0.2) < 0.06)] = 'trim'
        return mt
    m.add(robe, 'robe', None, robe_tex)
    m.add(torus(pel + V(0, 3.2, 0.4), 5.8, 1.0), 'sash', None)
    m.add(ellipsoid(chest, (7.0, 7.4, 5.2)), 'robe', 'body')
    m.add(ellipsoid(chest + V(0, 0.4, 1.4), (5.2, 5.6, 4.2)), 'plate', None,
          lambda P, mt: np.where(np.abs(np.sqrt(((P[:, 0] - chest[0]) / 4.6) ** 2 + ((P[:, 1] - chest[1] - 0.4) / 5.0) ** 2) - 0.9) < 0.08, 'trim', mt))
    if s.get('emblem'):
        m.stamps.append((chest + V(0, 0.8, 5.8), s['emblem'], V(0, 0, 1)))
    m.add(cone(neck + V(0, -2.0, -0.4), neck + V(0, 1.6, -0.8), 4.6, 4.2), 'robe', None)


def beast_body(m, p, A, s):
    """Upright beast: barrel torso and belly, short thick legs with paws; leather harness and saddle (`harness` False: bare fur),
    optional shoulder `hump`."""
    pel, chest, neck = A['pel'], A['chest'], A['neck']; h = A['h']; harness = s.get('harness', True)
    for side, ft in ((-1, p['feet'][0]), (1, p['feet'][1])):
        hip = pel + V(5.2 * side, -2.0, 0)
        kn = ik(hip, ft + V(0, 3.2, 0), 8.0 * h, 7.2 * h, V(0.3 * side, 0, 1))
        m.add(cone(hip, kn, 6.0, 4.8), 'fur', 'leg')
        m.add(cone(kn, ft + V(0, 3.0, 0), 4.6, 3.8), 'fur', 'leg')
        m.add(ellipsoid(ft + V(0, 1.8, 1.8), (4.0, 2.2, 4.8)), 'fur', 'leg')
        for i in (-1, 0, 1):
            m.add(cone(ft + V(1.3 * i, 1.4, 5.6), ft + V(1.4 * i, 0.4, 7.4), 0.55, 0.15), 'claw', None)
    m.group('leg', 1.6)

    def fur_tex(P, mt):
        mt = mt.copy(); q = P - chest
        tuft = np.sin(q[:, 0] * 1.3 + q[:, 1] * 2.1) * np.sin(q[:, 1] * 1.7 - q[:, 2] * 1.1) > 0.55
        mt[tuft] = 'fur_s'
        mt[(q[:, 2] > 3.0) & (np.abs(q[:, 0]) < 5.0 * h) & (q[:, 1] < 2)] = 'fur_l'
        if not harness:
            return mt
        front = q[:, 2] > -2.0
        x1 = np.abs(q[:, 0] * 0.8 - q[:, 1] * 0.6 - 1.0) < 0.9; x2 = np.abs(q[:, 0] * 0.8 + q[:, 1] * 0.6 + 1.0) < 0.9
        mt[front & (x1 | x2) & (q[:, 1] > -9) & (q[:, 1] < 9)] = 'leather'
        mt[np.abs(q[:, 1] + 9.6) < 1.0] = 'leather'
        return mt
    m.add(ellipsoid(pel + V(0, 5.0, 0.8), (10.0 * h, 10.0 * h, 8.6 * h)), 'fur', 'body', fur_tex)
    m.add(ellipsoid(chest + V(0, 1.0, -0.6), (10.6 * h, 8.6 * h, 8.0 * h)), 'fur', 'body', fur_tex)
    m.add(ellipsoid(neck + V(0, -1.2, -0.4), (6.6 * h, 4.6 * h, 5.6 * h)), 'fur', 'body', fur_tex)
    m.group('body', 2.6)
    if s.get('hump'):
        m.add(ellipsoid(chest + V(0, 7.0 * h, -3.4 * h), (7.6 * h, 4.4 * h, 5.6 * h)), 'fur', 'body', fur_tex)
    if not harness:
        return
    m.add(octa(chest + V(0, -1.3, 7.8 * h), 1.8), 'gold', None)
    m.add(sphere(chest + V(0, -1.3, 7.8 * h + 0.9), 0.8), 'gem', None)
    for sd in (-1, 1):
        m.add(octa(chest + V(5.2 * sd, -9.6, 7.0 * h), 1.0), 'gold', None)
        for i in range(3):
            m.dots.append((chest + V((2.2 + 3.0 * i) * sd, 4.6 - 2.4 * i, 8.6 * h - 0.6 * i), '#fff2b0', 0.0, 2.0))
    m.add(ellipsoid(chest + V(0, 8.0 * h, -6.0 * h), (7.4, 2.6, 5.4)), 'leather', None, bands(chest, UP, (8.0 * h + 1.6,), 0.4, 'gold'))


def plate_arm(m, p, A, side, hand, grip, axis, s):
    """Lamed pauldron, gold boss, steel arm, winged elbow cop, gauntlet with gold cuff."""
    sh = A['sh'][side]
    for i, (dy, r) in enumerate(((1.8, (4.8, 3.4, 4.6)), (-0.6, (4.4, 2.6, 4.2)), (-2.6, (4.0, 2.2, 3.8)))):
        c = sh + V((0.8 + 0.5 * i) * side, dy, 0.2); rt = rot_z(-(0.35 + 0.12 * i) * side)
        m.add(lame(c, r, rt, 0.7), 'steel', None, bands(c, rt.T @ UP, (-0.55 * r[1],), 0.38))
        m.dots.append((c + V(0.9 * side, 0.2 * r[1], 0.7 * r[2]), RIVET, 0.0, 1.5))
    m.add(sphere(sh + V(0.6 * side, 3.4, -0.4), 1.4), 'gold', None)
    el = ik(sh, hand, 7.2, 7.4, V(side * 1.0, -0.6, -0.2))
    m.add(cone(sh, el, 2.6, 2.2), 'dsteel', 'arm%d' % side)
    fa = unit(hand - el)
    m.add(ellipsoid(el, (1.7, 1.7, 1.7)), 'gold', None)
    m.add(ellipsoid(el + V(1.1 * side, 0, -0.6), (0.6, 1.8, 1.5)), 'dgold', None)
    m.dots.append((el + V(0.6 * side, 0.4, 1.8), RIVET, 0.0, 1.5))
    wr = add_hand(m, el, hand, side, grip, axis=axis, size=s.get('hand', 1.3), cuff=('gold', 2.4), knuckle=s.get('knuckle'), claw=s.get('claw'),
                  palm=p.get('palm', {}).get(side), point=p.get('point', {}).get(side))
    m.add(cone(el, wr, 2.5, 2.2), 'steel', 'arm%d' % side, bands(el, fa, (2.6,), 0.3))
    m.group('arm%d' % side, 0.5)


def gladiator_arm(m, p, A, side, hand, grip, axis, s):
    """Fur arm; the near (+x) shoulder wears a lamed spiked pauldron, both forearms leather bracers with gold studs."""
    sh = A['sh'][side]
    if side == s.get('pauldron', 1):
        for i, (dy, r) in enumerate(((1.6, (5.0, 3.4, 4.8)), (-0.8, (4.4, 2.6, 4.2)))):
            c = sh + V((0.8 + 0.5 * i) * side, dy, 0.2); rt = rot_z(-(0.4 + 0.12 * i) * side)
            m.add(lame(c, r, rt, 0.7), 'steel', None, bands(c, rt.T @ UP, (-0.55 * r[1],), 0.38))
            m.dots.append((c + V(0.9 * side, 0.2 * r[1], 0.7 * r[2]), RIVET, 0.0, 1.5))
        m.add(cone(sh + V(2.4 * side, 3.8, 0), sh + V(4.2 * side, 7.4, -0.4), 1.0, 0.1), 'gold', None)
    else:
        m.add(sphere(sh + V(0.6 * side, 0.6, 0), 3.4), 'fur', 'arm%d' % side)
    el = ik(sh, hand, 7.4, 7.4, V(side * 1.0, -0.6, -0.2))
    m.add(cone(sh, el, 3.0, 2.6), 'fur', 'arm%d' % side)
    fa = unit(hand - el)
    wr = add_hand(m, el, hand, side, grip, axis=axis, size=s.get('hand', 1.3), cuff=('gold', 2.0), knuckle=s.get('knuckle'), claw=s.get('claw'),
                  palm=p.get('palm', {}).get(side), point=p.get('point', {}).get(side))
    m.add(cone(el, wr, 2.6, 2.3), 'leather', 'arm%d' % side, bands(el, fa, (1.6, 4.4), 0.32, 'gold'))
    m.group('arm%d' % side, 0.6)


def robe_arm(m, p, A, side, hand, grip, axis, s):
    """Wide sleeve flaring to a gold cuff, bare hand."""
    sh = A['sh'][side]
    m.add(sphere(sh + V(0.4 * side, 0.4, 0), 3.4), 'robe', 'arm%d' % side)
    el = ik(sh, hand, 7.2, 7.4, V(side * 1.0, -0.6, -0.2))
    m.add(cone(sh, el, 3.0, 2.8), 'robe', 'arm%d' % side)
    wr = add_hand(m, el, hand, side, grip, axis=axis, size=s.get('hand', 1.2), knuckle=s.get('knuckle'), claw=s.get('claw'),
                  palm=p.get('palm', {}).get(side), point=p.get('point', {}).get(side))
    fa = unit(hand - el)
    m.add(cone(el, wr - fa * 0.4, 2.9, 3.6), 'robe', 'arm%d' % side, bands(el, fa, (np.linalg.norm(wr - el) - 1.6,), 0.5, 'trim'))
    m.group('arm%d' % side, 0.6)


def beast_arm(m, p, A, side, hand, grip, axis, s):
    """Thick fur arm ending in a paw: pale palm pad toward the enemy, four toe pads with seams, curved ivory claws."""
    sh = A['sh'][side]
    el = ik(sh, hand, 9.0, 8.4, V(side * 1.0, -0.8, -0.2))
    m.add(cone(sh, el, 5.0, 4.0), 'fur', 'arm%d' % side)
    wr = add_paw(m, el, hand, side, s.get('hand', 1.6), p.get('palm', {}).get(side))
    m.add(cone(el, wr, 4.0, 3.2), 'fur', 'arm%d' % side)
    m.group('arm%d' % side, 1.4)


def scales(c, k=1.0):
    """Texture: staggered scale rows (darker 'scale_s' crescents) over a reptile hide."""
    def t(P, mt):
        mt = mt.copy(); q = (P - c) * k
        row = np.floor(q[:, 1] / 1.4); u = q[:, 0] / 1.6 + 0.5 * row
        f = (q[:, 1] / 1.4 - row) + 0.35 * (2 * np.abs(u - np.round(u)))
        mt[(f < 0.32) & (mt == 'scale')] = 'scale_s'
        return mt
    return t


def kobold_body(m, p, A, s):
    """Kobold: hunched scaly torso with a pale ribbed belly, digitigrade legs with three-toed claws, ragged loincloth on a rope
    belt, bandolier with a tooth necklace, spine ridges and a long tail; `wisp` replaces the legs with a swirling ectoplasm tail."""
    pel, chest, neck = A['pel'], A['chest'], A['neck']; h = A['h']
    if s.get('wisp'):
        sw = p['fold']

        def wisp(P):
            k = np.clip((pel[1] - P[:, 1]) / 16, 0, 1)
            q = P - np.stack([3.4 * k ** 1.5 * np.sin(TAU * k + sw), 0 * k, -2.6 * k ** 2 + 1.6 * k * np.cos(TAU * k + sw)], 1)
            return cone(pel + V(0, 1.0, 0), pel + V(0, -16.0, -2.0), 5.4, 0.6)(q) - 0.5 * k * np.sin(np.arctan2(q[:, 0], q[:, 2]) * 5 + 3 * sw)
        m.add(wisp, 'scale', 'body', lambda P, mt: np.where(np.sin((P[:, 1] - pel[1]) * 0.9 + np.arctan2(P[:, 0], P[:, 2]) * 2) > 0.6, 'scale_s', mt))
    else:
        for side, ft in ((-1, p['feet'][0]), (1, p['feet'][1])):
            hip = pel + V(3.0 * side, -1.2, 0)
            hock = ft + V(0, 3.6 * h, -2.4 * h)
            kn = ik(hip, hock, 6.4 * h, 6.2 * h, V(0.2 * side, 0.2, 1))
            m.add(cone(hip, kn, 3.0, 2.0), 'scale', 'leg', scales(hip))
            m.add(cone(kn, hock, 1.9, 1.3), 'scale', 'leg', scales(kn))
            m.add(cone(hock, ft + V(0, 0.9, 0.6), 1.3, 1.1), 'scale', 'leg')
            for i in (-1, 0, 1):
                t0 = ft + V(0.9 * i, 0.7, 1.4); t1 = ft + V(1.5 * i, 0.4, 3.4 - abs(i) * 0.6)
                m.add(cone(t0, t1, 0.75, 0.5), 'scale', None)
                m.add(cone(t1, t1 + V(0.2 * i, -0.5, 1.2), 0.45, 0.08), 'claw', None)
            m.add(cone(hock, hock + V(0, -0.6, -1.6), 0.5, 0.1), 'claw', None)
    tl = p['tail']; t0 = pel + V(0, 0.4, -3.4)
    pts = [t0, t0 + V(0, -3.0, -4.6) + tl * 0.4, t0 + V(0.6, -6.2, -9.6) + tl * 1.0, t0 + V(1.6, -7.4, -14.6) + tl * 1.6,
           t0 + V(2.8, -6.4, -18.6) + tl * 2.2]
    for i, (a_, b_) in enumerate(zip(pts, pts[1:])):
        m.add(cone(a_, b_, 2.6 - 0.6 * i, 2.0 - 0.6 * i if i < 3 else 0.2), 'scale', 'tail', scales(t0))
        m.add(cone(a_ + V(0, 2.0 - 0.4 * i, 0), a_ + V(0, 3.0 - 0.5 * i, -1.2), 0.6, 0.1), 'spine', None)
    m.group('tail', 1.0)

    def belly(P, mt):
        mt = scales(chest)(P, mt); q = P - chest
        b = (q[:, 2] > 2.2) & (np.abs(q[:, 0]) < 3.4)
        mt[b] = 'belly'; mt[b & (np.abs(np.sin(q[:, 1] * 1.6)) < 0.22)] = 'belly_s'
        return mt
    m.add(ellipsoid(chest + V(0, -0.4, 0), (5.2, 5.6, 4.4)), 'scale', 'body', belly)
    m.add(ellipsoid(pel + V(0, 3.0, 0.2), (4.4, 3.8, 3.8)), 'scale', 'body', belly)
    m.add(cone(neck + V(0, -1.6, -0.4), neck + V(0, 1.4, 0.4), 2.8, 2.2), 'scale', 'body', scales(neck))
    for i in range(4):
        c = chest + V(0, 4.4 - 2.6 * i, -4.0 + 0.2 * i)
        m.add(cone(c, c + V(0, 1.2, -1.6), 0.7, 0.1), 'spine', None)
    if not s.get('wisp'):
        sw = p['fold']
        rag = inter(cone(pel + V(0, 0.6, 0), pel + V(0, -6.0, 0.6), 4.8, 5.8),
                    lambda P: (pel[1] - 5.4 + 1.2 * np.abs(np.sin(np.arctan2(P[:, 0], P[:, 2] - pel[2]) * 4 + sw))) - P[:, 1])
        m.add(rag, 'rag', None, lambda P, mt: np.where(np.sin(np.arctan2(P[:, 0] - pel[0], P[:, 2] - pel[2]) * 7) > 0.7, 'rag_s', mt))
    m.add(torus(pel + V(0, 0.9, 0.2), 4.7, 0.6), 'leather', None, bands(pel, V(1, 0, 0), (-3, -1, 1, 3), 0.22, 'rag_s'))
    a0 = chest + V(4.2, 3.6, 0.8); a1 = pel + V(-3.6, 1.6, 3.6)
    m.add(cone(a0, a1, 0.7, 0.7), 'leather', None)
    m.add(box(chest + V(0.4, 0.0, 4.6), (1.0, 0.8, 0.35)), 'rust', None)
    for i, x in enumerate((-2.2, -0.8, 0.8, 2.2)):
        c = neck + V(x, -2.4 - 0.7 * (1.5 - abs(i - 1.5)), 2.6)
        m.add(cone(c, c + V(0, -1.4, 0.4), 0.45, 0.08), 'bone', None)
    m.lines.append((neck + V(-2.8, -1.9, 2.4), neck + V(2.8, -1.9, 2.4), s.get('cord', '#3a2418'), 1.0))


def kobold_arm(m, p, A, side, hand, grip, axis, s):
    """Thin scaly arm with a rag-wrapped forearm, bony elbow spur and a clawed four-finger hand."""
    sh = A['sh'][side]
    m.add(sphere(sh + V(0.4 * side, 0.2, 0), 2.2), 'scale', 'arm%d' % side, scales(sh))
    el = ik(sh, hand, 5.6, 5.4, V(side * 1.0, -0.8, -0.4))
    m.add(cone(sh, el, 1.7, 1.3), 'scale', 'arm%d' % side, scales(sh))
    m.add(cone(el, el + unit(el - hand) * 1.6 + V(0, 0.4, 0), 0.6, 0.1), 'spine', None)
    wr = add_hand(m, el, hand, side, grip, axis=axis, size=s.get('hand', 1.1), claw=s.get('claw', 'claw'),
                  palm=p.get('palm', {}).get(side), point=p.get('point', {}).get(side), rod=0.7)
    fa = unit(hand - el)
    m.add(cone(el, wr, 1.3, 1.1), 'scale', 'arm%d' % side, bands(el, fa, (np.linalg.norm(wr - el) - 1.4, np.linalg.norm(wr - el) - 2.6), 0.4, 'rag'))
    m.group('arm%d' % side, 0.5)


BODY = dict(plate=plate_body, gladiator=gladiator_body, robe=robe_body, beast=beast_body, kobold=kobold_body)
ARM = dict(plate=plate_arm, gladiator=gladiator_arm, robe=robe_arm, beast=beast_arm, kobold=kobold_arm)
