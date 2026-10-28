"""Tier: maroon bear in a leather harness and saddle, two grinning red imps riding on his shoulders, a violet-winged fairy with a glowing wand."""
import numpy as np

RAMPS = {
    'maroon': ['#120406', '#22080c', '#3a0e14', '#56161c', '#702024', '#8a2c2c', '#a63c36', '#c05444'],
    'tan': ['#4a2418', '#7a4430', '#a86a4a', '#d09a72', '#ecc8a0'],
    'hide': ['#1c1014', '#2e1c22', '#4f3028', '#6a4232', '#8c5a3e', '#b07a54'],
    'gild': ['#2a160e', '#4f3016', '#82541c', '#b8862e', '#e0ac44', '#f8d270', '#fff2b0', '#fffbe8'],
    'ivory': ['#6a5a48', '#b8a888', '#f2ead4', '#ffffff'],
    'coal': ['#06060a', '#14141c', '#2a2a36', '#50505e'],
    'impred': ['#2a0408', '#5a0a10', '#8e1418', '#c42420', '#ee4a2c', '#ff8a5a'],
    'horn': ['#1a1010', '#3a2a24', '#6a5a48', '#b8a888'],
    'lilac': ['#2a1446', '#4c2a7a', '#7a4ab4', '#a87ae0', '#d4b4ff', '#f4ecff'],
    'wing': ['#6a4ab4', '#a07ae8', '#d0b4ff', '#f4ecff'],
    'pinkhair': ['#5a1a3a', '#9a3060', '#d45a8a', '#f496ba', '#ffd0e4'],
    'peach': ['#5a2824', '#9a4a3a', '#d27c60', '#f0ae8a', '#ffd8bc', '#fff0e0'],
    'spark': ['#ffd8f0', '#ffffff'],
    'ruby': ['#3a0612', '#7a1026', '#c4243e', '#ff5a6a', '#ffc8c8'],
}
MATS = dict(
    fur=('maroon', {'wrap': 0.5, 'gamma': 1.0, 'bias': 0.0}), fur_s=('maroon', {'wrap': 0.5, 'bias': -0.9}),
    fur_l=('tan', {'wrap': 0.5, 'bias': 0.3}), leather=('hide', {'wrap': 0.4, 'bias': -0.1}),
    gold=('gild', {'kind': 'metal', 'bias': 0.4}), claw=('ivory', {'kind': 'metal'}),
    nose=('coal', {'kind': 'metal', 'bias': 0.2}), mouth=('coal', {'wrap': 0.2}),
    imp=('impred', {'wrap': 0.5, 'bias': 0.5}), horn=('horn', {'kind': 'metal', 'bias': 0.3}),
    dress=('lilac', {'wrap': 0.6, 'bias': 0.6}), wing=('wing', {'kind': 'emis', 'glow': 0.45}),
    fhair=('pinkhair', {'wrap': 0.6, 'bias': 0.4}), skin=('peach', {'kind': 'skin', 'bias': 0.6}),
    wand=('spark', {'kind': 'emis', 'glow': 1.0}), gem=('ruby', {'kind': 'metal', 'bias': 0.6}),
)
SPEC = dict(
    frames=8, scale=1.6, stance='brawler', hand_mat='fur',
    body=dict(kind='beast', height=1.25, width=1.5, hand=1.7),
    head=dict(kind='bear', iris='#ffcf40'),
    groups=dict(head=1.6, body=2.6),
)


def imp(m, c, face, ph, k):
    """A small red imp sitting on the saddle: round body, big head with horns, yellow eyes and a fanged grin, waving arm."""
    from core import V, sphere, ellipsoid, cone, pat
    bob = 0.6 * np.sin(2 * np.pi * (ph * 2 + k * 0.37))
    c = c + V(0, bob, 0)
    m.add(ellipsoid(c, (2.4, 2.6, 2.2)), 'imp', 'imp%d' % k)
    hd = c + V(0, 4.0, 0.6)
    m.add(sphere(hd, 2.8), 'imp', 'imp%d' % k)
    m.group('imp%d' % k, 0.8)
    for s in (-1, 1):
        m.add(cone(hd + V(1.8 * s, 1.8, -0.2), hd + V(3.4 * s, 4.6, -0.8), 0.8, 0.15), 'horn', None)
        m.add(cone(hd + V(2.4 * s, 0.4, 0), hd + V(4.4 * s, 1.4, -0.6), 0.7, 0.1), 'imp', None)
    wave = 0.9 * np.sin(2 * np.pi * (ph * 2 + k * 0.5))
    m.add(cone(c + V(1.8, 1.0, 0.6), c + V(3.6, 4.2 + wave, 1.6), 0.7, 0.6), 'imp', None)
    m.add(cone(c + V(-1.8, 0.4, 0.6), c + V(-2.4, -2.0, 2.4), 0.7, 0.6), 'imp', None)
    m.add(cone(c + V(-0.5, -1.4, -1.6), c + V(-1.6, -3.4, -4.6) + V(0, wave, 0), 0.5, 0.15), 'imp', None)
    eye = pat(['ky', 'yk'], {'k': '#1a0404', 'y': '#ffe040'})
    for s in (-1, 1):
        m.stamps.append((hd + V(1.1 * s, 0.4, 2.6), eye, face))
    m.lines.append((hd + V(-1.2, -1.0, 2.6), hd + V(1.4, -1.2, 2.6), '#2a0404', 1.0))
    m.dots.append((hd + V(0.6, -1.5, 2.7), '#ffffff', 0.0, 1.5))


def fairy(m, c, ph):
    """Tiny fairy: violet dress, pink hair bun, two pairs of glowing wings flapping, star wand with a white spark."""
    from core import V, sphere, ellipsoid, cone, rot_y, pat
    c = c + V(0, 1.6 * np.sin(2 * np.pi * ph), 0)
    m.add(cone(c + V(0, 2.4, 0), c + V(0, -2.4, 0), 0.9, 2.0), 'dress', 'fairy')
    hd = c + V(0, 4.4, 0.3)
    m.add(sphere(hd, 1.9), 'skin', 'fairy')
    m.add(ellipsoid(hd + V(0, 0.8, -0.5), (2.1, 1.7, 1.9)), 'fhair', 'fairy')
    m.add(sphere(hd + V(0, 2.4, -1.2), 1.1), 'fhair', 'fairy')
    m.group('fairy', 0.5)
    m.stamps.append((hd + V(0.6, -0.1, 1.8), pat(['k', 'b'], {'k': '#1a0c2a', 'b': '#7a4ab4'}), V(0, 0, 1)))
    flap = 0.5 + 0.6 * np.sin(2 * np.pi * ph * 4)
    for s in (-1, 1):
        for up, (rx, ry) in ((1, (3.6, 2.0)), (-1, (2.6, 1.4))):
            m.add(ellipsoid(c + V(2.6 * s, 1.6 + 1.6 * up, -1.6), (rx, ry, 0.35), rot=rot_y(flap * s)), 'wing', None)
    tip = c + V(-3.4, 3.4, 2.4)
    m.add(cone(c + V(-1.4, 0.8, 0.8), tip, 0.4, 0.3), 'gold', None)
    m.add(sphere(tip, 0.9), 'wand', None)
    for i in range(3):
        a = 2 * np.pi * (ph * 2 + i / 3)
        m.dots.append((tip + V(2.2 * np.cos(a), 2.2 * np.sin(a), 1.0), '#ffd8f0', 1.0, 9))


def extra(m, p, A):
    """Two imps on the saddle and the fairy hovering ahead of the bear's head."""
    from core import V
    ph = p['ph']; sad = A['chest'] + V(0, 8.0 * 1.25 + 2.0, -6.0 * 1.25)
    imp(m, sad + V(-10.4, -1.6, 5.0), V(0, 0, 1), ph, 0)
    imp(m, sad + V(7.8, 0.6, 1.6), V(0, 0, 1), ph, 1)
    fairy(m, A['head'] + V(-10.0, 9.0, 8.0), ph)
