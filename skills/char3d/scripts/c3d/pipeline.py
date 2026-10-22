"""Blender entry (blender -b ... --python pipeline.py -- CMD SPEC OUT): run one command's stages in order."""
import argparse
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402

from c3d import spec as specmod  # noqa: E402
from c3d.context import Context  # noqa: E402
from c3d.stages import (bake, body, detail, export, face, facerig, garments, hair, haircards, lod, lookdev,  # noqa: E402
                        materials, motion, props, qa_asset, qa_bake, render, retopo, rig, secondary, texture, uv)

BUILD = [body, face, hair, garments, props, materials, detail, retopo, uv, bake, texture, haircards,
         rig, facerig, motion, lookdev, secondary, export, lod]
COMMANDS = {'build': BUILD, 'render': [render], 'qa': [qa_bake, qa_asset]}


def main(argv):
    ap = argparse.ArgumentParser(prog='pipeline.py')
    ap.add_argument('cmd', choices=COMMANDS)
    ap.add_argument('spec')
    ap.add_argument('out')
    ap.add_argument('--draft', action='store_true')
    ap.add_argument('--until', choices=[s.NAME for s in BUILD])
    ap.add_argument('--shots', type=lambda s: s.split(','))
    ap.add_argument('--max-frames', type=int)
    a = ap.parse_args(argv)
    spec, out = specmod.load(a.spec), Path(a.out)
    if a.cmd == 'build':
        bpy.ops.wm.read_factory_settings(use_empty=True)
        ctx = Context(spec=spec, out=out, draft=a.draft)
    else:
        ctx = Context.load(out, spec, a.draft)
    ctx.options = {'shots': a.shots, 'max_frames': a.max_frames}
    for stage in COMMANDS[a.cmd]:
        t = time.perf_counter()
        metrics = stage.run(ctx)
        ctx.record(stage.NAME, time.perf_counter() - t, metrics)
        print(f'char3d stage {stage.NAME}: {ctx.stages[stage.NAME]}', flush=True)
        if stage.NAME == a.until:
            break
    if a.cmd == 'build':
        out.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(ctx.blend))
    ctx.save()


main(sys.argv[sys.argv.index('--') + 1:])
