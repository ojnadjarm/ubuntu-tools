"""Gakata: white lion gladiator, cream mane, gunmetal spiked pauldron, red-orange tattered kilt, chrome round shield, raised shamshir."""
RAMPS = {
    'lionfur': ['#1e1a22', '#3a3440', '#5e5662', '#8a8290', '#b4adb6', '#d8d2d6', '#f2eee8', '#ffffff'],
    'muzzle': ['#4a3a40', '#8a7a7c', '#c8bcb8', '#ece4dc', '#fffaf2'],
    'manec': ['#3a3034', '#6a5c5a', '#a09088', '#cfc4b6', '#ece6da', '#fffcf4'],
    'gunmetal': ['#06070e', '#10131e', '#1c2230', '#2c3446', '#465166', '#6c7890', '#a2aec4', '#dce4f0', '#ffffff'],
    'gild': ['#2a160e', '#4f3016', '#82541c', '#b8862e', '#e0ac44', '#f8d270', '#fff2b0', '#fffbe8'],
    'ember': ['#2a0a08', '#561410', '#8e2216', '#c4381a', '#e8642a', '#ff9a48', '#ffc884'],
    'hide': ['#1c1014', '#2e1c22', '#4f3028', '#6a4232', '#8c5a3e', '#b07a54'],
    'chrome': ['#0a0e1c', '#1c2436', '#34405a', '#5a6a8a', '#8ea2c4', '#c4d4ec', '#f2f8ff', '#ffffff'],
    'ruby': ['#3a0612', '#7a1026', '#c4243e', '#ff5a6a', '#ffc8c8'],
    'rose': ['#2a0e14', '#5a1e2a', '#8e3a48'],
    'ivory': ['#6a5a48', '#b8a888', '#f2ead4', '#ffffff'],
    'scim': ['#0a1424', '#1a2a44', '#2e4668', '#4c6c94', '#7a9cc2', '#aecae6', '#e0f0ff', '#ffffff'],
}
MATS = dict(
    fur=('lionfur', {'wrap': 0.5, 'gamma': 1.0, 'bias': 0.4}), fur_l=('muzzle', {'wrap': 0.5, 'bias': 0.3}),
    mane=('manec', {'wrap': 0.6, 'gamma': 0.9, 'bias': 0.3}), mane_s=('manec', {'wrap': 0.6, 'bias': -0.9}),
    steel=('gunmetal', {'kind': 'metal', 'bias': 0.2}), dsteel=('gunmetal', {'kind': 'metal', 'bias': -1.4}),
    gold=('gild', {'kind': 'metal', 'bias': 0.4}), dgold=('gild', {'kind': 'metal', 'bias': -0.8}),
    kilt=('ember', {'wrap': 0.5, 'gamma': 0.9, 'bias': 0.5}), kilt_s=('ember', {'wrap': 0.5, 'bias': -1.0}),
    leather=('hide', {'wrap': 0.4, 'bias': -0.2}), gem=('ruby', {'kind': 'metal', 'bias': 0.6}),
    nose=('rose', {'wrap': 0.3}), mouth=('rose', {'wrap': 0.2, 'bias': -0.8}), claw=('ivory', {'kind': 'metal'}),
    blade=('scim', {'kind': 'metal', 'bias': 0.8}), blade_f=('scim', {'kind': 'metal', 'bias': -1.0}),
    blade_e=('scim', {'kind': 'metal', 'bias': 1.8}),
)
MATS['shield'] = MATS['blade']
SPEC = dict(
    frames=8, scale=1.6, stance='high_guard', hand_mat='fur',
    body=dict(kind='gladiator', hand=1.4, width=1.05, pauldron=1),
    head=dict(kind='lion', iris='#f2b030'),
    weapon=dict(kind='scimitar', length=19.0, curve=1.0, edge_side=-1),
    offhand=dict(kind='shield', r=7.4),
    groups=dict(body=1.4),
)

def extra(m, p, A):
    """Lion tail with a dark tuft, swinging behind the kilt."""
    from core import V, cone, sphere
    pel = A['pel']; t = p['tail']
    a = pel + V(0, 0, -5.0); b = pel + V(-3.0, -6.0, -10.0) + t * 2; c = b + V(-4.0, 4.0, -2.0) + t * 3
    m.add(cone(a, b, 1.1, 0.9), 'fur', None); m.add(cone(b, c, 0.9, 0.8), 'fur', None)
    m.add(sphere(c, 1.8), 'mane_s', None)
