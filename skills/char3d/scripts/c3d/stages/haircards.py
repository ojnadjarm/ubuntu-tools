"""Stage haircards: game hair cards: a strand atlas rendered from our groom under the render lock, layered cards on the guides."""
import contextlib
import fcntl
import hashlib
import os
import shutil
import signal
import time
from pathlib import Path

import bpy
import numpy as np

from . import hair
from .materials import srgb_to_linear

NAME = 'haircards'
LOCK = os.environ.get('CHAR3D_LOCK', '~/agent-work/research/2026-10-20/T1032/render.lock')
LOCK_WAIT_S = 3600
CACHE = Path(os.path.expanduser(os.environ.get('CHAR3D_CACHE', '~/.local/share/char3d/cache'))) / 'haircards'
TILES = 8
CHANNELS = 'R root-tip, G strand id, B depth (1 = front), A alpha'
ATLAS_VERSION = 4
TILE_STRANDS = (520, 520, 440, 440, 280, 280, 120, 120)
TILE_CLUMPS = (5, 5, 4, 4, 3, 3, 2, 2)
TILE_SPREAD = (0.46, 0.46, 0.44, 0.44, 0.38, 0.38, 0.32, 0.32)
TILE_RADIUS_PX = (1.3, 0.45)
SEGS = {'beard': 8, 'moustache': 4, 'scalp': 6}
LAYERS = {'beard': 3, 'moustache': 2, 'scalp': 2}
LIFT = {'beard': 1.0, 'moustache': 0.6, 'scalp': 0.3}
TWIST = {'beard': 1.0, 'moustache': 1.0, 'scalp': 0.25}
WIDTH = {'scalp': 1.1}
TIP_WIDTH = 0.4
SHELL = 0.6
LAYER_STYLE = (  # tiles, width x, length x, lift x width, twist rad, every nth guide
    ((0, 1, 2, 3), 1.3, 0.92, 0.0, 0.0, 1),
    ((4, 5), 1.0, 1.0, 0.45, 0.35, 1),
    ((6, 7), 0.8, 0.97, 0.9, 0.6, 2))
CURL = 0.2
MARGIN = 0.004
NORMAL_K = 6.0
CULL_M, SKIN_GAP_M = 0.008, 0.001


@contextlib.contextmanager
def render_lock():
    """Hold the T1032 render lock (one render at a time, blocking in the kernel queue); yields the seconds waited."""
    path = Path(os.path.expanduser(LOCK))
    path.parent.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()

    def give_up(*_):
        raise TimeoutError(f'haircards: render lock {path} busy for {LOCK_WAIT_S} s')
    with open(path, 'a') as f:
        old = signal.signal(signal.SIGALRM, give_up)
        signal.alarm(LOCK_WAIT_S)
        try:
            fcntl.flock(f, fcntl.LOCK_EX)
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, old)
        try:
            yield time.perf_counter() - t0
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def read_guides(name):
    hc = bpy.data.hair_curves[name]
    m = len(hc.curves)
    pos = np.empty(len(hc.points) * 3, np.float32)
    hc.position_data.foreach_get('vector', pos)
    nrm, wid = np.empty(m * 3, np.float32), np.empty(m, np.float32)
    hc.attributes['c3d_normal'].data.foreach_get('vector', nrm)
    hc.attributes['c3d_width'].data.foreach_get('value', wid)
    return pos.reshape(m, -1, 3).astype(float), nrm.reshape(m, 3).astype(float), wid.astype(float)


def arc(g):
    return np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(g, axis=0), axis=1))])


def resample(g, n, frac=1.0):
    """n points along a polyline by arc length, up to frac of its length."""
    s = arc(g)
    t = np.linspace(0, frac * s[-1], n)
    return np.stack([np.interp(t, s, g[:, i]) for i in range(3)], 1)


def tile_strands(guides, widths, size, rng, k=24):
    """Tile strands (render space: x across the atlas, y down the lock, z depth): a few clumps per tile that pinch to
    pointed tips, sparse edges, staggered lengths and the hair stage's share of flyaways; the cards carry the bend."""
    length = float(np.median([arc(g)[-1] for g in guides]))
    tw, px = length / TILES, length / size
    depth = 0.4 * float(np.median(widths)) * LAYER_STYLE[0][1]
    s = np.linspace(0, 1, k)[None]
    paths = []
    for t in range(TILES):
        n, m = TILE_STRANDS[t], TILE_CLUMPS[t]
        centre = rng.uniform(-0.6, 0.6, m) * TILE_SPREAD[t] * tw
        own = rng.integers(0, m, (n, 1))
        u = centre[own] + rng.normal(0, 0.45, (n, 1)) * TILE_SPREAD[t] * tw / m
        pinch = 1 - 0.6 * s ** 1.3
        frac = rng.uniform(0.4 if t > 5 else 0.55, 1.0, (n, 1)) ** 0.7
        stray = np.where(rng.random((n, 1)) < hair.FLYAWAY, 0.25, 0.04) * tw
        wave = rng.uniform(0.02, 0.05) * tw * np.sin(2 * np.pi * (1.1 * s + rng.uniform())) * s
        x = (t + 0.5) * tw + centre[own] * (1 - 0.3 * s) + (u - centre[own]) * pinch + wave + rng.normal(0, 1, (n, 1)) * stray * s ** 1.5
        x = np.clip(x, t * tw + MARGIN * length, (t + 1) * tw - MARGIN * length)
        paths.append(np.stack([x, -s * frac * length, np.repeat(depth * rng.uniform(-1, 1, (n, 1)), k, 1)], 2))
    return np.concatenate(paths), (TILE_RADIUS_PX[0] * px, TILE_RADIUS_PX[1] * px), length, depth


def atlas_material(depth):
    mat = bpy.data.materials.new('c3d_atlas')
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    nd, ln = nt.nodes.new, nt.links.new
    info, geo, sep = nd('ShaderNodeHairInfo'), nd('ShaderNodeNewGeometry'), nd('ShaderNodeSeparateXYZ')
    rng = nd('ShaderNodeMapRange')
    rng.inputs['From Min'].default_value, rng.inputs['From Max'].default_value = -depth, depth
    comb, emit, out = nd('ShaderNodeCombineColor'), nd('ShaderNodeEmission'), nd('ShaderNodeOutputMaterial')
    ln(geo.outputs['Position'], sep.inputs[0])
    ln(sep.outputs['Z'], rng.inputs['Value'])
    ln(info.outputs['Intercept'], comb.inputs['Red'])
    ln(info.outputs['Random'], comb.inputs['Green'])
    ln(rng.outputs['Result'], comb.inputs['Blue'])
    ln(comb.outputs[0], emit.inputs['Color'])
    ln(emit.outputs[0], out.inputs['Surface'])
    return mat


def render_atlas(path, paths, radius, length, depth, size, samples):
    """Orthographic EEVEE render of the tile strands into one RGBA PNG (see CHANNELS) in a throwaway scene."""
    n, k = paths.shape[:2]
    hc = bpy.data.hair_curves.new('c3d_atlas')
    hc.add_curves([k] * n)
    hc.position_data.foreach_set('vector', paths.astype(np.float32).ravel())
    hair._attr(hc, 'radius', 'FLOAT', 'POINT', np.tile(np.linspace(*radius, k), n).astype(np.float32), 'value')
    hc.materials.append(atlas_material(depth))
    sc = bpy.data.scenes.new('c3d_atlas')
    ob = bpy.data.objects.new('c3d_atlas', hc)
    cam = bpy.data.objects.new('c3d_atlas_cam', bpy.data.cameras.new('c3d_atlas_cam'))
    for o in (ob, cam):
        sc.collection.objects.link(o)
    cam.data.type, cam.data.ortho_scale, cam.data.clip_end = 'ORTHO', length, 10.0
    cam.location = (length / 2, -length / 2, 1.0)
    sc.camera = cam
    r = sc.render
    r.engine, r.film_transparent, r.hair_type = 'BLENDER_EEVEE', True, 'STRIP'
    r.resolution_x = r.resolution_y = size
    r.resolution_percentage = 100
    r.image_settings.file_format, r.image_settings.color_mode, r.image_settings.color_depth = 'PNG', 'RGBA', '16'
    r.filepath = str(path)
    sc.eevee.taa_render_samples = samples
    sc.view_settings.view_transform = 'Raw'
    sc.view_settings.look = 'None'
    t = time.perf_counter()
    bpy.ops.render.render(write_still=True, scene=sc.name)
    seconds = time.perf_counter() - t
    mat, cam_data = hc.materials[0], cam.data
    bpy.data.objects.remove(ob)
    bpy.data.objects.remove(cam)
    bpy.data.cameras.remove(cam_data)
    bpy.data.hair_curves.remove(hc)
    bpy.data.materials.remove(mat)
    bpy.data.scenes.remove(sc)
    return seconds


def lay_cards(guides, normals, widths, kind, layers, rng, center=None):
    """Layered cards along each guide: dense inner layer, lifted and twisted outer layers; 3 verts across, V curl,
    tapering to a tip; the card faces the lock's root normal, or the direction from `center` (a head centre, so scalp
    cards lie on the skull along their whole path); returns per-vertex shell normals for volume shading."""
    segs = SEGS.get(kind, 6)
    verts, faces, uvs, nrm = [], [], [], []
    du = 1 / TILES
    for tiles, wf, lf, lift, twist, every in LAYER_STYLE[:layers]:
        for c in range(0, len(guides), every):
            g = resample(guides[c], segs + 1, lf)
            t = np.linspace(0, 1, segs + 1)[:, None]
            tan = np.gradient(g, axis=0)
            tan /= np.maximum(np.linalg.norm(tan, axis=1, keepdims=True), 1e-9)
            shell = np.broadcast_to(normals[c], g.shape) if center is None else g - center
            shell = shell / np.maximum(np.linalg.norm(shell, axis=1, keepdims=True), 1e-9)
            side = np.cross(tan, shell)
            side /= np.maximum(np.linalg.norm(side, axis=1, keepdims=True), 1e-9)
            up = np.cross(side, tan)
            a = twist * TWIST.get(kind, 1.0) * rng.choice([-1, 1])
            side, up = side * np.cos(a) + up * np.sin(a), up * np.cos(a) - side * np.sin(a)
            w = widths[c] * wf * WIDTH.get(kind, 1.0)
            half = (w / 2) * (1 - (1 - TIP_WIDTH) * t ** 1.5)
            lift_k = lift * LIFT.get(kind, 1.0)
            core = g + up * lift_k * widths[c] * (0.2 + 0.8 * t) + side * rng.uniform(-0.35, 0.35) * widths[c] * (lift > 0)
            u0 = int(rng.choice(tiles)) * du + MARGIN
            base = len(verts)
            for i in range(segs + 1):
                for j in (-1, 0, 1):
                    verts.append(core[i] + side[i] * j * half[i] + up[i] * CURL * half[i] * (1 - abs(j)))
                    uvs.append((u0 + (j + 1) / 2 * (du - 2 * MARGIN), 1 - MARGIN - (1 - 2 * MARGIN) * t[i, 0]))
                    nrm.append(SHELL * shell[i] + (1 - SHELL) * up[i] + 0.3 * j * side[i])
            for i in range(segs):
                for j in range(2):
                    q = base + 3 * i + j
                    faces.append((q, q + 1, q + 4, q + 3))
    nrm = np.array(nrm)
    return verts, faces, np.array(uvs, np.float32), nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)


def skin_bvh(ctx):
    """World BVH of the evaluated (masked) body skin."""
    from mathutils.bvhtree import BVHTree
    ob = bpy.data.objects[ctx.parts['body']['object']]
    return BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get()), ob.matrix_world.copy()


def clear_skin(verts, faces, uvs, nrm, segs, skin):
    """Cards outside the skin: vertices up to CULL_M behind it move onto it (+ SKIN_GAP_M), cards deeper are dropped
    (the qa garment_depth rule: nearest skin point within 5 cm, vertex behind its normal); returns arrays + counts."""
    from mathutils import Vector
    bvh, mw = skin
    mi = mw.inverted()
    v = np.array(verts, float)
    vb, fb = 3 * (segs + 1), 2 * segs
    n = len(v) // vb
    depth, moved = np.zeros(len(v)), 0
    for i, p in enumerate(v.tolist()):
        loc, nr, _, dist = bvh.find_nearest(mi @ Vector(p), 0.05)
        if loc is None:
            continue
        loc, nr = mw @ loc, (mw.to_3x3() @ nr).normalized()
        if (Vector(p) - loc).dot(nr) < -0.9 * dist:
            depth[i] = dist
            if dist <= CULL_M:
                v[i], moved = np.array(loc + nr * SKIN_GAP_M), moved + 1
    keep = depth.reshape(n, vb).max(1) <= CULL_M
    idx = np.flatnonzero(np.repeat(keep, vb))
    remap = np.full(len(v), -1)
    remap[idx] = np.arange(len(idx))
    f = np.array(faces).reshape(n, fb, 4)[keep].reshape(-1, 4)
    return (v[idx], [tuple(q) for q in remap[f]], uvs[idx], nrm[idx],
            {'moved': moved, 'dropped': int((~keep).sum()), 'max_mm': round(float(depth.max()) * 1000, 1)})


def atlas_maps(atlas, m, folder, hid):
    """Game maps of one groom from its strand atlas (see CHANNELS): albedo RGBA (root-dark gradient, per-strand jitter,
    depth shade; empty texels filled with the mean strand colour), tangent normal from depth, ORM, black emissive."""
    img = bpy.data.images.load(str(atlas), check_existing=True)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    r, g, d, a = px.reshape(h, w, 4).transpose(2, 0, 1)
    col = np.array(srgb_to_linear(m['color'])[:3], np.float32)
    shade = (0.8 + 0.3 * g) * (0.65 + 0.35 * d)
    rgb = (col * (0.45 + 0.55 * r[..., None])) * shade[..., None]
    hit = a > 0.05
    rgb[~hit] = rgb[hit].mean(0) if hit.any() else col
    height = d * a
    gy, gx = np.gradient(height)
    n = np.dstack([-gx * NORMAL_K, -gy * NORMAL_K, np.ones_like(gx)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    ao = 0.65 + 0.35 * np.where(hit, d, 1.0)
    maps = {'albedo': (np.dstack([rgb, a]), 'sRGB'), 'normal': (n * 0.5 + 0.5, 'Non-Color'),
            'orm': (np.dstack([ao, np.full_like(ao, m.get('roughness', 0.45)), np.zeros_like(ao)]), 'Non-Color'),
            'emissive': (np.zeros((h, w, 3), np.float32), 'sRGB')}
    out = {}
    for key, (arr, cs) in maps.items():
        path = folder / f'{hid}_{key}.png'
        if cs == 'sRGB':
            arr = np.concatenate([np.where(arr[..., :3] <= 0.0031308, 12.92 * arr[..., :3],
                                           1.055 * np.power(np.clip(arr[..., :3], 0, 1), 1 / 2.4) - 0.055),
                                  arr[..., 3:]], 2) if key == 'albedo' else arr
        rgba = arr if arr.shape[2] == 4 else np.dstack([arr, np.ones((h, w), np.float32)])
        im = bpy.data.images.new(f'{hid}_{key}', w, h, alpha=arr.shape[2] == 4)
        im.colorspace_settings.name = 'Non-Color'
        im.pixels.foreach_set(np.clip(rgba, 0, 1).astype(np.float32).ravel())
        im.filepath_raw, im.file_format = str(path), 'PNG'
        im.save()
        bpy.data.images.remove(im)
        out[key] = str(path)
    out['alpha_cover_pct'] = round(100.0 * float(a.mean()), 1)
    return out


def card_material(name, m, maps):
    """Principled fed by the groom's baked maps: albedo (+ alpha), ORM roughness, normal, emissive."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nd, ln = nt.nodes.new, nt.links.new
    b = nt.nodes['Principled BSDF']

    def tex(key, cs):
        n = nd('ShaderNodeTexImage')
        n.image = bpy.data.images.load(maps[key], check_existing=True)
        n.image.colorspace_settings.name = cs
        return n
    alb = tex('albedo', 'sRGB')
    ln(alb.outputs['Color'], b.inputs['Base Color'])
    ln(alb.outputs['Alpha'], b.inputs['Alpha'])
    orm = nd('ShaderNodeSeparateColor')
    ln(tex('orm', 'Non-Color').outputs['Color'], orm.inputs[0])
    ln(orm.outputs['Green'], b.inputs['Roughness'])
    nm = nd('ShaderNodeNormalMap')
    ln(tex('normal', 'Non-Color').outputs['Color'], nm.inputs['Color'])
    ln(nm.outputs['Normal'], b.inputs['Normal'])
    ln(tex('emissive', 'sRGB').outputs['Color'], b.inputs['Emission Color'])
    b.inputs['Sheen Weight'].default_value = 0.3
    b.inputs['Specular IOR Level'].default_value = 0.35
    mat.surface_render_method = 'DITHERED'
    mat.use_backface_culling = False
    return mat


def publish_set(ctx, groom):
    """The hair texture set = the groom maps: first groom's files, every card material by groom id."""
    sid = next((sid for sid, t in ctx.textures.items() if any(p in t['parts'] for p, _, _ in groom)), None)
    if sid is None or not groom:
        return None
    t = ctx.textures[sid]
    _, mat, maps = groom[0]
    size = bpy.data.images.load(maps['albedo'], check_existing=True).size[0]
    t.update({k: maps[k] for k in ('albedo', 'normal', 'orm', 'emissive')}, material=mat.name, baked_size=size,
             stub=False, materials={pid: m.name for pid, m, _ in groom}, grooms={pid: mp for pid, _, mp in groom})
    t.pop('curvature', None)
    return sid


def replace_mesh(ob, verts, faces, uvs, mat, normals):
    me = bpy.data.meshes.new(ob.data.name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    vi = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get('vertex_index', vi)
    me.uv_layers.new(name='UVMap').data.foreach_set('uv', uvs[vi].ravel())
    me.polygons.foreach_set('use_smooth', [True] * len(faces))
    me.normals_split_custom_set_from_vertices([tuple(n) for n in normals])
    me.materials.append(mat)
    old, ob.data = ob.data, me
    if not old.users:
        bpy.data.meshes.remove(old)
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def run(ctx):
    rng = np.random.default_rng(ctx.spec.get('seed', 1032) + 11)
    tex_dir = ctx.out / 'textures'
    tex_dir.mkdir(parents=True, exist_ok=True)
    samples = 16 if ctx.draft else 32
    metrics = {'stub': False, 'todo': [], 'atlas_files': {}, 'atlas': {}, 'atlas_channels': CHANNELS, 'tiles': TILES,
               'cards': {}, 'cards_tris': {}, 'render_s': 0.0}
    metrics['drape'] = hair.drape(ctx)
    jobs = []
    for h in ctx.spec['hair']:
        cid = ctx.parts.get(h['id'], {}).get('cards', h['id'])
        part = ctx.parts.get(cid, {})
        if 'guides' not in part:
            metrics['todo'].append(f'{h["id"]}: no guide set from the hair stage')
            continue
        size = h.get('cards', {}).get('atlas', 2048) // (2 if ctx.draft else 1)
        jobs.append((h, part, size, *read_guides(part['guides'])))
    renders = []
    for h, part, size, guides, normals, widths in jobs:
        path = tex_dir / f'{h["id"]}_atlas.png'
        paths, radius, length, depth = tile_strands(guides, widths, size, rng)
        key = hashlib.sha1(np.ascontiguousarray(paths, np.float32).tobytes()
                           + repr((radius, length, depth, size, samples, CHANNELS, ATLAS_VERSION)).encode()).hexdigest()[:16]
        cached = CACHE / f'{key}.png'
        if cached.exists():
            shutil.copyfile(cached, path)
        else:
            renders.append((path, cached, paths, radius, length, depth, size))
        metrics['atlas_files'][h['id']], metrics['atlas'][h['id']] = str(path), size
    metrics['cache'] = 'hit' if not renders else 'miss'
    if renders:
        CACHE.mkdir(parents=True, exist_ok=True)
        with render_lock() as wait:
            metrics['lock_wait_s'] = round(wait, 2)
            for path, cached, *args in renders:
                metrics['render_s'] += render_atlas(path, *args, samples)
                shutil.copyfile(path, cached)
    groom, skin = [], skin_bvh(ctx)
    metrics['skin_clear'], metrics['alpha_cover_pct'] = {}, {}
    for h, part, size, guides, normals, widths in jobs:
        layers = min(h.get('cards', {}).get('layers', LAYERS.get(h['kind'], 2)), len(LAYER_STYLE))
        center = np.array(ctx.landmarks['head']) if h['kind'] == 'scalp' else None
        verts, faces, uvs, nrm = lay_cards(guides, normals, widths, h['kind'], layers, rng, center)
        verts, faces, uvs, nrm, metrics['skin_clear'][h['id']] = clear_skin(verts, faces, uvs, nrm,
                                                                            SEGS.get(h['kind'], 6), skin)
        m = ctx.spec['materials'][h['material']]
        maps = atlas_maps(metrics['atlas_files'][h['id']], m, tex_dir, h['id'])
        mat = card_material(f'{h["id"]}.cards', m, maps)
        metrics['cards_tris'][h['id']] = replace_mesh(bpy.data.objects[part['object']], verts, faces, uvs, mat, nrm)
        groom.append((ctx.parts.get(h['id'], {}).get('cards', h['id']), mat, maps))
        metrics['alpha_cover_pct'][h['id']] = maps['alpha_cover_pct']
        metrics['cards'][h['id']] = len(faces) // (2 * SEGS.get(h['kind'], 6))
    metrics['texture_set'] = publish_set(ctx, groom)
    metrics['render_s'] = round(metrics['render_s'], 2)
    metrics['tris'] = sum(metrics['cards_tris'].values())
    metrics['stub'] = bool(metrics['todo'])
    return metrics
