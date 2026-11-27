"""Synthetic clips for the harness tests: a painted-like picture moved by exact sub-pixel shifts."""
import os

import cv2
import numpy as np

W, H, N = 320, 180, 30


def picture(seed=1):
    """Blobs, gradients and hard edges at a few scales, float BGR 0..255."""
    rng = np.random.default_rng(seed)
    pad = 64
    a = np.zeros((H + 2 * pad, W + 2 * pad, 3), np.float32)
    for s, amp in ((12, 60), (4, 30), (1.5, 12)):
        a += cv2.GaussianBlur(rng.normal(size=a.shape).astype(np.float32), (0, 0), s) * amp * s ** 0.5
    for _ in range(12):
        c = tuple(int(v) for v in rng.integers(0, a.shape[1], 2))
        cv2.circle(a, c, int(rng.integers(6, 30)), tuple(float(v) for v in rng.uniform(-40, 40, 3)), -1, cv2.LINE_AA)
    return np.clip(a + 90, 0, 255)


def fshift(a, dx, dy):
    """Exact band-limited shift (Fourier), float out."""
    h, w = a.shape[:2]
    ph = np.exp(-2j * np.pi * (np.fft.fftfreq(w)[None, :] * dx + np.fft.fftfreq(h)[:, None] * dy))
    return np.stack([np.fft.ifft2(np.fft.fft2(a[..., c]) * ph).real for c in range(3)], -1)


def write(d, frames):
    os.makedirs(d, exist_ok=True)
    for i, f in enumerate(frames):
        cv2.imwrite(os.path.join(d, "f_%04d.png" % i), np.clip(np.round(f), 0, 255).astype(np.uint8))
    return d


def crop(a):
    return a[64:64 + H, 64:64 + W]


def grit(rng):
    """Canvas-like grain about 3 px across, 6 levels deep."""
    g = cv2.GaussianBlur(rng.normal(size=(H, W)).astype(np.float32), (0, 0), 1.5)
    return (g * 6 / g.std())[..., None]


def moving(d, dx=0.7, dy=0.3, grain=None, seed=1):
    """A picture moved by (dx, dy) px a frame; grain: None, 'screen' (fixed to the frame) or 'fresh' (new each frame)."""
    a, rng = picture(seed), np.random.default_rng(seed + 7)
    fixed = grit(rng)
    out = []
    for i in range(N):
        f = crop(fshift(a, dx * i, dy * i))
        if grain == "screen":
            f = f + fixed
        elif grain == "fresh":
            f = f + grit(rng)
        out.append(f)
    return write(d, out)


def wobble(d, hz=4.0, gain=0.05, fps=24, seed=1):
    """A still picture whose brightness pulses at hz with the given gain."""
    a = crop(picture(seed))
    return write(d, [a * (1 + gain * np.sin(2 * np.pi * hz * i / fps)) for i in range(N)])


def lab_bgr(L, a, b):
    """BGR uint8 from float Lab planes."""
    lab = np.stack([L, a, b], -1).astype(np.float32)
    return np.clip(np.round(cv2.cvtColor(lab, cv2.COLOR_Lab2BGR) * 255), 0, 255).astype(np.uint8)


def look_target(seed=3, w=480, h=270):
    """A cool, dense, detailed night picture: blue-green values full of strokes and edges."""
    rng = np.random.default_rng(seed)
    n = sum(cv2.GaussianBlur(rng.normal(size=(h, w)).astype(np.float32), (0, 0), s) * s ** 0.5 for s in (1, 3, 9))
    L = 30 + 12 * n / n.std()
    for _ in range(240):
        p = tuple(int(v) for v in rng.integers(0, (w, h)))
        q = (p[0] + int(rng.integers(-40, 40)), p[1] + int(rng.integers(-20, 20)))
        cv2.line(L, p, q, float(rng.uniform(10, 60)), int(rng.integers(1, 4)), cv2.LINE_AA)
    return lab_bgr(np.clip(L, 0, 100), -6 + 3 * n / n.std(), np.full((h, w), -16.0))


def look_bad(seed=4, w=480, h=270):
    """A warm, empty picture: a smooth orange-brown glow with nothing drawn in it."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.hypot((x - w / 2) / w, (y - h / 2) / h)
    return lab_bgr(np.clip(35 - 40 * r, 0, 100), np.full((h, w), 14.0), 30 - 10 * r)
