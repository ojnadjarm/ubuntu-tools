"""Stage rig: Rigify rig fitted to the landmarks (cached), capsule and transferred weights (<= 4 per vertex), rigid-bound
hard pieces, every part bound by role, and a game skeleton (DEF bones only, one root, linear bones)."""
import hashlib
import json
import os
from pathlib import Path

import addon_utils
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

from .. import bpyutil as bu

NAME = 'rig'
VERSION = 1
CACHE = Path(os.environ.get('CHAR3D_CACHE', '~/.cache/char3d')).expanduser() / 'rigify'
SRC = {'hips': 'spine', 'spine': 'spine.001', 'chest': 'spine.003', 'neck': 'spine.004', 'head': 'spine.006',
       'jaw': 'jaw', 'eye.L': 'eye.L', 'eye.R': 'eye.R', 'hand.L': 'hand.L', 'hand.R': 'hand.R',
       'foot.L': 'foot.L', 'foot.R': 'foot.R', 'toe.L': 'toe.L', 'toe.R': 'toe.R'}
ROLES = ['root', *SRC]
CONTROLS = {'root': 'root', 'hips': 'hips', 'spine': 'spine_fk.001', 'chest': 'chest', 'neck': 'neck', 'head': 'head',
            'jaw': 'jaw_master', 'eye.L': 'eye.L', 'eye.R': 'eye.R', 'torso': 'torso', 'eyes': 'eyes'}
for _s in 'LR':
    CONTROLS.update({f'hand.{_s}': f'hand_ik.{_s}', f'foot.{_s}': f'foot_ik.{_s}', f'toe.{_s}': f'toe_ik.{_s}',
                     f'heel.{_s}': f'foot_heel_ik.{_s}', f'fk:hand.{_s}': f'hand_fk.{_s}', f'fk:foot.{_s}': f'foot_fk.{_s}',
                     f'pole:arm.{_s}': f'upper_arm_ik_target.{_s}', f'pole:leg.{_s}': f'thigh_ik_target.{_s}',
                     f'ik_fk:arm.{_s}': f'upper_arm_parent.{_s}', f'ik_fk:leg.{_s}': f'thigh_parent.{_s}'})
SKIP_CAPSULE = ('pelvis', 'breast')
HIP_OFFSET = (0.126, 0.01, -0.03)
GROUND = 'DEF-ground'
HEM_GAP_M = (0.02, 0.12)
RIGID_KINDS = {'hat', 'helmet', 'pouch', 'pauldron', 'bracer'}
RIGID_PIECES = ('buckle',)
MAX_INFLUENCES = 4
FALLOFF_M = 0.02
SMOOTH_ITERS = 4
PLACEHOLDER_PARENT = {'hips': 'root', 'spine': 'hips', 'chest': 'spine', 'neck': 'chest', 'head': 'neck', 'jaw': 'head',
                      'eye.L': 'head', 'eye.R': 'head', 'hand.L': 'chest', 'hand.R': 'chest',
                      'foot.L': 'hips', 'foot.R': 'hips', 'toe.L': 'foot.L', 'toe.R': 'foot.R'}


def run(ctx):
    cfg = ctx.spec.get('rig', {})
    if cfg.get('generator') != 'rigify':
        return _placeholder(ctx)
    addon_utils.enable('rigify', default_set=True)
    rig, cache = _rigify(ctx, cfg.get('metarig', 'human'))
    for pb in rig.pose.bones:
        if 'IK_Stretch' in pb.keys():
            pb['IK_Stretch'] = float(cfg.get('ik_stretch', 0.0))
    ctx.bones = {role: _def_bone(rig, SRC.get(role, role)) for role in ROLES}
    ctx.controls = {k: v for k, v in CONTROLS.items() if v in rig.pose.bones}
    ctx.controls.update({f'prop:{p["id"]}': f'prop_{p["id"]}' for p in ctx.spec.get('props', [])})
    ctx.add_part('rig', rig.name, NAME)
    bound = _bind_parts(ctx, rig)
    skinned = [bpy.data.objects[o] for o in bound['skinned']]
    for ob in skinned:
        _skin_safe(ob)
    game = _game_skeleton(rig, skinned, ctx.bones.values())
    bpy.context.view_layer.update()
    meshes = [bpy.data.objects[p['object']] for p in ctx.parts.values() if bpy.data.objects[p['object']].type == 'MESH']
    min_z = min((bu.world_verts(ob)[:, 2].min() for ob in meshes if len(ob.data.vertices)), default=0.0)
    return {'stub': False, 'bones': len(rig.data.bones), 'def_bones': sum(b.use_deform for b in rig.data.bones),
            'cache': cache, 'unweighted_verts': sum(_unweighted(ob) for ob in skinned),
            'max_influences': max((_influences(ob) for ob in skinned), default=0), 'game': game,
            'rest_min_z_mm': round(1000 * float(min_z), 3),
            'bound': {k: len(v) for k, v in bound.items()}}


def _placeholder(ctx):
    arm_data = bpy.data.armatures.new('rig')
    arm = bpy.data.objects.new('rig', arm_data)
    bu.collection('char3d').objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    for role in ROLES:
        x, y, z = ctx.landmarks[role]
        eb = arm_data.edit_bones.new(role)
        eb.head, eb.tail = (x, y, z), (x, y, z + 0.08)
    for role, parent in PLACEHOLDER_PARENT.items():
        arm_data.edit_bones[role].parent = arm_data.edit_bones[parent]
    props = {p['id']: f'prop_{p["id"]}' for p in ctx.spec.get('props', [])}
    for p in ctx.spec.get('props', []):
        eb = arm_data.edit_bones.new(props[p['id']])
        eb.head = arm_data.edit_bones[p['attach']].head
        eb.tail = eb.head + Vector((0, 0, 0.1))
        eb.parent = arm_data.edit_bones[p['attach']]
    bpy.ops.object.mode_set(mode='OBJECT')
    ctx.bones = {role: role for role in ROLES}
    ctx.controls = dict(ctx.bones)
    ctx.controls.update({f'prop:{pid}': bone for pid, bone in props.items()})
    ctx.add_part('rig', arm.name, NAME)
    for part in ctx.parts.values():
        if part['attach']:
            bu.parent_to_bone(bpy.data.objects[part['object']], arm, ctx.bones[part['attach']])
    return {'stub': True, 'bones': len(arm_data.bones), 'unweighted_verts': 0}


# ---- metarig fit and generation -------------------------------------------------------------------------------

def _rigify(ctx, metarig):
    """Add the metarig, fit it to the landmarks, then generate it or append the cached result for the same fit."""
    getattr(bpy.ops.object, f'armature_{metarig}_metarig_add')()
    meta = bpy.context.object
    bpy.ops.object.mode_set(mode='EDIT')
    _fit(meta.data.edit_bones, {k: Vector(v) for k, v in ctx.landmarks.items()})
    key = _fit_key(meta.data.edit_bones, metarig)
    bpy.ops.object.mode_set(mode='OBJECT')
    path = CACHE / f'{key}.blend'
    if path.exists():
        _remove(meta)
        with bpy.data.libraries.load(str(path), link=False) as (_src, dst):
            dst.objects = ['rig']
        rig, cache = dst.objects[0], 'hit'
    else:
        bpy.context.view_layer.objects.active = meta
        bpy.ops.pose.rigify_generate()
        rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o is not meta)
        _remove(meta)
        for parent in [bpy.context.scene.collection, *bpy.data.collections]:
            for col in [c for c in parent.children if c.name.startswith('WGTS')]:
                parent.children.unlink(col)
        CACHE.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix('.tmp.blend')
        bpy.data.libraries.write(str(tmp), {rig}, fake_user=True)
        os.replace(tmp, path)
        cache = 'miss'
    for col in list(rig.users_collection):
        col.objects.unlink(rig)
    bu.collection('char3d').objects.link(rig)
    _add_helper_bones(ctx, rig)
    return rig, cache


def _remove(ob):
    data = ob.data
    bpy.data.objects.remove(ob)
    bpy.data.armatures.remove(data)


def _fit_key(ebs, metarig):
    rows = sorted((b.name, *(round(c, 5) for c in (*b.head, *b.tail)), round(b.roll, 4)) for b in ebs)
    rigify = '.'.join(map(str, next(m.bl_info.get('version', ()) for m in addon_utils.modules() if m.__name__ == 'rigify')))
    blob = json.dumps([VERSION, metarig, bpy.app.version_string, rigify, rows])
    return f'{metarig}-{hashlib.sha1(blob.encode()).hexdigest()[:16]}'


def _region(eb):
    """Fit region of a metarig bone: face, arm.X, hand.X, leg.X, foot.X or torso."""
    chain = [eb] + list(eb.parent_recursive)
    names = [b.name for b in chain]
    if 'face' in names:
        return 'face'
    for b in chain:
        base, _, side = b.name.rpartition('.')
        if base in ('hand', 'foot'):
            return f'{base}.{side}'
    base, _, side = eb.name.rpartition('.')
    if base in ('upper_arm', 'forearm'):
        return f'arm.{side}'
    if base in ('thigh', 'shin'):
        return f'leg.{side}'
    if base == 'heel.02':
        return f'foot.{side}'
    return 'torso'


def _fit(ebs, lm):
    """Move every metarig bone onto the body: trunk by height knots, limbs onto joints, extremities rigidly."""
    src = {role: ebs[b].head.copy() for role, b in SRC.items() if b in ebs}
    src['root'] = Vector((0, 0, 0))
    s = lm['head'].z / src['head'].z
    torso = _torso_map(src, lm, s)
    old = {b.name: (b.head.copy(), b.tail.copy(), b.z_axis.copy(), _region(b)) for b in ebs}
    maps = {'torso': (torso, lambda v: v)}
    maps['face'] = _face_map(src, lm, s) if 'eye.L' in src else maps['torso']
    new = {}
    for side, sign in (('L', 1), ('R', -1)):
        ua, fa, th, sh = (ebs[f'{n}.{side}'] for n in ('upper_arm', 'forearm', 'thigh', 'shin'))
        wrist, ankle = lm[f'hand.{side}'], lm[f'foot.{side}']
        shoulder = lm.get(f'shoulder.{side}', torso(ua.head))
        elbow = lm.get(f'elbow.{side}', _joint_guess(shoulder, wrist, ua, fa, Vector((0, 1, 0))))
        hip = lm.get(f'thigh.{side}', lm['hips'] + s * Vector((sign * HIP_OFFSET[0], *HIP_OFFSET[1:])))
        knee = lm.get(f'knee.{side}', _joint_guess(hip, ankle, th, sh, Vector((0, -1, 0))))
        for b, h, t in ((ua, shoulder, elbow), (fa, elbow, wrist), (th, hip, knee), (sh, knee, ankle)):
            new[b.name] = (h, t, (b.tail - b.head).rotation_difference(t - h) @ b.z_axis)
        r_fo = (fa.tail - fa.head).rotation_difference(wrist - elbow)
        maps[f'hand.{side}'] = _rigid(src[f'hand.{side}'], wrist, r_fo, s)
        d_src, d_tgt = src[f'toe.{side}'] - src[f'foot.{side}'], lm[f'toe.{side}'] - ankle
        maps[f'foot.{side}'] = _rigid(src[f'foot.{side}'], ankle, d_src.rotation_difference(d_tgt),
                                      d_tgt.length / d_src.length)
    for name, (h, t, z, region) in old.items():
        if name not in new:
            point, lin = maps[region]
            new[name] = (point(h), point(t), lin(z))
    if 'jaw' in ebs and 'jaw' in lm:
        new['jaw'] = (lm['jaw'].copy(), *new['jaw'][1:])
    for name, (h, t, z) in new.items():
        if name.startswith(('heel.02', 'toe.')):
            h.z, t.z = max(h.z, 0.0), max(t.z, 0.0)
        eb = ebs[name]
        eb.head, eb.tail = h, t
        eb.align_roll(z)


def _joint_guess(a, c, b1, b2, bend):
    """Middle joint at the source length ratio along a-c, pushed 3 % of the span toward `bend`."""
    u = c - a
    return a + u * (b1.length / (b1.length + b2.length)) + 0.03 * u.length * (bend - bend.dot(u.normalized()) * u.normalized())


def _torso_map(src, lm, s):
    """Height-knot warp for the trunk: z piecewise linear, centre line offset, width scaled by s."""
    roles = ['root', 'hips', 'spine', 'chest', 'neck', 'head']
    zs = [src[r].z for r in roles] + [src['head'].z + 1.0]
    zt = [lm[r].z for r in roles] + [lm['head'].z + s]
    ys, yt = [src[r].y for r in roles] + [src['head'].y], [lm[r].y for r in roles] + [lm['head'].y]
    xt = [lm[r].x for r in roles] + [lm['head'].x]

    def point(p):
        z = float(np.interp(p.z, zs, zt))
        return Vector((s * p.x + np.interp(z, zt, xt), s * (p.y - np.interp(p.z, zs, ys)) + np.interp(z, zt, yt), z))
    return point


def _face_map(src, lm, s):
    """Face bones anchored on the eye midpoint: width scaled by eye distance, height and depth by s."""
    mid_s, mid_t = (src['eye.L'] + src['eye.R']) / 2, (lm['eye.L'] + lm['eye.R']) / 2
    a = Vector(((lm['eye.L'] - lm['eye.R']).length / (src['eye.L'] - src['eye.R']).length, s, s))
    return (lambda p: mid_t + (p - mid_s) * a), (lambda v: v * a)


def _rigid(anchor_src, anchor_tgt, rot, scale):
    return (lambda p: anchor_tgt + scale * (rot @ (p - anchor_src))), (lambda v: rot @ v)


def _def_bone(rig, base):
    for name in (f'DEF-{base}', f'ORG-{base}', base, 'DEF-spine.006'):
        if name in rig.data.bones:
            return name


def _add_helper_bones(ctx, rig):
    """DEF-ground (deforming, under root: hem anchor and game root); one deforming `prop_<id>` bone per prop under it,
    Child Of its attach bone."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones.new(GROUND)
    eb.head, eb.tail, eb.parent, eb.use_deform = (0, 0, 0), (0, 0.1, 0), rig.data.edit_bones['root'], True
    for p in ctx.spec.get('props', []):
        eb = rig.data.edit_bones.new(f'prop_{p["id"]}')
        eb.head = Vector(ctx.landmarks[p['attach']])
        eb.tail = eb.head + Vector((0, 0, 0.15))
        eb.parent, eb.use_deform = rig.data.edit_bones[GROUND], True
    bpy.ops.object.mode_set(mode='OBJECT')
    for p in ctx.spec.get('props', []):
        target = _def_bone(rig, SRC.get(p['attach'], p['attach']))
        con = rig.pose.bones[f'prop_{p["id"]}'].constraints.new('CHILD_OF')
        con.name, con.target, con.subtarget = 'hold', rig, target
        con.inverse_matrix = rig.data.bones[target].matrix_local.inverted()


# ---- weights and binding ----------------------------------------------------------------------------------------

def _bind_parts(ctx, rig):
    """Body: capsule weights; garments and hair cards: transfer from the body; hats: rigid group; rest: bone parent."""
    kinds = {g['id']: g['kind'] for g in ctx.spec.get('garments', [])}
    props = {f'{p["id"]}.{q["id"]}': p['id'] for p in ctx.spec.get('props', []) for q in p['parts']}
    out = {'skinned': [], 'rigid': [], 'parented': [], 'kept': []}
    body = [(pid, bpy.data.objects[p['object']]) for pid, p in ctx.parts.items()
            if p['stage'] == 'body' and bpy.data.objects[p['object']].type == 'MESH']
    defs = _capsule_bones(rig)
    ankle_z = min(ctx.landmarks['foot.L'][2], ctx.landmarks['foot.R'][2])
    src_co, src_w, polys = np.zeros((0, 3)), np.zeros((0, len(defs))), []
    for _, ob in body:
        co = _rest_co(ob)
        w = _plant_soles(co, _capsule_weights(co, rig, defs), defs, ankle_z)
        _write_weights(ob, rig, defs, w)
        polys += [[i + len(src_co) for i in f.vertices] for f in ob.data.polygons]
        src_co, src_w = np.concatenate([src_co, co]), np.concatenate([src_w, w])
        out['skinned'].append(ob.name)
    tree = BVHTree.FromPolygons([tuple(v) for v in src_co], polys) if polys else None
    for pid, part in ctx.parts.items():
        ob = bpy.data.objects[part['object']]
        if part['stage'] in ('body', NAME):
            continue
        if ob.parent is not None:
            out['kept'].append(ob.name)
        elif pid in props:
            bu.parent_to_bone(ob, rig, f'prop_{props[pid]}')
            out['parented'].append(ob.name)
        elif ob.type == 'MESH' and kinds.get(pid.split('.')[0]) in RIGID_KINDS:
            bone = ctx.bones[part['attach'] or 'head']
            _write_weights(ob, rig, [bone], np.ones((len(ob.data.vertices), 1)))
            out['rigid'].append(ob.name)
            out['skinned'].append(ob.name)
        elif ob.type == 'MESH' and part['stage'] in ('garments', 'hair') and tree is not None:
            co = _rest_co(ob)
            w, dist = _transfer(co, tree, polys, src_co, src_w)
            hard = part['stage'] == 'hair' or pid.rpartition('.')[2] in RIGID_PIECES
            if hard:
                w = _rigid_islands(ob, w, dist if part['stage'] == 'hair' else None)
                out['rigid'].append(ob.name)
            else:
                w = _smooth(ob, _anchor_hem(co, w, dist, ctx.landmarks['hips'][2]))
                w = _plant_soles(co, w, defs + [GROUND], ankle_z)
            _write_weights(ob, rig, defs + [GROUND], np.hstack([w, np.zeros((len(w), 1))]) if hard else w)
            out['skinned'].append(ob.name)
        else:
            bu.parent_to_bone(ob, rig, ctx.bones.get(pid) or ctx.bones[part['attach'] or 'root'])
            out['parented'].append(ob.name)
    return out


def _capsule_bones(rig):
    """Deform bones that skin the body: every DEF bone outside the face, minus pelvis/breast helpers."""
    face = {b.name for b in rig.data.bones if b.name.startswith('ORG-') and
            any(p.name == 'ORG-face' for p in b.parent_recursive)} | {'ORG-face'}
    face_bases = {n[4:] for n in face}

    def is_face(n):
        base = n[4:]
        while base and base not in face_bases and base[-4:-3] == '.' and base[-3:].isdigit():
            base = base[:-4]
        return base in face_bases
    return [b.name for b in rig.data.bones if b.use_deform and b.name.startswith('DEF-')
            and not is_face(b.name) and not any(k in b.name for k in SKIP_CAPSULE)]


def _capsule_weights(co, rig, names, chunk=4096):
    """Softmax over the two nearest bone segments (FALLOFF_M), never across the body midline for .L/.R bones."""
    mw = np.array(rig.matrix_world)
    h = np.array([rig.data.bones[n].head_local for n in names]) @ mw[:3, :3].T + mw[:3, 3]
    t = np.array([rig.data.bones[n].tail_local for n in names]) @ mw[:3, :3].T + mw[:3, 3]
    side = np.array([1 if n.endswith('.L') or '.L.' in n else -1 if n.endswith('.R') or '.R.' in n else 0 for n in names])
    ab = t - h
    w = np.zeros((len(co), len(names)))
    for i in range(0, len(co), chunk):
        c = co[i:i + chunk]
        u = np.clip(np.einsum('vbk,bk->vb', c[:, None] - h[None], ab) / (ab * ab).sum(1), 0, 1)
        d = np.linalg.norm(c[:, None] - (h[None] + u[..., None] * ab[None]), axis=2)
        vs = np.where(c[:, 0] > 0.01, 1, np.where(c[:, 0] < -0.01, -1, 0))
        d[(vs[:, None] * side[None]) < 0] = np.inf
        k2 = np.argsort(d, axis=1)[:, :2]
        dk = np.take_along_axis(d, k2, 1)
        e = np.exp(-(dk - dk[:, :1]) / FALLOFF_M)
        np.put_along_axis(w[i:i + chunk], k2, e / e.sum(1, keepdims=True), 1)
    return w


def _transfer(co, tree, polys, src_co, src_w):
    """Nearest-surface interpolated body weights (Data Transfer POLYINTERP_NEAREST in numpy) and the distance."""
    w, dist = np.zeros((len(co), src_w.shape[1])), np.zeros(len(co))
    for i, p in enumerate(co):
        loc, _, fi, dist[i] = tree.find_nearest(Vector(p))
        idx = polys[fi]
        w[i] = np.dot(poly_3d_calc([Vector(src_co[j]) for j in idx], loc), src_w[idx])
    return w, dist


def _plant_soles(co, w, names, ankle_z):
    """Below the ankle, weights fade to foot/toe/ground bones only, so a planted foot never pushes skin under z=0."""
    keep = np.array([any(k in n for k in ('foot', 'toe', 'heel')) or n == GROUND for n in names])
    k = np.clip(co[:, 2] / ankle_z, 0, 1)[:, None]
    out = np.where(keep[None], w, w * k)
    lost = out.sum(1) < 1e-6
    if lost.any():
        foot = [names.index(f'DEF-foot.{"L" if x > 0 else "R"}') for x in co[lost, 0]]
        out[np.flatnonzero(lost), foot] = 1.0
    return out


def _anchor_hem(co, w, dist, hips_z):
    """Garment hanging free below the hips blends toward DEF-ground, so a hem never sinks with the pelvis."""
    h = np.clip((hips_z - co[:, 2]) / hips_z, 0, 1)
    t = np.clip((dist - HEM_GAP_M[0]) / (HEM_GAP_M[1] - HEM_GAP_M[0]), 0, 1)
    f = (h * t * t * (3 - 2 * t))[:, None]
    return np.hstack([(1 - f) * w, f])


def _rigid_islands(ob, w, dist=None):
    """Rigid bind: each loose piece goes whole to one bone, the top bone of its root vertex (closest to the body, for
    hair cards) or of its summed weights (hard pieces such as buckles)."""
    island = _islands(ob, len(w))
    out = np.zeros_like(w)
    for k in np.unique(island):
        sel = np.flatnonzero(island == k)
        src = w[sel[dist[sel].argmin()]] if dist is not None else w[sel].sum(0)
        out[sel, int(src.argmax())] = 1.0
    return out


def _islands(ob, n):
    """Loose-part id per vertex (union-find over edges)."""
    e = np.empty(len(ob.data.edges) * 2, np.int64)
    ob.data.edges.foreach_get('vertices', e)
    parent = np.arange(n)

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for a, b in e.reshape(-1, 2):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)
    return np.array([find(i) for i in range(n)])


def _smooth(ob, w, iters=SMOOTH_ITERS):
    """Uniform Laplacian smoothing of weights over mesh edges, so garment seams between limbs blend."""
    e = np.empty(len(ob.data.edges) * 2, np.int64)
    ob.data.edges.foreach_get('vertices', e)
    e = e.reshape(-1, 2)
    deg = np.bincount(e.ravel(), minlength=len(w)).astype(float)[:, None]
    for _ in range(iters):
        acc = np.zeros_like(w)
        np.add.at(acc, e[:, 0], w[e[:, 1]])
        np.add.at(acc, e[:, 1], w[e[:, 0]])
        w = np.where(deg > 0, 0.5 * w + 0.5 * acc / np.maximum(deg, 1), w)
    return w


def _write_weights(ob, rig, names, w, keep=MAX_INFLUENCES, floor=0.01):
    """Top-`keep` normalized weights into vertex groups, then an Armature modifier first in the stack."""
    top = np.argsort(-w, axis=1)[:, :keep]
    tw = np.take_along_axis(w, top, 1)
    tw[tw < floor] = 0
    tw /= np.maximum(tw.sum(1, keepdims=True), 1e-9)
    groups = {}
    for vi in range(len(w)):
        for j in range(top.shape[1]):
            if tw[vi, j] > 0:
                n = names[top[vi, j]]
                g = groups.get(n) or groups.setdefault(n, ob.vertex_groups.get(n) or ob.vertex_groups.new(name=n))
                g.add([vi], float(tw[vi, j]), 'REPLACE')
    mod = ob.modifiers.new('rig', 'ARMATURE')
    mod.object = rig
    with bpy.context.temp_override(object=ob, active_object=ob):
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    mw = ob.matrix_world.copy()
    ob.parent = rig
    ob.matrix_world = mw


def _rest_co(ob):
    """Base-mesh vertex positions in world space (vertex groups index these, not the evaluated mesh)."""
    co = np.empty(len(ob.data.vertices) * 3)
    ob.data.vertices.foreach_get('co', co)
    m = np.array(ob.matrix_world)
    return co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3]


def _skin_safe(ob):
    """Solidify even-offset spikes metres out on faces that skinning folds (measured -4.8 m on the robe): plain offset."""
    for m in ob.modifiers:
        if m.type == 'SOLIDIFY':
            m.use_even_offset = False


def _influences(ob):
    deform = {g.index for g in ob.vertex_groups if g.name.startswith('DEF-')}
    return max((sum(1 for g in v.groups if g.group in deform and g.weight > 1e-6) for v in ob.data.vertices), default=0)


def _game_skeleton(rig, skinned, roles):
    """DEF bones only, one root: unweighted DEF bones stop deforming, B-bones go linear (what engines skin), and every
    other DEF root hangs under GROUND, its pose kept by a world Copy Transforms from its old parent (or a copy of it)."""
    used = {g.name for ob in skinned for g in ob.vertex_groups} | set(roles)
    used |= {ob.parent_bone for ob in bpy.data.objects if ob.parent == rig and ob.parent_type == 'BONE'}
    eb = None
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    ebs = rig.data.edit_bones
    for b in ebs:
        if b.use_deform and b.name not in used and b.name != GROUND:
            b.use_deform = False
    for b in ebs:
        if b.use_deform:
            b.bbone_segments = 1
    pins = {}
    for b in [b for b in ebs if b.use_deform and b.name != GROUND and not (b.parent and b.parent.use_deform)]:
        old, new = b.parent, _game_parent(b, ebs)
        if not _world_copy(rig.pose.bones[b.name]) and old is not None:
            same = np.allclose(old.matrix, b.matrix, atol=1e-5) and (old.tail - b.tail).length < 1e-5
            if not same:
                eb = ebs.new(f'MCH-game.{b.name[4:]}')
                eb.head, eb.tail, eb.roll, eb.parent, eb.use_deform = b.head, b.tail, b.roll, old, False
            pins[b.name] = old.name if same else eb.name
        b.use_connect, b.parent = False, new
    bpy.ops.object.mode_set(mode='OBJECT')
    for name, target in pins.items():
        pb = rig.pose.bones[name]
        con = pb.constraints.new('COPY_TRANSFORMS')
        con.name, con.target, con.subtarget = 'game_pin', rig, target
        pb.constraints.move(len(pb.constraints) - 1, 0)
    deform = [b for b in rig.data.bones if b.use_deform]
    roots = [b.name for b in deform if not any(p.use_deform for p in b.parent_recursive)]
    col = rig.data.collections.get('GAME') or rig.data.collections.new('GAME')
    for b in deform:
        col.assign(b)
    rig['c3d_game_root'] = GROUND
    return {'bones': len(deform), 'roots': roots, 'pinned': len(pins)}


def _game_parent(b, ebs):
    """Nearest kept DEF bone up the Rigify hierarchy (an ORG-x ancestor maps to DEF-x), else the GROUND root."""
    a = b.parent
    while a is not None:
        for cand in (a, ebs.get('DEF-' + a.name[4:]) if a.name.startswith('ORG-') else None):
            if cand is not None and cand != b and cand.use_deform:
                return cand
        a = a.parent
    return ebs[GROUND]


def _world_copy(pb):
    """First active constraint is a full world Copy Transforms, so the bone's parent does not change its pose."""
    cons = [c for c in pb.constraints if not c.mute and c.influence > 0]
    c = cons[0] if cons else None
    return bool(c and c.type == 'COPY_TRANSFORMS' and c.influence == 1.0 and c.mix_mode == 'REPLACE'
                and c.owner_space == 'WORLD' and c.target_space == 'WORLD')


def _unweighted(ob):
    deform = {g.index for g in ob.vertex_groups if g.name.startswith('DEF-')}
    return sum(1 for v in ob.data.vertices if sum(g.weight for g in v.groups if g.group in deform) < 1e-4)
