"""The oil medium: strokes -> bristle sprites on linen, depth-tested against the reference, lit as paint (A5).

Takes BrushBank, Linen, Frame.finish and broken from the oil-paint skill; keeps its own compositor (oilc.c, with the
depth test). Colour per stroke: the solver's area colour, graded in Lab (the look's "grade"), broken by the id.
"""
import ctypes
import os
import subprocess
import sys

import cv2
import numpy as np

from ..anchor import mix, unit
from ..refio import display

sys.path.insert(0, os.path.expanduser("~/.claude/skills/oil-paint/scripts"))
import oilpaint as op  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
_BUILT = {}  # brush banks and linens by their parameters: built once, never written to
MIN_PX = 1.5  # rule 9: no stroke is drawn thinner (px); a thinner one is drawn MIN_PX wide with its ink kept


def _load_c():
    """Compile oilc.c next to this file when missing or older, and load it with ctypes."""
    src, lib = os.path.join(HERE, "oilc.c"), os.path.join(HERE, "_oilc.so")
    if not os.path.exists(lib) or os.path.getmtime(lib) < os.path.getmtime(src):
        tmp = lib + ".%d" % os.getpid()
        subprocess.run(["gcc", "-O3", "-march=native", "-ffast-math", "-shared", "-fPIC", "-o", tmp, src, "-lm"], check=True)
        os.replace(tmp, lib)
    f = ctypes.CDLL(lib).paint_strokes
    P = np.ctypeslib.ndpointer
    fp, ip = P(np.float32, flags="C_CONTIGUOUS"), P(np.int32, flags="C_CONTIGUOUS")
    i, fl = ctypes.c_int, ctypes.c_float
    f.argtypes = [fp, fp, i, i, fp, ip, ip, ip, ip, fp, fl, i, fp, fp, fp, fp, fp, ip, fp, fp, fp, fp, fl, fp, fp, fp, fp, fp, fl, fl,
                  ctypes.c_void_p, fl, ctypes.c_void_p, ctypes.c_void_p]
    f.restype = None
    return f


_PAINT = _load_c()


def _reach(near, cover, other, r, grow):
    """The depth r + 1 px around each pixel (grow: the farthest, else the nearest) and the pixel's share within r px of
    that depth's surface, from each pixel's coverage of its own surface and of its neighbour's (refio.ident_cover):
    max over the pixels q in reach of share(q) + r - |p - q|, clipped to 0..1 (T2047, rule 5)."""
    k = r + 1
    se = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * k + 1,) * 2)
    morph = cv2.dilate if grow else cv2.erode
    dm = morph(near, se)
    ser = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1,) * 2)
    inner = morph(near, ser) if r > 0 else near
    off = lambda a: np.abs(a - dm) > 2.0 * (0.005 + 0.005 * dm)  # noqa: E731  (the depth tests' band)
    # a pixel on that surface itself, or within r of a clean pixel of it, is wholly in reach
    todo = off(near) & (off(inner) | (cv2.dilate((cover < 1.0).astype(np.uint8), ser) > 0))
    s = np.ones(near.shape, np.float32)
    ys, xs = np.nonzero(todo)
    if len(ys):
        H, W = near.shape
        far = near.ravel()[other]
        d0 = dm[ys, xs]
        tol = 2.0 * (0.005 + 0.005 * d0)
        best = np.zeros(len(ys), np.float32)
        for dy, dx in zip(*np.nonzero(se)):
            dy, dx = dy - k, dx - k
            y2, x2 = np.clip(ys + dy, 0, H - 1), np.clip(xs + dx, 0, W - 1)
            c, gap = cover[y2, x2], r - np.hypot(dy, dx)
            for dq, nq in ((near[y2, x2], c), (far[y2, x2], 1.0 - c)):
                best = np.maximum(best, np.where((nq > 0) & (np.abs(dq - d0) <= tol), nq + gap, 0.0))
        s[ys, xs] = np.clip(best, 0.0, 1.0)
    return dm, s


def _built(key, make):
    if key not in _BUILT:
        _BUILT[key] = make()
    return _BUILT[key]


def _at(img, x, y, sr):
    """img (ref pixels) bilinear at picture places (x, y)."""
    h, w = img.shape
    u = np.clip((x + 0.5) * sr - 0.5, 0, w - 1.001)
    v = np.clip((y + 0.5) * sr - 0.5, 0, h - 1.001)
    j, i = u.astype(np.int64), v.astype(np.int64)
    fu, fv = u - j, v - i
    return ((img[i, j] * (1 - fu) + img[i, j + 1] * fu) * (1 - fv) + (img[i + 1, j] * (1 - fu) + img[i + 1, j + 1] * fu) * fv)


def _lab(rgb):
    return cv2.cvtColor(np.ascontiguousarray(rgb, np.float32)[None], cv2.COLOR_RGB2Lab)[0]


def grade(col, flame_ref, L_ref, x, y, sr, g):
    """Display colours (k, 3) pulled to the look's palette family in Lab (T2025's Tight grade), all smooth ramps:
    value into the dark half, cold low-chroma stone, warm only at flames and their pools; the broad value swing
    and the flame pools come from the reference, blurred, read at each stroke's centre."""
    L, a, b = _lab(col).T
    fl = op.smooth((L - g["flame_lo"]) / (g["flame_hi"] - g["flame_lo"]))
    if g["local"]:
        big = cv2.GaussianBlur(L_ref, (0, 0), g["local_sigma"] * sr)
        L = L - g["local"] * (_at(big, x, y, sr) - big.mean()) * (1 - fl)
    L2 = (g["l0"] + g["lk"] * L) * (1 - fl) + L * fl
    a2 = (a * g["a_k"] + g["a_off"]) * (1 - fl) + (a * g["flame_chroma"] + g["flame_a"]) * fl
    b2 = (b * g["b_k"] + g["b_off"]) * (1 - fl) + (b * g["flame_chroma"] + g["flame_b"]) * fl
    pool = _at(cv2.GaussianBlur(flame_ref, (0, 0), g["glow_sigma"] * sr), x, y, sr)
    gl = g["glow"] * np.clip(pool * 4, 0, 1) * (1 - fl)
    pl, pa, pb = g.get("pool", (5.0, 5.0, 18.0))  # what a flame's pool adds in Lab
    lab = np.column_stack([L2 + pl * gl, a2 + pa * gl, b2 + pb * gl]).astype(np.float32)
    return np.clip(cv2.cvtColor(lab[None], cv2.COLOR_Lab2RGB)[0], 0, 1)


class OilMedium:
    """Medium protocol (ARCHITECTURE.md 4): composite(strokes, ref, look, size) -> uint8 RGB."""

    def composite(self, strokes, ref, look, size):
        """Strokes in their fixed order, bristle sprites depth-tested against ref, on linen fixed to the frame."""
        W, H = size
        cv, br = look["canvas"], look["brush"]
        bank = _built(("bank", br["seed"]), lambda: op.BrushBank(seed=br["seed"]))
        linen = _built(("linen", W, H, cv["seed"], cv["period"], tuple(cv["ground"])),
                       lambda: op.Linen(W, H, seed=cv["seed"], period=cv["period"], ground=tuple(cv["ground"])))
        frame = op.Frame(linen, bank)
        st, k = strokes, len(strokes.order)
        if k:
            sr = ref.camera.size[0] / W
            L_ref = _lab(display(ref.lit).reshape(-1, 3)).reshape(ref.lit.shape)[..., 0]
            g = look["grade"]
            flame = op.smooth((L_ref - g["flame_lo"]) / (g["flame_hi"] - g["flame_lo"]))
            col = grade(display(st.c1), flame, L_ref, st.x, st.y, sr, g)
            jit = unit(mix(st.order[:, None], np.arange(6)[None, :])).astype(np.float32)
            c1 = op.broken(col, jit, look["broken"], shadow_tint=look["shadow_tint"], light_tint=look["light_tint"],
                           tints=look["tints"])
            c2 = op.broken(col, jit[:, ::-1], look["broken"], tints=0)
            per = len(bank.masters) // len(bank.ASPECTS)
            cls = int(np.abs(np.log(look["aspect"] / np.array(bank.ASPECTS))).argmin())
            var = (cls * per + (unit(mix(st.order, 0xB2)) * per).astype(np.int64)).astype(np.int32)
            depth = near = cv2.resize(np.where(np.isfinite(ref.depth), ref.depth, 1e9).astype(np.float32), (W, H),
                                      interpolation=cv2.INTER_NEAREST)
            r = int(round(look["edge_spill_px"]))
            soft = ref.cover is not None and ref.cover.shape == (H, W)  # the outline's coverage, at the picture's size
            smax = smin = None
            if soft:
                depth, smax = _reach(near, ref.cover, ref.other, r, True)
            elif r > 0:
                depth = cv2.dilate(depth, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1)))
            f32 = lambda v: np.ascontiguousarray(v, np.float32)  # noqa: E731
            wid = np.maximum(st.width, MIN_PX)
            opac = np.clip(st.opacity, 0, 1) * np.minimum(st.width / MIN_PX, 1.0)
            # T2038: "face" (cosine ramp of the face cut), "overhang_px" (a stroke's reach past its outline), "hard"
            f0, f1 = look.get("face", (0.0, 0.0))
            over = look.get("overhang_px")
            dmin = None if over is None else f32(cv2.erode(near, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * int(round(over)) + 1,) * 2)))
            if soft and over is not None:
                dmin, smin = _reach(near, ref.cover, ref.other, int(round(over)), False)
            ptr = lambda v: None if v is None else v.ctypes.data  # noqa: E731
            _PAINT(frame.img, frame.hgt, W, H, bank.atlas, bank.off, bank.mw, bank.mh, bank.nlev, bank.bw, float(bank.L), k,
                   f32(st.x), f32(st.y), f32(st.ang), f32(st.length), f32(wid), var, f32(c1), f32(c2),
                   f32(opac), f32(br["hs"] * np.minimum(1.0, br.get("thick_px", np.inf) / wid)), float(br["level"]), depth,
                   f32(st.z), f32(st.zg), f32(cv2.resize(ref.normal, (W, H), interpolation=cv2.INTER_AREA)), f32(st.n),
                   float(f0), float(f1), ptr(dmin), float(look.get("hard", 1.0)), ptr(smax), ptr(smin))
        return frame.finish(light=tuple(cv["light"]), relief=cv["relief"], gloss=cv["gloss"], shine=cv["shine"],
                            exposure=cv["exposure"], vignette=cv["vignette"])
