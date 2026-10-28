"""Kobold raising its spear overhand for a downward stab, jaw wide, darker scales: the second of a pair next to `kobold`."""
import importlib.util
import os

import numpy as np
from core import V

_sp = importlib.util.spec_from_file_location('kobold', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kobold.py'))
K = importlib.util.module_from_spec(_sp); _sp.loader.exec_module(K)

RAMPS = dict(K.RAMPS, rustscale=['#100806', '#220e0a', '#3a160e', '#561f10', '#742e16', '#93421e', '#b2602c', '#d08444'])
MATS = K.MATS


def pose(ph, p):
    """Overhand stab: spear lifted over the shoulder, point angled down at the enemy, weight back on the rear foot."""
    s = np.sin(2 * np.pi * ph)
    p['hilt'] = V(1.0, 25.0 + 0.6 * np.sin(2 * np.pi * ph - 0.5), 1.0)
    p['sword'] = V(0.78, -0.3, 0.55)
    p['lean'] = 3.6; p['head'] = V(0, 0.3 * s, 1.6)
    p['feet'] = [V(-4.0, 0, 4.2), V(5.0, 0, -3.4)]
    return p


SPEC = dict(K.SPEC, pose=pose, weapon=dict(K.SPEC['weapon'], back=5.6, up=12.0, down=11.0))
