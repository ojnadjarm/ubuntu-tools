"""Stage bake: per texture set, Cycles selected-to-active high -> low maps packed to albedo, normal, ORM, emissive PNGs."""
import contextlib
import fcntl
import os
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Euler

from .. import bpyutil as bu
from .materials import srgb_to_linear

NAME = 'bake'
MAPS = ('albedo', 'normal', 'orm', 'emissive')
ALL = ('normal', 'ao', 'curvature', 'albedo', 'roughness', 'metallic', 'emissive')
COLOURSPACE = {'albedo': 'sRGB', 'emissive': 'sRGB', 'normal': 'Non-Color', 'orm': 'Non-Color', 'curvature': 'Non-Color'}
LOCK = '~/agent-work/research/2026-10-20/T1032/render.lock'
EMPTY = {'normal': (0.5, 0.5, 1.0), 'ao': (1.0, 1.0, 1.0), 'rmc': (0.5, 0.0, 0.5)}
COARSE = {'folds', 'weave', 'facets'}
DETAIL = {'cavity': 0.45, 'ao': 0.3, 'edge': 0.12, 'wear': 0.3}


def flat_maps(m):
    """Constant maps from the spec material: the bake.mode "flat" stand-in."""
    metal = 1.0 if m['kind'] == 'metal' else 0.0
    glow = m['color'] if m['kind'] == 'emissive' else '#000000'
    return {'albedo': m['color'], 'normal': (0.5, 0.5, 1.0), 'orm': (1.0, m.get('roughness', 0.5), metal),
            'emissive': glow}


def save(path, size, value, colourspace):
    rgb = [int(value[i:i + 2], 16) / 255 for i in (1, 3, 5)] if isinstance(value, str) else list(value)
    img = bpy.data.images.new(path.stem, size, size, alpha=False)
    img.colorspace_settings.name = colourspace
    img.pixels.foreach_set(np.tile(np.array(rgb + [1.0], np.float32), size * size))
    img.filepath_raw, img.file_format = str(path), 'PNG'
    img.save()
    return str(path)


def flat(ctx, folder, size_of):
    mats = ctx.spec['materials']
    for sid, t in ctx.textures.items():
        size = size_of(t)
        mid = next((ctx.parts[p]['material'] for p in t['parts'] if ctx.parts[p]['material'] in mats), None)
        maps = flat_maps(mats[mid]) if mid else flat_maps({'kind': 'cloth', 'color': '#808080'})
        t.update({k: save(folder / f'{sid}_{k}.png', size, maps[k], COLOURSPACE[k]) for k in MAPS})
        t.update(baked_size=size, stub=True)
    return {'stub': True, 'todo': 'bake.mode cycles bakes from parts[].high', 'mode': 'flat'}


@contextlib.contextmanager
def held_lock():
    """Exclusive fcntl lock on CHAR3D_LOCK (the render lock): one bake or render at a time."""
    path = Path(os.path.expanduser(os.environ.get('CHAR3D_LOCK', LOCK)))
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'a') as f:
        t = time.perf_counter()
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield time.perf_counter() - t
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


@contextlib.contextmanager
def bake_scene(objs):
    """Cycles CPU; only objs render, garment solidify off, subdivision at render level so lows match the bake."""
    sc, vl = bpy.context.scene, bpy.context.view_layer
    saved = (sc.render.engine, sc.cycles.samples, sc.cycles.use_denoising, sc.cycles.use_adaptive_sampling)
    sc.render.engine, sc.cycles.device = 'CYCLES', 'CPU'
    sc.cycles.use_denoising = sc.cycles.use_adaptive_sampling = False
    col = vl.layer_collection.children.get('char3d_high')
    if col:
        col.exclude = False
    keep = set(objs)
    others = [ob for ob in vl.objects if ob not in keep and not ob.hide_render]
    state = [(ob, ob.hide_render, ob.hide_get()) for ob in objs]
    solid = [m for ob in objs for m in ob.modifiers if m.type == 'SOLIDIFY' and m.show_render]
    subs = [(m, m.levels) for ob in objs for m in ob.modifiers if m.type == 'SUBSURF']
    for ob in others:
        ob.hide_render = True
    for ob in objs:
        ob.hide_render = False
        ob.hide_set(False)
    for m in solid:
        m.show_render = m.show_viewport = False
    for m, _ in subs:
        m.levels = m.render_levels
    try:
        yield sc
    finally:
        for ob, hr, hv in state:
            ob.hide_render = hr
            ob.hide_set(hv)
        for ob in others:
            ob.hide_render = False
        for m in solid:
            m.show_render = m.show_viewport = True
        for m, lv in subs:
            m.levels = lv
        sc.render.engine, sc.cycles.samples, sc.cycles.use_denoising, sc.cycles.use_adaptive_sampling = saved
        if col:
            col.exclude = True


@contextlib.contextmanager
def ray_hidden(obs):
    """Lows that only cast bake rays must not shadow or occlude their own sources."""
    saved = [(ob, ob.visible_diffuse, ob.visible_shadow, ob.visible_glossy) for ob in obs]
    for ob in obs:
        ob.visible_diffuse = ob.visible_shadow = ob.visible_glossy = False
    try:
        yield
    finally:
        for ob, d, s, g in saved:
            ob.visible_diffuse, ob.visible_shadow, ob.visible_glossy = d, s, g


def high_of(part):
    """The part's high twin object, or None."""
    return bpy.data.objects.get(part['high']) if part.get('high') else None


def materials(obs):
    return {s.material for ob in obs for s in ob.material_slots if s.material and s.material.use_nodes}


def emits(mat):
    b = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    return bool(b) and (b.inputs['Emission Strength'].is_linked or b.inputs['Emission Strength'].default_value > 0)


def feed(nt, bsdf, name, dst, fallback):
    """Link a Principled input (its source when linked, else its value) into dst."""
    sock = bsdf.inputs[name] if bsdf else None
    if sock is not None and sock.is_linked:
        nt.links.new(sock.links[0].from_socket, dst)
        return
    v = sock.default_value if sock is not None else fallback
    if dst.type == 'RGBA':
        dst.default_value = (v, v, v, 1.0) if isinstance(v, float) else tuple(v)
    else:
        dst.default_value = v if isinstance(v, float) else v[0]


def attr_mask(nt, nodes, kinds):
    """Socket: max over kinds of |c3d_<kind>| / depth_m (the detail stage's stored offsets), clamped to 0-1."""
    out = None
    for kind, depth in kinds:
        a = nt.nodes.new('ShaderNodeAttribute')
        a.attribute_type, a.attribute_name = 'GEOMETRY', f'c3d_{kind}'
        ab, k = nt.nodes.new('ShaderNodeMath'), nt.nodes.new('ShaderNodeMath')
        ab.operation, k.operation, k.use_clamp = 'ABSOLUTE', 'MULTIPLY', True
        k.inputs[1].default_value = 1.0 / max(abs(depth), 1e-6)
        nt.links.new(a.outputs['Fac'], ab.inputs[0])
        nt.links.new(ab.outputs[0], k.inputs[0])
        nodes += [a, ab, k]
        if out is not None:
            mx = nt.nodes.new('ShaderNodeMath')
            mx.operation = 'MAXIMUM'
            nt.links.new(out, mx.inputs[0])
            nt.links.new(k.outputs[0], mx.inputs[1])
            nodes.append(mx)
            k = mx
        out = k.outputs[0]
    return out


@contextlib.contextmanager
def emit(mats, channel, layers=((), ())):
    """Rewire each material to emit one channel: albedo (sRGB 239 white for a clear shell without a Principled BSDF, e.g. the
    cornea), emissive, rmc = (roughness, metallic, curvature), or masks = (overlay layers, wear layers, 0)."""
    added, outputs = [], []
    for mat in mats:
        nt = mat.node_tree
        outs = [n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL']
        outputs += [(n, n.is_active_output) for n in outs]
        em, out = nt.nodes.new('ShaderNodeEmission'), nt.nodes.new('ShaderNodeOutputMaterial')
        nodes = [em, out]
        added.append((nt, nodes))
        nt.links.new(em.outputs[0], out.inputs['Surface'])
        for n in outs:
            n.is_active_output = False
        out.is_active_output, out.target = True, 'ALL'
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if channel == 'albedo':
            feed(nt, bsdf, 'Base Color', em.inputs['Color'], (0.87, 0.87, 0.87, 1.0))
        elif channel == 'emissive':
            feed(nt, bsdf if emits(mat) else None, 'Emission Color', em.inputs['Color'], (0.0, 0.0, 0.0, 1.0))
        elif channel == 'masks':
            comb = nt.nodes.new('ShaderNodeCombineColor')
            nodes.append(comb)
            for sock, kinds in zip(('Red', 'Green'), layers):
                if kinds:
                    nt.links.new(attr_mask(nt, nodes, kinds), comb.inputs[sock])
            nt.links.new(comb.outputs['Color'], em.inputs['Color'])
        else:
            comb, geo, ramp = (nt.nodes.new(k) for k in ('ShaderNodeCombineColor', 'ShaderNodeNewGeometry',
                                                          'ShaderNodeValToRGB'))
            nodes += [comb, geo, ramp]
            ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[1].position = 0.4, 0.6
            feed(nt, bsdf, 'Roughness', comb.inputs['Red'], 0.5)
            feed(nt, bsdf, 'Metallic', comb.inputs['Green'], 0.0)
            nt.links.new(geo.outputs['Pointiness'], ramp.inputs['Fac'])
            nt.links.new(ramp.outputs['Color'], comb.inputs['Blue'])
            nt.links.new(comb.outputs['Color'], em.inputs['Color'])
    try:
        yield
    finally:
        for nt, nodes in added:
            for n in nodes:
                nt.nodes.remove(n)
        for n, active in outputs:
            n.is_active_output = active


def target(lows, img):
    """Point every low material's active image node at img; returns the nodes to remove."""
    nodes = []
    for mat in materials(lows):
        n = mat.node_tree.nodes.new('ShaderNodeTexImage')
        n.image = img
        mat.node_tree.nodes.active = n
        nodes.append((mat.node_tree, n))
    return nodes


def select(obs, active):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in obs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = active


def bake_pass(kind, jobs, size, b, layers=((), ())):
    """One map for a set; jobs = [(targets, sources, cage_m)]: selected-to-active from sources, or targets from
    their own surfaces when sources is empty; only AO sees the scene."""
    sc = bpy.context.scene
    img = bpy.data.images.new(f'_c3d_bake_{kind}', size, size, alpha=True, float_buffer=True)
    img.colorspace_settings.name = 'Non-Color'
    img.pixels.foreach_set(np.full(size * size * 4, -1.0, np.float32))
    btype = {'normal': 'NORMAL', 'ao': 'AO'}.get(kind, 'EMIT')
    sc.cycles.samples = b.get('samples', {}).get(kind, 16 if kind == 'ao' else 1)
    bk = sc.render.bake
    bk.target, bk.margin, bk.use_clear, bk.normal_space = 'IMAGE_TEXTURES', 0, False, 'TANGENT'
    bk.use_cage = False
    targets, sources = [t for j in jobs for t in j[0]], [s for j in jobs for s in j[1]]
    paired, selfs = [t for ts, srcs, _ in jobs if srcs for t in ts], [t for ts, srcs, _ in jobs if not srcs for t in ts]
    shown = [ob for ob in bpy.context.view_layer.objects if ob is not None and not ob.hide_render]
    with emit(materials(sources + selfs), kind, layers) if btype == 'EMIT' else contextlib.nullcontext(), ray_hidden(paired):
        nodes = target(targets, img)
        for ts, srcs, cage in jobs:
            if kind != 'ao':
                job = {*ts, *srcs}
                for ob in shown:
                    ob.hide_render = ob not in job
            bk.use_selected_to_active = bool(srcs)
            bk.cage_extrusion, bk.max_ray_distance = cage, 2 * cage
            select(ts + srcs, ts[0])
            bpy.ops.object.bake(type=btype)
        for ob in shown:
            ob.hide_render = False
        for nt, n in nodes:
            nt.nodes.remove(n)
    px = np.empty(size * size * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(size, size, 4)[..., :3]


def blur(x, r=1):
    """Box blur of radius r (edge-clamped) over the first two axes."""
    pad = np.pad(x, [(r, r), (r, r)] + [(0, 0)] * (x.ndim - 2), mode='edge')
    c = np.cumsum(np.cumsum(pad, 0), 1)
    c = np.pad(c, [(1, 0), (1, 0)] + [(0, 0)] * (x.ndim - 2))
    k, h, w = 2 * r + 1, x.shape[0], x.shape[1]
    return (c[k:k + h, k:k + w] - c[:h, k:k + w] - c[k:k + h, :w] + c[:h, :w]) / (k * k)


def up2(x):
    """2x upsample: nearest, then a 3x3 box to remove the blocks."""
    return blur(np.repeat(np.repeat(x, 2, 0), 2, 1))


def fill(px, empty):
    """Push-pull gutter fill: uncovered texels (still -1) take the coverage-weighted average of a mip pyramid, so seams
    and mips see each island's own smooth colour instead of streaked edge texels; an empty map gets `empty`."""
    cov = (px[..., 0] >= 0).astype(np.float32)
    if cov.all():
        return px.copy()
    if not cov.any():
        return np.broadcast_to(np.array(empty, np.float32), px.shape).copy()
    levels, c, w = [], px * cov[..., None], cov
    while c.shape[0] > 1 and c.shape[0] % 2 == 0:
        levels.append((c, w))
        h = c.shape[0] // 2
        c, w = c.reshape(h, 2, h, 2, 3).sum((1, 3)), w.reshape(h, 2, h, 2).sum((1, 3))
    out = np.where(w[..., None] > 0, c / np.maximum(w, 1e-9)[..., None], np.array(empty, np.float32))
    for c, w in reversed(levels):
        a = np.minimum(w, 1.0)[..., None]
        out = a * c / np.maximum(w, 1e-9)[..., None] + (1 - a) * up2(out)
    return np.where(cov[..., None] > 0, px, out).astype(np.float32)


def relief(normal, cov):
    """Signed fine relief from the tangent normal map's divergence (convex > 0), scaled by its 98th percentile to -1..1."""
    div = np.gradient(2 * normal[..., 0] - 1, axis=1) + np.gradient(2 * normal[..., 1] - 1, axis=0)
    div = blur(div) * cov
    scale = np.percentile(np.abs(div[cov > 0]), 98) if cov.any() else 0.0
    return np.clip(div / max(scale, 1e-6), -1.0, 1.0)


def detail(albedo, orm, normal, cov, masks, overlay, d):
    """Albedo/ORM detail on the baked fills: grime in cavities (normal-map relief) and AO, lighter worn ridges, faded worn
    zones (masks G), and the overlay material (e.g. gold embroidery thread) where masks R."""
    k = {**DETAIL, **d}
    r = relief(normal, cov)
    grime = np.clip(k['cavity'] * np.maximum(-r, 0) + k['ao'] * (1 - orm[..., 0]), 0, 1)[..., None]
    albedo = albedo * (1 - grime) + albedo * np.array(srgb_to_linear('#4a3b2a')[:3]) * 2 * grime
    albedo = albedo + (np.minimum(albedo * 1.5, 1.0) - albedo) * (k['edge'] * np.maximum(r, 0))[..., None]
    if masks is not None:
        wear = masks[..., 1:2] * k['wear']
        albedo = albedo + (np.minimum(albedo * 1.3 + 0.03, 1.0) - albedo) * wear
        orm[..., 1] = np.clip(orm[..., 1] + 0.15 * wear[..., 0], 0, 1)
        if overlay:
            a = np.clip((masks[..., 0] - 0.05) / 0.3, 0, 1)
            thread = np.array(overlay['colour'])[None, None] * (0.6 + 0.4 * masks[..., 0:1])
            albedo = albedo * (1 - a[..., None]) + thread * a[..., None]
            orm[..., 1] = orm[..., 1] * (1 - a) + overlay['roughness'] * a
            orm[..., 2] = orm[..., 2] * (1 - a) + overlay['metallic'] * a
    return np.clip(albedo, 0, 1), orm


def to_srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def write(path, rgb, colourspace):
    size = rgb.shape[0]
    img = bpy.data.images.new(path.stem, size, size, alpha=False)
    img.colorspace_settings.name = colourspace
    rgba = np.concatenate([np.clip(rgb, 0.0, 1.0), np.ones((size, size, 1), np.float32)], axis=2)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.filepath_raw, img.file_format = str(path), 'PNG'
    img.save()
    bpy.data.images.remove(img)
    return str(path)


def owns(pid, names):
    return any(pid == p or pid.startswith(p + '.') for p in names)


def set_layers(ctx, pids):
    """Detail layers on the set's parts: (overlay kinds with depth, wear kinds with depth, overlay material or None)."""
    lys = [ly for ly in ctx.spec.get('detail', {}).get('layers', []) if any(owns(p, ly.get('parts', [])) for p in pids)]
    depth = lambda ly: ly.get('depth_m') or 1e-3  # noqa: E731
    over = [ly for ly in lys if ly.get('material') in ctx.spec.get('materials', {})]
    wear = tuple((ly['kind'], depth(ly)) for ly in lys if ly['kind'] == 'wear')
    m = ctx.spec['materials'][over[0]['material']] if over else None
    mat = m and {'colour': srgb_to_linear(m['color'])[:3], 'roughness': m.get('roughness', 0.4),
                 'metallic': 1.0 if m['kind'] == 'metal' else 0.0}
    return tuple((ly['kind'], depth(ly)) for ly in over), wear, mat


def bake_set(ctx, sid, t, size, b, folder):
    """Every wanted map of one set (AO at half size), push-pull filled, detailed and packed into the published PNGs
    (+ curvature for wear masks); returns (means, stats)."""
    parts = [(ctx.parts[pid], bpy.data.objects[ctx.parts[pid]['object']]) for pid in t['parts']]
    singles = [ob for p, ob in parts if not high_of(p)]
    wanted = set(b.get('maps', ALL))
    passes = [k for k in ('normal', 'ao', 'albedo') if k in wanted]
    passes += ['rmc'] if wanted & {'roughness', 'metallic', 'curvature'} else []
    if 'emissive' in wanted and any(emits(m) for m in materials([ob for _, ob in parts])):
        passes.append('emissive')
    over, wear, overlay = set_layers(ctx, t['parts'])
    if (over or wear) and 'albedo' in wanted:
        passes.append('masks')
    jobs = [([ob], [high_of(p)], b.get('cage_m', 0.01)) for p, ob in parts if high_of(p)]
    jobs += [(singles, [], 0.0)] if singles else []
    half = size // 2 if size >= 512 else size
    raw, seconds = {}, {}
    for k in passes:
        s = time.perf_counter()
        raw[k] = bake_pass(k, jobs, half if k == 'ao' else size, b, (over, wear))
        seconds[k] = round(time.perf_counter() - s, 2)
    stats = {'pass_s': seconds}
    cov = raw['normal'][..., 0] >= 0 if 'normal' in raw else np.ones((size, size), bool)
    if 'normal' in raw:
        stats.update(cover_pct=round(100 * float(cov.mean()), 1),
                     normal_back_pct=round(100 * float((raw['normal'][cov][:, 2] < 0.5).mean()) if cov.any() else 0.0, 2))
    raw = {k: fill(v, EMPTY.get(k, (0.0, 0.0, 0.0))) for k, v in raw.items()}
    if 'ao' in raw and half != size:
        raw['ao'] = up2(raw['ao'])
    full = lambda v: np.full((size, size), v, np.float32)  # noqa: E731
    rmc = raw.get('rmc')
    orm = np.stack([raw['ao'][..., 0] if 'ao' in raw else full(1.0),
                    rmc[..., 0] if rmc is not None and 'roughness' in wanted else full(0.5),
                    rmc[..., 1] if rmc is not None and 'metallic' in wanted else full(0.0)], axis=2)
    normal = raw['normal'] if 'normal' in raw else np.stack([full(c) for c in EMPTY['normal']], axis=2)
    albedo = raw.get('albedo')
    if albedo is not None and b.get('detail', {}) is not False:
        albedo, orm = detail(albedo, orm, normal, cov.astype(np.float32), raw.get('masks'), overlay, b.get('detail') or {})
    out = {'albedo': to_srgb(albedo) if albedo is not None else np.full((size, size, 3), 0.5, np.float32),
           'normal': normal, 'orm': orm,
           'emissive': to_srgb(raw['emissive']) if 'emissive' in raw else np.zeros((size, size, 3), np.float32)}
    if rmc is not None and 'curvature' in wanted:
        out['curvature'] = np.repeat(rmc[..., 2:3], 3, axis=2)
    t.update({k: write(folder / f'{sid}_{k}.png', v, COLOURSPACE[k]) for k, v in out.items()})
    t.update(baked_size=size, stub=False)
    return {k: [round(float(c), 3) for c in v.reshape(-1, 3).mean(axis=0)] for k, v in out.items()}, stats


def plane(name, level):
    """A tilted flat grid far from the character (tilted so an object- or world-space bake would show as bias)."""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=8, y_subdivisions=8, size=0.4, location=(50.0, 50.0, 0.0))
    ob = bpy.context.active_object
    ob.data.transform(Euler((0.52, 0.0, 0.35)).to_matrix().to_4x4())
    ob.name = name
    if level:
        ob.modifiers.new('s', 'SUBSURF').levels = level
    return ob


def normal_bias(b):
    """Flat high over a flat low through the same bake settings: worst |mean - 0.5| of tangent R and G."""
    lo, hi = plane('_c3d_bias_low', 0), plane('_c3d_bias_high', 2)
    mat = bpy.data.materials.new('_c3d_bias')
    mat.use_nodes = True
    lo.data.materials.append(mat)
    hi.data.materials.append(mat)
    try:
        px = bake_pass('normal', [([lo], [hi], b.get('cage_m', 0.01))], 64, b)
    finally:
        for ob in (lo, hi):
            me = ob.data
            bpy.data.objects.remove(ob)
            bpy.data.meshes.remove(me)
        bpy.data.materials.remove(mat)
    cov = px[..., 0] >= 0
    return round(float(np.abs(px[cov][:, :2].mean(axis=0) - 0.5).max()), 4), round(float(cov.mean()), 3)


def run(ctx):
    b = ctx.spec.get('bake', {})
    folder = ctx.out / 'textures'
    folder.mkdir(parents=True, exist_ok=True)
    sizes = b.get('size', {})
    size_of = (lambda t: sizes.get('draft', 256)) if ctx.draft else (lambda t: sizes.get('final') or t['size'])
    if b.get('mode', 'flat') == 'flat':
        return flat(ctx, folder, size_of)
    baked = {p for t in ctx.textures.values() for p in t['parts']}
    lows = [ob for pid, ob in bu.mesh_parts(ctx) if pid in baked]
    highs = [high_of(ctx.parts[pid]) for pid in baked if high_of(ctx.parts[pid])]
    means, stats, seconds = {}, {}, {}
    paired = [bpy.data.objects[ctx.parts[pid]['object']] for pid in baked if high_of(ctx.parts[pid])]
    with held_lock() as waited, bake_scene(lows + highs), ray_hidden(paired):
        bias, bias_cover = normal_bias(b)
        for sid, t in ctx.textures.items():
            s = time.perf_counter()
            means[sid], stats[sid] = bake_set(ctx, sid, t, size_of(t), b, folder)
            seconds[sid] = round(time.perf_counter() - s, 2)
    return {'stub': False, 'mode': 'cycles', 'sets': len(ctx.textures), 'maps': len(MAPS) * len(ctx.textures),
            'size': {sid: t['baked_size'] for sid, t in ctx.textures.items()}, 'normal_bias': bias,
            'normal_bias_cover': bias_cover,
            'normal_back_pct': max((v.get('normal_back_pct', 0.0) for v in stats.values()), default=0.0),
            'cover_pct': {sid: v.get('cover_pct') for sid, v in stats.items()},
            'normal_back_per_set': {sid: v.get('normal_back_pct') for sid, v in stats.items()},
            'lock_wait_s': round(waited, 2), 'set_seconds': seconds,
            'pass_seconds': {sid: v.get('pass_s') for sid, v in stats.items()}, 'means': means}
