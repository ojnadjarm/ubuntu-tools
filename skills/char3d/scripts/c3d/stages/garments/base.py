"""Garment kit basics: constants, vector helpers, builder input (Env) and output (Built)."""
import math
from dataclasses import dataclass, field

import numpy as np

NAME = 'garments'
TAU = 2 * math.pi
FRONT = -math.pi / 2
Z = np.array([0.0, 0.0, 1.0])
THICK = {'robe': 0.005, 'mantle': 0.005, 'sash': 0.006, 'belt': 0.006, 'hat': 0.004, 'boots': 0.0, 'pouch': 0.0}
CLEAR = {'boots': 0.004, 'hat': 0.006}
DRAPE = {'robe': 'sim_once', 'mantle': 'sim_once'}


def unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, float) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def wrap(a):
    return (a + math.pi) % TAU - math.pi


def fold_field(th, t, count, rng, drift=0.0, width=(0.35, 0.6)):
    """Irregular cloth folds around a ring: rounded ridges, creased valleys, jittered spacing and height; mean 0, peak 1."""
    c0 = TAU * (np.arange(count) + rng.uniform(-0.3, 0.3, count)) / count
    w = TAU / count * rng.uniform(*width, count)
    a = rng.uniform(0.55, 1.3, count)
    d = rng.uniform(-1, 1, count) * drift
    x = wrap(th[..., None] - c0 - d * np.asarray(t, float).reshape(-1, 1, 1)) / w
    f = (a * np.where(np.abs(x) < 1, 0.5 * (1 + np.cos(math.pi * x)), 0)).sum(-1)
    f = f - f.mean(1, keepdims=True)
    return f / max(np.abs(f).max(), 1e-9)


@dataclass
class Built:
    """A builder's output: fitted sheets, trim edges, decal regions, caps, drape pins, rigid add-on pieces, (host, tube) sheet joins."""
    sheets: dict
    edges: dict = field(default_factory=dict)
    regions: dict = field(default_factory=dict)
    caps: list = field(default_factory=list)
    pins: dict = field(default_factory=dict)
    pieces: object = None
    fitted: bool = True
    split: bool = False
    joins: list = field(default_factory=list)
    info: dict = field(default_factory=dict)


@dataclass
class Env:
    lm: dict
    s: float
    h: float
    materials: dict

    @property
    def waist(self):
        return self.lm['spine'][2] - 0.02 * self.s


def arms(env):
    """(shoulder, hand) per side, left first; the shoulder is estimated from the neck landmark."""
    neck = env.lm['neck']
    return [(np.array([sgn * 0.1 * env.h, neck[1], neck[2] - 0.1 * env.s]), env.lm[f'hand.{side}'])
            for sgn, side in ((1, 'L'), (-1, 'R'))]


def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(P - (a + t[..., None] * ab), axis=-1)
