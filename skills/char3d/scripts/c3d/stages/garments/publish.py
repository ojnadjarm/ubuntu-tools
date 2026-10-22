"""Garment objects from fitted sheets (main, trim, ornament, pieces) registered as parts, plus their metrics."""
import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from ... import bpyutil as bu
from .base import NAME
from .geom import Geo
from .ornament import LIFT, decals, strip
from .surface import Surface

CORNER = 0.004
COVER_REACH = 0.1
COVER_RINGS = 2


def part(ctx, pid, geo, mat, attach, thick, merge=False):
    ob = geo.build(pid, thick, merge)
    ctx.add_part(pid, ob.name, NAME, mat, attach)
    return ob


def evaluated(ob, dg):
    """World verts, triangles and (quads, faces) of the evaluated mesh."""
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    tot = np.empty(len(me.polygons), np.int32)
    me.polygons.foreach_get('loop_total', tot)
    ev.to_mesh_clear()
    return bu.world_verts(ob, dg), int((tot - 2).sum()), (int((tot == 4).sum()), len(tot))


def self_pairs(ob, dg):
    """Unique crossing polygon pairs of the evaluated object (solidify included; the BVH overlap skips neighbours)."""
    t = BVHTree.FromObject(ob, dg)
    p = np.array(t.overlap(t), int).reshape(-1, 2)
    p = np.sort(p[p[:, 0] != p[:, 1]], 1)
    return len(np.unique(p, axis=0)) if len(p) else 0


def uv_missing(ob):
    """Faces without a UV map or with a zero-area UV polygon."""
    me = ob.data
    if not me.uv_layers:
        return len(me.polygons)
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers[0].data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2)
    start, tot = np.empty(len(me.polygons), np.int64), np.empty(len(me.polygons), np.int64)
    me.polygons.foreach_get('loop_start', start)
    me.polygons.foreach_get('loop_total', tot)
    nxt = np.arange(len(uv)) + 1
    nxt[start + tot - 1] = start
    cross = uv[:, 0] * uv[nxt, 1] - uv[nxt, 0] * uv[:, 1]
    return int((np.abs(np.add.reduceat(cross, start)) < 1e-12).sum())


def ring_ids(grid, side):
    return grid[0] if side == 'first_row' else grid[-1]


def shell(sheets, caps):
    """Geo of sheets (by index or key) closed by ladder caps [(key, row side, outward)]."""
    geo, grids = Geo(), {}
    for k, sh in sheets.items():
        grids[k] = geo.sheet(sh)
    for k, side, out in caps:
        geo.cap(ring_ids(grids[k], side).tolist(), np.asarray(out, float))
    return geo


def publish(ctx, g, env, built, below, thick):
    """Create the garment objects (main, trim, decals, pieces) from fitted sheets and register them as parts."""
    gid = g['id']
    attach = g.get('attach', 'hips')
    objects = []
    if built.split:
        for side, sh in built.sheets.items():
            geo = shell({side: sh}, [c for c in built.caps if c[0] == side])
            pid = gid if side == attach.rsplit('.', 1)[-1] else f'{gid}.{side}'
            objects.append(part(ctx, pid, geo, g['material'], f'foot.{side}', thick))
    else:
        objects.append(part(ctx, gid, shell(built.sheets, built.caps), g['material'], attach, thick))
    own = Surface.of_sheets([(sh, thick) for sh in built.sheets.values()])
    trim = g.get('trim')
    if trim:
        geo, w = Geo(), trim.get('width_m', 0.03) * env.s
        rows = {kv for e in trim['edges'] for kv in built.edges.get(e, []) if kv[1] in ('first_row', 'last_row')}
        for k, e in enumerate(trim['edges']):
            for key, side in built.edges.get(e, []):
                cut = [(w + CORNER * env.s) * ((key, r) in rows) for r in ('first_row', 'last_row')] if 'col' in side else None
                geo.sheet(strip(built.sheets[key], side, w, thick + LIFT * (1 + k % 2), crown=0.0012 * env.s, cut=cut))
        if geo.F:
            objects.append(part(ctx, f'{gid}.trim', geo, trim['material'], attach, 0.0015 * env.s))
    for kind in dict.fromkeys(d['kind'] for d in g.get('decals', [])):
        geo, ds = Geo(), [d for d in g['decals'] if d['kind'] == kind]
        if sum(decals(d, built, own, below, geo, env.s) for d in ds):
            objects.append(part(ctx, f'{gid}.{kind}', geo, ds[0]['material'], attach, 0))
    for suffix, (sheets, caps), mat, t in (built.pieces(built, own) if built.pieces else []):
        if sheets:
            geo = shell(dict(enumerate(sheets)), caps)
            objects.append(part(ctx, f'{gid}.{suffix}', geo, mat, attach, t, merge=suffix == 'buckle'))
    return objects


def inside_points(objects, body):
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    return [p for ob in objects for p in bu.world_verts(ob, dg) if body.inside(p)[0]]


def cull_covered(lower, uppers):
    """Delete the lower garment's faces lying straight under an upper garment (a ray along the vertex normal hits it within
    COVER_REACH), keeping COVER_RINGS edge rings beyond every uncovered vertex so gaps such as a front opening stay lined;
    the hidden layer can then never show through. Returns the number of faces deleted."""
    trees = []
    for ob in uppers:
        M = ob.matrix_world
        trees.append(BVHTree.FromPolygons([M @ v.co for v in ob.data.vertices], [tuple(p.vertices) for p in ob.data.polygons]))
    bm = bmesh.new()
    bm.from_mesh(lower.data)
    bm.normal_update()
    M, R = lower.matrix_world, lower.matrix_world.to_3x3()
    seen = set()
    for v in bm.verts:
        o, d = M @ v.co, (R @ v.normal).normalized()
        if not any(t.ray_cast(o + d * 1e-3, d, COVER_REACH)[0] is not None for t in trees):
            seen.add(v.index)
    for _ in range(COVER_RINGS):
        seen |= {e.other_vert(v).index for v in bm.verts if v.index in seen for e in v.link_edges}
    gone = [f for f in bm.faces if not any(v.index in seen for v in f.verts)]
    bmesh.ops.delete(bm, geom=gone, context='FACES')
    bm.to_mesh(lower.data)
    bm.free()
    lower.data.update()
    return len(gone)
