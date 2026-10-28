"""Gamelyn: silver plate knight with gold trim, violet cape under the pauldrons, ginger ponytail, low guard, light-blue glowing longsword."""
RAMPS = {
    'plate': ['#080b1e', '#151d36', '#25314f', '#3b4b6e', '#5b7096', '#8aa3c8', '#bfd3ec', '#eef6ff', '#ffffff'],
    'gild': ['#2a160e', '#4f3016', '#82541c', '#b8862e', '#e0ac44', '#f8d270', '#fff2b0', '#fffbe8'],
    'ginger': ['#3a120c', '#5e2012', '#8a3618', '#b4501e', '#d9772f', '#f3a457', '#ffd08a'],
    'skyblade': ['#0a1c48', '#0e3478', '#1250a8', '#1a6cd0', '#2a8ae8', '#44a6f6', '#64bcff', '#88d0ff', '#a8e0ff'],
    'violet': ['#120b24', '#1d1335', '#2c1b4f', '#43286c', '#5c3889', '#7e52ac', '#a77ad0', '#c9a4ec'],
    'lining': ['#1a0c1e', '#2e1430', '#4c1d48', '#6c2a5e'],
    'hide': ['#1c1014', '#2e1c22', '#4f3028', '#6a4232', '#8c5a3e', '#b07a54'],
    'glint': ['#d9772f', '#f3a457', '#ffd08a', '#fff0c8'],
    'peach': ['#5a2824', '#9a4a3a', '#d27c60', '#f0ae8a', '#ffd8bc', '#fff0e0'],
    'ruby': ['#3a0612', '#7a1026', '#c4243e', '#ff5a6a', '#ffc8c8'],
}
MATS = dict(
    steel=('plate', {'kind': 'metal'}), dsteel=('plate', {'kind': 'metal', 'bias': -1.6}),
    gold=('gild', {'kind': 'metal', 'bias': 0.4}), dgold=('gild', {'kind': 'metal', 'bias': -0.8}),
    cape=('violet', {'wrap': 0.5, 'gamma': 0.9, 'bias': 0.7}), cape_in=('lining', {'wrap': 0.6}),
    trim=('gild', {'kind': 'metal', 'bias': 0.2}), leather=('hide', {'wrap': 0.4, 'bias': -0.3}),
    skin=('peach', {'kind': 'skin', 'bias': 0.6}), hair=('ginger', {'wrap': 0.4, 'gamma': 1.0, 'bias': 0.0}),
    hair_h=('glint', {'wrap': 0.8, 'bias': 0.6}), hair_s=('ginger', {'wrap': 0.5, 'bias': -1.1}),
    blade=('skyblade', {'kind': 'metal', 'bias': 0.6, 'glow': 0.55}), blade_f=('skyblade', {'kind': 'metal', 'bias': -1.2, 'glow': 0.4}),
    blade_e=('skyblade', {'kind': 'metal', 'bias': 2.0, 'glow': 0.8}),
    gem=('ruby', {'kind': 'metal', 'bias': 0.6}),
)
STAR = {(0, -3): '#fff2b0', (0, -2): '#fffbe8', (0, -1): '#fffbe8', (-3, 0): '#e0ac44', (-2, 0): '#f8d270', (-1, 0): '#fffbe8',
        (0, 0): '#ffffff', (1, 0): '#fffbe8', (2, 0): '#f8d270', (3, 0): '#e0ac44', (0, 1): '#f8d270', (-1, 1): '#b8862e',
        (1, 1): '#b8862e', (0, 2): '#e0ac44', (0, 3): '#b8862e', (-1, -1): '#f8d270', (1, -1): '#f8d270'}
SPEC = dict(
    frames=8, scale=1.6, stance='low_guard', hand_bias=0.5,
    body=dict(kind='plate', emblem=STAR, hand=1.45, knuckle='gold'),
    head=dict(kind='anime', ponytail=True, iris=('#173a8c', '#2f7ee6', '#8fd8ff')),
    cape=dict(length=1.0),
    weapon=dict(kind='sword', hands=2, length=26.0, rune='#7fd0ff', rune_glow=1.0, edge='#9ad6ff'),
)
