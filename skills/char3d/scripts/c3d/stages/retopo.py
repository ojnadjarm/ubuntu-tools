"""Stage retopo: the game low per part fitted to a per-part LOD0 budget (construction mesh un-subdivided, decimated or remeshed)."""
import math
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils.bvhtree import BVHTree

from .. import bpyutil as bu

NAME = 'retopo'
LOD0 = 60000
FLEX = {'garments', 'props'}
CARD_M = 0.0015
MIN_QUADS = 88.0
DEV_FRAC = 0.03
IM_HOME = Path('~/.local/share/char3d/bin/instant-meshes').expanduser()


def instant_meshes_bin():
    """Instant Meshes CLI (BSD-3): $CHAR3D_INSTANT_MESHES, PATH, or the char3d data dir."""
    for p in (os.environ.get('CHAR3D_INSTANT_MESHES'), shutil.which('instant-meshes'), str(IM_HOME)):
        if p and os.access(p, os.X_OK):
            return p
    return None


def quads(ob):
    """Share (%) of the evaluated game mesh's faces that are quads."""
    ev = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    n = np.empty(len(me.polygons), np.int32)
    me.polygons.foreach_get('loop_total', n)
    ev.to_mesh_clear()
    return round(100 * float((n == 4).mean()), 2) if len(n) else 0.0


def swap(ob, me):
    """Make `me` the object's mesh under the old name; the old mesh is freed."""
    old = ob.data
    if old is me:
        return
    ob.data = me
    name = old.name
    bpy.data.meshes.remove(old)
    me.name = name


def sheet(me):
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get('co', co)
    return co.reshape(-1, 3)


def deviation(src, dst):
    """Max distance (m) from the source mesh's vertices to the reduced surface."""
    bvh = BVHTree.FromPolygons([tuple(v) for v in sheet(dst)], [tuple(p.vertices) for p in dst.polygons])
    pts = sheet(src)[::2]
    return max((bvh.find_nearest(p)[3] or 0.0) for p in pts) if len(pts) else 0.0


def thin_to_card(ob):
    """A shell thinner than CARD_M (decals) ships single-sided: its solidify is off in the game mesh."""
    hit = [m for m in ob.modifiers if m.type == 'SOLIDIFY' and m.show_viewport and abs(m.thickness) <= CARD_M]
    for m in hit:
        m.show_viewport = False
    return bool(hit)


def unsubdivide(ob, budget):
    """Quad-preserving un-subdivision: the iteration count closest to the budget that keeps quads and silhouette."""
    base = ob.data
    t0 = bu.tri_count(ob)
    ext = np.ptp(sheet(base), 0) if len(base.vertices) else np.zeros(3)
    tol = DEV_FRAC * float(ext.min())
    best, best_k, score = base, 0, abs(math.log(max(t0, 1) / budget))
    for k in (1, 2, 3):
        me = base.copy()
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.unsubdivide(bm, verts=bm.verts, iterations=k)
        bm.to_mesh(me)
        bm.free()
        ob.data = me
        t = bu.tri_count(ob)
        ok = quads(ob) >= MIN_QUADS and t < t0 and deviation(base, me) <= tol
        s = abs(math.log(max(t, 1) / budget))
        if ok and s < score:
            if best is not base:
                bpy.data.meshes.remove(best)
            best, best_k, score = me, k, s
        else:
            ob.data = base
            bpy.data.meshes.remove(me)
        if not ok or t <= budget:
            break
    ob.data = base
    swap(ob, best)
    return f'unsub{best_k}' if best_k else 'kept'


def walk(e, v, seen):
    """Edges continuing the loop of `e` past `v` (stops at boundaries, poles, non-quads or where it closes)."""
    out = []
    while not v.is_boundary and len(v.link_edges) == 4 and all(len(f.verts) == 4 for f in v.link_faces):
        nxt = next((x for x in v.link_edges if x is not e and not set(x.link_faces) & set(e.link_faces)), None)
        if nxt is None or nxt in seen:
            break
        seen.add(nxt)
        out.append(nxt)
        e, v = nxt, nxt.other_vert(v)
    return out


def edge_loop(e):
    seen = {e}
    return walk(e, e.verts[0], seen)[::-1] + [e] + walk(e, e.verts[1], seen)


def ring_walk(e, f, seen):
    out = []
    while f is not None and len(f.verts) == 4:
        opp = next(x for x in f.edges if not set(x.verts) & set(e.verts))
        if opp in seen:
            break
        seen.add(opp)
        out.append(opp)
        f = next((x for x in opp.link_faces if x is not f), None)
        e = opp
    return out


def edge_ring(e):
    seen = {e}
    fs = list(e.link_faces) + [None, None]
    return ring_walk(e, fs[0], seen)[::-1] + [e] + ring_walk(e, fs[1], seen)


def locked(e):
    """Edges a loop dissolve must keep: boundaries, seams, sharp edges, material borders."""
    return (e.is_boundary or e.seam or not e.smooth or len(e.link_faces) != 2
            or e.link_faces[0].material_index != e.link_faces[1].material_index)


def sag(loop):
    """How far the loop bows out of the straight line between its neighbour loops (m): what dissolving it loses."""
    on, err = set(loop), 0.0
    for v in {v for x in loop for v in x.verts}:
        cross = [x.other_vert(v).co for x in v.link_edges if x not in on]
        if len(cross) == 2:
            err = max(err, (v.co - (cross[0] + cross[1]) / 2).length)
    return err


def alternate_loops(bm, max_err):
    """Every other edge loop of each quad grid that bows less than `max_err`, by family: 'v' loops run along z, 'h' around it."""
    taken, out = set(), {'v': [], 'h': []}
    for e0 in bm.edges:
        if e0 in taken or locked(e0):
            continue
        prev = False
        for i, r in enumerate(edge_ring(e0)):
            if r in taken:
                prev = False
                continue
            loop = edge_loop(r)
            taken.update(loop)
            pick = not prev and not any(locked(x) for x in loop) and sag(loop) <= max_err
            if pick:
                d = np.array([(x.verts[1].co - x.verts[0].co).normalized().z for x in loop])
                out['v' if float(np.abs(d).mean()) > 0.7 else 'h'].append(loop)
            prev = pick
    return out


def loop_reduce(ob, budget, tol):
    """Quad-preserving reduction of a grid shell: dissolve every other edge loop, one family per round, while the silhouette holds."""
    base, done = ob.data, []
    for _ in range(4):
        if bu.tri_count(ob) <= budget:
            break
        best = None
        for fam in ('h', 'v'):
            me = ob.data.copy()
            bm = bmesh.new()
            bm.from_mesh(me)
            loops = alternate_loops(bm, tol / 3)[fam]
            if not loops:
                bm.free()
                bpy.data.meshes.remove(me)
                continue
            bmesh.ops.dissolve_edges(bm, edges=list({x for lp in loops for x in lp}), use_verts=True)
            bm.to_mesh(me)
            bm.free()
            cur, ob.data = ob.data, me
            dev, q = deviation(base, me), quads(ob)
            ob.data = cur
            if q >= MIN_QUADS and dev <= tol and (best is None or dev < best[1]):
                if best:
                    bpy.data.meshes.remove(best[0])
                best = (me, dev, fam)
            else:
                bpy.data.meshes.remove(me)
        if best is None:
            break
        if ob.data is not base:
            old = ob.data
            ob.data = best[0]
            bpy.data.meshes.remove(old)
        else:
            ob.data = best[0]
        done.append(best[2])
    if not done:
        return ''
    me, ob.data = ob.data, base
    swap(ob, me)
    return '+loops' + ''.join(done)


def apply_alone(ob, kind, **props):
    """The mesh data with one new modifier applied (the object's own stack muted while it evaluates)."""
    live = [m for m in ob.modifiers if m.show_viewport]
    for m in live:
        m.show_viewport = False
    mod = ob.modifiers.new('c3d_retopo', kind)
    for k, v in props.items():
        setattr(mod, k, v)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    ob.modifiers.remove(mod)
    for m in live:
        m.show_viewport = True
    swap(ob, me)


def decimate(ob, ratio):
    """Collapse decimation to `ratio`, then triangle pairs re-joined into quads."""
    apply_alone(ob, 'DECIMATE', decimate_type='COLLAPSE', ratio=max(0.01, min(ratio, 1.0)))
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.join_triangles(bm, faces=bm.faces, cmp_seam=False, cmp_sharp=False, cmp_uvs=False, cmp_vcols=False,
                             cmp_materials=True, angle_face_threshold=math.radians(40), angle_shape_threshold=math.radians(40))
    bm.to_mesh(ob.data)
    bm.free()
    return 'decimate'


def new_mesh(ob, verts, faces):
    me = bpy.data.meshes.new(ob.data.name + '.retopo')
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    for mat in ob.data.materials:
        me.materials.append(mat)
    me.shade_smooth()
    me.update()
    swap(ob, me)


def quadriflow(ob, faces):
    """QuadriFlow on a cleaned copy (merge by distance, dissolve degenerate); None when it refuses the mesh."""
    tmp = bpy.data.objects.new('c3d_quadriflow', ob.data.copy())
    bpy.context.scene.collection.objects.link(tmp)
    bm = bmesh.new()
    bm.from_mesh(tmp.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bm.to_mesh(tmp.data)
    bm.free()
    n0 = len(tmp.data.polygons)
    with bpy.context.temp_override(object=tmp, active_object=tmp, selected_objects=[tmp], selected_editable_objects=[tmp]):
        try:
            r = bpy.ops.object.quadriflow_remesh(mode='FACES', target_faces=max(int(faces), 8), seed=0,
                                                 use_preserve_boundary=True, use_mesh_symmetry=False)
        except RuntimeError:
            r = set()
    me = tmp.data
    done = 'FINISHED' in r and len(me.polygons) != n0
    if done:
        new_mesh(ob, sheet(me), [tuple(p.vertices) for p in me.polygons])
    bpy.data.objects.remove(tmp)
    bpy.data.meshes.remove(me)
    return 'quadriflow' if done else None


def instant_meshes(ob, faces, exe):
    """Instant Meshes batch (-d deterministic, -b boundary aligned, pure quads; it subdivides once, so ask for N/4)."""
    me = ob.data
    with tempfile.TemporaryDirectory(prefix='c3d_im_') as d:
        src, dst = Path(d) / 'in.obj', Path(d) / 'out.obj'
        with open(src, 'w') as f:
            f.writelines(f'v {x:.6f} {y:.6f} {z:.6f}\n' for x, y, z in sheet(me))
            f.writelines('f ' + ' '.join(str(i + 1) for i in p.vertices) + '\n' for p in me.polygons)
        r = subprocess.run([exe, '-d', '-b', '-f', str(max(int(faces) // 4, 8)), '-o', str(dst), str(src)],
                           capture_output=True, text=True)
        if r.returncode or not dst.exists():
            return None
        verts, polys = [], []
        for line in open(dst):
            if line.startswith('v '):
                verts.append([float(t) for t in line.split()[1:4]])
            elif line.startswith('f '):
                polys.append([int(t.split('/')[0]) - 1 for t in line.split()[1:]])
    if not polys:
        return None
    new_mesh(ob, verts, polys)
    return 'instant_meshes'


def remesh(ob, method, budget, factor, ratio):
    """Run the part's method toward `budget` evaluated tris; SDF methods fall back IM -> QuadriFlow -> decimate."""
    faces = budget / factor / 2
    if method == 'decimate':
        return decimate(ob, ratio if ratio is not None else budget / max(bu.tri_count(ob), 1))
    if method == 'instant_meshes':
        exe = instant_meshes_bin()
        done = exe and instant_meshes(ob, faces, exe)
        return done or ((quadriflow(ob, faces) or decimate(ob, budget / max(bu.tri_count(ob), 1))) + ':fallback')
    if method == 'quadriflow':
        exe = instant_meshes_bin()
        done = quadriflow(ob, faces) or (exe and instant_meshes(ob, faces, exe))
        return done or decimate(ob, budget / max(bu.tri_count(ob), 1)) + ':fallback'
    card = thin_to_card(ob)
    step = unsubdivide(ob, budget) if bu.tri_count(ob) > budget else 'kept'
    if bu.tri_count(ob) > budget:
        step += loop_reduce(ob, budget, DEV_FRAC * float(np.ptp(sheet(ob.data), 0).min()))
    return ('card+' if card else '') + step


def budgets(rows, flex, target):
    """Per-part LOD0 budgets: fixed parts keep theirs; flexible parts share what is left in proportion to their size."""
    fixed = sum(t for p, t in rows.items() if p not in flex)
    pool = sum(rows[p] for p in flex)
    scale = min(1.0, max(target - fixed, 0.1 * pool) / max(pool, 1))
    return {p: max(int(rows[p] * scale), 1) for p in flex}


def run(ctx):
    r = ctx.spec.get('retopo', {})
    default, per, ratios = r.get('default', 'construction'), r.get('parts', {}), r.get('ratio', {})
    parts = bu.mesh_parts(ctx)
    off = even = 0
    for _, ob in parts:
        for m in ob.modifiers:
            if m.type == 'SUBSURF' and m.show_viewport:
                m.show_viewport = False
                off += 1
            elif m.type == 'SOLIDIFY' and m.use_even_offset:  # spikes shell verts up to 0.3 m out at sharp folds
                m.use_even_offset = False
                even += 1
    rows = {pid: bu.tri_count(ob) for pid, ob in parts}
    keyed = {pid for pid, ob in parts if ob.data.shape_keys}
    flex = {pid for pid, _ in parts if (pid in per or ctx.parts[pid]['stage'] in FLEX) and pid not in keyed}
    budget = budgets(rows, flex, LOD0)
    method, tris, quad, todo = {}, {}, {}, []
    for pid, ob in parts:
        m = per.get(pid, default)
        if pid in keyed and m != 'construction':
            todo.append(f'{pid}:{m} (shape keys keep the construction mesh)')
        if pid in flex:
            factor = rows[pid] / max(sum(len(p.vertices) - 2 for p in ob.data.polygons), 1)
            method[pid] = remesh(ob, m, budget[pid], factor, ratios.get(pid))
        tris[pid], quad[pid] = bu.tri_count(ob), quads(ob)
        ctx.parts[pid]['tris'] = tris[pid]
    total = sum(tris.values())
    return {'stub': False, 'todo': todo, 'lod0_tris': total, 'target': LOD0, 'construction_tris': sum(rows.values()),
            'quads_pct': round(sum(quad[p] * tris[p] for p in tris) / max(total, 1), 2), 'subsurf_off': off, 'even_offset_off': even,
            'per_part': tris, 'budget': budget, 'method': method, 'instant_meshes': instant_meshes_bin() is not None}
