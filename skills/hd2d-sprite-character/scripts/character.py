"""Assemble an HD-2D battle sprite from a character spec: palette, body/armour, head/hair, weapon, off hand, cape, stance.

A spec module defines RAMPS (name -> hex ramp), MATS (material -> ramp + shading), SPEC (dict below) and optionally
`extra(m, p, A)` for one-off parts (riders, familiars). `load(path)` returns an object with FRAMES, SCALE and build(f).

SPEC keys: frames, scale, stance (stances.STANCES name), pose (callable(ph, p) -> p tweaks), body {kind, height, width,
head_lift, emblem, hand}, head {kind, ...heads.py options}, weapon {kind, ...gear.py options} or None, offhand {kind} or None,
cape {length} or None, groups {name: k} smooth-union radii.
"""
import importlib.util
import os

from core import Model, V
from rig import RAMPS, mats
from body import BODY, ARM, anchors
from heads import HEAD
from gear import WEAPON, OFFHAND, cape, grips
from stances import STANCES

GROUPS = dict(leg=0.7, body=1.0, head=0.8, hair=0.9, tail=1.2)


class Character:
    def __init__(self, spec, mats_, extra=None):
        self.S, self.MATS, self.extra = spec, mats_, extra
        self.FRAMES = spec.get('frames', 8); self.SCALE = spec.get('scale', 1.6)

    def pose(self, f):
        """Stance preset at phase f/FRAMES, then the spec's per-character tweaks."""
        ph = f / self.FRAMES
        p = STANCES[self.S['stance']](ph)
        if self.S.get('pose'):
            p = self.S['pose'](ph, p) or p
        return p

    def build(self, f):
        S = self.S; p = self.pose(f); bs = S['body']
        m = Model(); m.sel = {'hand', 'hand_d'}
        for g, k in dict(GROUPS, **S.get('groups', {})).items():
            m.group(g, k)
        A = anchors(p, bs)
        BODY[bs['kind']](m, p, A, bs)
        if S.get('cape') is not None:
            cape(m, p, A, S['cape'])
        w = S.get('weapon')
        hands = {sd: (pt, 'relaxed', None) for sd, pt in p['hands'].items()} if 'hands' in p else grips(p, w or {})
        for sd, (pt, grip, axis) in hands.items():
            ARM[bs['kind']](m, p, A, sd, pt, grip, axis, bs)
        if w:
            WEAPON[w['kind']](m, p, A, w)
        if S.get('offhand'):
            OFFHAND[S['offhand']['kind']](m, p, A, S['offhand'])
        HEAD[S['head']['kind']](m, p, A, S['head'])
        if self.extra:
            self.extra(m, p, A)
        return m, self.MATS


def load(path):
    """Import a spec file (path or module name on sys.path) and return its Character; a module without SPEC is returned as is."""
    if os.path.exists(path):
        sp = importlib.util.spec_from_file_location(os.path.splitext(os.path.basename(path))[0], path)
        mod = importlib.util.module_from_spec(sp); sp.loader.exec_module(mod)
    else:
        mod = importlib.import_module(path)
    if not hasattr(mod, 'SPEC'):
        return mod
    RAMPS.update(getattr(mod, 'RAMPS', {}))
    ms = mats(**mod.MATS) if isinstance(next(iter(mod.MATS.values())), (str, tuple)) else mod.MATS
    if 'hand' not in ms:
        ms['hand'] = dict(ramp=ms[mod.SPEC.get('hand_mat', 'steel')]['ramp'], wrap=0.55, gamma=0.9, bias=mod.SPEC.get('hand_bias', 0.0))
    if 'hand_d' not in ms:
        ms['hand_d'] = dict(ms['hand'], bias=ms['hand'].get('bias', 0.0) - 1.8)
    return Character(mod.SPEC, ms, getattr(mod, 'extra', None))


__all__ = ['Character', 'load', 'V']
