"""Ojo Penetrante (Overseer Orawk): birdfolk vizier with a grey-green feathered face and white beard, a brow eye, a tall Dracula collar,
spiked gunmetal pauldrons with gold rims, a blue scaled tabard framed in gold with the eye, gold belt with a round green gem, violet robe,
red staff with a gold finial and a ruby, and a spectral green eye coiling up from the open hand."""
import numpy as np
from core import V, box, cone, ellipsoid, octa, pat, rot_z, sphere, sub, inter
from parts import unit
RAMPS = {
    'plum': ['#0e0820', '#1a1036', '#2a1a52', '#3e2672', '#563494', '#7248b4', '#9466d2', '#b890ea'],
    'plum_in': ['#0a0614', '#140c26', '#22143c'],
    'gild': ['#2a160e', '#4f3016', '#82541c', '#b8862e', '#e0ac44', '#f8d270', '#fff2b0', '#fffbe8'],
    'gunmetal': ['#0c0e14', '#1a1e28', '#2a303c', '#3e4652', '#56606c', '#727d8a', '#98a3ae', '#c6ced6'],
    'azure': ['#060c26', '#0e1c48', '#16306e', '#1e4896', '#2c66bc', '#4a8ad8', '#7ab0ee', '#b6d8ff'],
    'sage': ['#101a14', '#1e2e24', '#304636', '#48604a', '#64806a', '#86a08a', '#aec4ae'],
    'snow': ['#3a3c44', '#6a6e78', '#9ea2aa', '#cdd0d4', '#ecedee', '#ffffff'],
    'crimson': ['#1e0608', '#3e0c10', '#6a1418', '#962020', '#c03428', '#e05a3c'],
    'ruby': ['#3a0612', '#7a1026', '#c4243e', '#ff5a6a', '#ffc8c8'],
    'jade': ['#0c3a18', '#1a7a2a', '#36c040', '#5ee04e', '#7dff6a', '#b8ff9a'],
    'mint': ['#062a16', '#0e5028', '#1a8040', '#30ae5c', '#5cd480', '#a8f0bc'],
    'skirt': ['#0a0a10', '#14141e', '#20202e', '#30303e', '#444456'],
}
MATS = dict(
    robe=('plum', {'wrap': 0.4, 'gamma': 1.1, 'bias': -0.2}), robe_in=('plum_in', {'wrap': 0.5}),
    trim=('gild', {'kind': 'metal', 'bias': 0.3}), gold=('gild', {'kind': 'metal', 'bias': 0.5}),
    pauldron=('gunmetal', {'kind': 'metal', 'bias': 0.3}), plate=('azure', {'kind': 'metal', 'bias': 0.4}),
    scale_d=('azure', {'kind': 'metal', 'bias': -1.2}), sash=('gild', {'kind': 'metal', 'bias': 0.4}),
    feather=('sage', {'wrap': 0.5, 'bias': 0.4}), feather_l=('snow', {'wrap': 0.6, 'bias': 0.4}), beard=('snow', {'wrap': 0.7, 'bias': 0.5}),
    beak=('sage', {'wrap': 0.55, 'bias': 0.6}), beak_d=('sage', {'wrap': 0.55, 'bias': -0.8}), wood=('crimson', {'wrap': 0.4, 'bias': 0.3}),
    gem_e=('jade', {'kind': 'emis', 'glow': 1.0}), ruby_e=('ruby', {'kind': 'emis', 'glow': 0.7}), belt_gem=('mint', {'kind': 'metal', 'bias': 0.6, 'glow': 0.35}),
    skirt=('skirt', {'wrap': 0.4, 'bias': 0.2}),
)
EYE = {(0, -2): '#e0ac44', (-2, -1): '#e0ac44', (-1, -1): '#fff2b0', (0, -1): '#fff2b0', (1, -1): '#fff2b0', (2, -1): '#e0ac44',
       (-3, 0): '#e0ac44', (-2, 0): '#fff2b0', (-1, 0): '#b8862e', (0, 0): '#2a160e', (1, 0): '#b8862e', (2, 0): '#fff2b0', (3, 0): '#e0ac44',
       (-2, 1): '#e0ac44', (-1, 1): '#fff2b0', (0, 1): '#fff2b0', (1, 1): '#fff2b0', (2, 1): '#e0ac44', (0, 2): '#e0ac44'}
BROW = pat(['.yyy.', 'yw.wy', '.yyy.'], {'y': '#f8d270', 'w': '#fffbe8'}, 2, 1)
BROW[(0, 0)] = '#2a160e'
SPEC = dict(
    frames=8, scale=1.6, stance='spellcast', hand_mat='beak', hand_bias=0.2,
    body=dict(kind='robe', hand=1.35, height=1.04, claw='beak_d'),
    head=dict(kind='falcon', iris='#7dff6a', hood=False),
    weapon=dict(kind='staff', up=26.0, down=24.0),
    offhand=dict(kind='orb', r=2.6, spark='#c8ffb8'),
    groups=dict(body=1.2),
)


def _rim(c, half, rot, w):
    """Texture: trim material on the outer band of a rotated box face."""
    def t(P, mt):
        q = (P - c) @ rot if rot is not None else P - c
        e = np.maximum(np.abs(q[:, 0]) / half[0], np.abs(q[:, 2]) / half[2])
        return np.where(e > 1 - w, 'trim', mt)
    return t


def extra(m, p, A):
    """Card details over the robe: Dracula collar, spiked pauldrons, scaled tabard in a gold frame, belt gem, bracers, beard, brow eye,
    gold staff finial with a ruby, and the spectral eye over the open hand."""
    H, chest, pel, neck = A['head'], A['chest'], A['pel'], A['neck']
    shell = sub(cone(neck + V(0, -1.0, -1.0), neck + V(0, 15.0, -3.4), 5.4, 10.6), cone(neck + V(0, -0.4, -0.2), neck + V(0, 16.0, -2.4), 4.8, 10.0))
    ctop = neck[1] + 12.0
    collar = inter(inter(shell, lambda P: P[:, 2] - (neck[2] + 1.6)),
                   lambda P: P[:, 1] - (ctop + 3.2 * np.clip(np.abs(P[:, 0]) / 9.0, 0, 1) ** 2))
    m.add(collar, 'robe', None, lambda P, mt: np.where(P[:, 1] > ctop - 1.0 + 3.2 * np.clip(np.abs(P[:, 0]) / 9.0, 0, 1) ** 2, 'trim',
                                                     np.where(P[:, 2] > neck[2] - 1.4, 'robe_in', mt)))
    for sd in (-1, 1):
        sh = A['sh'][sd]; r = rot_z(-0.5 * sd)
        for k, (off, half) in enumerate(((V(3.0 * sd, 3.6, 0.6), V(6.6, 1.8, 5.4)), (V(5.0 * sd, 0.2, 1.0), V(5.0, 1.4, 4.8)))):
            c = sh + off; hf = half
            m.add(box(c, hf, rot=r, r=0.4), 'pauldron', None, _rim(c, hf, r, 0.13))
        tip = sh + V(7.8 * sd, 5.6, 0.2)
        m.add(cone(tip, tip + V(3.4 * sd, 8.4, -0.8), 1.8, 0.15), 'pauldron', None)
        m.add(cone(tip + V(-1.6 * sd, -0.6, 2.8), tip + V(0.6 * sd, 4.8, 3.4), 1.2, 0.12), 'pauldron', None)
        m.add(cone(tip + V(1.0 * sd, -3.6, 4.4), tip + V(2.8 * sd, -0.2, 4.8), 0.9, 0.12), 'trim', None)
        m.add(cone(sh + V(-3.4 * sd, -4.0, 4.6), pel + V(-3.0 * sd, 5.0, 4.8), 0.75, 0.75), 'trim', None)
    tab = chest + V(0, -2.2, 4.4)
    m.add(box(tab, V(3.2, 7.4, 1.2), r=0.6), 'plate', None,
          lambda P, mt: np.where(np.abs(P[:, 0] - tab[0]) > 2.5, 'trim', np.where(np.mod(P[:, 1] - tab[1], 1.6) < 0.45, 'scale_d', mt)))
    m.stamps.append((chest + V(0, 1.2, 6.0), EYE, V(0, 0, 1)))
    belt = pel + V(0, 3.6, 0.6)
    m.add(box(belt + V(0, 0, 4.6), V(6.2, 1.8, 1.0), r=0.5), 'gold', None)
    m.add(cone(belt + V(0, -1.0, 5.6), belt + V(0, -5.6, 5.0), 2.6, 0.6), 'gold', None)
    m.add(sphere(belt + V(0, -1.4, 6.6), 1.9), 'belt_gem', None)
    m.dots.append((belt + V(-0.6, -0.6, 8.4), '#e8fff6', 0.6, 4))
    m.add(cone(pel + V(0, 1.0, 3.6), V(0, 2.0, 5.6 + p['cape'][2] * 0.2), 3.4, 4.6), 'skirt', None,
          lambda P, mt: np.where(np.abs(P[:, 0]) > 3.4, 'trim', mt))
    m.add(ellipsoid(H + V(0, -3.0, 3.6), (3.6, 3.6, 2.6)), 'beard', 'head')
    m.add(cone(H + V(0, -4.4, 3.6), H + V(0, -8.6, 3.2), 2.6, 0.5), 'beard', None)
    m.stamps.append((H + V(0, 3.6, 5.6), BROW, V(0, 0, 1)))
    for sd in (-1, 1):
        m.add(cone(H + V(3.6 * sd, 3.4, 1.0), H + V(7.6 * sd, 6.6, -3.0), 1.3, 0.2), 'feather', None)
    sd_ = unit(p['sword']); top = p['hilt'] + V(0, A['b'] * 0.6, 0) + sd_ * 26.0
    m.add(octa(top + sd_ * 2.8 + V(0, 0, 0.9), 1.5, sy=1.7), 'ruby_e', None)
    for s in (-1, 1):
        m.add(cone(top + V(0.6 * s, 0.4, 0.4), top + V(2.6 * s, 5.6, 0.6), 0.7, 0.2), 'gold', None)
    if p.get('off') is None:
        return
    hand = p['off'] + V(0, A['b'] * 0.6, 0); c = hand + V(0, 3.4, 1.0)
    m.stamps.append((c + V(0, 0, 2.8), pat(['.ww.', 'wkkw', 'wkkw', '.ww.'], {'w': '#f2fff0', 'k': '#04200a'}, 2, 2), None))
    ph = p.get('ph', 0.0)
    for i in range(22):
        f = i / 21; a = 6.283 * (1.6 * f + ph)
        q = hand + V(3.6 * (1 - f) * np.cos(a), -4.0 + 6.6 * f, 1.0 + 3.6 * (1 - f) * np.sin(a))
        m.dots.append((q, '#7dff6a' if i % 3 else '#d8ffc8', 1.0, 9))
