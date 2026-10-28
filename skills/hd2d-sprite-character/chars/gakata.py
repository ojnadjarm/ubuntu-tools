"""Gakata, blade warrior: gunmetal Knight's Cuirass with gold trim and a bolt emblem, crimson tabard, dark spiky hair,
Lightning Staff raised high crackling with arcs, sparks over the off fist and a sheathed blade on the off hip."""
import numpy as np
from core import V, cone, octa, sphere
from gear import lightning

RAMPS = {
    'gunmetal': ['#06070e', '#10131e', '#1c2230', '#2c3446', '#465166', '#6c7890', '#a2aec4', '#dce4f0', '#ffffff'],
    'gild': ['#2a160e', '#4f3016', '#82541c', '#b8862e', '#e0ac44', '#f8d270', '#fff2b0', '#fffbe8'],
    'crimson': ['#1a0408', '#340a10', '#561218', '#7e1a1e', '#a62824', '#cc4030', '#e86a48'],
    'lining': ['#12060a', '#220c12', '#36141a'],
    'hide': ['#1c1014', '#2e1c22', '#4f3028', '#6a4232', '#8c5a3e', '#b07a54'],
    'tan': ['#3e1e16', '#6e3a28', '#a4624a', '#c98a6a', '#e6b08e', '#f8d4b8'],
    'ink': ['#06060e', '#0e1020', '#181c34', '#24304e', '#36486c', '#4c6690'],
    'storm': ['#2a3a6e', '#4c6ab0', '#7aa0e8', '#b6d0ff'],
    'ebony': ['#0a0810', '#18121e', '#2a2030', '#3e3044', '#56445a'],
    'volt': ['#0c1450', '#1a2c9a', '#3a5ee0', '#6a9cff', '#a8ccff', '#e8f2ff'],
    'ruby': ['#3a0612', '#7a1026', '#c4243e', '#ff5a6a', '#ffc8c8'],
}
MATS = dict(
    steel=('gunmetal', {'kind': 'metal', 'bias': 0.1}), dsteel=('gunmetal', {'kind': 'metal', 'bias': -1.4}),
    gold=('gild', {'kind': 'metal', 'bias': 0.4}), dgold=('gild', {'kind': 'metal', 'bias': -0.8}),
    cape=('crimson', {'wrap': 0.5, 'gamma': 0.9, 'bias': 0.6}), cape_in=('lining', {'wrap': 0.6}),
    trim=('gild', {'kind': 'metal', 'bias': 0.2}), leather=('hide', {'wrap': 0.4, 'bias': -0.3}),
    skin=('tan', {'kind': 'skin', 'bias': 0.4}), hair=('ink', {'wrap': 0.4, 'gamma': 1.0, 'bias': 0.2}),
    hair_h=('storm', {'wrap': 0.8, 'bias': 0.4}), hair_s=('ink', {'wrap': 0.5, 'bias': -1.2}),
    wood=('ebony', {'wrap': 0.4, 'bias': 0.3}), gem_e=('volt', {'kind': 'emis', 'glow': 1.0}),
    gem=('ruby', {'kind': 'metal', 'bias': 0.6}),
)
BOLT = {(1, -3): '#f8d270', (0, -2): '#fff2b0', (1, -2): '#e0ac44', (-1, -1): '#f8d270', (0, -1): '#fffbe8', (1, -1): '#f8d270',
        (0, 0): '#ffffff', (1, 0): '#fff2b0', (-1, 1): '#e0ac44', (0, 1): '#f8d270', (-1, 2): '#b8862e'}
ARCS = ('#f4f6ff', '#6a9cff')
SPEC = dict(
    frames=8, scale=1.6, stance='high_guard', hand_bias=0.4, pose=lambda ph, p: p.update(ph=ph, off_grip='claw'),
    body=dict(kind='plate', emblem=BOLT, hand=1.45, knuckle='gold'),
    head=dict(kind='anime', iris=('#1a1446', '#4a5ae0', '#a8c8ff'), hair_lines=('#06060e', '#b6d0ff'),
              spikes=((V(-1.4, 5.6, 1.6), V(-4.6, 10.4, 2.2)), (V(1.0, 6.0, 0.6), V(3.2, 10.8, -0.4)),
                      (V(-3.6, 4.8, 0.6), V(-7.6, 7.4, 0.6)), (V(2.8, 5.0, -1.4), V(6.4, 8.4, -3.0)))),
    weapon=dict(kind='staff', up=17.0, down=21.0, bolt=ARCS, arcs=5, reach=10.0),
)


def extra(m, p, A):
    """Sheathed blade on the off hip, hilt forward (guard, pommel gem), scabbard sweeping back and sparks crackling over the off hand."""
    d = V(-0.25, -0.6, -0.76) / np.linalg.norm(V(-0.25, -0.6, -0.76))
    top = A['pel'] + V(-6.8, 1.6, 3.4)
    m.add(cone(top, top + d * 17.0, 1.2, 0.9), 'leather', None)
    m.add(cone(top + d * 15.2, top + d * 17.6, 1.1, 0.5), 'gold', None)
    m.add(cone(top - d * 0.2, top - d * 4.8, 0.75, 0.75), 'leather', None)
    m.add(cone(top + V(-2.4, -1.2, 0.2), top + V(2.4, 1.2, -0.2), 0.65, 0.65), 'gold', None)
    m.add(octa(top - d * 5.4, 1.1), 'gold', None)
    m.add(sphere(top - d * 5.4 + V(0, 0, 0.7), 0.6), 'gem', None)
    if p.get('off') is not None:
        lightning(m, p['off'] + V(0, A['b'] * 0.6 + 2.6, 1.4), ARCS, p['ph'] + 0.37, 3, 4.5)
