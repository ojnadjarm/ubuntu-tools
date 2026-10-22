"""Stage qa_asset: game-asset probes once per build (tris, quads, skin, UV range and overlap, texel density, texture sets,
skeleton) -> qa/asset.json for qa_metrics."""
import json
import os

import bpy
import numpy as np

from .. import bpyutil as bu
from .qa_bake import is_hair
from .uv import hidden_faces

NAME = 'qa_asset'
UV_TOL = 1e-4
MAPS = ('albedo', 'normal', 'orm', 'emissive')


def influences(ob, deform):
    """Max deform influences on any vertex and the count of vertices with none."""
    idx = {vg.index for vg in ob.vertex_groups if vg.name in deform}
    counts = [sum(1 for g in v.groups if g.group in idx and g.weight > 1e-6) for v in ob.data.vertices]
    return (max(counts), counts.count(0)) if counts else (0, 0)


def uv_outside(ob):
    if not ob.data.uv_layers:
        return len(ob.data.loops)
    uv = np.empty(len(ob.data.loops) * 2, np.float32)
    ob.data.uv_layers.active.data.foreach_get('uv', uv)
    return int(((uv < -UV_TOL) | (uv > 1 + UV_TOL)).reshape(-1, 2).any(1).sum())


def texel_px_cm(ob, size):
    """Area-weighted texel density (px/cm) of a part's active UVs at a square map size, mask-deleted faces excluded."""
    me = ob.data
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    if not n or not me.uv_layers:
        return 0.0
    loops, verts, poly = np.empty(n * 3, np.int32), np.empty(n * 3, np.int32), np.empty(n, np.int32)
    me.loop_triangles.foreach_get('loops', loops)
    me.loop_triangles.foreach_get('vertices', verts)
    me.loop_triangles.foreach_get('polygon_index', poly)
    shown = ~hidden_faces(ob)[poly]
    uv = np.empty(len(me.loops) * 2, np.float32)
    me.uv_layers.active.data.foreach_get('uv', uv)
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get('co', co)
    t = uv.reshape(-1, 2)[loops].reshape(n, 3, 2)[shown]
    w = co.reshape(-1, 3)[verts].reshape(n, 3, 3)[shown] * np.abs(np.array(ob.matrix_world.to_scale())).mean()
    a_uv = 0.5 * np.abs(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])).sum()
    a_cm2 = 0.5 * np.linalg.norm(np.cross(w[:, 1] - w[:, 0], w[:, 2] - w[:, 0]), axis=1).sum() * 1e4
    return round(float(np.sqrt(a_uv * size ** 2 / max(a_cm2, 1e-12))), 2)


def uv_tris(ob):
    """Active-UV loop triangles of a mesh as an (n, 3, 2) array."""
    me = ob.data
    if not me.uv_layers:
        return np.zeros((0, 3, 2), np.float32)
    me.calc_loop_triangles()
    loops = np.empty(len(me.loop_triangles) * 3, np.int32)
    me.loop_triangles.foreach_get('loops', loops)
    uv = np.empty(len(me.loops) * 2, np.float32)
    me.uv_layers.active.data.foreach_get('uv', uv)
    return uv.reshape(-1, 2)[loops].reshape(-1, 3, 2)


def coverage(ctx, sid, t):
    """The set's UV triangles saved as qa/uv_<set>.npz: the texel mask qa_metrics judges map content on."""
    obs = [bpy.data.objects.get(ctx.parts[p]['object']) for p in t.get('parts', []) if p in ctx.parts]
    tris = [uv_tris(ob) for ob in obs if ob and ob.type == 'MESH']
    path = ctx.out / 'qa' / f'uv_{sid}.npz'
    np.savez_compressed(path, tris=np.concatenate(tris) if tris else np.zeros((0, 3, 2), np.float32))
    return str(path)


def ngons(ob):
    n = np.empty(len(ob.data.polygons), np.int32)
    ob.data.polygons.foreach_get('loop_total', n)
    return int((n > 4).sum())


def uv_overlap(obs):
    """Faces whose UVs overlap another face of the same texture set (all objects edited together), per object."""
    obs = [ob for ob in obs if ob.visible_get() and ob.data.uv_layers]
    if not obs:
        return {}
    ts = bpy.context.scene.tool_settings
    sync = ts.use_uv_select_sync
    ts.use_uv_select_sync = True
    bpy.ops.object.select_all(action='DESELECT')
    for ob in obs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.uv.select_overlap()
    bpy.ops.object.mode_set(mode='OBJECT')
    ts.use_uv_select_sync = sync
    out = {}
    for ob in obs:
        sel = np.empty(len(ob.data.polygons), bool)
        ob.data.polygons.foreach_get('select', sel)
        out[ob.name] = int(sel.sum())
    return out


def stacked(pid, ids):
    """Right-side twin of a left part: its islands stack on the left one's by design (mirrored UVs)."""
    return pid.endswith('.R') and pid[:-2] + '.L' in ids


def texture_maps(t):
    """Per map: file, pixel size and colourspace as the set material loads it."""
    mat = bpy.data.materials.get(t.get('material') or '')
    imgs = {os.path.basename(bpy.path.abspath(n.image.filepath)): n.image
            for n in (mat.node_tree.nodes if mat and mat.node_tree else []) if n.type == 'TEX_IMAGE' and n.image}
    out = {}
    for m in MAPS:
        img = imgs.get(os.path.basename(t[m])) if t.get(m) else None
        out[m] = {'file': t.get(m), 'size': list(img.size) if img else None,
                  'colourspace': img.colorspace_settings.name if img else None}
    return out


def skeleton(arm):
    """Deform bone count, deform roots (no deform ancestor) and whether the rig object has its transforms applied."""
    if arm is None:
        return {'deform_bones': 0, 'deform_roots': 0, 'transforms_applied': False}
    deform = [b for b in arm.data.bones if b.use_deform]

    def root(b):
        p = b.parent
        while p and not p.use_deform:
            p = p.parent
        return p is None
    applied = np.allclose(arm.scale, 1, atol=1e-4) and np.allclose(arm.rotation_euler, 0, atol=1e-4)
    return {'deform_bones': len(deform), 'deform_roots': sum(map(root, deform)), 'transforms_applied': bool(applied)}


def run(ctx):
    rig = ctx.parts.get('rig')
    arm = bpy.data.objects[rig['object']] if rig else None
    deform = {b.name for b in arm.data.bones if b.use_deform} if arm else set()
    sets = {s['id']: s for s in ctx.spec.get('uv', {}).get('sets', [])}
    hero = ctx.spec.get('qa', {}).get('thresholds', {}).get('texel_px_cm_hero')
    parts, tris, quads, maxinf, unweighted, outside = {}, 0, 0.0, 0, 0, 0
    qtris, by_set = 0, {}
    for pid, ob in bu.mesh_parts(ctx):
        t, q = bu.tri_count(ob), bu.quads_pct(ob)
        hair = is_hair(ctx, pid)
        skinned = any(m.type == 'ARMATURE' for m in ob.modifiers)
        mi, un = influences(ob, deform) if skinned else (0, 0)
        uo = uv_outside(ob)
        sid = ctx.parts[pid].get('set')
        size = ctx.textures.get(sid, {}).get('size', 2048)
        target = sets.get(sid, {}).get('texel_px_cm')
        parts[pid] = {'tris': t, 'quads_pct': q, 'ngons': ngons(ob), 'hair': hair, 'max_influences': mi, 'unweighted': un,
                      'uv_outside': uo, 'set': sid, 'texel_px_cm': None if hair else texel_px_cm(ob, size),
                      'hero': bool(hero and target and target >= hero)}
        tris, maxinf, unweighted, outside = tris + t, max(maxinf, mi), unweighted + un, outside + uo
        if not hair:
            qtris, quads = qtris + t, quads + q * t
        if not hair and not stacked(pid, ctx.parts):
            by_set.setdefault(sid, []).append((pid, ob))
    for members in by_set.values():
        names = uv_overlap([ob for _, ob in members])
        for pid, ob in members:
            parts[pid]['uv_overlap'] = names.get(ob.name, 0)
    (ctx.out / 'qa').mkdir(parents=True, exist_ok=True)
    textures = {sid: {'size': t.get('size'), 'baked_size': t.get('baked_size'), 'stub': t.get('stub'),
                      'material': bool(bpy.data.materials.get(t.get('material') or '')),
                      'maps': texture_maps(t), 'uv': coverage(ctx, sid, t)} for sid, t in ctx.textures.items()}
    sizes = {sid: t.get('baked_size', t.get('size')) for sid, t in ctx.textures.items()}
    rep = {'lod0_tris': tris, 'quads_pct': round(quads / max(qtris, 1), 2),
           'ngons': sum(p['ngons'] for p in parts.values() if not p['hair']), 'max_influences': maxinf,
           'unweighted': unweighted, 'uv_outside': outside,
           'uv_overlap': sum(p.get('uv_overlap', 0) for p in parts.values()), 'texture_sets': sizes,
           'pow2': all(s and s & (s - 1) == 0 for s in sizes.values()), 'textures': textures,
           'skeleton': skeleton(arm), 'parts': parts}
    path = ctx.out / 'qa' / 'asset.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(rep, indent=1))
    ctx.files['qa_asset'] = str(path)
    return {k: rep[k] for k in ('lod0_tris', 'quads_pct', 'ngons', 'max_influences', 'unweighted', 'uv_outside',
                                'uv_overlap', 'pow2')}
