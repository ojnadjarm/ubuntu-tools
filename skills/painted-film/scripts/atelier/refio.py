"""Read a reference frame in the venv: the five EXR passes and the JSON that ref.py writes (OpenCV here has no EXR)."""
import json
import struct
import zlib
from dataclasses import dataclass

import cv2
import numpy as np

from .scene import Camera, ident_code, ident_decode

PASSES = ("lit", "albedo", "depth", "normal", "ident")
_LINES = {0: 1, 2: 1, 3: 16}  # compression NONE, ZIPS, ZIP: scanlines per chunk
_TYPE = {0: np.uint32, 1: np.float16, 2: np.float32}


@dataclass
class Ref:
    lit: np.ndarray  # (H, W, 3) linear f32, with the haze
    albedo: np.ndarray  # (H, W, 3) linear f32: flat colour times tone
    depth: np.ndarray  # (H, W) view depth in metres, inf where nothing is
    normal: np.ndarray  # (H, W, 3) world space, 0 where nothing is
    ident: np.ndarray  # (H, W) i32, 0 where nothing is
    camera: Camera  # sized to this reference
    scale: float  # reference width / shot width
    meta: dict
    cover: np.ndarray = None  # (H, W) f32 share of the pixel its ident covers (anti-aliased); None: all 1
    other: np.ndarray = None  # (H, W) i64 flat index of the nearest pixel of the ident holding the rest
    air: np.ndarray = None  # (H, W, 3) linear f32: the haze's own light, part of lit; None: not rendered


def read_exr(path):
    """Channels of a single-part scanline EXR (NONE, ZIPS or ZIP) by name, each (H, W)."""
    with open(path, "rb") as fh:
        b = fh.read()
    if b[:4] != b"\x76\x2f\x31\x01" or struct.unpack_from("<I", b, 4)[0] & 0x1600:
        raise ValueError("not a single-part scanline EXR: %s" % path)
    p, hdr = 8, {}
    while b[p]:
        e = b.index(b"\0", p)
        name = b[p:e].decode()
        p = b.index(b"\0", e + 1) + 1
        n = struct.unpack_from("<i", b, p)[0]
        hdr[name] = b[p + 4:p + 4 + n]
        p += 4 + n
    p += 1
    ch, q, raw = [], 0, hdr["channels"]
    while raw[q]:
        e = raw.index(b"\0", q)
        ch.append((raw[q:e].decode(), _TYPE[struct.unpack_from("<i", raw, e + 1)[0]]))
        q = e + 17
    comp = hdr["compression"][0]
    if comp not in _LINES:
        raise ValueError("EXR compression %d not read here (write ZIP): %s" % (comp, path))
    x0, y0, x1, y1 = struct.unpack("<4i", hdr["dataWindow"])
    w, h, nl = x1 - x0 + 1, y1 - y0 + 1, _LINES[comp]
    out = {nm: np.empty((h, w), dt) for nm, dt in ch}
    row = w * sum(np.dtype(dt).itemsize for _, dt in ch)
    for o in np.frombuffer(b, np.uint64, (h + nl - 1) // nl, p):
        y, size = struct.unpack_from("<ii", b, int(o))
        d = b[int(o) + 8:int(o) + 8 + size]
        rows = min(nl, y1 + 1 - y)
        if comp and size < rows * row:  # zlib, then undo the predictor and the byte split
            t = np.frombuffer(zlib.decompress(d), np.uint8).astype(np.int64)
            t[1:] -= 128
            t = (np.cumsum(t) & 0xFF).astype(np.uint8)
            u = np.empty_like(t)
            u[0::2], u[1::2] = t[:(len(t) + 1) // 2], t[(len(t) + 1) // 2:]
            d = u.tobytes()
        q = 0
        for r in range(rows):
            for nm, dt in ch:
                out[nm][y - y0 + r] = np.frombuffer(d, dt, w, q)
                q += w * np.dtype(dt).itemsize
    return out


def _rgb(c, names):
    return np.stack([c[n].astype(np.float32) for n in names], -1)


def decode_ident(code, depth, reach=2):
    """Ident per pixel from the anti-aliased ident code: a blended pixel takes the ident of the clean pixel within
    `reach` whose depth is nearest its own (depth is not anti-aliased, so it says which side the pixel is on)."""
    ident, clean = ident_decode(code)
    out = np.where(clean, ident, 0)
    todo = ~clean & np.isfinite(depth)
    if todo.any():
        H, W = depth.shape
        ys, xs = np.nonzero(todo)
        best, err = np.zeros(len(ys), np.int64), np.full(len(ys), np.inf)
        z = depth[ys, xs]
        for dy in range(-reach, reach + 1):
            for dx in range(-reach, reach + 1):
                y2, x2 = np.clip(ys + dy, 0, H - 1), np.clip(xs + dx, 0, W - 1)
                e = np.where(clean[y2, x2] & np.isfinite(depth[y2, x2]), np.abs(depth[y2, x2] - z), np.inf)
                e = e + 1e-6 * (abs(dy) + abs(dx))  # ties go to the nearer pixel
                take = e < err
                best[take], err[take] = ident[y2, x2][take], e[take]
        out[ys, xs] = best
    return out.astype(np.int32)


def ident_cover(code, ident, reach=2):
    """Each pixel's share of its own ident and the flat index of the nearest pixel of the other ident, from the
    anti-aliased code (a blend of two idents' codes): the outline at its sub-pixel place, where depth and ident step."""
    H, W = ident.shape
    cover, other = np.ones((H, W), np.float32), np.arange(H * W, dtype=np.int64).reshape(H, W)
    ys, xs = np.nonzero(~ident_decode(code)[1])
    if len(ys):
        u, inv = np.unique(ident, return_inverse=True)
        pure = np.where((u > 0)[:, None], ident_code(u), 0.0)[inv.reshape(H, W)]  # nothing writes no code
        c, a = code[ys, xs].astype(np.float64), pure[ys, xs]
        best = np.full(len(ys), np.inf)
        for dy in range(-reach, reach + 1):
            for dx in range(-reach, reach + 1):
                y2, x2 = np.clip(ys + dy, 0, H - 1), np.clip(xs + dx, 0, W - 1)
                b = pure[y2, x2]
                d = a - b
                n2 = np.maximum((d * d).sum(1), 1e-12)
                s = np.clip(((c - b) * d).sum(1) / n2, 0.0, 1.0)
                e = np.linalg.norm(c - b - s[:, None] * d, axis=1) / np.sqrt(n2) + 1e-6 * (abs(dy) + abs(dx))
                take = (ident[y2, x2] != ident[ys, xs]) & (e < best)
                best[take] = e[take]
                cover[ys[take], xs[take]] = s[take]
                other[ys[take], xs[take]] = y2[take] * W + x2[take]
    return cover, other


def load(prefix):
    """The reference frame written as prefix.{lit,albedo,depth,normal,ident}.exr and prefix.json."""
    with open(prefix + ".json") as fh:
        meta = json.load(fh)
    c = {p: read_exr("%s.%s.exr" % (prefix, p)) for p in PASSES}
    depth = next(iter(c["depth"].values())).astype(np.float32)
    depth[depth >= 0.99 * meta["clip"][1]] = np.inf
    code = _rgb(c["ident"], "RGBA")
    ident = decode_ident(code, depth)
    normal = _rgb(c["normal"], "XYZ")
    normal[ident == 0] = 0
    air = _rgb(read_exr(prefix + ".air.exr"), "RGB") if "air" in meta.get("passes", ()) else None
    return Ref(_rgb(c["lit"], "RGB"), _rgb(c["albedo"], "RGB"), depth, normal, ident,
               Camera.from_json(meta["camera"]), float(meta["scale"]), meta, *ident_cover(code, ident), air)


def display(lit):
    """The fixed display curve the measures use: clip to 0..1, gamma 2.2."""
    return np.clip(lit, 0.0, 1.0) ** (1 / 2.2)


def shift(img, dx, dy):
    """Exact band-limited move of a float picture by (dx, dy) px: out(x, y) = img(x - dx, y - dy). Fourier on the
    picture mirrored both ways, which is periodic without a jump (a padded edge rings across the whole picture)."""
    h, w = img.shape[:2]
    m = np.concatenate([img, img[:, ::-1]], 1)
    m = np.concatenate([m, m[::-1]], 0)
    ph = np.exp(-2j * np.pi * (np.fft.fftfreq(2 * w)[None, :] * dx + np.fft.fftfreq(2 * h)[:, None] * dy))
    return np.stack([np.fft.ifft2(np.fft.fft2(m[..., c]) * ph).real[:h, :w] for c in range(m.shape[2])], -1).astype(np.float32)


def seed_diff(a, b, sigma=2.0, border=16):
    """Mean difference, in % of full scale, of two renders of one frame whose sampling patterns lie differently on the
    picture (b rendered with meta pattern_shift); blurred by sigma px of the shot (scaled to the reference)."""
    s = sigma * a.scale
    blur = [cv2.GaussianBlur(display(r.lit), (0, 0), s) for r in (a, b)]
    dx, dy = np.subtract(b.meta["pattern_shift"], a.meta["pattern_shift"])
    back = shift(blur[1], dx, -dy)
    k = int(np.ceil(border * a.scale))
    return float(np.abs(blur[0] - back)[k:-k, k:-k].mean() * 100)
