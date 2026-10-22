"""Stage qa_bake: per clip frame and per shot, bake the geometry probes qa_metrics judges into <out>/qa/*.npz.

Two passes per clip keep it fast: a dense pass on every frame with subdivision off (joints, lowest vertex, framing,
lids at blink frames; vertices read only for parts whose world bounds can decide the value) and a full pass every
HEAVY_S seconds on the shipped mesh (self-x, garment depth, exact min z)."""
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from .. import bpyutil as bu
from . import render
from .lookdev import CAMERA

NAME = 'qa_bake'
DEPTH_STAGES = ('garments', 'hair', 'props')
GRIP_M = 0.12
DEPTH_MAX_M = 0.05
LID_VIEW_M = 0.4
LID_NEAR_M = 0.05
FACE_M = 0.09
MASK_W = 160
MASK_SAMPLES = 8
HEAVY_S = 1.0
SOLE_Z_M = 0.03
SOLES = ('heel.L', 'ball.L', 'heel.R', 'ball.R')
LAYER_REACH_M = 0.03
SHEETS = ('robe', 'mantle')
PEN = ('beard-robe', 'robe-body', 'layer-layer', 'hat-head', 'staff-hand')
HAIR_PTS_MAX = 20000


def run(ctx):
    sc = bpy.context.scene
    arm = bpy.data.objects[ctx.parts['rig']['object']]
    meshes = {pid: ob for pid, ob in bu.mesh_parts(ctx)}
    eyes = [pid for pid, p in ctx.parts.items() if p['object'] in ctx.face.get('eyes', [])]
    selfx = [pid for pid in meshes if not is_hair(ctx, pid)]
    depth = [pid for pid in meshes if ctx.parts[pid]['stage'] in DEPTH_STAGES] if 'body' in meshes else []
    occl = lid_occluders(ctx, meshes, eyes)
    roles = sorted(ctx.bones)
    views = shot_views(ctx)
    margins = {sid: np.full(v['n'], np.nan) for sid, v in views.items()}
    masks = {sid: {} for sid in views}
    (ctx.out / 'qa').mkdir(parents=True, exist_ok=True)
    staff = held_prop(ctx, meshes)
    staff_parts = [pid for pid in meshes if staff and pid.split('.')[0] == staff[0].split('.')[0]]
    layers = layer_pairs(ctx, meshes)
    grp = pen_groups(ctx, meshes, depth)
    with subdivision(meshes, False):
        soles, grip0 = rest_probes(ctx, arm, meshes, staff)
    heavy_frames = 0
    for cid, clip in ctx.clips.items():
        arm.animation_data.action = bpy.data.actions[clip['action']]
        frames = list(range(clip['start'], clip['end'] + 2))
        n = len(frames)
        rec = {'joints': [], 'min_z': np.zeros(n), 'lid': np.full((n, len(eyes)), np.nan),
               'self_x': np.zeros((n, len(selfx)), int), 'depth': np.zeros((n, len(depth))), 'heavy': np.zeros(n, bool),
               'low_part': np.zeros(n, int), 'soles': np.zeros((n, len(soles), 3)), 'grip': np.zeros((n, 2, 3)),
               'staff_low': np.full(n, np.nan), 'layer': np.zeros((n, len(layers))), 'pen': np.zeros((n, len(PEN)))}
        pids = list(meshes)
        blinks = set(clip['blinks']) if 'blinks' in clip else None
        near = None
        with subdivision(meshes, False):
            for i, f in enumerate(frames):
                sc.frame_set(f)
                fr = Frame(meshes, bpy.context.evaluated_depsgraph_get())
                rec['joints'].append([bu.bone_world_head(arm, ctx.bones[r]) for r in roles])
                rec['min_z'][i], low = fr.lowest()
                rec['low_part'][i] = pids.index(low) if low in pids else -1
                rec['soles'][i] = [fr.verts(pid)[vi] for pid, vi in soles]
                if staff:
                    rec['grip'][i] = grip_points(arm, ctx.bones[staff[1]], meshes[staff[0]])
                    rec['staff_low'][i] = min(float(fr.verts(pid)[:, 2].min()) for pid in staff_parts)
                if blinks is None or f in blinks:
                    geo = {pid: (fr.verts(pid), loop_tris(meshes[pid], fr.dg)) for pid in occl + eyes}
                    near = near or {e: near_tris(geo[e][0].mean(0), {o: geo[o] for o in occl}) for e in eyes}
                    fwd = head_forward(arm, ctx.bones.get('head'))
                    rec['lid'][i] = [lid_visible(geo[e][0], near[e], geo, fwd) for e in eyes]
                observe(ctx, arm, views, margins, masks, cid, f, fr, eyes)
        step = max(1, round(HEAVY_S * clip['fps']))
        picks = sorted(set(range(0, n - 1, step)) | {n - 2})
        rigid = {}
        for i in picks:
            sc.frame_set(frames[i])
            dg = bpy.context.evaluated_depsgraph_get()
            geo = {pid: (coords(ob, dg), loop_tris(ob, dg)) for pid, ob in meshes.items()}
            lows = {pid: float(v[:, 2].min()) for pid, (v, _) in geo.items() if len(v)}
            low = min(lows, key=lows.get)
            rec['min_z'][i], rec['low_part'][i] = lows[low], pids.index(low)
            for k, pid in enumerate(selfx):
                if pid not in rigid:
                    rec['self_x'][i, k] = self_pairs(meshes[pid], dg)
                    if not deforms(meshes[pid]):
                        rigid[pid] = rec['self_x'][i, k]
                else:
                    rec['self_x'][i, k] = rigid[pid]
            body = tree(*geo['body']) if depth else None
            rec['depth'][i] = [inside_depth(body, geo[pid][0], grip(ctx, arm, pid)) for pid in depth]
            rec['pen'][i, 1] = max((rec['depth'][i][k] for k in grp['robe_cols']), default=0.0)
            rec['pen'][i, 3] = max((rec['depth'][i][k] for k in grp['hat_cols']), default=0.0)
            rec['pen'][i, 4] = staff_hand(arm, ctx.bones[staff[1]], body, geo, grp['staff']) if staff and body is not None else 0.0
            rec['heavy'][i] = True
        with solidify(meshes, [pid for pair in layers for pid in pair] + grp['hat'], False):
            for i in picks:
                sc.frame_set(frames[i])
                dg = bpy.context.evaluated_depsgraph_get()
                rec['layer'][i] = layer_poke(meshes, layers, dg)
                rec['pen'][i, 0] = hair_depth(grp['hair'], grp['sheets'], meshes, dg)
                rec['pen'][i, 2] = max(rec['layer'][i], default=0.0)
                rec['pen'][i, 3] = max(rec['pen'][i, 3], hat_poke(grp['heads'], grp['hat'], meshes, dg))
        heavy_frames += len(picks)
        path = ctx.out / 'qa' / f'{cid}.npz'
        np.savez(path, joints=np.array(rec['joints']), roles=np.array(roles), min_z=rec['min_z'], fps=clip['fps'],
                 contacts=np.array(clip['contacts']), loop=clip['loop'], start=clip['start'], frames=np.array(frames),
                 blinks=np.array(clip.get('blinks', []), int), self_x=rec['self_x'], self_x_parts=np.array(selfx, str),
                 depth=rec['depth'], depth_parts=np.array(depth, str), lid=rec['lid'], eyes=np.array(eyes, str),
                 heavy=rec['heavy'], impacts=np.array(clip.get('impacts', []), int), low_part=rec['low_part'],
                 parts=np.array(pids, str), soles=rec['soles'], sole_names=np.array(SOLES[:len(soles)], str),
                 grip=rec['grip'] if staff else np.zeros((0, 2, 3)), grip_rest=grip0, staff_low=rec['staff_low'],
                 staff_plants=np.array(clip.get('staff_plants', []), int), layer=rec['layer'],
                 layer_pairs=np.array(['>'.join(pr) for pr in layers], str), pen=rec['pen'],
                 pen_pairs=np.array(PEN, str), pen_probed=np.array(grp['probed'], bool))
        ctx.files[f'qa:{cid}'] = str(path)
    extra = finish_shots(ctx, arm, views, margins, masks, meshes, eyes)
    out = {}
    for sid in views:
        out[f'framing:{sid}'] = margins[sid]
        if masks[sid]:
            out[f'mask:{sid}'] = np.array([masks[sid][i] for i in sorted(masks[sid])])
            out[f'mask_frames:{sid}'] = np.array(sorted(masks[sid]))
    ctx.files['qa_shots'] = str(ctx.out / 'qa' / 'shots.npz')
    np.savez(ctx.files['qa_shots'], **out)
    return {'clips': len(ctx.clips), 'shots': len(views), 'self_x_parts': len(selfx), 'depth_parts': len(depth),
            'eyes': len(eyes), 'heavy_frames': heavy_frames, 'shot_extra_frames': extra}


class subdivision:
    """Context manager: Subdivision modifiers on or off for the probes (restored on exit)."""

    def __init__(self, meshes, on):
        self.mods = [m for ob in meshes.values() for m in ob.modifiers if m.type == 'SUBSURF' and m.show_viewport != on]
        self.on = on

    def __enter__(self):
        for m in self.mods:
            m.show_viewport = self.on

    def __exit__(self, *exc):
        for m in self.mods:
            m.show_viewport = not self.on


class solidify:
    """Context manager: Solidify modifiers of the named parts on or off (restored on exit)."""

    def __init__(self, meshes, pids, on):
        self.mods = [m for pid in set(pids) for m in meshes[pid].modifiers if m.type == 'SOLIDIFY' and m.show_viewport != on]
        self.on = on

    def __enter__(self):
        for m in self.mods:
            m.show_viewport = self.on

    def __exit__(self, *exc):
        for m in self.mods:
            m.show_viewport = not self.on


def layer_pairs(ctx, meshes):
    """(lower, upper) cloth garment pairs (robe, mantle sheets: their normals face away from the body) by spec layer: the
    lower garment must stay behind the upper wherever it lies under it."""
    lay = {g['id']: g.get('layer', 0) for g in ctx.spec.get('garments', []) if g['id'] in meshes and g['kind'] in SHEETS}
    return [(a, b) for a in lay for b in lay if lay[a] < lay[b]]


def shell(ob):
    """(outward, inward) reach of the Solidify shell from the base surface, metres."""
    m = next((m for m in ob.modifiers if m.type == 'SOLIDIFY'), None)
    return (m.thickness * (1 + m.offset) / 2, m.thickness * (1 - m.offset) / 2) if m else (0.0, 0.0)


def layer_poke(meshes, pairs, dg):
    """Per pair: deepest lower-garment shell point past the upper garment's inner shell, measured straight along an upper
    face normal within LAYER_REACH_M (gaps such as a front opening have no face straight above), metres; 0 when clean."""
    base = {}
    out = []
    for lo, hi in pairs:
        for pid in (lo, hi):
            if pid not in base:
                base[pid] = (coords(meshes[pid], dg), loop_tris(meshes[pid], dg))
        V, (U, T) = base[lo][0], base[hi]
        box = (U.min(0) - LAYER_REACH_M, U.max(0) + LAYER_REACH_M)
        cand = np.flatnonzero(np.all((V > box[0]) & (V < box[1]), axis=1))
        worst = 0.0
        if len(cand):
            t = tree(U, T)
            pad = shell(meshes[lo])[0] + shell(meshes[hi])[1]
            for j in cand:
                loc, nrm, _, dist = t.find_nearest(Vector(V[j]), LAYER_REACH_M)
                if loc is None:
                    continue
                n = sum((h[1] for h in t.find_nearest_range(Vector(V[j]), dist + 1e-5)), Vector())
                sd = (Vector(V[j]) - loc).dot(n.normalized()) if n.length > 1e-9 else 0.0
                if abs(sd) >= 0.9 * dist:
                    worst = max(worst, sd + pad)
        out.append(worst)
    return out


def pen_groups(ctx, meshes, depth):
    """Parts and garment_depth columns behind each PEN pair (sheets and hats by spec garment kind)."""
    kind = {g['id']: g['kind'] for g in ctx.spec.get('garments', [])}
    sheets = [pid for pid in meshes if kind.get(pid) in SHEETS]
    hat = [pid for pid in meshes if kind.get(pid) == 'hat']
    hair = [ob for ob in (bpy.data.objects[p['object']] for p in ctx.parts.values() if p['stage'] == 'hair')
            if ob.type == 'CURVES' and not ob.hide_render]
    heads = [pid for pid in meshes if pid == 'body' or (ctx.parts[pid]['stage'] == 'hair' and not meshes[pid].hide_render)]
    staff = held_prop(ctx, meshes)
    parts = [pid for pid in meshes if staff and pid.split('.')[0] == staff[0].split('.')[0]]
    robe_cols = [k for k, pid in enumerate(depth) if kind.get(pid.split('.')[0]) in SHEETS]
    hat_cols = [k for k, pid in enumerate(depth) if kind.get(pid.split('.')[0]) == 'hat']
    probed = [bool(hair and sheets), bool(robe_cols), len(sheets) > 1, bool(hat and heads), bool(parts and depth)]
    return {'sheets': sheets, 'hat': hat, 'hair': hair, 'heads': heads, 'staff': parts, 'robe_cols': robe_cols,
            'hat_cols': hat_cols, 'probed': probed}


def hair_points(ob, dg, stride):
    """Evaluated world-space control points of a hair Curves object, every stride-th."""
    a = ob.evaluated_get(dg).data.attributes['position']
    co = np.empty(len(a.data) * 3, np.float32)
    a.data.foreach_get('vector', co)
    m = np.array(ob.matrix_world, np.float32)
    return (co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3])[::stride]


def hair_depth(hair, sheets, meshes, dg):
    """Deepest hair point inside or behind a sheet garment's outer shell (base surface, Solidify off, plus its outward
    shell), judged along the pseudo-normal like layer_poke; metres, 0 when every strand stays on top."""
    if not hair or not sheets:
        return 0.0
    stride = max(1, -(-sum(len(ob.data.points) for ob in hair) // HAIR_PTS_MAX))
    pts = np.concatenate([hair_points(ob, dg, stride) for ob in hair])
    worst = 0.0
    for ob in (meshes[s] for s in sheets):
        V, T = coords(ob, dg), loop_tris(ob, dg)
        box = (V.min(0) - DEPTH_MAX_M, V.max(0) + DEPTH_MAX_M)
        t, pad = tree(V, T), shell(ob)[0]
        for v in pts[np.all((pts > box[0]) & (pts < box[1]), axis=1)].tolist():
            loc, nrm, _, dist = t.find_nearest(v, DEPTH_MAX_M)
            if loc is None or pad - (Vector(v) - loc).dot(nrm) <= worst:
                continue
            n = sum((h[1] for h in t.find_nearest_range(v, dist + 1e-5)), Vector())
            sd = (Vector(v) - loc).dot(n.normalized()) if n.length > 1e-9 else 0.0
            if abs(sd) >= 0.9 * dist:
                worst = max(worst, pad - sd)
    return worst


def hat_poke(heads, hat, meshes, dg):
    """Head or scalp vertex poking out of the hat: inside the hat's bounds but not under its inner side (the first hat
    face straight above is missing or faces down), metres past the hat's outer shell; 0 when the hat covers the head."""
    worst = 0.0
    for hid in hat:
        V = coords(meshes[hid], dg)
        t, pad, up = tree(V, loop_tris(meshes[hid], dg)), shell(meshes[hid])[0], Vector((0, 0, 1))
        lo, hi = V.min(0), V.max(0)
        for pid in heads:
            P = coords(meshes[pid], dg)
            for v in P[np.all((P > lo) & (P < hi), axis=1)].tolist():
                loc, _, _, dist = t.find_nearest(v, DEPTH_MAX_M)
                if loc is None or dist - pad <= worst:
                    continue
                hit, nrm = t.ray_cast(Vector(v), up)[:2]
                if hit is None or nrm.z < 0:
                    worst = dist - pad
    return worst


def staff_hand(arm, bone, body, geo, staff):
    """Hand vertices inside the held staff and staff vertices inside the hand, within GRIP_M of the hand bone, metres."""
    c = bu.bone_world_head(arm, bone)
    hand = geo['body'][0][np.linalg.norm(geo['body'][0] - c, axis=1) < GRIP_M]
    sv = np.concatenate([geo[p][0] for p in staff])
    near = sv[np.linalg.norm(sv - c, axis=1) < GRIP_M]
    return max(inside_depth(merged_tree([geo[p] for p in staff]), hand, None), inside_depth(body, near, None))


class Frame:
    """Evaluated geometry of the current frame: world bounding boxes of every part, vertices read on demand."""

    def __init__(self, meshes, dg):
        self.meshes, self.dg, self.cache = meshes, dg, {}
        self.box = {pid: world_box(ob, dg) for pid, ob in meshes.items()}

    def verts(self, pid):
        if pid not in self.cache:
            self.cache[pid] = coords(self.meshes[pid], self.dg)
        return self.cache[pid]

    def lowest(self):
        """(lowest vertex z, its part id): parts visited by box bottom, stopping once no box can go lower."""
        best, who = np.inf, None
        for pid in sorted(self.box, key=lambda p: self.box[p][:, 2].min()):
            if self.box[pid][:, 2].min() >= best:
                break
            v = self.verts(pid)
            if len(v) and float(v[:, 2].min()) < best:
                best, who = float(v[:, 2].min()), pid
        return best, who

    def extent(self, view, pids):
        """Largest NDC extent over the parts' vertices (inf if any is behind the camera); a box corner bound prunes parts
        (|x/z| is quasi-convex, so its maximum over a box sits at a corner)."""
        bound = {pid: ndc_extent(self.box[pid], view) for pid in pids}
        best = -np.inf
        for pid in sorted(bound, key=bound.get, reverse=True):
            if bound[pid] <= best:
                break
            v = self.verts(pid)
            best = max(best, ndc_extent(v, view)) if len(v) else best
        return best


def held_prop(ctx, meshes):
    """(part id, hand role) of the first prop mesh held in a hand, else None."""
    for pid, p in ctx.parts.items():
        role = str(p['attach'] or '')
        if pid in meshes and p['stage'] == 'props' and role.startswith('hand') and role in ctx.bones:
            return pid, role
    return None


def grip_points(arm, bone, prop):
    """Hand bone head and tail in the held prop's local frame (constant while the prop stays in the hand)."""
    pb = arm.pose.bones[bone]
    M = np.array(prop.matrix_world.inverted() @ arm.matrix_world)
    return [M[:3, :3] @ np.array(p) + M[:3, 3] for p in (pb.head, pb.tail)]


def rest_probes(ctx, arm, meshes, staff):
    """At the rig's rest pose: sole vertices (heel = rearmost, ball = frontmost of the lowest SOLE_Z_M of each foot's
    boot, else the body near the ankle; the character faces -Y) and the bind grip of the held prop."""
    pos = arm.data.pose_position
    arm.data.pose_position = 'REST'
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    soles = []
    for s in ('L', 'R'):
        own = [pid for pid, p in ctx.parts.items() if pid in meshes and p['attach'] == f'foot.{s}']
        for pid in own or (['body'] if 'body' in meshes else []):
            v = coords(meshes[pid], dg)
            ank = np.array(ctx.landmarks[f'foot.{s}'])
            m = np.flatnonzero((v[:, 2] < v[:, 2].min() + SOLE_Z_M) & (np.abs(v[:, 0] - ank[0]) < 0.08))
            if len(m):
                soles += [(pid, int(m[v[m, 1].argmax()])), (pid, int(m[v[m, 1].argmin()]))]
                break
    grip0 = np.array(grip_points(arm, ctx.bones[staff[1]], meshes[staff[0]])) if staff else np.zeros((0, 3))
    arm.data.pose_position = pos
    bpy.context.view_layer.update()
    return soles, grip0


def world_box(ob, dg):
    """World-space corners (8, 3) of the evaluated object's bounding box."""
    m = np.array(ob.matrix_world, np.float32)
    return np.array(ob.evaluated_get(dg).bound_box, np.float32) @ m[:3, :3].T + m[:3, 3]


def shot_views(ctx):
    """Per spec shot except stills: frame count, clip, mask sample frames and, for a static camera, its view."""
    views = {}
    for shot in ctx.spec['renders']:
        if shot['kind'] == 'still':
            continue
        done = ctx.renders.get(shot['id'])
        n = done['frames'] if done else render.frame_count(ctx, shot)
        sample = set(range(0, n, max(1, n // MASK_SAMPLES))) if done else set()
        v = {'shot': shot, 'n': n, 'clip': shot.get('clip'), 'sample': sample, 'view': None}
        if shot['kind'] != 'turntable' and not render.cycle(ctx, shot):
            render.place_camera(ctx, shot, n)
            bpy.context.view_layer.update()
            v['view'] = camera_view(bpy.data.objects[CAMERA], bpy.context.scene)
        views[shot['id']] = v
    return views


def camera_view(cam, sc):
    """World-to-camera matrix plus the frustum half extents at the camera's current state."""
    fr = cam.data.view_frame(scene=sc)
    return np.array(cam.matrix_world.inverted()), (abs(fr[0].x), abs(fr[0].y), abs(fr[0].z)), cam.matrix_world.copy()


def observe(ctx, arm, views, margins, masks, cid, f, fr, eyes):
    """Framing margin (and mask on sample frames) for every static-camera shot of this clip at scene frame f."""
    for sid, v in views.items():
        i = f - 1
        if v['clip'] != cid or v['view'] is None or not 0 <= i < v['n']:
            continue
        margins[sid][i] = shot_margin(ctx, arm, v, fr, eyes)
        if i in v['sample']:
            masks[sid][i] = subject_mask(fr.meshes, fr.dg, v['view'])


def finish_shots(ctx, arm, views, margins, masks, meshes, eyes):
    """Shot frames no clip pass covered (turntables, shots longer than their clip): own frame loop, cage meshes."""
    sc, extra = bpy.context.scene, 0
    with subdivision(meshes, False):
        for sid, v in views.items():
            todo = np.flatnonzero(np.isnan(margins[sid]))
            if not len(todo):
                continue
            if v['clip']:
                arm.animation_data.action = bpy.data.actions[ctx.clips[v['clip']]['action']]
            fol = render.Follow(ctx, v['shot'], v['n']) if render.cycle(ctx, v['shot']) else None
            if not fol:
                render.place_camera(ctx, v['shot'], v['n'])
            for i in todo.tolist():
                fol.pose(i) if fol else sc.frame_set(i + 1)
                fr = Frame(meshes, bpy.context.evaluated_depsgraph_get())
                view = v['view'] or camera_view(bpy.data.objects[CAMERA], sc)
                margins[sid][i] = shot_margin(ctx, arm, dict(v, view=view), fr, eyes)
                if i in v['sample']:
                    masks[sid][i] = subject_mask(meshes, fr.dg, view)
            extra += len(todo)
            if fol:
                fol.restore()
    return extra


def shot_margin(ctx, arm, v, fr, eyes):
    """1 - largest NDC extent of the subject (close-ups: vertices within FACE_M of the face point); -1 if cut off."""
    if v['shot']['kind'] != 'closeup':
        e = fr.extent(v['view'], list(fr.meshes))
    else:
        c = face_point(ctx, arm, v['shot'], [fr.verts(e).mean(0) for e in eyes])
        near = [pid for pid, b in fr.box.items() if np.linalg.norm(np.clip(c, b.min(0), b.max(0)) - c) < FACE_M]
        pts = [x[np.linalg.norm(x - c, axis=1) < FACE_M] for x in map(fr.verts, near)]
        pts = [x for x in pts if len(x)]
        e = ndc_extent(np.concatenate(pts), v['view']) if pts else -np.inf
    return -1.0 if not np.isfinite(e) else 1 - e


def lid_occluders(ctx, meshes, eyes):
    """Body plus the face lane's lid meshes; without lid_parts, every part not attached to an eye and no occlusion shell."""
    lids = {names[0] for names in ctx.face.get('lid_parts', {}).values()}
    if lids:
        return [pid for pid in meshes if pid == 'body' or ctx.parts[pid]['object'] in lids]
    return [pid for pid in meshes if pid not in eyes and 'occlusion' not in pid
            and not (ctx.parts[pid]['attach'] or '').startswith('eye')]


def face_point(ctx, arm, shot, eye_centres):
    """Close-up subject centre: between the posed eyes, 3.5 cm down (render.face_centre), else the target bone."""
    role = shot.get('target', 'head')
    if role == 'head' and eye_centres:
        return np.mean(eye_centres, 0) - [0, 0, 0.035]
    return bu.bone_world_head(arm, ctx.bones[role]) if role in ctx.bones else np.array(ctx.landmarks[role])


def coords(ob, dg):
    """Evaluated world-space vertices (N, 3), read in place from the evaluated mesh."""
    me = ob.evaluated_get(dg).data
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get('co', co)
    m = np.array(ob.matrix_world, np.float32)
    return co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3]


def loop_tris(ob, dg):
    """Loop triangles (T, 3) of the evaluated mesh."""
    me = ob.evaluated_get(dg).data
    tri = np.empty(len(me.loop_triangles) * 3, np.int32)
    me.loop_triangles.foreach_get('vertices', tri)
    return tri.reshape(-1, 3)


def tree(verts, tris):
    return BVHTree.FromPolygons(verts.tolist(), tris.tolist())


def self_pairs(ob, dg):
    """Unique crossing polygon pairs of one evaluated mesh (the BVH overlap already skips pairs sharing a vertex)."""
    t = BVHTree.FromObject(ob, dg)
    pairs = np.array(t.overlap(t), int).reshape(-1, 2)
    pairs = np.sort(pairs[pairs[:, 0] != pairs[:, 1]], 1)
    return len(np.unique(pairs, axis=0)) if len(pairs) else 0


def inside_depth(body, verts, skip):
    """Deepest vertex behind the body surface, metres: nearest point within 5 cm, offset along the inward pseudo-normal
    (sum of the normals of every face touching that point, so a hit on an edge, crease or mask boundary of the open body
    takes all its faces into account; oblique offsets are ignored); skip = (centre, radius)."""
    worst = 0.0
    if skip:
        verts = verts[np.linalg.norm(verts - skip[0], axis=1) > skip[1]]
    for v in verts.tolist():
        loc, nrm, _, dist = body.find_nearest(v, DEPTH_MAX_M)
        if loc is None or (Vector(v) - loc).dot(nrm) >= -0.9 * dist:
            continue
        n = sum((h[1] for h in body.find_nearest_range(v, dist + 1e-5)), Vector())
        if n.length > 1e-9 and (Vector(v) - loc).dot(n.normalized()) < -0.9 * dist:
            worst = max(worst, dist)
    return worst


def is_hair(ctx, pid):
    """Hair stage parts and hair-material cards (brows, lashes) cross each other by design."""
    mat = ctx.spec['materials'].get(ctx.parts[pid]['material'] or '', {})
    return ctx.parts[pid]['stage'] == 'hair' or mat.get('kind') == 'hair'


def grip(ctx, arm, pid):
    """Props held in a hand: ignore the grip zone around that hand."""
    role = ctx.parts[pid]['attach']
    if ctx.parts[pid]['stage'] == 'props' and role and role.startswith('hand') and role in ctx.bones:
        return bu.bone_world_head(arm, ctx.bones[role]), GRIP_M
    return None


def head_forward(arm, bone):
    """World forward of the posed head (rest forward is -Y)."""
    if not bone:
        return Vector((0, -1, 0))
    pb = arm.pose.bones[bone]
    rot = arm.matrix_world.to_3x3()
    return (rot @ (pb.matrix @ pb.bone.matrix_local.inverted()).to_3x3() @ rot.inverted() @ Vector((0, -1, 0))).normalized()


def deforms(ob):
    """Modifiers or shape keys can change a mesh's own shape; otherwise it only moves rigidly."""
    return bool(ob.modifiers) or ob.data.shape_keys is not None


def near_tris(c, occluders):
    """Per occluder: (used vertex ids, remapped triangles) of triangles within 5 cm of the eye; topology is fixed per clip."""
    out = {}
    for pid, (v, t) in occluders.items():
        keep = t[(np.linalg.norm(v[t] - c, axis=2) < LID_NEAR_M).any(1)]
        if len(keep):
            used, remap = np.unique(keep, return_inverse=True)
            out[pid] = (used, remap.reshape(-1, 3))
    return out


def merged_tree(geo):
    off = np.cumsum([0] + [len(v) for v, _ in geo[:-1]])
    return tree(np.concatenate([v for v, _ in geo]), np.concatenate([t + o for (_, t), o in zip(geo, off)]))


def lid_visible(eye, near, geo, fwd):
    """Fraction of front-facing eyeball vertices with a clear ray to a viewpoint 40 cm ahead of the eye."""
    c = eye.mean(0)
    view = c + np.array(fwd) * LID_VIEW_M
    facing = eye[((view - eye) * (eye - c)).sum(1) > 0]
    if not len(facing):
        return 0.0
    if not near:
        return 1.0
    occ = merged_tree([(geo[pid][0][used], t) for pid, (used, t) in near.items()])
    vis = 0
    for v in facing.tolist():
        d = Vector(view) - Vector(v)
        dist = d.length
        d.normalize()
        vis += occ.ray_cast(Vector(v) + d * 1e-5, d, dist)[0] is None
    return vis / len(facing)


def ndc_extent(verts, view):
    """Largest |x|, |y| in NDC (frame half-width = 1) over the vertices; inf if any is at or behind the camera plane."""
    m, (fx, fy, fz), _ = view
    pc = verts @ m[:3, :3].T + m[:3, 3]
    if (pc[:, 2] >= 0).any():
        return np.inf
    z = -pc[:, 2]
    return float(max(np.abs(pc[:, 0] / z).max() * fz / fx, np.abs(pc[:, 1] / z).max() * fz / fy))


def subject_mask(meshes, dg, view, w=MASK_W):
    """Low-res boolean image (row 0 = top): camera ray through the pixel hits the subject."""
    sc = bpy.context.scene
    subject = merged_tree([(coords(ob, dg), loop_tris(ob, dg)) for ob in meshes.values()])
    _, (fx, fy, fz), mw = view
    h = max(1, round(w * sc.render.resolution_y / sc.render.resolution_x))
    xs = ((np.arange(w) + 0.5) / w * 2 - 1) * fx
    ys = (1 - (np.arange(h) + 0.5) / h * 2) * fy
    gx, gy = np.meshgrid(xs, ys)
    d = np.stack([gx, gy, np.full(gx.shape, -fz)], -1).reshape(-1, 3) @ np.array(mw.to_3x3()).T
    origin = mw.translation
    hits = [subject.ray_cast(origin, Vector(v))[0] is not None for v in d.tolist()]
    return np.array(hits).reshape(h, w)
