"""The harness: flicker, sub-frame, purity, look distance and gates."""
import numpy as np

from .flick import flick, measure
from .gates import DEFAULT_GATES, gate
from .look import lookdist


def subframe(render_fn, t, fps, k=10) -> float:
    """Change over 1/k of a frame against the change over a whole frame (a smooth move gives about 1/k)."""
    f0 = render_fn(t).astype(np.float32)
    whole = np.abs(render_fn(t + 1.0 / fps).astype(np.float32) - f0).mean()
    part = np.abs(render_fn(t + 1.0 / (k * fps)).astype(np.float32) - f0).mean()
    return float(part / max(whole, 1e-9))


def purity(render_fn, t) -> bool:
    """A frame rendered alone equals the same frame rendered after others, byte for byte."""
    a = render_fn(t)
    render_fn(t - 1.0)
    render_fn(t + 0.5)
    return bool(np.array_equal(a, render_fn(t)))


__all__ = ["DEFAULT_GATES", "flick", "gate", "lookdist", "measure", "purity", "subframe"]
