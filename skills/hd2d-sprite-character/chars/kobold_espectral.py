"""Spectral kobold: the kobold risen as a ghost, cyan ectoplasm hide, legs dissolving into a swirling wisp, white-hot eyes, claws reaching."""
import importlib.util
import os

import numpy as np
from core import V

_sp = importlib.util.spec_from_file_location('kobold', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kobold.py'))
K = importlib.util.module_from_spec(_sp); _sp.loader.exec_module(K)

RAMPS = dict(K.RAMPS, **{
    'ecto': ['#01080c', '#021419', '#042429', '#06383c', '#0a5052', '#106c6a', '#1a8c84', '#2cb0a0', '#5adcc4'],
    'ectob': ['#0a3a40', '#1a6a6a', '#3aa89a', '#7ae0c8', '#c0fff0', '#ffffff'],
    'void': ['#010407', '#03090e', '#061418', '#0a2026'],
})
MATS = dict(
    scale=('ecto', {'kind': 'emis', 'bias': -0.6, 'glow': 0.25}), scale_s=('ecto', {'kind': 'emis', 'bias': -2.2, 'glow': 0.15}),
    belly=('ecto', {'kind': 'emis', 'bias': 0.6, 'glow': 0.4}), belly_s=('ecto', {'kind': 'emis', 'bias': -1.0, 'glow': 0.3}),
    spine=('ectob', {'kind': 'metal', 'bias': -0.4, 'glow': 0.5}), horn=('ectob', {'kind': 'metal', 'glow': 0.6}),
    horn_d=('ectob', {'kind': 'metal', 'bias': -1.4, 'glow': 0.4}), frill=('ecto', {'kind': 'emis', 'bias': -1.6, 'glow': 0.3}),
    frill_d=('ecto', {'kind': 'emis', 'bias': -2.6, 'glow': 0.2}), rag=('ecto', {'kind': 'emis', 'bias': -2.0, 'glow': 0.2}),
    rag_s=('ecto', {'kind': 'emis', 'bias': -3.0, 'glow': 0.1}), leather=('ecto', {'kind': 'emis', 'bias': -2.4, 'glow': 0.1}),
    rust=('ectob', {'kind': 'metal', 'bias': -1.0, 'glow': 0.3}), bone=('ectob', {'kind': 'metal', 'bias': 0.4, 'glow': 0.9}),
    claw=('ectob', {'kind': 'metal', 'bias': 0.6, 'glow': 1.0}), mouth=('void', {'wrap': 0.2}),
    tongue=('ecto', {'kind': 'emis', 'bias': 1.0, 'glow': 0.6}),
)


def pose(ph, p):
    """Hovering lunge: both clawed hands thrust at the enemy, a slow float bob."""
    s = np.sin(2 * np.pi * ph)
    p['b'] += 1.6 * s
    p['hands'] = {-1: V(7.2, 22.0 + 1.2 * np.sin(2 * np.pi * ph - 0.5), 8.6), 1: V(9.4, 19.6 + 1.2 * np.sin(2 * np.pi * ph - 1.0), 3.0)}
    p['hand_grip'] = 'claw'; p['palm'] = {-1: V(0.6, -0.2, 0.6), 1: V(0.8, -0.3, 0.4)}
    p['point'] = {-1: V(1.0, 0.3, 0.4), 1: V(1.0, 0.1, 0.2)}
    return p


SPEC = dict(K.SPEC, pose=pose, weapon=None, hand_mat='scale', hand_bias=0.8,
            body=dict(K.SPEC['body'], wisp=True, cord='#147a74'), head=dict(K.SPEC['head'], iris='#f0fffa', glow=1.0))
