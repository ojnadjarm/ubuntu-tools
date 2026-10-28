"""Ojo Penetrante, sorceress of the Piercing Eye: long silver-lilac hair, gold circlet with a glowing green eye-gem, deep violet
robe with a blue chest plate bearing the eye, red staff with a green gem beside the hip and a spectral green orb over her open hand."""
RAMPS = {
    'plum': ['#0e0820', '#1a1036', '#2a1a52', '#3e2672', '#563494', '#7248b4', '#9466d2', '#b890ea'],
    'plum_in': ['#0a0614', '#140c26', '#22143c'],
    'gild': ['#2a160e', '#4f3016', '#82541c', '#b8862e', '#e0ac44', '#f8d270', '#fff2b0', '#fffbe8'],
    'azure': ['#060c26', '#0e1c48', '#16306e', '#1e4896', '#2c66bc', '#4a8ad8', '#7ab0ee', '#b6d8ff'],
    'porcelain': ['#5a2c34', '#94545a', '#cc8a84', '#ecb8a8', '#fcdccc', '#fff2ea'],
    'silver': ['#2a2238', '#4a4062', '#726890', '#9c94ba', '#c4bedc', '#e4e0f4', '#fbf8ff'],
    'sheen': ['#c4bedc', '#e4e0f4', '#ffffff'],
    'crimson': ['#1e0608', '#3e0c10', '#6a1418', '#962020', '#c03428', '#e05a3c'],
    'jade': ['#0c3a18', '#1a7a2a', '#36c040', '#5ee04e', '#7dff6a', '#b8ff9a'],
    'teal': ['#06161c', '#0c2a32', '#16444c', '#226068', '#347e84'],
}
MATS = dict(
    robe=('plum', {'wrap': 0.4, 'gamma': 1.1, 'bias': -0.2}), robe_in=('plum_in', {'wrap': 0.5}),
    trim=('gild', {'kind': 'metal', 'bias': 0.3}), gold=('gild', {'kind': 'metal', 'bias': 0.4}),
    plate=('azure', {'kind': 'metal', 'bias': 0.4}), sash=('teal', {'wrap': 0.4, 'bias': 0.2}),
    skin=('porcelain', {'kind': 'skin', 'bias': 0.5}), hair=('silver', {'wrap': 0.5, 'gamma': 1.0, 'bias': 0.2}),
    hair_h=('sheen', {'wrap': 0.8, 'bias': 0.5}), hair_s=('silver', {'wrap': 0.5, 'bias': -1.2}),
    wood=('crimson', {'wrap': 0.4, 'bias': 0.3}), gem_e=('jade', {'kind': 'emis', 'glow': 1.0}),
)
EYE = {(0, -2): '#e0ac44', (-2, -1): '#e0ac44', (-1, -1): '#fff2b0', (0, -1): '#fff2b0', (1, -1): '#fff2b0', (2, -1): '#e0ac44',
       (-3, 0): '#e0ac44', (-2, 0): '#ffffff', (-1, 0): '#36c040', (0, 0): '#0c3a18', (1, 0): '#36c040', (2, 0): '#ffffff', (3, 0): '#e0ac44',
       (-2, 1): '#e0ac44', (-1, 1): '#fff2b0', (0, 1): '#fff2b0', (1, 1): '#fff2b0', (2, 1): '#e0ac44', (0, 2): '#e0ac44'}
SPEC = dict(
    frames=8, scale=1.6, stance='spellcast', hand_mat='skin', hand_bias=0.3,
    body=dict(kind='robe', emblem=EYE, hand=1.25, height=1.0),
    head=dict(kind='anime', iris=('#0c4a1c', '#36c040', '#b8ff9a'), hair_lines=('#4a4062', '#ffffff'), tail_line='#fbf8ff',
              long=17.0, locks=10.0, circlet='gem_e', spikes=()),
    weapon=dict(kind='staff', up=26.0, down=24.0),
    offhand=dict(kind='orb', r=2.0, spark='#c8ffb8'),
    groups=dict(body=1.2),
)
