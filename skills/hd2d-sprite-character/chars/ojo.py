"""Ojo Penetrante: falcon vizier in a deep violet hooded robe, blue chest plate with an eye, red staff with a green gem, spectral green orb."""
RAMPS = {
    'plum': ['#0e0820', '#1a1036', '#2a1a52', '#3e2672', '#563494', '#7248b4', '#9466d2', '#b890ea'],
    'plum_in': ['#0a0614', '#140c26', '#22143c'],
    'gild': ['#2a160e', '#4f3016', '#82541c', '#b8862e', '#e0ac44', '#f8d270', '#fff2b0', '#fffbe8'],
    'azure': ['#060c26', '#0e1c48', '#16306e', '#1e4896', '#2c66bc', '#4a8ad8', '#7ab0ee', '#b6d8ff'],
    'tawny': ['#1e0e08', '#3a1e10', '#5e3418', '#865024', '#ac6e34', '#cc9250', '#e8b878'],
    'cream': ['#6a4a30', '#a88660', '#d8bc94', '#f2e2c4', '#fff8ea'],
    'beakc': ['#3a2408', '#7a5010', '#c08a18', '#f0c030', '#ffe680', '#fff8c8'],
    'crimson': ['#1e0608', '#3e0c10', '#6a1418', '#962020', '#c03428', '#e05a3c'],
    'jade': ['#0c3a18', '#1a7a2a', '#36c040', '#5ee04e', '#7dff6a', '#b8ff9a'],
    'teal': ['#06161c', '#0c2a32', '#16444c', '#226068', '#347e84'],
}
MATS = dict(
    robe=('plum', {'wrap': 0.4, 'gamma': 1.1, 'bias': -0.2}), robe_in=('plum_in', {'wrap': 0.5}),
    trim=('gild', {'kind': 'metal', 'bias': 0.3}), gold=('gild', {'kind': 'metal', 'bias': 0.4}),
    plate=('azure', {'kind': 'metal', 'bias': 0.4}), sash=('teal', {'wrap': 0.4, 'bias': 0.2}),
    feather=('tawny', {'wrap': 0.5, 'bias': 0.5}), feather_l=('cream', {'wrap': 0.5, 'bias': 0.3}),
    beak=('beakc', {'kind': 'metal', 'bias': 0.5}), beak_d=('beakc', {'kind': 'metal', 'bias': -1.4}), wood=('crimson', {'wrap': 0.4, 'bias': 0.3}),
    gem_e=('jade', {'kind': 'emis', 'glow': 1.0}),
)
EYE = {(0, -2): '#e0ac44', (-2, -1): '#e0ac44', (-1, -1): '#fff2b0', (0, -1): '#fff2b0', (1, -1): '#fff2b0', (2, -1): '#e0ac44',
       (-3, 0): '#e0ac44', (-2, 0): '#ffffff', (-1, 0): '#36c040', (0, 0): '#0c3a18', (1, 0): '#36c040', (2, 0): '#ffffff', (3, 0): '#e0ac44',
       (-2, 1): '#e0ac44', (-1, 1): '#fff2b0', (0, 1): '#fff2b0', (1, 1): '#fff2b0', (2, 1): '#e0ac44', (0, 2): '#e0ac44'}
SPEC = dict(
    frames=8, scale=1.6, stance='spellcast', hand_mat='beak', hand_bias=-0.2,
    body=dict(kind='robe', emblem=EYE, hand=1.35, height=1.04, claw='beak_d'),
    head=dict(kind='falcon', iris='#7dff6a', circlet='gem_e'),
    weapon=dict(kind='staff', up=26.0, down=24.0),
    offhand=dict(kind='orb', r=2.0, spark='#c8ffb8'),
    groups=dict(body=1.2),
)
