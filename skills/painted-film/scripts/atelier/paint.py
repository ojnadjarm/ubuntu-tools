"""The stroke solver: seeds + reference + look -> strokes on the picture (ARCHITECTURE.md 5, rules 2 to 6). Pure."""
from dataclasses import dataclass

import cv2
import numpy as np

from .anchor import NEAR, mix, unit

# colour_levels: the colour taps read the reference 2^n coarser than their spacing (A4: 2, its noise moves whole strokes)
DEFAULTS = {"max_px": 64.0, "size": 1.4, "aspect": 2.5, "broken": 0.0, "colour_levels": 2.0}
EPS_W = 0.05  # weight of the plain tap mean when no tap shares the seed's ident
MIN_OPACITY = 1e-3
LO = 0.75  # the seed's plane depth at a tap is kept within [LO, 2] times its own depth (grazing planes)
REACH = 8  # ref px: the window of the hidden pre-test


def _band(z):
    """Depth band of the soft visibility test, m: the plane test is exact but for depth precision."""
    return 0.005 + 0.005 * z


def _surely_hidden(depth, xr, yr, zs, ts):
    """Seeds every tap of whose visibility test is 0: all depths within REACH are nearer than the lowest plane depth
    the test allows by two bands. Only a shortcut: the full test gives these seeds opacity 0."""
    d = cv2.dilate(np.where(np.isfinite(depth), depth, 1e9).astype(np.float32), np.ones((2 * REACH + 1,) * 2, np.uint8))
    H, W = depth.shape
    i, j = np.clip(np.rint(yr), 0, H - 1).astype(np.int64), np.clip(np.rint(xr), 0, W - 1).astype(np.int64)
    inside = (xr > -0.5) & (xr < W - 0.5) & (yr > -0.5) & (yr < H - 0.5)
    return inside & (ts + 1.5 <= REACH) & (d[i, j] < LO * zs - 2 * _band(zs))


@dataclass
class Strokes:
    """Screen strokes in drawing order: by layer (coarse to fine), then by order (the seed id)."""
    x: np.ndarray  # (k,) f32 px, pixel (i, j)'s centre at x = j, y = i
    y: np.ndarray
    ang: np.ndarray  # (k,) f32 rad in [0, pi): the stroke's line on the picture
    length: np.ndarray  # (k,) f32 px, along ang
    width: np.ndarray  # (k,) f32 px
    variant: np.ndarray  # (k,) u8, brush variant from the id
    c1: np.ndarray  # (k, 3) f32 linear colour from the reference
    c2: np.ndarray  # (k, 3) f32 linear broken colour from the id
    opacity: np.ndarray  # (k,) f32: octave fade times visibility
    z: np.ndarray  # (k,) f32 view depth, m
    layer: np.ndarray  # (k,) u8, the octave
    order: np.ndarray  # (k,) u64, the seed id
    zg: np.ndarray  # (k, 2) f32: d(1/z)/d(x, y) per px, the stroke's plane on the picture (A5, the depth test)


def _bilinear(img, u, v):
    """img at float pixel places (u = column, v = row), edges clamped."""
    H, W = img.shape[:2]
    u, v = np.clip(u, 0, W - 1), np.clip(v, 0, H - 1)
    i0, j0 = np.minimum(v.astype(np.int64), H - 2 if H > 1 else 0), np.minimum(u.astype(np.int64), W - 2 if W > 1 else 0)
    fv, fu = v - i0, u - j0
    if img.ndim == 3:
        fv, fu = fv[..., None], fu[..., None]
    i1, j1 = np.minimum(i0 + 1, H - 1), np.minimum(j0 + 1, W - 1)
    return (img[i0, j0] * (1 - fu) * (1 - fv) + img[i0, j1] * fu * (1 - fv) + img[i1, j0] * (1 - fu) * fv
            + img[i1, j1] * fu * fv)


def _pyramid(lit):
    out = [lit.astype(np.float32)]
    while min(out[-1].shape[:2]) >= 16:
        out.append(cv2.pyrDown(out[-1]))
    return out


def _sample(pyr, u, v, lev):
    """Trilinear: the pyramid at level lev (float), place (u, v) in level-0 pixels (pyrDown keeps pixel 2i at i)."""
    l0 = np.clip(np.floor(lev).astype(np.int64), 0, len(pyr) - 1)
    l1, fr = np.minimum(l0 + 1, len(pyr) - 1), np.clip(lev - l0, 0, 1)[..., None]
    out = np.zeros(u.shape + (3,))
    for k in np.unique(np.concatenate([l0.ravel(), l1.ravel()])):
        w = np.where(l0 == k, 1 - fr[..., 0], 0.0) + np.where(l1 == k, fr[..., 0], 0.0)
        m = w > 0
        out[m] += w[m][:, None] * _bilinear(pyr[k], u[m] / 2.0 ** k, v[m] / 2.0 ** k)
    return out


def solve(ref, seeds, look, size) -> Strokes:
    """Strokes of the seeds on a picture of `size`, coloured and tested against the reference `ref`."""
    lk = {k: float(look.get(k, v)) for k, v in DEFAULTS.items()}
    W, H = size
    cam = ref.camera
    Wr, Hr = cam.size
    sr = Wr / W
    fr = cam.lens_mm / cam.sensor_mm * Wr
    cx, cy = Wr / 2 - 0.5, Hr / 2 - 0.5
    c = (seeds.P - cam.pos) @ cam.R
    z = -c[:, 2]
    zs = np.maximum(z, NEAR)
    xr, yr = cx + fr * c[:, 0] / zs, cy - fr * c[:, 1] / zs
    width = np.minimum(lk["size"] * seeds.px, lk["max_px"])
    a = np.nonzero((z > NEAR) & ~_surely_hidden(ref.depth, xr, yr, zs, width * sr / 3.0))[0]
    c, z, zs, xr, yr, width = c[a], z[a], zs[a], xr[a], yr[a], width[a]
    sid, octave, ident = seeds.id[a], seeds.octave[a], seeds.ident[a]

    full = np.minimum(width * lk["aspect"], lk["max_px"])
    t = seeds.T[a] @ cam.R  # rule 5: the tangent on the picture; toward the viewer it shortens to a dab
    dx = fr * (t[:, 0] + c[:, 0] * t[:, 2] / zs) / zs
    dy = -fr * (t[:, 1] + c[:, 1] * t[:, 2] / zs) / zs
    r = np.clip(np.hypot(dx, dy) * zs / fr, 0.0, 1.0)
    length = width + (full - width) * r * r
    ang = np.arctan2(dy, dx) % np.pi
    ang = np.where(ang >= np.pi, 0.0, ang)

    # rules 3 and 4: a 3x3 pattern over the footprint, each tap read bilinearly from its four pixels
    n = seeds.N[a] @ cam.R
    num = (n * c).sum(1)
    ts = width * sr / 3.0
    off = np.array([(a, b) for b in (-1, 0, 1) for a in (-1, 0, 1)], float)
    tu, tv = xr[:, None] + off[:, 0] * ts[:, None], yr[:, None] + off[:, 1] * ts[:, None]
    band = _band(zs)[:, None]
    vis, same = np.zeros(tu.shape), np.zeros(tu.shape)
    j0, i0 = np.floor(tu), np.floor(tv)
    for dj in (0, 1):
        for di in (0, 1):
            pj, pi = j0 + dj, i0 + di
            w = (1 - np.abs(tu - pj)) * (1 - np.abs(tv - pi))
            jj, ii = np.clip(pj, 0, Wr - 1).astype(np.int64), np.clip(pi, 0, Hr - 1).astype(np.int64)
            ray = np.stack([(pj - cx) / fr, -(pi - cy) / fr, -np.ones_like(pj)], -1)
            den = (n[:, None, :] * ray).sum(-1)
            with np.errstate(divide="ignore", invalid="ignore"):
                zp = np.where(np.abs(den) > 1e-9, num[:, None] / den, np.inf)
            zp = np.clip(np.nan_to_num(zp, nan=np.inf, posinf=np.inf, neginf=np.inf), LO * zs[:, None], 2.0 * zs[:, None])
            d = ref.depth[ii, jj]
            v = np.clip((np.where(np.isfinite(d), d, 1e9) - zp) / band + 2.0, 0.0, 1.0)
            vis += w * v
            same += w * v * (ref.ident[ii, jj] == ident[:, None])
    opacity = seeds.opacity[a] * vis.mean(1)

    k = np.nonzero(opacity > MIN_OPACITY)[0]
    k = k[np.lexsort((sid[k], octave[k]))]
    pyr = _pyramid(np.clip(ref.lit, 0.0, 1.0))  # display range: an emitter (lit 60) must not flood its neighbours
    col = _sample(pyr, tu[k], tv[k], (np.log2(np.maximum(ts[k], 1.0)) + lk["colour_levels"])[:, None] * np.ones((len(k), 9)))
    c1 = ((same[k, :, None] * col).sum(1) + EPS_W * col.mean(1)) / (same[k].sum(1) + EPS_W)[:, None]
    jit = 2.0 * unit(mix(sid[k, None], np.arange(3)[None, :])) - 1.0
    c2 = c1 * (1.0 + lk["broken"] * jit)
    f32 = lambda a: a[k].astype(np.float32)
    with np.errstate(divide="ignore", invalid="ignore"):  # 1/z on the plane n.X = num is linear in the picture
        zg = np.column_stack([n[:, 0], -n[:, 1]]) * (sr / fr) / num[:, None]
    zg = np.where(np.isfinite(zg) & (np.abs(num) > 1e-9)[:, None], zg, 0.0)
    return Strokes(f32((xr + 0.5) / sr - 0.5), f32((yr + 0.5) / sr - 0.5), f32(ang), f32(length), f32(width),
                   ((sid[k] >> np.uint64(8)) & np.uint64(255)).astype(np.uint8), c1.astype(np.float32), c2.astype(np.float32), f32(opacity),
                   f32(z), octave[k].astype(np.uint8), sid[k].astype(np.uint64), f32(zg))
