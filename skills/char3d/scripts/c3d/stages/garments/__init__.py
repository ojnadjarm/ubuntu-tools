"""Stage garments: layered robe with sleeves, mantle, belt, pouches, hat and boots as quad game lows, draped once on the A-pose."""
import time

import bpy
import numpy as np

from .base import CLEAR, DRAPE, NAME, THICK, Env
from .boots import build_boots
from .cloth import cut_joins, drape, fit, floor, nudge, remove
from .gear import build_band, build_pouch
from .hat import build_hat
from .publish import cull_covered, evaluated, inside_points, publish, self_pairs, uv_missing
from .robe import build_mantle, build_robe
from .surface import Surface

FLOOR = 0.003
JOIN_CLEAR = 0.004
BUILDERS = {'robe': build_robe, 'mantle': build_mantle, 'sash': build_band, 'belt': build_band, 'hat': build_hat,
            'boots': build_boots, 'pouch': build_pouch}
__all__ = ['NAME', 'BUILDERS', 'run']


def run(ctx):
    h = ctx.spec['body']['height_m']
    env = Env({k: np.array(v, float) for k, v in ctx.landmarks.items()}, h / 1.78, h, ctx.spec.get('materials', {}))
    body = Surface.of_object(bpy.data.objects[ctx.parts['body']['object']])
    layers, objects, moved, repairs, inside = {}, [], 0, 0, 0
    main, todo, info, drapes = {}, [], {'sleeves': 0}, {}
    for g in sorted(ctx.spec['garments'], key=lambda g: g.get('layer', 0)):
        kind, layer, p = g['kind'], g.get('layer', 0), g.get('params', {})
        if kind not in BUILDERS:
            todo.append(f"{g['id']}:{kind}")
            continue
        lower = [x for lay, xs in layers.items() if lay < layer for x in xs]
        below = Surface.of_sheets(lower) if lower else None
        built = BUILDERS[kind](g, env, body, below)
        sheets = list(built.sheets.values())
        for sh in sheets:
            sh.update_normals()
        clear = CLEAR.get(kind, 0.008) * env.s
        thick = p.get('thickness_m', THICK.get(kind, 0.005))
        if built.fitted:
            moved += fit(sheets, body, below, clear)
        if built.pins and p.get('drape', DRAPE.get(kind, 'none')) == 'sim_once':
            t0 = time.perf_counter()
            pins = [built.pins.get(k, np.ones(sh.P.shape[:2])) for k, sh in built.sheets.items()]
            floor(sheets, FLOOR + thick)
            drapes[g['id']] = drape(sheets, pins, [body],
                                    int(p.get('drape_frames', 60)), env.s)
            moved += fit(sheets, body, below, clear, iters=4)
            drapes[g['id']]['seconds'] = round(time.perf_counter() - t0, 2)
        floor(sheets, FLOOR + thick)
        for k, v in built.info.items():
            info[k] = info.get(k, 0) + v if k == 'sleeves' else v
        saved = cut_joins(built, 2 * thick + JOIN_CLEAR * env.s)
        for attempt in range(6):
            obs = publish(ctx, g, env, built, below, thick)
            bad = inside_points(obs, body)
            print(f'char3d garments: {g["id"]} pass {attempt} inside {len(bad)}', flush=True)
            if not bad or attempt == 5:
                break
            remove(obs)
            repairs += 1
            nudge(sheets, bad, 0.004 * env.s)
            floor(sheets, FLOOR + thick)
        inside += len(bad)
        for k, keep in saved.items():
            built.sheets[k].keep = keep
        objects += obs
        main.setdefault(kind, []).append((layer, obs[0]))
        layers.setdefault(layer, []).extend((sh, thick) for sh in sheets)
    robes = sorted(main.get('robe', []), key=lambda x: x[0])
    hidden = {ob.name: cull_covered(ob, [o for lay, o in robes if lay > layer]) for layer, ob in robes[:-1]}
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    tris, zmin, quads, faces = {}, {}, 0, 0
    for ob in objects:
        co, tris[ob.name], (q, f) = evaluated(ob, dg)
        zmin[ob.name] = float(co[:, 2].min())
        quads, faces = quads + q, faces + f
    robe = max(main.get('robe', []), key=lambda x: x[0], default=(0, None))[1]
    hat_h = 0.0
    if main.get('hat'):
        hz = evaluated(main['hat'][0][1], dg)[0][:, 2]
        hat_h = float(hz.max() - hz.min())
    return {'stub': bool(todo), 'todo': todo, 'garments': len(ctx.spec['garments']), 'objects': len(objects),
            'robe_tris': tris[robe.name] if robe else 0, 'tris_total': sum(tris.values()),
            'tris': {k: v for k, v in sorted(tris.items())},
            'quads_pct': round(100 * quads / max(faces, 1), 2), **info, 'drape': drapes,
            'hat_height_m': round(hat_h, 4), 'rest_penetration_verts': inside, 'hidden_faces': hidden,
            'uv_missing': sum(uv_missing(ob) for ob in objects), 'fit_moved_verts': moved, 'repair_passes': repairs,
            'min_z_m': round(min(zmin.values()), 4) if zmin else 0.0,
            'self_x': {k: v for k, v in sorted((ob.name, self_pairs(ob, dg)) for ob in objects) if v}}
