"""Ornament as geometry: piped trim bands along garment edges and couched-thread scrollwork inside embroidery bands."""
import math

import numpy as np

from .base import TAU, unit
from .geom import Sheet

LIFT = 0.0015
TRIM_AT = np.array([0.0, 0.15, 0.5, 0.85, 1.0])
TRIM_RISE = np.array([0.1, 1.0, 0.55, 1.0, 0.1])


def strip(sh, side, width, lift, crown=0.0, cut=None):
    """Trim band `width` m into the sheet from one edge: two raised piping beads around a sunken braid, lifted off the cloth;
    `cut` (start, end) m of a column edge are left bare where a row trim already runs, so the corners butt instead of cross."""
    P, N = sh.P, sh.N
    if side == 'last_row':
        P, N = P[::-1], N[::-1]
    elif side == 'first_col':
        P, N = P.transpose(1, 0, 2), N.transpose(1, 0, 2)
    elif side == 'last_col':
        P, N = P[:, ::-1].transpose(1, 0, 2), N[:, ::-1].transpose(1, 0, 2)
    act = sh.active()
    act = {'last_row': act[::-1], 'first_col': act.T, 'last_col': act[:, ::-1].T}.get(side, act)[0]
    if cut:
        along = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P[0], axis=0), axis=-1))])
        act = act & (along >= cut[0]) & (along <= along[-1] - cut[1])
    acc = np.vstack([np.zeros((1, P.shape[1])), np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=-1), 0)])
    ws, rows = TRIM_AT * width, len(TRIM_AT)
    Q, M = np.empty((rows, P.shape[1], 3)), np.empty((rows, P.shape[1], 3))
    for k in range(P.shape[1]):
        for d in range(3):
            Q[:, k, d] = np.interp(ws, acc[:, k], P[:, k, d])
            M[:, k, d] = np.interp(ws, acc[:, k], N[:, k, d])
    M = unit(M)
    out = Sheet(Q + M * (lift + crown * TRIM_RISE)[:, None, None], sh.closed and side in ('first_row', 'last_row'), ref=M).update_normals()
    if not act.all():
        K = len(act)
        out.keep = np.broadcast_to((act & np.roll(act, -1))[:K if out.closed else K - 1], (rows - 1, K if out.closed else K - 1)).copy()
    return out


def ribbon(sheet, surf, line, width, th0, geo):
    """A couched cord along (along, arc) points: three rows projected onto the target surface, the middle one raised."""
    line = np.asarray(line)
    tdir = unit(np.gradient(line, axis=0))
    nrm = np.stack([-tdir[:, 1], tdir[:, 0]], 1)
    Q, M = [], []
    for sgn, rise in ((-1, 0.0), (0, 0.45), (1, 0.0)):
        row, nr = [], []
        for (al, arc), (dal, darc) in zip(line, nrm * width / 2 * sgn):
            _, _, r = sheet.ray(al + dal, th0)
            o, d, _ = sheet.ray(al + dal, th0 + (arc + darc) / max(r, 1e-3))
            hit = surf.ray_in(o, d)
            if hit is None:
                return 0
            row.append(hit[0] + hit[1] * (LIFT + rise * width))
            nr.append(hit[1])
        Q.append(row)
        M.append(nr)
    geo.sheet(Sheet(np.array(Q), False, ref=np.array(M)).update_normals())
    return 1


def scroll_lines(length, half, wave, gap=0.0):
    """Rinceau in band coordinates (x along, y across): a wavy stem and a tapering spiral curl into every hollow, each
    curl set `gap` off the stem crest so the cords sit side by side instead of crossing."""
    n = max(1, round(length / wave))
    lam = length / n
    x = np.linspace(0, length, max(4, int(length / 0.02) + 1))
    stem = np.stack([x, 0.45 * half * np.sin(TAU * x / lam)], 1)
    curls, r0 = [], 0.6 * half
    psi = np.linspace(0, 1.7 * math.pi, 11)
    for k in range(2 * n):
        sg = 1 if k % 2 == 0 else -1
        xc = lam / 4 + k * lam / 2
        c = np.array([xc, sg * (0.45 * half - r0 - gap)])
        phi = sg * math.pi / 2 - sg * psi
        curls.append(c + (r0 * np.exp(-0.22 * psi))[:, None] * np.stack([np.cos(phi), np.sin(phi)], 1))
    return [(stem, 1.0)] + [(cu, 0.75) for cu in curls]


def scroll(d, band, sheet, surf, geo, s):
    n = 0
    t = d.get('thread_m', 0.005) * s
    for line, w in scroll_lines(band['length'], band['half'], d.get('wave_m', 0.15) * s, 1.4 * t):
        n += ribbon(sheet, surf, [band['at'](x, y) for x, y in line], w * t, band['th0'], geo)
    return n


DECALS = {'scroll': scroll}


def decals(d, built, own, below, geo, s):
    """Lay one decal (`kind` in DECALS) over every band of its region; returns the number of pieces made."""
    if d['kind'] not in DECALS:
        raise ValueError(f'decal kind {d["kind"]!r} unknown ({" | ".join(DECALS)})')
    n = 0
    for band in built.regions.get(d.get('region'), []):
        surf = below if band['target'] == 'below' and below else own
        n += DECALS[d['kind']](d, band, built.sheets[band['sheet']], surf, geo, s)
    return n
