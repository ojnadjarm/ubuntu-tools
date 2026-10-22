"""Garment envelope from the spec: outermost lathe radius at a height, so hair and props stay outside clothes."""
import numpy as np


def radius(spec, z):
    """Max radius over spec garments that carry a lathe `profile` [[r, z], ...]; 0 where none covers z."""
    z = np.asarray(z, float)
    r = np.zeros_like(z)
    for g in spec.get('garments', []):
        prof = np.array(g.get('profile') or [], float)
        if len(prof) < 2:
            continue
        prof = prof[np.argsort(prof[:, 1])]
        inside = (z >= prof[0, 1]) & (z <= prof[-1, 1])
        r = np.where(inside, np.maximum(r, np.interp(z, prof[:, 1], prof[:, 0])), r)
    return r
