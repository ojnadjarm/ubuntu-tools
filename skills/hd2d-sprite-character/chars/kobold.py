"""Kobold: small rust-scaled reptile raider with a pale ribbed belly, swept horns, finned frills, slit yellow eyes, ragged loincloth, crude spear."""
RAMPS = {
    'rustscale': ['#140806', '#2a100a', '#45190e', '#642812', '#86391a', '#a85224', '#c87436', '#e49a52'],
    'paleb': ['#3a2216', '#6a4228', '#9a6a3e', '#c49a62', '#e6c690', '#f8e6bc'],
    'hornb': ['#1a1210', '#3a2c22', '#6a5640', '#a08a68', '#d6c8a4', '#f6eed6'],
    'frillg': ['#1a0806', '#3a120c', '#5e1e14', '#82301c', '#a8482a'],
    'ragc': ['#120e0c', '#241c16', '#3c3024', '#5a4834', '#7a6446', '#9a825a'],
    'hide': ['#1c1014', '#2e1c22', '#4f3028', '#6a4232', '#8c5a3e', '#b07a54'],
    'rusty': ['#140c0a', '#2e1a12', '#4c2c1a', '#6e4a2e', '#8c6a4a', '#a89078', '#c8bcae', '#e8e4dc'],
    'ivory': ['#4a3a2a', '#8a7a5a', '#cfc2a0', '#f2ead4', '#ffffff'],
    'coal': ['#06060a', '#14141c', '#2a1a1e', '#4a2028'],
    'tonguep': ['#3a0a12', '#7a1a26', '#c4424a', '#f08080'],
}
MATS = dict(
    scale=('rustscale', {'wrap': 0.45, 'gamma': 1.1, 'bias': 0.3}), scale_s=('rustscale', {'wrap': 0.45, 'bias': -1.0}),
    belly=('paleb', {'wrap': 0.5, 'bias': 0.2}), belly_s=('paleb', {'wrap': 0.5, 'bias': -1.0}),
    spine=('hornb', {'kind': 'metal', 'bias': -0.2}), horn=('hornb', {'kind': 'metal', 'bias': 0.2}),
    horn_d=('hornb', {'kind': 'metal', 'bias': -1.2}), frill=('frillg', {'wrap': 0.6, 'bias': 0.4}), frill_d=('frillg', {'wrap': 0.6, 'bias': -1.0}),
    rag=('ragc', {'wrap': 0.5, 'bias': 0.2}), rag_s=('ragc', {'wrap': 0.5, 'bias': -1.0}),
    leather=('hide', {'wrap': 0.4, 'bias': -0.2}), rust=('rusty', {'kind': 'metal', 'bias': -0.4}),
    wood=('hide', {'wrap': 0.4, 'bias': 0.2}), bone=('ivory', {'kind': 'metal', 'bias': 0.3}),
    claw=('ivory', {'kind': 'metal'}), mouth=('coal', {'wrap': 0.2}), tongue=('tonguep', {'wrap': 0.5, 'bias': 0.3}),
    blade=('rusty', {'kind': 'metal', 'bias': 0.2}), blade_f=('rusty', {'kind': 'metal', 'bias': -1.6}),
    blade_e=('rusty', {'kind': 'metal', 'bias': 2.6}),
)
SPEC = dict(
    frames=8, scale=1.6, stance='skulk', hand_mat='scale', hand_bias=0.4,
    body=dict(kind='kobold', height=0.88, width=0.7, head_lift=-1.0, hand=1.1),
    head=dict(kind='kobold', iris='#ffd23a', glow=0.6),
    weapon=dict(kind='spear', hands=2, back=5.2, up=13.0, down=9.0, length=9.0),
    groups=dict(body=1.4, leg=0.8),
)
