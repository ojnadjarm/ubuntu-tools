"""The stroke solver: seeds + reference + look -> strokes on the picture (ARCHITECTURE.md 5, rules 2 to 6). Pure."""
from dataclasses import dataclass

import cv2
import numpy as np

from .anchor import NEAR, mix, unit

# colour_levels: the colour taps read the reference 2^n coarser than their spacing (A4: 2, its noise moves whole strokes)
# block: the octaves under the finest are this much wider (a block-in that leaves no bare ground); needs px_per_stroke
DEFAULTS = {"max_px": 64.0, "size": 1.4, "aspect": 2.5, "broken": 0.0, "colour_levels": 2.0, "block": 1.0,
            "px_per_stroke": 0.0, "hug": 0.0}  # hug: how hard a stroke shrinks and moves to stay on its own thing
# "form": {"light": world vector, "gain": g}: a fill's colour times 1 + g * (its normal . light), the painter's own light
# marks (picture px): width, length over spacing, reach of the colour taps, value gain of lit edges and joints,
# true width (px) over which a mark fades in, how hard the taps lean to the light or dark side
# "weight": how much a mark's opacity and width vary by its id (a drawn line, not a ruled one)
MARK = {"width": 1.8, "aspect": 2.5, "reach": 3.0, "light": 0.5, "dark": 0.5, "fade": (0.15, 0.6), "power": 4.0,
        "weight": 0.0}
MARK_BAND = 0.3  # a mark's depth band against a fill stroke's: an edge just behind a wall must not show through
MARK_LAYER = 64  # marks are drawn after every fill octave
LUMA = np.array([0.2126, 0.7152, 0.0722])
EPS_W = 0.05  # weight of the plain tap mean when no tap shares the seed's ident
MIN_OPACITY = 1e-3
HUG_FLOOR = 1.8  # the least tap share the hug's grip divides by: a stroke with a sliver of its own thing barely moves
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
    n: np.ndarray = None  # (k, 3) f32 world normal turned to the viewer, 0 for a mark (the medium's face cut)

    def __post_init__(self):
        if self.n is None:
            self.n = np.zeros((len(self.order), 3), np.float32)


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


def _box_own(ident, own, u, v, half):
    """The share of each box (centre u, v, half size half, ref px) whose pixels carry the seed's ident: an area,
    continuous in u, v and half (a summed-area table read bilinearly), never one pixel."""
    H, W = ident.shape
    hb = half[:, None]
    x0, x1 = np.clip(u - hb, -0.5, W - 0.5), np.clip(u + hb, -0.5, W - 0.5)
    y0, y1 = np.clip(v - hb, -0.5, H - 0.5), np.clip(v + hb, -0.5, H - 0.5)
    out = np.zeros(u.shape)
    o = np.argsort(own, kind="stable")
    for g in np.split(o, np.flatnonzero(np.diff(own[o])) + 1):
        if not len(g):
            continue
        c0, c1 = int(np.floor(x0[g].min() + 0.5)), int(np.ceil(x1[g].max() + 0.5))
        r0, r1 = int(np.floor(y0[g].min() + 0.5)), int(np.ceil(y1[g].max() + 0.5))
        S = np.zeros((r1 - r0 + 1, c1 - c0 + 1))
        S[1:, 1:] = (ident[r0:r1, c0:c1] == own[g[0]]).cumsum(0).cumsum(1)
        F = lambda x, y: _bilinear(S, x + 0.5 - c0, y + 0.5 - r0)  # noqa: E731
        out[g] = (F(x1[g], y1[g]) - F(x0[g], y1[g]) - F(x1[g], y0[g]) + F(x0[g], y0[g])) / (4.0 * hb[g] ** 2)
    return np.clip(out, 0.0, 1.0)


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
    mk = dict(MARK, **look.get("mark", {}))
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
    mark = seeds.kind > 0
    true = fr / sr * seeds.width_m / zs  # a mark's own width on the picture
    with np.errstate(divide="ignore"):
        under = 1.0 + (lk["block"] - 1.0) * np.clip(np.log2(seeds.px / lk["px_per_stroke"]) - 0.5, 0.0, 1.0) if lk["px_per_stroke"] else 1.0
    heavy = 1.0 - mk["weight"] * unit(mix(seeds.id, 0x77))
    width = np.where(mark, np.clip(true, mk["width"], 3.0 * mk["width"]) * (0.5 + 0.5 * heavy),
                     np.minimum(lk["size"] * seeds.px * under, lk["max_px"]))
    a = np.nonzero((z > NEAR) & ~_surely_hidden(ref.depth, xr, yr, zs, width * sr / 3.0))[0]
    c, z, zs, xr, yr, width, mark, true, heavy = c[a], z[a], zs[a], xr[a], yr[a], width[a], mark[a], true[a], heavy[a]
    sid, octave, ident, kind = seeds.id[a], seeds.octave[a] + MARK_LAYER * mark, seeds.ident[a], seeds.kind[a]

    edge = np.maximum(1.5 * fr / sr * seeds.length_m[a] / zs, width)  # a mark is no longer than its edge allows
    full = np.minimum(np.where(mark, np.minimum(seeds.px[a] * mk["aspect"], edge), width * lk["aspect"]), lk["max_px"])
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
    band = (_band(zs) * np.where(mark, MARK_BAND, 1.0))[:, None]
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
    opacity = seeds.opacity[a] * vis.mean(1) * np.where(mark, heavy * np.clip((true - mk["fade"][0]) / (mk["fade"][1] - mk["fade"][0]), 0, 1), 1.0)

    hug = np.where(mark, 0.0, lk["hug"])
    share = np.zeros(tu.shape)
    h = np.nonzero((hug > 0) & (opacity > MIN_OPACITY))[0]
    share[h] = _box_own(ref.ident, ident[h], tu[h], tv[h], np.maximum(ts[h] / 2.0, 0.5))
    own = share.mean(1)  # the share of the footprint that shows the seed's own thing, as an area (rule 5)
    grip = np.minimum(hug, 1.0) / np.maximum(share.sum(1), HUG_FLOOR)
    xr, yr = xr + grip * (share * (tu - xr[:, None])).sum(1), yr + grip * (share * (tv - yr[:, None])).sum(1)
    width, length = width * own ** hug, length * own ** hug
    k = np.nonzero(opacity > MIN_OPACITY)[0]
    k = k[np.lexsort((sid[k], octave[k]))]
    pyr = _pyramid(np.clip(ref.lit, 0.0, 1.0))  # display range: an emitter (lit 60) must not flood its neighbours
    col = _sample(pyr, tu[k], tv[k], (np.log2(np.maximum(ts[k], 1.0)) + lk["colour_levels"])[:, None] * np.ones((len(k), 9)))
    c1 = ((same[k, :, None] * col).sum(1) + EPS_W * col.mean(1)) / (same[k].sum(1) + EPS_W)[:, None]
    nw = seeds.N[a[k]] * np.where(num[k] > 0, -1.0, 1.0)[:, None]
    if "form" in look:
        light = np.asarray(look["form"]["light"], float)
        c1 *= np.maximum(1.0 + look["form"]["gain"] * (nw @ (light / np.linalg.norm(light))), 0.0)[:, None]
    nw[mark[k]] = 0.0
    m = np.nonzero(mark[k])[0]
    if len(m):  # a mark reads both sides of its edge and leans to the light one (lit edge) or the dark one (joint)
        km, lit = k[m], kind[k[m]] == 1
        tm = np.full(len(m), mk["reach"] * sr)
        mu, mv = xr[km, None] + off[:, 0] * tm[:, None], yr[km, None] + off[:, 1] * tm[:, None]
        col = _sample(pyr, mu, mv, np.maximum(np.log2(tm), 0.0)[:, None] * np.ones((len(m), 9)))  # a tap reads its tm
        own = _box_own(ref.ident, ident[km], mu, mv, tm / 2.0)
        w = (own + EPS_W) * (col @ LUMA + 1e-3) ** np.where(lit, mk["power"], -mk["power"])[:, None]
        c1[m] = (w[..., None] * col).sum(1) / w.sum(1)[:, None] * np.where(lit, 1.0 + mk["light"], 1.0 - mk["dark"])[:, None]
    jit = 2.0 * unit(mix(sid[k, None], np.arange(3)[None, :])) - 1.0
    c2 = c1 * (1.0 + lk["broken"] * jit)
    f32 = lambda a: a[k].astype(np.float32)
    with np.errstate(divide="ignore", invalid="ignore"):  # 1/z on the plane n.X = num is linear in the picture
        zg = np.column_stack([n[:, 0], -n[:, 1]]) * (sr / fr) / num[:, None]
    zg = np.where(np.isfinite(zg) & (np.abs(num) > 1e-9)[:, None], zg, 0.0)
    return Strokes(f32((xr + 0.5) / sr - 0.5), f32((yr + 0.5) / sr - 0.5), f32(ang), f32(length), f32(width),
                   ((sid[k] >> np.uint64(8)) & np.uint64(255)).astype(np.uint8), c1.astype(np.float32), c2.astype(np.float32), f32(opacity),
                   f32(z), octave[k].astype(np.uint8), sid[k].astype(np.uint64), f32(zg),
                   nw.astype(np.float32))
