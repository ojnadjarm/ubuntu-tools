"""Render a character spec to frame PNGs (albedo a##, emissive e##, normal n##) and an optional zoomed sheet.

    python3 sprite.py chars/gamelyn.py out_dir [--yaw -0.6] [--cell 176] [--pitch 18] [--sheet preview.png] [--frames 0,4]
"""
import argparse
import os
import sys
from multiprocessing import Pool

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import core  # noqa: E402
from character import load  # noqa: E402


def job(a):
    path, f, cell, piv, yw, pitch = a
    core.set_pitch(pitch)
    ch = load(path)
    m, mats = ch.build(f)
    o = core.render(m, mats, cell, cell, piv, getattr(ch, 'SCALE', 1.12), yw)
    core.overlay(o, m, None)
    return f, o['rgba'], (np.clip(o['emis'], 0, 1) * 255).astype(np.uint8), core.normal_map(o)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('spec'); ap.add_argument('out')
    ap.add_argument('--yaw', type=float, default=-0.6); ap.add_argument('--pitch', type=float, default=18.0)
    ap.add_argument('--cell', type=int, default=176); ap.add_argument('--sheet', default='')
    ap.add_argument('--frames', default='')
    a = ap.parse_args()
    path = os.path.abspath(a.spec) if os.path.exists(a.spec) else a.spec
    n = load(path).FRAMES
    fr = [int(x) for x in a.frames.split(',')] if a.frames else range(n)
    piv = (a.cell // 2, a.cell - 10)
    os.makedirs(a.out, exist_ok=True)
    with Pool(max(1, min(len(fr), (os.cpu_count() or 2) - 2))) as pool:
        res = pool.map(job, [(path, f, a.cell, piv, a.yaw, a.pitch) for f in fr], chunksize=1)
    for f, rgba, emis, nrm in res:
        Image.fromarray(rgba, 'RGBA').save(f'{a.out}/a{f:02d}.png')
        Image.fromarray(emis, 'L').save(f'{a.out}/e{f:02d}.png')
        Image.fromarray(nrm, 'RGBA').save(f'{a.out}/n{f:02d}.png')
    if a.sheet:
        sh = Image.new('RGBA', (a.cell * len(res), a.cell), (24, 30, 58, 255))
        for i, (f, rgba, *_) in enumerate(res):
            im = Image.fromarray(rgba, 'RGBA'); sh.paste(im, (i * a.cell, 0), im)
        sh.resize((sh.width * 3, sh.height * 3), Image.NEAREST).save(a.sheet)
    print('ok', len(res), 'frames')


if __name__ == '__main__':
    main()
