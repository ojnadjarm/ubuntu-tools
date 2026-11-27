"""Flicker in motion: what is left of each frame after warping its neighbours onto it (flick v2 of T2019)."""
import os
from multiprocessing import Pool

import cv2
import numpy as np

E = 0.25  # px: the floor triplet's offset from the source frame
STILL_PX = 0.25  # mean motion a frame under which the camera counts as still (pop gate)


def _init():
    cv2.setNumThreads(1)


def read(d, f):
    a = cv2.imread(os.path.join(d, "f_%04d.png" % f))
    if a is None:
        raise FileNotFoundError(os.path.join(d, "f_%04d.png" % f))
    return a.astype(np.float32)


def grey(v):
    return cv2.cvtColor(np.clip(v, 0, 255).astype(np.uint8), cv2.COLOR_BGR2GRAY)


def warp(img, fl, grid):
    return cv2.remap(img, grid[0] + fl[..., 0], grid[1] + fl[..., 1], cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)


def flows(g):
    """Backward and forward flow of the middle grey frame, and where both survive a there-and-back check."""
    dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    h, w = g[1].shape
    grid = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))
    fb, ff = dis.calc(g[1], g[0], None), dis.calc(g[1], g[2], None)
    ok = np.ones((h, w), bool)
    for fl, k in ((fb, 0), (ff, 2)):
        rt = fl + warp(dis.calc(g[k], g[1], None), fl, grid)
        x, y = grid[0] + fl[..., 0], grid[1] + fl[..., 1]
        ok &= (np.hypot(rt[..., 0], rt[..., 1]) < 1.0) & (x > 2) & (x < w - 3) & (y > 2) & (y < h - 3)
    return fb, ff, ok, grid


def resid(s, fb, ff, grid, sigma):
    """Signed second difference of three float frames after a blur of sigma px."""
    b = [cv2.GaussianBlur(v, (0, 0), sigma) if sigma > 0 else v for v in s]
    return b[1] - 0.5 * (warp(b[0], fb, grid) + warp(b[2], ff, grid))


def fshift(a, dx, dy):
    """Exact band-limited shift of a picture (Fourier, reflect-padded), rounded as an 8-bit frame on disk."""
    p = 64
    b = cv2.copyMakeBorder(a, p, p, p, p, cv2.BORDER_REFLECT)
    h, w = b.shape[:2]
    ph = np.exp(-2j * np.pi * (np.fft.fftfreq(w)[None, :] * dx + np.fft.fftfreq(h)[:, None] * dy))
    out = np.stack([np.fft.ifft2(np.fft.fft2(b[..., c]) * ph).real for c in range(3)], -1)
    return np.round(np.clip(out[p:-p, p:-p], 0, 255)).astype(np.float32)


def _mean(a, m):
    return float(a[m].mean() / 2.55) if m.any() else 0.0


def _one(job):
    """Measures of frame f in every source, flow from the flow folder."""
    f, sources, flow_dir, sigma = job
    raw = [read(flow_dir, f + k) for k in (-1, 0, 1)]
    g = [grey(v) for v in raw]
    fb, ff, ok, grid = flows(g)
    lum = g[1].astype(np.float32)
    th = cv2.morphologyEx(lum, cv2.MORPH_TOPHAT, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    thin = cv2.dilate((th > 12).astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    edge = cv2.dilate((np.hypot(cv2.Sobel(lum, cv2.CV_32F, 1, 0), cv2.Sobel(lum, cv2.CV_32F, 0, 1)) > 60).astype(np.uint8),
                      np.ones((5, 5), np.uint8)) > 0
    rows = []
    for d in sources:
        s = raw if d == flow_dir else [read(d, f + k) for k in (-1, 0, 1)]
        r = resid(s, fb, ff, grid, sigma)
        a = np.abs(r).mean(2)
        t = [cv2.resize(v.mean(2), (16, 9), interpolation=cv2.INTER_AREA) for v in s]
        rows.append(dict(flick=_mean(a, ok), broad=_mean(np.abs(cv2.GaussianBlur(r, (0, 0), 16)).mean(2), ok),
                         pop=float((a[ok] > 0.02 * 255).mean() * 100) if ok.any() else 0.0,
                         thin=_mean(a, ok & thin), flat=_mean(a, ok & ~edge & ~thin),
                         tile=float((np.abs(t[1] - 0.5 * (t[0] + t[2])) / np.maximum(t[1], 2.55)).mean() * 100)))
    return float(np.hypot(fb[..., 0], fb[..., 1]).mean()), rows


def _floor(job):
    """The measure's own floor at frame f: the frame moved by an exact shift equal to its median motion.

    All three frames are resampled (a quarter pixel apart from the source) so each carries its own 8-bit rounding,
    as a renderer's frames do; without that the floor reads about a third low."""
    f, sources, flow_dir, sigma = job
    ref = read(flow_dir, f)
    ff = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM).calc(grey(ref), grey(read(flow_dir, f + 1)), None)
    dx, dy = float(np.median(ff[..., 0])), float(np.median(ff[..., 1]))
    trip = lambda a: [fshift(a, E - dx, E - dy), fshift(a, E, E), fshift(a, E + dx, E + dy)]
    fb, ffw, ok, grid = flows([grey(v) for v in trip(ref)])
    out = []
    for d in sources:
        s = trip(read(d, f))
        out.append(_mean(np.abs(resid(s, fb, ffw, grid, sigma)).mean(2), ok))
    return out


def measure(sources, first, last, flow_dir=None, sigma=2.0, fps=24, samples=6, workers=8) -> list:
    """flick() of several frame folders in one pass, sharing the flow; one dict per source."""
    flow_dir = flow_dir or sources[0]
    frames = list(range(first + 1, last))
    picks = sorted({frames[int(i)] for i in np.linspace(0, len(frames) - 1, min(samples, len(frames)))})
    with Pool(min(workers, os.cpu_count() or 1), initializer=_init) as pool:
        per = pool.map(_one, [(f, sources, flow_dir, sigma) for f in frames], chunksize=2)
        floors = np.array(pool.map(_floor, [(f, sources, flow_dir, sigma) for f in picks]))
    motion = np.array([m for m, _ in per])
    still = motion < STILL_PX
    out = []
    for i, d in enumerate(sources):
        col = {k: np.array([rows[i][k] for _, rows in per]) for k in per[0][1][i]}
        series = col["flick"]
        n = min(fps, len(series))
        worst = float(np.convolve(series, np.ones(n) / n, "valid").max())
        floor = float(floors[:, i].mean())
        out.append(dict(mean=float(series.mean()), worst_1s=worst, floor=floor, excess=float(series.mean()) - floor,
                        excess_1s=worst - floor, broad=float(col["broad"].mean()), pop=float(col["pop"].mean()),
                        pop_still=float(col["pop"][still].mean()) if still.any() else None,
                        thin=float(col["thin"].mean()), flat=float(col["flat"].mean()), tile=float(col["tile"].mean()),
                        motion=float(motion.mean()), n=len(frames), still_frames=int(still.sum()),
                        series=[round(float(v), 5) for v in series]))
    return out


def flick(frames_dir, first, last, flow_dir=None, sigma=2.0, fps=24) -> dict:
    """Flicker of frames first..last of a folder of f_%04d.png, in % of full scale, flow from flow_dir (default: itself)."""
    return measure([frames_dir], first, last, flow_dir, sigma, fps)[0]
