"""Stage facerig: lid bones about the eye centre, eye aim with convergence, lid follow, blink/jaw drivers, beard on jaw."""
import math

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

from .. import bpyutil as bu
from . import face as facemod

NAME = 'facerig'
TARGET_M = 0.6
APERTURE_DEG, VIEW_TILT_DEG = 55.0, 25.0
SHELL_GROW = 25.0
LOOK_KEYS = {'eyeLookUp': 1.0, 'eyeLookDown': -1.0}
SIDE = {'L': 'Left', 'R': 'Right'}
LOOK_FULL_DEG, LOOK_MAX = 30.0, 2.0
REACH_R_M, MOUTH_R_M = 0.11, 0.025


def add_bone(arm, name, head, parent, length=0.02):
    eb = arm.data.edit_bones.new(name)
    eb.head, eb.tail = head, head + Vector((0, -length, 0))
    eb.align_roll(Vector((0, 0, 1)))
    eb.parent, eb.use_deform = arm.data.edit_bones[parent], False
    return name


def hinge_sign(arm, bone):
    """+1 when the bone's X axis is world +X: a world rotation of -dtheta about +X raises a point by dtheta."""
    x = arm.matrix_world.to_3x3() @ arm.data.bones[bone].matrix_local.to_3x3().col[0]
    return 1.0 if x.x > 0 else -1.0


def rebind(ob, arm, bone):
    for m in [m for m in ob.modifiers if m.type == 'ARMATURE']:
        ob.modifiers.remove(m)
    bu.parent_to_bone(ob, arm, bone)


def bind_jaw(ob, arm, body, pivot, deg):
    """Beard root on the jaw: surface curves ride the skin; skinned cards move jaw weights to jaw_follow; else parent."""
    if ob.type == 'CURVES' and ob.data.surface:
        return 'surface'
    if any(m.type == 'ARMATURE' for m in ob.modifiers):
        return jaw_weights(ob, body, pivot, math.radians(deg))
    rebind(ob, arm, 'jaw_follow')
    return 'parent'


def jaw_weights(ob, body, pivot, rad):
    """Skinned cards: per strip, jaw_follow weight = how far jawOpen moves the skin at its root, fading to the tip."""
    kb = body.data.shape_keys.key_blocks
    n, m = len(body.data.vertices), np.array(body.matrix_world)
    a, b = np.empty(n * 3), np.empty(n * 3)
    kb[0].data.foreach_get('co', a)
    kb['jawOpen'].data.foreach_get('co', b)
    a, b = (x.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3] for x in (a, b))
    kd = KDTree(n)
    for i, v in enumerate(a):
        kd.insert(v, i)
    kd.balance()
    co = np.array([tuple(ob.matrix_world @ v.co) for v in ob.data.vertices])
    near = np.array([kd.find(Vector(v))[1:] for v in co], dtype=object)
    idx, dist = near[:, 0].astype(int), near[:, 1].astype(float)
    move = np.linalg.norm(b[idx] - a[idx], axis=1) / np.maximum(np.linalg.norm(a[idx] - np.array(pivot), axis=1) * rad, 1e-6)
    parent = list(range(len(co)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for e in ob.data.edges:
        parent[root(e.vertices[0])] = root(e.vertices[1])
    isl = np.array([root(i) for i in range(len(co))])
    w = np.zeros(len(co))
    for k in np.unique(isl):
        sel = np.where(isl == k)[0]
        r = sel[dist[sel].argmin()]
        along = np.linalg.norm(co[sel] - co[r], axis=1)
        w[sel] = np.clip(move[r], 0, 1) * (1 - 0.6 * along / max(along.max(), 1e-6))
    dst = ob.vertex_groups.get('jaw_follow') or ob.vertex_groups.new(name='jaw_follow')
    for v in ob.data.vertices:
        for g in v.groups:
            if g.group != dst.index:
                g.weight *= 1 - w[v.index]
        if w[v.index] > 1e-3:
            dst.add([v.index], float(w[v.index]), 'REPLACE')
    return f'weights max {w.max():.2f}'


def jaw_open_deg(body, pivot, default):
    """Rotation (deg) about the jaw pivot that the body's jawOpen key applies to its 200 most moved verts."""
    kb = body.data.shape_keys.key_blocks
    n, m = len(body.data.vertices), np.array(body.matrix_world)
    a, b = np.empty(n * 3), np.empty(n * 3)
    kb[0].data.foreach_get('co', a)
    kb['jawOpen'].data.foreach_get('co', b)
    a, b = (x.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3] - np.array(pivot) for x in (a, b))
    i = np.linalg.norm(b - a, axis=1).argsort()[-200:]
    ang = np.degrees(np.median(np.arctan2(a[i, 2], -a[i, 1]) - np.arctan2(b[i, 2], -b[i, 1])))
    return float(ang) if 3 < ang < 45 else default


def revalidate():
    """Clear 'invalid' flags left by evaluations that ran before new rig properties reached the evaluated copies."""
    for coll in (bpy.data.shape_keys, bpy.data.objects):
        for idb in coll:
            for fc in (idb.animation_data.drivers if idb.animation_data else []):
                fc.driver.is_valid = True
    bpy.context.view_layer.update()


def evaluate():
    """Re-evaluate drivers after rig-property edits (shape-key datablocks are tagged explicitly)."""
    for key in bpy.data.shape_keys:
        key.update_tag()
    sc = bpy.context.scene
    sc.frame_set(sc.frame_current)
    return bpy.context.evaluated_depsgraph_get()


def world(ob, dg):
    """Evaluated world-space points (mesh verts or curve points) and mesh polygons."""
    ev = ob.evaluated_get(dg)
    if ev.type == 'CURVES':
        pos = np.empty(len(ev.data.points) * 3)
        ev.data.attributes['position'].data.foreach_get('vector', pos)
        m = np.array(ev.matrix_world)
        return pos.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3], []
    me = ev.to_mesh()
    co = np.array([tuple(ev.matrix_world @ v.co) for v in me.vertices])
    polys = [tuple(p.vertices) for p in me.polygons]
    ev.to_mesh_clear()
    return co, polys


def lid_visible_pct(ctx, arm, blink):
    """% of eyeball/iris/cornea verts inside the aperture cone that see past the lids (skin + shells) along view rays."""
    arm['blink_L'] = arm['blink_R'] = blink
    arm.update_tag()
    dg = evaluate()
    verts, polys = [], []
    lids = [ctx.parts['body']['object']] + [names[0] for names in ctx.face['lid_parts'].values()]
    for name in lids:
        co, pl = world(bpy.data.objects[name], dg)
        polys += [tuple(i + len(verts) for i in p) for p in pl]
        verts += [tuple(v) for v in co]
    bvh = BVHTree.FromPolygons(verts, polys)
    fwd = np.array([0, -1.0, 0])
    tilt = math.radians(VIEW_TILT_DEG)
    dirs = [fwd] + [np.array([math.sin(tilt) * math.cos(a), -math.cos(tilt), math.sin(tilt) * math.sin(a)])
                    for a in np.linspace(0, 2 * math.pi, 8, endpoint=False)]
    seen = total = 0
    for side in 'LR':
        c = np.array(ctx.landmarks[f'eye.{side}'])
        for part in ('eye', 'iris', 'cornea'):
            co, _ = world(bpy.data.objects[f'{part}.{side}'], dg)
            rel = co - c
            cosang = (rel @ fwd) / np.maximum(np.linalg.norm(rel, axis=1), 1e-9)
            for p in co[cosang >= math.cos(math.radians(APERTURE_DEG))]:
                total += 1
                seen += any(bvh.ray_cast(Vector(p + d * 1e-5), Vector(d), 0.2)[0] is None for d in dirs)
    arm['blink_L'] = arm['blink_R'] = 0.0
    arm.update_tag()
    return round(100.0 * seen / max(1, total), 3), total


def pitch_deg(arm, bone, dg):
    m = arm.evaluated_get(dg).matrix_world @ arm.evaluated_get(dg).pose.bones[bone].matrix
    y = m.to_3x3().col[1]
    return math.degrees(math.atan2(y.z, -y.y))


def run(ctx):
    arm = bpy.data.objects[ctx.parts['rig']['object']]
    f, gaze = ctx.face, ctx.spec['face'].get('gaze', {})
    conv, follow = gaze.get('convergence_offset_deg', 1.0), gaze.get('lid_follow', 0.5)
    mi = arm.matrix_world.inverted()
    eyes = {s: mi @ Vector(ctx.landmarks[f'eye.{s}']) for s in 'LR'}
    e0 = (eyes['L'] + eyes['R']) / 2
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    head, jaw = ctx.bones['head'], ctx.bones['jaw']
    add_bone(arm, 'eye_target', e0 + Vector((0, -TARGET_M, 0)), head, 0.05)
    lid_bones = {}
    for s, sx in (('L', 1), ('R', -1)):
        add_bone(arm, f'eye_target.{s}', e0 + Vector((sx * TARGET_M * math.tan(math.radians(conv)), -TARGET_M, 0)),
                 'eye_target', 0.03)
        add_bone(arm, f'eye_aim.{s}', eyes[s], head)
        if ctx.face['lid_parts']:
            for which in facemod.LIDS:
                lid_bones[f'{which}.{s}'] = add_bone(arm, f'lid.{which}.{s}', eyes[s], head, 0.015)
    add_bone(arm, 'jaw_follow', mi @ Vector(ctx.landmarks['jaw']), jaw, 0.03)
    arm.data.edit_bones['jaw_follow'].use_deform = True
    bpy.ops.object.mode_set(mode='OBJECT')
    pb = arm.pose.bones
    for s in 'LR':
        c = pb[f'eye_aim.{s}'].constraints.new('DAMPED_TRACK')
        c.target, c.subtarget = arm, f'eye_target.{s}'
        arm[f'blink_{s}'] = 0.0
        arm.id_properties_ui(f'blink_{s}').update(min=0.0, max=1.0)
    arm.update_tag()
    bpy.context.view_layer.update()
    body = bpy.data.objects[f['shape_key_object']]
    keys = body.data.shape_keys
    for key, bone in lid_bones.items():
        which, s = key.split('.')
        cfg = f['lid_angles'][key]
        b = pb[bone]
        b.rotation_mode = 'XYZ'
        rebind(bpy.data.objects[f['lid_parts'][key][0]], arm, bone)
        rad = -math.radians(cfg['closed'] - cfg['open']) * hinge_sign(arm, bone)
        facemod.drive(b, 'rotation_euler', arm, f'["blink_{s}"]', 'OBJECT', f'{rad:.6f}*v', index=0)
        for axis in range(3):
            facemod.drive(b, 'scale', arm, f'["blink_{s}"]', 'OBJECT', f'min(1.0, {SHELL_GROW:.1f}*v + 0.001)', index=axis)
        cr = b.constraints.new('COPY_ROTATION')
        cr.target, cr.subtarget = arm, f'eye_aim.{s}'
        cr.use_y = cr.use_z = False
        cr.mix_mode, cr.target_space, cr.owner_space = 'ADD', 'LOCAL', 'LOCAL'
        cr.influence = follow if which == 'upper' else 0.5 * follow
    controls = {n: f'["blink_{n[8]}"]' if n.startswith('eyeBlink') else f'["{n}"]' for n in facemod.ARKIT
                if n in keys.key_blocks}
    for name in controls:
        if not name.startswith('eyeBlink'):
            arm[name] = 0.0
            arm.id_properties_ui(name).update(min=0.0, max=1.0)
    arm.update_tag()
    bpy.context.view_layer.update()
    for name, path in controls.items():
        facemod.drive(keys.key_blocks[name], 'value', arm, path, 'OBJECT')
    for s in 'LR':
        for part in ('eye', 'iris', 'cornea'):
            rebind(bpy.data.objects[f'{part}.{s}'], arm, f'eye_aim.{s}')
    jb = pb['jaw_follow']
    jb.rotation_mode = 'XYZ'
    f['jaw_open_deg'] = jaw_open_deg(body, Vector(ctx.landmarks['jaw']), f['jaw_open_deg'])
    jrad = math.radians(f['jaw_open_deg']) * hinge_sign(arm, 'jaw_follow')
    facemod.drive(jb, 'rotation_euler', arm, controls['jawOpen'], 'OBJECT', f'{jrad:.6f}*v', index=0)
    for name in (f['teeth_lower'], f['gums_lower'], f['tongue']):
        rebind(bpy.data.objects[name], arm, 'jaw_follow')
    beard_ids = {h['id'] for h in ctx.spec.get('hair', []) if h.get('kind') == 'beard'}
    beards = [pid for pid, p in ctx.parts.items() if p['stage'] == 'hair' and pid.split('.')[0] in beard_ids]
    binding = {pid: bind_jaw(bpy.data.objects[ctx.parts[pid]['object']], arm, body, ctx.landmarks['jaw'],
                             f['jaw_open_deg']) for pid in beards}
    revalidate()
    blink = {f'blink.{s}': f'["blink_{s}"]' for s in 'LR' if f'eyeBlink{SIDE[s]}' in controls}
    ctx.face.update(lid_bones=lid_bones, eye_aim='eye_target', controls={**blink, **controls},
                    gaze_rig={'eyes': {'L': 'eye_aim.L', 'R': 'eye_aim.R'}, 'targets': {'L': 'eye_target.L',
                              'R': 'eye_target.R'}, 'distance_m': TARGET_M, 'convergence_offset_deg': conv,
                              'lid_follow': follow, 'jaw': 'jaw_follow'})
    metrics = {'stub': False, 'lid_bones': len(lid_bones), 'eye_aim': 2, 'arkit_controls': len(controls),
               'beard_binding': binding,
               'jaw_open_deg': round(f['jaw_open_deg'], 2),
               'lid_clearance_mm': round((facemod.LID_IN - facemod.CORNEA_APEX) * f['eye_radius_m'] * 1000, 2)}
    metrics['lid_visible_pct'], metrics['lid_test_verts'] = lid_visible_pct(ctx, arm, 1.0)
    metrics['lid_visible_open_pct'] = lid_visible_pct(ctx, arm, 0.0)[0]
    if lid_bones:
        metrics.update(follow_check(ctx, arm))
        metrics.update(skin_follow(ctx, arm, keys, controls, follow))
    metrics.update(jaw_check(ctx, arm, beards))
    metrics.update(expression_reach(ctx, arm, keys, ctx.face['controls']))
    return metrics


def set_weights(arm, keys, controls, weights, base):
    """ARKit weights through the controls, other keys directly; anything unnamed back to its `base` value."""
    for name, path in controls.items():
        arm[path[2:-2]] = weights.get(name, base.get(path, 0.0))
    for kb in list(keys.key_blocks)[1:]:
        if kb.name not in controls:
            kb.value = weights.get(kb.name, base.get(kb.name, 0.0))
    arm.update_tag()
    return evaluate()


def expression_reach(ctx, arm, keys, controls):
    """Per expression and viseme: p99 skin displacement (mm) from neutral over the front face skin a camera ahead can
    see past the hair cards and brows (what a viewer can read); `expr_reach_min_mm` = the weakest one."""
    body = bpy.data.objects[ctx.face['shape_key_object']]
    e0 = (np.array(ctx.landmarks['eye.L']) + np.array(ctx.landmarks['eye.R'])) / 2
    base = {**{p: arm.get(p[2:-2], 0.0) for p in controls.values()}, **{kb.name: kb.value for kb in keys.key_blocks}}
    dg = set_weights(arm, keys, controls, {}, base)
    co0, _ = world(body, dg)
    region = np.flatnonzero((np.linalg.norm(co0 - e0, axis=1) < REACH_R_M) & (co0[:, 1] < e0[1] + 0.01))
    hair = [p['object'] for pid, p in ctx.parts.items() if pid != 'body' and p['stage'] in ('hair', 'face')
            and ctx.spec['materials'].get(p.get('material') or '', {}).get('kind') == 'hair']
    verts, polys = [], []
    for name in hair:
        co, pl = world(bpy.data.objects[name], dg)
        polys += [tuple(i + len(verts) for i in q) for q in pl]
        verts += [tuple(v) for v in co]
    bvh = BVHTree.FromPolygons(verts, polys) if polys else None
    seen = np.array([bvh is None or bvh.ray_cast(Vector(co0[i]) + Vector((0, -1e-4, 0)), Vector((0, -1, 0)), 0.5)[0]
                     is None for i in region])
    vis = region[seen]
    m = ctx.face.get('mouth', {})
    lips = np.linalg.norm(co0[region] - [e0[0], m.get('mouth_front_y', e0[1]), m.get('mouth_z', e0[2] - 0.07)],
                          axis=1) < MOUTH_R_M
    face = ctx.spec['face']
    reach = {}
    for group in ('expressions', 'visemes'):
        for name, w in face.get(group, {}).items():
            if not w:
                continue
            co, _ = world(body, set_weights(arm, keys, controls, w, base))
            d = np.linalg.norm(co[vis] - co0[vis], axis=1) * 1000
            reach[f'{group[0]}:{name}'] = round(float(np.percentile(d, 99)), 2) if len(d) else 0.0
    set_weights(arm, keys, controls, {}, base)
    weak = min(reach, key=reach.get) if reach else None
    return {'expr_reach_mm': reach, 'expr_reach_min_mm': reach.get(weak, 0.0), 'expr_reach_weakest': weak,
            'face_skin_visible_pct': round(100.0 * len(vis) / max(1, len(region)), 1),
            'mouth_visible_pct': round(100.0 * float(seen[lips].mean()), 1) if lips.any() else 0.0}


def follow_check(ctx, arm):
    """Raise the gaze 10 deg: measured eye pitch, upper-lid pitch and their ratio (lid follow)."""
    pb = arm.pose.bones['eye_target']
    dg = evaluate()
    e0, l0 = pitch_deg(arm, 'eye_aim.L', dg), pitch_deg(arm, 'lid.upper.L', dg)
    rest = arm.data.bones['eye_target'].matrix_local.to_3x3()
    pb.location = rest.inverted() @ Vector((0, 0, TARGET_M * math.tan(math.radians(10))))
    dg = evaluate()
    de, dl = pitch_deg(arm, 'eye_aim.L', dg) - e0, pitch_deg(arm, 'lid.upper.L', dg) - l0
    pb.location = (0, 0, 0)
    evaluate()
    return {'gaze_up_deg': round(de, 2), 'lid_follow_measured': round(dl / de, 3) if de else 0.0}


def drive_look(arm, keys, controls, gain):
    """Skin eyeLookUp/Down = max(rig value, gain * eye-target height, up to LOOK_MAX): the visible lids follow the gaze."""
    for base, sgn in LOOK_KEYS.items():
        for name in (base + 'Left', base + 'Right'):
            if name not in keys.key_blocks:
                continue
            kb = keys.key_blocks[name]
            kb.driver_remove('value')
            kb.slider_max = LOOK_MAX
            fc = facemod.drive(kb, 'value', arm, controls[name], 'OBJECT',
                               f'max(v, min({LOOK_MAX:.1f}, {sgn * gain:.4f}*z))')
            var = fc.driver.variables.new()
            var.name, var.type = 'z', 'TRANSFORMS'
            t = var.targets[0]
            t.id, t.bone_target, t.transform_type, t.transform_space = arm, 'eye_target', 'LOC_Z', 'LOCAL_SPACE'
            fc.driver.is_valid = True


def skin_lid_ratio(ctx, arm, deg=10.0):
    """Raise the gaze deg: upper-lid skin margin pitch change / eye pitch change (left eye), or None."""
    f, pb = ctx.face, arm.pose.bones['eye_target']
    body, c, r = bpy.data.objects[f['shape_key_object']], np.array(ctx.landmarks['eye.L']), f['eye_radius_m']
    rest = arm.data.bones['eye_target'].matrix_local.to_3x3()
    res = []
    for d in (0.0, deg):
        pb.location = rest.inverted() @ Vector((0, 0, TARGET_M * math.tan(math.radians(d))))
        dg = evaluate()
        m = facemod.lid_margins(body, c, r, dg)
        if len(m['upper']) < 3:
            pb.location = (0, 0, 0)
            evaluate()
            return None
        res.append((pitch_deg(arm, 'eye_aim.L', dg), facemod.margin_angles(c, r, m)['upper']))
    pb.location = (0, 0, 0)
    evaluate()
    de, dl = res[1][0] - res[0][0], res[1][1] - res[0][1]
    return dl / de if de else None


def skin_follow(ctx, arm, keys, controls, follow):
    """Calibrate the look-key gain so the visible upper lid follows the gaze by `follow`, then measure it."""
    gain = TARGET_M ** -1 * math.degrees(1) / LOOK_FULL_DEG
    ratio = None
    for _ in range(4):
        drive_look(arm, keys, controls, gain)
        revalidate()
        ratio = skin_lid_ratio(ctx, arm)
        if ratio is None or abs(ratio) < 1e-3 or abs(abs(ratio) - follow) < 0.1 * follow:
            break
        gain = math.copysign(min(30.0, max(0.5, abs(gain) * follow / abs(ratio))), gain * ratio)
    return {'lid_skin_follow_gain': round(gain, 3), 'lid_skin_follow_measured': round(ratio, 3) if ratio else ratio}


def jaw_check(ctx, arm, beards):
    """jawOpen = 1: lower-teeth and beard-root travel (mm) through the jaw_follow driver."""
    names = [ctx.face['teeth_lower']] + [ctx.parts[b]['object'] for b in beards]
    dg = evaluate()
    before = {n: world(bpy.data.objects[n], dg)[0] for n in names}
    arm['jawOpen'] = 1.0
    arm.update_tag()
    dg = evaluate()
    out = {}
    for n in names:
        co = world(bpy.data.objects[n], dg)[0]
        top = before[n][:, 2] >= np.percentile(before[n][:, 2], 80)
        out[n] = round(float(np.linalg.norm(co[top] - before[n][top], axis=1).mean() * 1000), 1)
    arm['jawOpen'] = 0.0
    arm.update_tag()
    evaluate()
    res = {'jaw_teeth_mm': out[names[0]]}
    if beards:
        res['beard_root_follow_mm'] = {b: out[ctx.parts[b]['object']] for b in beards}
    return res


def key_gaze(arm, frame, yaw_deg, pitch_deg_, blink, face_ctx):
    """Key the eye target (gaze in deg from straight ahead) and both blink properties at frame."""
    d = face_ctx['gaze_rig']['distance_m']
    pb = arm.pose.bones[face_ctx['eye_aim']]
    rest = arm.data.bones[pb.name].matrix_local.to_3x3()
    pb.location = rest.inverted() @ Vector((d * math.tan(math.radians(yaw_deg)), 0, d * math.tan(math.radians(pitch_deg_))))
    pb.keyframe_insert('location', frame=frame)
    for s in 'LR':
        arm[f'blink_{s}'] = blink
        arm.keyframe_insert(f'["blink_{s}"]', frame=frame)
