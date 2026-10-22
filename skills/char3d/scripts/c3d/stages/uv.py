"""Stage uv: one unique UV layout per texture set (islands scaled to equal density and packed across objects)."""
import bmesh
import bpy
import numpy as np
from bpy_extras.bmesh_utils import bmesh_linked_uv_islands

from .. import bpyutil as bu

NAME = 'uv'
HAND_RADIUS_M = 0.15
MAX_ASPECT = 4.0
HIDDEN_SCALE = 0.02


def game_uv(ob):
    """The UV layer the game asset ships (stage-private layers are named c3d_*); created when missing."""
    uv = next((u for u in ob.data.uv_layers if not u.name.startswith('c3d_')), None)
    uv = uv or ob.data.uv_layers.new(name='UVMap')
    ob.data.uv_layers.active = uv
    uv.active_render = True
    return uv


def edit(obs):
    """Multi-object edit mode on obs with every face selected."""
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    for ob in obs:
        ob.hide_set(False)
        ob.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.reveal()
    bpy.ops.mesh.select_all(action='SELECT')


def overlap_faces(obs):
    """Faces whose UVs overlap another face of any object in obs (uv.select_overlap, sync selection); left selected."""
    bpy.context.scene.tool_settings.use_uv_select_sync = True
    edit(obs)
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.uv.select_overlap()
    bpy.ops.object.mode_set(mode='OBJECT')
    n = 0
    for ob in obs:
        sel = np.empty(len(ob.data.polygons), bool)
        ob.data.polygons.foreach_get('select', sel)
        n += int(sel.sum())
    return n


def smart_project(ob, angle=1.15, selected_only=False):
    """Smart UV project of the whole part, or of only its selected faces into their own islands."""
    if selected_only:
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.mode_set(mode='EDIT')
    else:
        edit([ob])
    bpy.ops.uv.smart_project(angle_limit=angle, island_margin=0.002)
    bpy.ops.object.mode_set(mode='OBJECT')


def unique(ob, project):
    """Islands without self-overlap: re-project overlapping faces at smaller angles, then conformal, then one per face."""
    if project:
        smart_project(ob)
    for step in (0.5, 0.2, 0.05, 'conformal', 'reset', None):
        pack([ob], 0.002, 'AABB')
        if not overlap_faces([ob]) or step is None:
            return
        if isinstance(step, float):
            smart_project(ob, step, selected_only=True)
            continue
        if step == 'conformal':
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.uv.unwrap(method='CONFORMAL', margin=0.002)
            bpy.ops.object.mode_set(mode='OBJECT')
        else:
            own_islands(ob)


def own_islands(ob):
    """Each selected face becomes its own regular-polygon island (folded faces no projection can flatten)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    layer = bm.loops.layers.uv.active
    for i, f in enumerate(f for f in bm.faces if f.select):
        n = len(f.loops)
        for k, lp in enumerate(f.loops):
            a = 2 * np.pi * k / n
            lp[layer].uv = (2.0 * (i + 1) + 0.5 + 0.5 * np.cos(a), 0.5 + 0.5 * np.sin(a))
    bm.to_mesh(ob.data)
    bm.free()


def hidden_faces(ob):
    """Faces a vertex-group Mask modifier deletes (any vertex masked out): they never render, so need no texels."""
    me = ob.data
    keep = np.ones(len(me.vertices), bool)
    for md in ob.modifiers:
        if md.type != 'MASK' or md.mode != 'VERTEX_GROUP' or md.vertex_group not in ob.vertex_groups:
            continue
        gi = ob.vertex_groups[md.vertex_group].index
        grp = np.array([any(g.group == gi and g.weight > md.threshold for g in v.groups) for v in me.vertices])
        keep &= ~grp if md.invert_vertex_group else grp
    if keep.all() or not len(me.polygons):
        return np.zeros(len(me.polygons), bool)
    start, lv = np.empty(len(me.polygons), np.int64), np.empty(len(me.loops), np.int64)
    me.polygons.foreach_get('loop_start', start)
    me.loops.foreach_get('vertex_index', lv)
    return ~np.logical_and.reduceat(keep[lv], start)


def shrink_hidden(obs):
    """Scale the UVs of mask-deleted faces by HIDDEN_SCALE about one point, so the pack spends no texels on them."""
    for ob in obs:
        hid = hidden_faces(ob)
        if not hid.any():
            continue
        me = ob.data
        start, total = np.empty(len(me.polygons), np.int64), np.empty(len(me.polygons), np.int64)
        me.polygons.foreach_get('loop_start', start)
        me.polygons.foreach_get('loop_total', total)
        loops = np.concatenate([np.arange(s, s + t) for s, t in zip(start[hid], total[hid])])
        uv = np.empty(len(me.loops) * 2, np.float64)
        me.uv_layers.active.data.foreach_get('uv', uv)
        uv = uv.reshape(-1, 2)
        uv[loops] *= HIDDEN_SCALE
        me.uv_layers.active.data.foreach_set('uv', uv.ravel())


def slice_long(ob):
    """Cut projected islands longer than MAX_ASPECT into pieces along their main axis, so packing fills the map."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    layer = bm.loops.layers.uv.active
    cut = 0
    for faces in bmesh_linked_uv_islands(bm, layer):
        loops = [lp for f in faces for lp in f.loops]
        uv = np.array([lp[layer].uv for lp in loops])
        centre = uv.mean(axis=0)
        axes = np.linalg.svd(uv - centre, full_matrices=False)[2]
        span = np.ptp((uv - centre) @ axes.T, axis=0)
        if span[1] <= 1e-9 or span[0] / span[1] <= MAX_ASPECT:
            continue
        n = int(np.ceil(span[0] / span[1] / MAX_ASPECT))
        lo = ((uv - centre) @ axes[0]).min()
        for f in faces:
            fc = np.mean([lp[layer].uv for lp in f.loops], axis=0)
            k = min(n - 1, int((float((fc - centre) @ axes[0]) - lo) / span[0] * n))
            for lp in f.loops:
                lp[layer].uv.x += 2.0 * k
        cut += n - 1
    bm.to_mesh(ob.data)
    bm.free()
    return cut


def pack(obs, margin, shape):
    """Equal texel density across every island of the set (mask-deleted faces shrunk), then one pack over its objects."""
    edit(obs)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode='OBJECT')
    shrink_hidden(obs)
    edit(obs)
    bpy.ops.uv.pack_islands(rotate=True, margin_method='FRACTION', margin=margin, shape_method=shape)
    bpy.ops.object.mode_set(mode='OBJECT')


def tri_density(ob, size):
    """Per rendered triangle (uv area in px^2, world area in cm^2, world centroid) of the base mesh."""
    me = ob.data
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    loops, verts, poly = np.empty(n * 3, np.int32), np.empty(n * 3, np.int32), np.empty(n, np.int32)
    me.loop_triangles.foreach_get('loops', loops)
    me.loop_triangles.foreach_get('vertices', verts)
    me.loop_triangles.foreach_get('polygon_index', poly)
    uv = np.empty(len(me.loops) * 2, np.float64)
    me.uv_layers.active.data.foreach_get('uv', uv)
    co = np.empty(len(me.vertices) * 3, np.float64)
    me.vertices.foreach_get('co', co)
    m = np.array(ob.matrix_world)
    w = (co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3])[verts].reshape(n, 3, 3)
    t = uv.reshape(-1, 2)[loops].reshape(n, 3, 2) * size
    a_uv = 0.5 * np.abs(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]))
    a_w = 0.5 * np.linalg.norm(np.cross(w[:, 1] - w[:, 0], w[:, 2] - w[:, 0]), axis=1) * 1e4
    shown = ~hidden_faces(ob)[poly]
    return a_uv[shown], a_w[shown], w.mean(axis=1)[shown]


def px_cm(a_uv, a_w):
    return round(float(np.sqrt(a_uv.sum() / max(a_w.sum(), 1e-12))), 2)


def head_hands(ctx, ob, size):
    """Texel density of the body above the neck and around each hand."""
    lm = {k: np.array(v) for k, v in ctx.landmarks.items()}
    a_uv, a_w, c = tri_density(ob, size)
    out = {}
    if 'neck' in lm:
        sel = c[:, 2] > lm['neck'][2]
        out['head'] = px_cm(a_uv[sel], a_w[sel])
    for h in ('hand.L', 'hand.R'):
        if h in lm:
            sel = np.linalg.norm(c - lm[h], axis=1) < HAND_RADIUS_M
            out[h] = px_cm(a_uv[sel], a_w[sel])
    return out


def run(ctx):
    u = ctx.spec.get('uv', {})
    sets, default = u.get('sets', []), u.get('default_set', 'main')
    spec_sets = {s['id']: s for s in sets}
    margin_px = u.get('margin_px', 8)
    groups, projected = {}, []
    for pid, ob in bu.mesh_parts(ctx):
        had = any(not x.name.startswith('c3d_') for x in ob.data.uv_layers)
        game_uv(ob)
        project = not had or bool(overlap_faces([ob]))
        unique(ob, project)
        if project:
            projected.append(pid)
        sid = next((s['id'] for s in sets if any(pid == p or pid.startswith(p + '.') for p in s['parts'])), default)
        ctx.parts[pid]['set'] = sid
        groups.setdefault(sid, []).append((pid, ob))
    overlaps, texel, regions, ok, cuts, fill = {}, {}, {}, {}, {}, {}
    for sid, members in groups.items():
        size = spec_sets.get(sid, {}).get('size', 2048)
        ctx.textures[sid] = {'size': size, 'parts': [p for p, _ in members]}
        obs = [ob for _, ob in members]
        cuts[sid] = sum(slice_long(ob) for pid, ob in members if pid in projected)
        shape = 'AABB' if ctx.draft else 'CONCAVE'
        pack(obs, margin_px / size, shape)
        for attempt in range(3):
            overlaps[sid] = overlap_faces(obs)
            if not overlaps[sid] or attempt == 2:
                break
            for ob in obs:
                if any(f.select for f in ob.data.polygons):
                    unique(ob, True)
            pack(obs, margin_px / size, shape)
        dens = [tri_density(ob, size)[:2] for ob in obs]
        texel[sid] = min(px_cm(*d) for d in dens)
        fill[sid] = round(100 * float(sum(d[0].sum() for d in dens)) / size ** 2, 1)
        floor = spec_sets.get(sid, {}).get('texel_px_cm', 0.0)
        ok[sid] = texel[sid] >= floor
        if 'body' in ctx.parts and ctx.parts['body'].get('set') == sid:
            regions = head_hands(ctx, bpy.data.objects[ctx.parts['body']['object']], size)
    head_floor = max((s.get('texel_px_cm', 0.0) for s in sets if s['id'] == ctx.parts.get('body', {}).get('set')),
                     default=0.0)
    return {'stub': False, 'sets': {k: len(v) for k, v in groups.items()}, 'smart_projected': projected,
            'margin_px': margin_px, 'island_cuts': cuts, 'overlap_faces': sum(overlaps.values()), 'overlap_per_set': overlaps,
            'texel_px_cm': texel, 'fill_pct': fill, 'fill_pct_min': min(fill.values(), default=0.0), 'texel_px_cm_min': min(texel.values(), default=0.0),
            'texel_head_hands': regions, 'texel_head_hands_min': min(regions.values(), default=0.0),
            'texel_head_hands_floor': head_floor, 'texel_ok': all(ok.values()) and all(v >= head_floor for v in regions.values())}
