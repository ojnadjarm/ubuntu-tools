"""Stage body: MPFB 2 base body from spec macros/targets, CC0 skin, ARKit + viseme keys, hide-under masks, landmarks."""
import hashlib
import importlib
import json
import os
from pathlib import Path

import addon_utils
import bpy
import numpy as np
from mathutils import Matrix

from .. import bpyutil as bu

NAME = 'body'
MPFB = 'bl_ext.user_default.mpfb'
CACHE = Path(os.path.expanduser(os.environ.get('CHAR3D_CACHE', '~/.local/share/char3d/cache'))) / 'body'
RACES = ('african', 'asian', 'caucasian')
PACKS = ('faceunits01', 'visemes02')
ROLE_BONES = {'hips': 'spine05', 'spine': 'spine03', 'chest': 'spine01', 'neck': 'neck01', 'head': 'head', 'jaw': 'jaw',
              'eye.L': 'eye.L', 'eye.R': 'eye.R', 'hand.L': 'wrist.L', 'hand.R': 'wrist.R',
              'foot.L': 'foot.L', 'foot.R': 'foot.R', 'toe.L': 'toe3-1.L', 'toe.R': 'toe3-1.R'}
AUX_BONES = {'elbow.L': 'lowerarm01.L', 'elbow.R': 'lowerarm01.R'}
ALIASES = {
    'nose_long': {'nose-scale-vert-incr': 1.4, 'nose-point-down': 0.8, 'nose-scale-depth-incr': 0.7, 'nose-hump-incr': 0.8,
                  'nose-volume-incr': 0.4},
    'brow_heavy': {'eyebrows-trans-forward': 2.4, 'eyebrows-trans-down': 1.2, 'eyebrows-angle-down': 0.8,
                   'forehead-nubian-incr': 1.4, 'forehead-trans-backward': 0.6},
    'lower_face_narrow': {'chin-width-decr': 1.0, 'l-cheek-bones-decr': 0.5, 'r-cheek-bones-decr': 0.5},
    'elder_sag': {'head-age-incr': 2.0, 'mouth-angles-down': 1.6, 'l-cheek-trans-down': 1.8, 'r-cheek-trans-down': 1.8,
                  'neck-double-incr': 1.6, 'l-eye-bag-incr': 2.5, 'r-eye-bag-incr': 2.5, 'l-ear-lobe-incr': 2.0,
                  'l-eye-eyefold-down': 1.5, 'r-eye-eyefold-down': 1.5,
                  'r-ear-lobe-incr': 2.0, 'l-cheek-volume-decr': 1.8, 'r-cheek-volume-decr': 1.8,
                  'l-cheek-inner-decr': 1.2, 'r-cheek-inner-decr': 1.2,
                  'forehead-temple-decr': 1.8, 'mouth-upperlip-volume-decr': 1.4, 'mouth-lowerlip-volume-decr': 1.4,
                  'chin-prominent-incr': 1.2, 'chin-bones-incr': 1.6, 'chin-jaw-drop-incr': 1.2,
                  'neck-trans-forward': 1.2, 'torso-muscle-pectoral-decr': 2.0, 'stomach-tone-decr': 2.0,
                  'l-hand-fingers-diameter-decr': 2.0, 'r-hand-fingers-diameter-decr': 2.0},
}
# MPFB's lid margin rests on the pupil; these open the fissure to an elder's hooded 8-9 mm.
BASE_TARGETS = {f'{s}-eye-height{k}-incr': 0.45 for s in 'lr' for k in (1, 2, 3)}
# Elder skin on the MPFB group: deep pores, no clearcoat sheen, matte roughness; lips lose most of their tint.
SKIN_FINISH = {'Pore strength': 0.6, 'Clearcoat': 0.0, 'Roughness': 0.55}
LIP_TINT = 0.35
OPPOSITE = [('-incr', '-decr'), ('-up', '-down'), ('-forward', '-backward'), ('-in', '-out')]
NECK_GAP, HAND_GAP, CUFF_GAP = 0.04, 0.02, 0.02
# Elder hand relief (mm, radius mm) at the head of finger<n>-<seg>: MCP, PIP, DIP knuckles; thumb MCP and IP.
KNUCKLES = {1: (1.6, 7.0), 2: (1.0, 5.0), 3: (0.6, 4.0)}
THUMB = {2: (1.0, 5.5), 3: (0.7, 4.5)}
SHAFT_MM, TENDON_MM, TENDON_R_MM = -0.35, 0.7, 2.2


def _svc(name):
    return getattr(importlib.import_module(f'{MPFB}.services.{name.lower()}'), name)


def _enable_mpfb():
    if not addon_utils.check(MPFB)[1]:
        addon_utils.enable(MPFB, default_set=True)
    if not addon_utils.check(MPFB)[1]:
        raise RuntimeError('MPFB not installed in CHAR3D_BLENDER_RES: run char3d-setup')


def _mpfb_version():
    return addon_utils.module_bl_info(importlib.import_module(MPFB)).get('version', '?')


def _expand_targets(targets):
    """Spec targets (alias or raw MPFB name, -1..1) -> {mpfb target: weight >= 0}."""
    out = {}
    for key, val in targets.items():
        if key in ALIASES:
            parts = ALIASES[key]
        elif '-' in key:
            parts = {key: 1.0}
        else:
            raise ValueError(f'body.targets: unknown target {key!r} (alias {sorted(ALIASES)} or an MPFB target name)')
        for name, gain in parts.items():
            w = val * gain
            if w < 0:
                name, w = _opposite(name), -w
            out[name] = out.get(name, 0.0) + w
    return out


def _opposite(name):
    for a, b in OPPOSITE:
        for x, y in ((a, b), (b, a)):
            if name.endswith(x):
                return name[:-len(x)] + y
    raise ValueError(f'body.targets: {name!r} has no opposite for a negative weight')


def _macros(spec_macros):
    macro = _svc('TargetService').get_default_macro_info_dict()
    race = {k: v for k, v in spec_macros.items() if k in RACES} or {'caucasian': 1.0}
    total = sum(race.values()) or 1.0
    macro['race'] = {k: race.get(k, 0.0) / total for k in RACES}
    macro.update({k: v for k, v in spec_macros.items() if k not in RACES})
    return macro


def _skin_file(macro):
    age = 'young' if macro['age'] < 0.6 else 'middleage' if macro['age'] < 0.8 else 'old'
    race = max(RACES, key=lambda r: macro['race'].get(r, 0.0))
    sex = 'male' if macro['gender'] >= 0.5 else 'female'
    name = f'{age}_{race}_{sex}'
    return os.path.join(_svc('LocationService').get_user_data('skins'), name, f'{name}.mhmat')


def _body_co(ob):
    """Rest coordinates of the visible body (helpers excluded) as (N, 3) and their indices."""
    me = ob.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    gi = ob.vertex_groups['body'].index
    idx = np.array([v.index for v in me.vertices if any(g.group == gi for g in v.groups)])
    return co, idx


def _fit_height(ob, height_m):
    co, idx = _body_co(ob)
    s = height_m / (co[idx, 2].max() - co[idx, 2].min())
    ob.scale = (s, s, s)
    for o in bpy.context.view_layer.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    co, idx = _body_co(ob)
    ob.data.transform(Matrix.Translation((0, 0, -co[idx, 2].min())))
    ob.data.update()


def _head_profile(co):
    """(height, head height, menton z): vertex to chin, chin = lowest midline point well in front of the neck."""
    H = co[:, 2].max() - co[:, 2].min()
    mid = co[np.abs(co[:, 0]) < 0.003 * H]
    face = mid[mid[:, 2] > 0.8 * H]
    tip_z = face[face[:, 1].argmin(), 2]
    neck = mid[(mid[:, 2] > tip_z - 0.09 * H) & (mid[:, 2] < tip_z - 0.08 * H)]
    chin = mid[(mid[:, 1] < neck[:, 1].min() - 0.014 * H) & (mid[:, 2] > tip_z - 0.13 * H) & (mid[:, 2] < tip_z)]
    menton = chin[:, 2].min()
    return H, co[:, 2].max() - menton, menton


def _fit_heads(ob, heads):
    """Scale the head about the chin (neck blended over 4 % of the height) so height / head height = heads."""
    co, idx = _body_co(ob)
    H, h, mz = _head_profile(co[idx])
    k = (H - h) / (h * (heads - 1))
    ring = co[idx][np.abs(co[idx, 2] - mz) < 0.005 * H]
    pivot = np.array([0.0, 0.5 * (ring[:, 1].min() + ring[:, 1].max()), mz])
    t = np.clip((co[:, 2] - (mz - 0.04 * H)) / (0.04 * H), 0, 1)
    w = t * t * (3 - 2 * t)
    ob.data.vertices.foreach_set('co', (co + (k - 1) * w[:, None] * (co - pivot)).ravel())
    ob.data.update()


def _skeleton_joints(ob):
    """Rest joints from the MPFB default skeleton, which is added, read and removed."""
    arm = _svc('HumanService').add_builtin_rig(ob, 'default', import_weights=False)
    m = arm.matrix_world
    joints = {k: list(m @ arm.data.bones[b].head_local) for k, b in {**ROLE_BONES, **AUX_BONES}.items()}
    fingers = sum(1 for b in arm.data.bones if b.name.startswith('finger'))
    hand = {b.name: (np.array(m @ b.head_local), np.array(m @ b.tail_local)) for b in arm.data.bones
            if b.name.startswith(('finger', 'wrist'))}
    for mod in [md for md in ob.modifiers if md.type == 'ARMATURE']:
        ob.modifiers.remove(mod)
    mw = ob.matrix_world.copy()
    ob.parent = None
    ob.matrix_world = mw
    bpy.data.objects.remove(arm)
    hx, hy = joints['hips'][0], joints['hips'][1]
    joints['root'] = [hx, hy, 0.0]
    return {k: [round(c, 5) for c in v] for k, v in joints.items()}, fingers, hand


def _dorsal(bones, S):
    """Back-of-hand unit normal: curled fingers bow their PIP joints dorsally; the thumb tip sits palmar."""
    wrist, mcp = bones[f'wrist.{S}'][0], [bones[f'finger{k}-1.{S}'][0] for k in (2, 3, 4, 5)]
    n = np.cross(bones[f'finger3-3.{S}'][1] - wrist, mcp[0] - mcp[3])
    n /= np.linalg.norm(n)
    curl = sum(np.dot(bones[f'finger{k}-2.{S}'][0] - 0.5 * (bones[f'finger{k}-1.{S}'][0] + bones[f'finger{k}-3.{S}'][1]), n)
               for k in (2, 3, 4, 5))
    thumb = np.dot(bones[f'finger1-3.{S}'][1] - np.mean(mcp, axis=0), n)
    vote = curl if abs(curl) > 1e-3 else -thumb
    return (n if vote > 0 else -n), {'curl_mm': round(float(curl) * 1000, 2),
                                     'thumb_mm': round(float(thumb) * 1000, 2)}


def _sculpt_hands(ob, bones, k):
    """Elder hands: dorsal knuckle bumps at every finger joint, slimmer phalanx shafts, raised extensor tendons."""
    me = ob.data
    co, idx = _body_co(ob)
    nr = np.empty(len(me.vertices) * 3)
    me.vertex_normals.foreach_get('vector', nr)
    nr = nr.reshape(-1, 3)[idx]
    p = co[idx]
    d = np.zeros_like(p)
    info = {}

    def bump(center, amp_mm, r_mm, dorsal, power=1.5):
        dist = np.linalg.norm(p - center, axis=1) / (r_mm * 1e-3 * k)
        g = np.exp(-dist ** 2) * (dist < 2.5)
        side = np.clip(nr @ dorsal, 0, 1) ** power if dorsal is not None else 1.0
        d[:] += (amp_mm * 1e-3 * k * g * side)[:, None] * nr
    for S in 'LR':
        if f'wrist.{S}' not in bones:
            continue
        dorsal, info[S] = _dorsal(bones, S)
        for f in (2, 3, 4, 5):
            for seg, (amp, r) in KNUCKLES.items():
                head, tail = bones[f'finger{f}-{seg}.{S}']
                bump(head, amp, r, dorsal)
                bump(0.5 * (head + tail), SHAFT_MM, 0.5 * r, None)
            wrist, mcp = bones[f'wrist.{S}'][0], bones[f'finger{f}-1.{S}'][0]
            seg_v = mcp - wrist
            u = np.clip((p - wrist) @ seg_v / (seg_v @ seg_v), 0, 1)
            dist = np.linalg.norm(p - (wrist + u[:, None] * seg_v), axis=1) / (TENDON_R_MM * 1e-3 * k)
            w = np.exp(-dist ** 2) * (dist < 2.5) * 4 * u * (1 - u) * np.clip(nr @ dorsal, 0, 1) ** 3
            d += (TENDON_MM * 1e-3 * k * w)[:, None] * nr
        for seg, (amp, r) in THUMB.items():
            bump(bones[f'finger1-{seg}.{S}'][0], amp, r, dorsal)
    delta = np.zeros_like(co)
    delta[idx] = d
    me.vertices.foreach_set('co', (co + delta).ravel())
    for kb in (me.shape_keys.key_blocks if me.shape_keys else []):
        kc = np.empty(len(me.vertices) * 3)
        kb.data.foreach_get('co', kc)
        kb.data.foreach_set('co', kc + delta.ravel())
    me.update()
    info['moved_verts'] = int((np.linalg.norm(d, axis=1) > 1e-4).sum())
    info['max_mm'] = round(float(np.linalg.norm(d, axis=1).max()) * 1000, 2)
    return info


def _load_face_keys(ob, packs):
    fs = importlib.import_module(f'{MPFB}.services.faceservice')
    fs.FaceService.load_targets(ob, load_microsoft_visemes='visemes01' in packs, load_meta_visemes='visemes02' in packs,
                                load_arkit_faceunits='faceunits01' in packs)
    keys = set(ob.data.shape_keys.key_blocks.keys()) if ob.data.shape_keys else set()
    want = {'faceunits01': fs.ARKIT_FACEUNITS, 'visemes02': fs.META_VISEMES, 'visemes01': fs.MICROSOFT_VISEMES}
    counts = {}
    for p in packs:
        got = [n for n in want[p] if n in keys]
        if len(got) != len(want[p]):
            raise RuntimeError(f'body: pack {p} loaded {len(got)}/{len(want[p])} shape keys (missing pack? run char3d-setup)')
        counts[p] = len(got)
    return counts


def _cover_robe(g, co, j):
    zs = [z for _, z in g['profile']] if g.get('profile') else [j['foot.L'][2], j['neck'][2]]
    hide = (co[:, 2] >= min(zs)) & (co[:, 2] <= max(zs) - NECK_GAP)
    for side in 'LR':
        wrist, elbow = np.array(j[f'hand.{side}']), np.array(j[f'elbow.{side}'])
        d = (wrist - elbow) / np.linalg.norm(wrist - elbow)
        hand = ((co - wrist) @ d > -HAND_GAP) & (np.linalg.norm(co - wrist, axis=1) < 0.3)
        hide &= ~hand
    return hide


def _cover_boots(g, co, j):
    top = max(j['foot.L'][2], j['foot.R'][2]) + g.get('params', {}).get('cuff_m', 0.1) - CUFF_GAP
    return (co[:, 2] < top) & (co[:, 2] < j['hips'][2] * 0.5)


COVER = {'robe': _cover_robe, 'tunic': _cover_robe, 'boots': _cover_boots}


def _hide_under(ob, spec, joints):
    """Vertex groups delete.<garment> + one inverted Mask so skin under garments never renders."""
    co, idx = _body_co(ob)
    garments = {g['id']: g for g in spec.get('garments', [])}
    union = np.zeros(len(co), bool)
    for gid in spec['body'].get('hide_under', []):
        g = garments.get(gid)
        if g is None or g['kind'] not in COVER:
            raise ValueError(f'body.hide_under: {gid!r} is not a garment of kind {sorted(COVER)}')
        mask = np.zeros(len(co), bool)
        mask[idx] = COVER[g['kind']](g, co[idx], joints)
        ob.vertex_groups.new(name=f'delete.{gid}').add(np.flatnonzero(mask).tolist(), 1.0, 'REPLACE')
        union |= mask
    if union.any():
        ob.vertex_groups.new(name='delete').add(np.flatnonzero(union).tolist(), 1.0, 'REPLACE')
        mod = ob.modifiers.new('hide_under', 'MASK')
        mod.vertex_group, mod.invert_vertex_group = 'delete', True
    return int(union.sum())


def _cache_key(spec):
    src = Path(__file__).read_bytes()
    blob = json.dumps({'body': spec['body'], 'packs': _packs(spec), 'mpfb': _mpfb_version(),
                       'garments': [g for g in spec.get('garments', []) if g['id'] in spec['body'].get('hide_under', [])]},
                      sort_keys=True).encode()
    return hashlib.sha256(src + blob).hexdigest()[:16]


def _packs(spec):
    return list(spec.get('face', {}).get('shape_packs', PACKS))


def _build_mpfb(spec):
    ts, hs = _svc('TargetService'), _svc('HumanService')
    macro = _macros(spec['body'].get('macros', {}))
    ob = hs.create_human(macro_detail_dict=macro)
    targets = dict(BASE_TARGETS)
    for name, w in _expand_targets(spec['body'].get('targets', {})).items():
        targets[name] = targets.get(name, 0.0) + w
    for name, w in targets.items():
        path = ts.target_full_path(name)
        if path is None or os.path.basename(path).split('.')[0] != name:
            raise ValueError(f'body.targets: MPFB target {name!r} not found')
        ts.load_target(ob, path, weight=w)
    ts.bake_targets(ob)
    hs.set_character_skin(_skin_file(macro), ob, skin_type='ENHANCED_SSS')
    _fit_height(ob, spec['body']['height_m'])
    for _ in range(4 if spec['body'].get('heads_tall') else 0):
        _fit_heads(ob, spec['body']['heads_tall'])
        _fit_height(ob, spec['body']['height_m'])
    co, idx = _body_co(ob)
    H, h, _ = _head_profile(co[idx])
    packs = _packs(spec)
    counts = _load_face_keys(ob, packs)
    joints, fingers, hand = _skeleton_joints(ob)
    relief = _sculpt_hands(ob, hand, spec['body']['height_m'] / 1.78)
    hidden = _hide_under(ob, spec, joints)
    ob.name = ob.data.name = 'body'
    return ob, joints, {'heads_tall': round(H / h, 3), 'head_height_m': round(h, 4), 'finger_bones': fingers,
                        'packs': counts, 'hidden_verts': hidden, 'hand_relief': relief, 'skin': Path(_skin_file(macro)).stem,
                        'mpfb': '.'.join(map(str, _mpfb_version()))}


def _skin_finish(ob):
    """Matte aged skin: group inputs per material, plus crease and blotch noise in the shared group's bump and roughness."""
    groups = set()
    for m in ob.data.materials:
        g = m.node_tree.nodes.get('Human.body') if m and m.use_nodes else None
        if g is None:
            continue
        for k, v in SKIN_FINISH.items():
            g.inputs[k].default_value = v
        if m.name.endswith('lips'):
            g.inputs['colorMixInStrength'].default_value *= LIP_TINT
        groups.add(g.node_tree)
    for nt in groups:
        n = nt.nodes
        if 'c3d_crease' in n:
            continue
        uv = n['Texture Coordinate'].outputs['UV']
        crease = n.new('ShaderNodeTexNoise')
        crease.name = 'c3d_crease'
        crease.inputs['Scale'].default_value, crease.inputs['Detail'].default_value = 180.0, 6.0
        crease.inputs['Distortion'].default_value = 2.0
        nt.links.new(uv, crease.inputs['Vector'])
        add = n.new('ShaderNodeMath')
        add.operation, add.inputs[2].default_value = 'MULTIPLY_ADD', 0.0
        add.inputs[1].default_value = 0.6
        nt.links.new(crease.outputs['Fac'], add.inputs[0])
        nt.links.new(n['ColorRamp'].outputs['Color'], add.inputs[2])
        nt.links.new(add.outputs[0], n['Bump'].inputs['Height'])
        blotch = n.new('ShaderNodeTexNoise')
        blotch.inputs['Scale'].default_value, blotch.inputs['Detail'].default_value = 40.0, 4.0
        nt.links.new(uv, blotch.inputs['Vector'])
        rough = n.new('ShaderNodeMapRange')
        rough.inputs['To Min'].default_value, rough.inputs['To Max'].default_value = 0.8, 1.2
        nt.links.new(blotch.outputs['Fac'], rough.inputs['Value'])
        mul = n.new('ShaderNodeMath')
        mul.operation = 'MULTIPLY'
        nt.links.new(n['Group Input'].outputs['Roughness'], mul.inputs[0])
        nt.links.new(rough.outputs['Result'], mul.inputs[1])
        nt.links.new(mul.outputs[0], n['Principled BSDF'].inputs['Roughness'])


def _metrics(ob, extra):
    me = ob.data
    quads = sum(1 for p in me.polygons if p.loop_total == 4)
    keys = me.shape_keys.key_blocks if me.shape_keys else []
    face_keys = sum(extra['packs'].values())
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg).to_mesh()
    visible = len(ev.vertices)
    ob.evaluated_get(dg).to_mesh_clear()
    assert me.uv_layers, 'body has no UVs'
    return {'stub': False, 'verts': len(me.vertices), 'visible_verts': visible, 'faces': len(me.polygons),
            'quads_pct': round(100.0 * quads / len(me.polygons), 2), 'uv_layers': len(me.uv_layers),
            'shape_keys': face_keys, 'shape_keys_total': len(keys), **extra}


def _place(ob):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    bu.collection('char3d').objects.link(ob)


def _run_mpfb(ctx):
    _enable_mpfb()
    CACHE.mkdir(parents=True, exist_ok=True)
    key = _cache_key(ctx.spec)
    blend, meta = CACHE / f'{key}.blend', CACHE / f'{key}.json'
    if blend.exists() and meta.exists():
        info = json.loads(meta.read_text())
        with bpy.data.libraries.load(str(blend), link=False) as (src, dst):
            dst.objects = ['body']
        ob = dst.objects[0]
        bu.collection('char3d').objects.link(ob)
        info['metrics']['cache'] = 'hit'
    else:
        ob, joints, extra = _build_mpfb(ctx.spec)
        _place(ob)
        info = {'landmarks': joints, 'metrics': _metrics(ob, extra)}
        bpy.data.libraries.write(str(blend), {ob}, compress=True)
        meta.write_text(json.dumps(info, indent=1))
        info['metrics']['cache'] = 'miss'
    _skin_finish(ob)
    j = info['landmarks']
    ctx.landmarks = {r: j[r] for r in ['root', *ROLE_BONES]}
    assert j['eye.L'][0] > 0 > j['eye.L'][1], f'body: unexpected orientation eye.L={j["eye.L"]}'
    ctx.add_part('body', ob.name, NAME, ctx.spec['body']['skin'], 'hips')
    return {**info['metrics'], 'cache_key': key}


def _placeholder_landmarks(h):
    return {
        'root': (0, 0, 0), 'hips': (0, 0, 0.53 * h), 'spine': (0, 0, 0.62 * h), 'chest': (0, 0, 0.75 * h),
        'neck': (0, 0, 0.85 * h), 'head': (0, 0, 0.9 * h), 'jaw': (0, -0.03, 0.885 * h),
        'eye.L': (0.032, -0.085, 0.935 * h), 'eye.R': (-0.032, -0.085, 0.935 * h),
        'hand.L': (0.27, -0.06, 0.5 * h), 'hand.R': (-0.27, -0.06, 0.5 * h),
        'foot.L': (0.1, 0, 0.06), 'foot.R': (-0.1, 0, 0.06), 'toe.L': (0.1, -0.12, 0.02), 'toe.R': (-0.1, -0.12, 0.02),
    }


def _run_placeholder(ctx):
    h = ctx.spec['body']['height_m']
    ctx.landmarks = {k: list(v) for k, v in _placeholder_landmarks(h).items()}
    torso = bu.uv_sphere('body', 1.0, (0, 0, 0.43 * h + 0.03), scale=(0.18, 0.13, 0.43 * h))
    head = bu.uv_sphere('body_head', 0.11, (0, -0.01, 0.94 * h))
    for ob in bpy.context.view_layer.objects:
        ob.select_set(ob in (torso, head))
    bpy.context.view_layer.objects.active = torso
    bpy.ops.object.join()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ctx.add_part('body', torso.name, NAME, ctx.spec['body']['skin'], 'hips')
    return {'stub': True, 'verts': len(torso.data.vertices), 'heads_tall': round(h / 0.22, 3), 'finger_bones': 0}


BASES = {'mpfb': _run_mpfb, 'placeholder': _run_placeholder}


def run(ctx):
    return BASES[ctx.spec['body']['base']](ctx)
