"""Stage export: GLB and FBX of the parts with the deform (game) skeleton, morph targets and one animation per clip (hair as cards)."""
import importlib
import json
import struct

import bmesh
import bpy
import bpy_extras.io_utils as io_utils
import numpy as np

NAME = 'export'
MORPH_NORMALS = False  # measured: +11 MB (+73 %) on 91 MPFB face targets, would break the 30 MB budget
CLIP_GAP = 10
GAME_ROOT = 'root'
SIM = {'CLOTH', 'SOFT_BODY', 'COLLISION', 'SURFACE_DEFORM', 'MESH_DEFORM', 'MESH_CACHE', 'MESH_SEQUENCE_CACHE', 'DYNAMIC_PAINT'}


def export_objects(ctx, hair):
    """Mesh and armature part objects, parts left out, and hair curves shipped as their `<id>.cards` mesh part."""
    obs, skipped = [], []
    for pid, part in ctx.parts.items():
        if part['stage'] == 'hair' and hair == 'none':
            continue
        ob = bpy.data.objects.get(part['object'])
        if ob and ob.type in ('MESH', 'ARMATURE'):
            obs += [ob] if ob not in obs else []
        else:
            skipped.append(pid)
    names = {ob.name for ob in obs}
    carded = [p for p in skipped if ctx.parts.get(f'{p}.cards', {}).get('object') in names]
    return obs, [p for p in skipped if p not in carded], carded


def baked(ob):
    """Modifier stack applied except armature and simulation modifiers; shape keys re-evaluated one by one (pinned)."""
    hidden = [m for m in ob.modifiers if (m.type == 'ARMATURE' or m.type in SIM) and m.show_viewport]
    for m in hidden:
        m.show_viewport = False
    keys, pin, active = ob.data.shape_keys, ob.show_only_shape_key, ob.active_shape_key_index
    ob.show_only_shape_key, ob.active_shape_key_index = bool(keys), 0
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    shapes = []
    for i, kb in enumerate(keys.key_blocks[1:] if keys else [], 1):
        ob.active_shape_key_index = i
        bpy.context.view_layer.update()
        ev = ob.evaluated_get(dg)
        m = ev.to_mesh()
        co = np.empty(len(m.vertices) * 3, np.float32)
        m.vertices.foreach_get('co', co)
        ev.to_mesh_clear()
        if len(co) != 3 * len(me.vertices):
            raise RuntimeError(f'export: {ob.name} key {kb.name} changes the vertex count under its modifiers')
        shapes.append((kb.name, co))
    ob.show_only_shape_key, ob.active_shape_key_index = pin, active
    for m in hidden:
        m.show_viewport = True
    return me, shapes


def bake_proxy(ob):
    """Stand-in object under the source's name, so names, KEY slots and skin groups line up in the GLB."""
    me, shapes = baked(ob)
    name = ob.name
    ob.name = name + '.src'
    px = bpy.data.objects.new(name, me)
    for col in ob.users_collection:
        col.objects.link(px)
    if shapes:
        key_name = ob.data.shape_keys.name
        ob.data.shape_keys.name = key_name + '.src'
        px.shape_key_add(name='Basis', from_mix=False)
        px.data.shape_keys.name = key_name
        for kname, co in shapes:
            px.shape_key_add(name=kname, from_mix=False).data.foreach_set('co', co)
    for vg in ob.vertex_groups:
        px.vertex_groups.new(name=vg.name)
    for m in ob.modifiers:
        if m.type == 'ARMATURE':
            px.modifiers.new(m.name, 'ARMATURE').object = m.object
    px.parent, px.parent_type, px.parent_bone = ob.parent, ob.parent_type, ob.parent_bone
    px.matrix_parent_inverse = ob.matrix_parent_inverse.copy()
    px.matrix_basis = ob.matrix_basis.copy()
    px['c3d_src_hidden'], ob.hide_viewport = ob.hide_viewport, True
    return px


def deform_weights(ob):
    """Per vertex, its non-zero weights on deform bones of the mesh's armature, strongest first."""
    arm = next((m.object for m in ob.modifiers if m.type == 'ARMATURE' and m.object), None)
    if arm is None:
        return []
    deform = {vg.index for vg in ob.vertex_groups if vg.name in arm.data.bones and arm.data.bones[vg.name].use_deform}
    return [(v.index, sorted(((g.weight, g.group) for g in v.groups if g.group in deform and g.weight > 1e-6),
                             reverse=True)) for v in ob.data.vertices]


def influences(ob):
    return max((len(w) for _, w in deform_weights(ob)), default=0)


def limit_influences(ob, n):
    """Keep the n strongest deform weights per vertex, renormalised to 1 (the engine skinning limit)."""
    for vi, w in deform_weights(ob):
        if len(w) <= n:
            continue
        total = sum(x for x, _ in w[:n])
        for _, g in w[n:]:
            ob.vertex_groups[g].remove([vi])
        for x, g in w[:n]:
            ob.vertex_groups[g].add([vi], x / total, 'REPLACE')
    return influences(ob)


def ngons(ob):
    return sum(1 for f in ob.data.polygons if f.loop_total > 4)


def triangulate_ngons(ob):
    """Split faces over 4 sides into triangles (glTF exporters compute tangents only on tris and quads)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    faces = [f for f in bm.faces if len(f.verts) > 4]
    if faces:
        bmesh.ops.triangulate(bm, faces=faces)
        bm.to_mesh(ob.data)
    bm.free()
    return len(faces)


def drop_proxy(src, px):
    me, hidden = px.data, bool(px['c3d_src_hidden'])
    bpy.data.objects.remove(px)
    bpy.data.meshes.remove(me)
    src.name, src.hide_viewport = src.name[:-4], hidden
    if src.data.shape_keys:
        src.data.shape_keys.name = src.data.shape_keys.name[:-4]


def push_clips(ctx, obs, sequential=False):
    """One NLA track per clip named by its id: the rig gets the Action's object slot, each shape-key block its KEY slot.
    sequential lays the clips end to end without extrapolation, so a bake of one rig strip's range (FBX takes) sees
    only that clip's shape-key strip."""
    targets = [(ob, ob) for ob in obs if ob.type == 'ARMATURE']
    targets += [(ob.data.shape_keys, ob) for ob in obs if ob.type == 'MESH' and ob.data.shape_keys]
    saved = []
    for idb, ob in targets:
        ad = idb.animation_data or idb.animation_data_create()
        saved.append((ad, ad.action, ad.action_slot if ad.action else None, ad.use_nla, list(ad.nla_tracks)))
        ad.action = None
        ad.use_nla = True
        cursor = 1
        for cid, clip in ctx.clips.items():
            act = bpy.data.actions[clip['action']]
            start = cursor if sequential else int(clip['start'])
            cursor += clip['end'] - clip['start'] + 1 + CLIP_GAP
            want = 'OBJECT' if idb is ob else 'KEY'
            slots = [s for s in act.slots if s.target_id_type == want and (want == 'OBJECT' or s.name_display == idb.name)]
            if not slots:
                continue
            track = ad.nla_tracks.new()
            track.name = cid
            strip = track.strips.new(cid, start, act)
            strip.action_slot = slots[0]
            if sequential:
                strip.extrapolation = 'NOTHING'
    return saved


def pop_clips(saved):
    for ad, action, slot, use_nla, keep in saved:
        for track in [t for t in ad.nla_tracks if t not in keep]:
            ad.nla_tracks.remove(track)
        ad.action, ad.use_nla = action, use_nla
        if action is not None and slot is not None:
            ad.action_slot = slot


def unparent_skinned(obs):
    """Skinned meshes go to the glTF root (a parented skinned mesh is a validator warning); returns the restore list."""
    saved = []
    bpy.context.view_layer.update()
    for ob in obs:
        if ob.type == 'MESH' and ob.parent and any(m.type == 'ARMATURE' for m in ob.modifiers):
            saved.append((ob, ob.parent, ob.parent_type, ob.parent_bone, ob.matrix_parent_inverse.copy(), ob.matrix_basis.copy()))
            mw = ob.matrix_world.copy()
            ob.parent = None
            ob.matrix_world = mw
    return saved


def reparent(saved):
    for ob, parent, ptype, pbone, inv, basis in saved:
        ob.parent, ob.parent_type, ob.parent_bone = parent, ptype, pbone
        ob.matrix_parent_inverse, ob.matrix_basis = inv, basis


def glb_json(path):
    data = path.read_bytes()
    return json.loads(data[20:20 + struct.unpack('<I', data[12:16])[0]])


def fbx_operator():
    """Distro Blender on Python 3.14: orientation_helper drops the FBX exporter's class-body properties; re-register it."""
    if 'use_selection' in bpy.ops.export_scene.fbx.get_rna_type().properties:
        return
    import io_scene_fbx
    orig = io_utils.orientation_helper

    def keep_body(**kw):
        def wrap(cls):
            body = dict(cls.__annotations__)
            cls = orig(**kw)(cls)
            cls.__annotations__ = {**body, **cls.__annotations__}
            return cls
        return wrap

    io_scene_fbx.unregister()
    io_utils.orientation_helper = keep_body
    try:
        importlib.reload(io_scene_fbx)
    finally:
        io_utils.orientation_helper = orig
    io_scene_fbx.register()


def deform_parent(rig, bone, deform):
    """Nearest ancestor that is a deform bone or the ORG- twin of one (Rigify parents DEF bones to ORG/MCH chains)."""
    p = bone.parent
    while p:
        for name in (p.name, 'DEF-' + p.name[4:] if p.name.startswith('ORG-') else None):
            if name in deform and name != bone.name \
                    and all(a.name != bone.name for a in rig.data.bones[name].parent_recursive):
                return name
        p = p.parent
    return None


def game_skeleton(rig):
    """Armature of the rig's deform bones following the rig by Copy Transforms: each bone under its deform_parent, every
    leftover root under one `root` bone (it follows the rig's root bone when there is one): one root, no control bones."""
    game = bpy.data.objects.new(rig.name + '.game', bpy.data.armatures.new(rig.data.name + '.game'))
    rig.users_collection[0].objects.link(game)
    game.matrix_world = rig.matrix_world.copy()
    deform = {b.name for b in rig.data.bones if b.use_deform}
    parents = {name: deform_parent(rig, rig.data.bones[name], deform) for name in deform}
    for name in parents:
        seen, p = {name}, parents[name]
        while p and p not in seen:
            seen.add(p)
            p = parents[p]
        if p:
            parents[name] = None
    roots = [n for n, p in parents.items() if p is None]
    top = roots[0] if len(roots) == 1 else GAME_ROOT
    for ob in bpy.context.view_layer.objects:
        ob.select_set(ob is game)
    bpy.context.view_layer.objects.active = game
    bpy.ops.object.mode_set(mode='EDIT')
    eb = game.data.edit_bones
    if top == GAME_ROOT:
        src = rig.data.bones.get(GAME_ROOT)
        e = eb.new(GAME_ROOT)
        e.head, e.tail = (src.head_local, src.tail_local) if src else ((0, 0, 0), (0, 0.2, 0))
    for name in deform:
        b, e = rig.data.bones[name], eb.new(name)
        e.head, e.tail = b.head_local, b.tail_local
        e.matrix = b.matrix_local
        e.length = b.length
    for name, p in parents.items():
        if name != top:
            eb[name].parent = eb[p or top]
    bpy.ops.object.mode_set(mode='OBJECT')
    for b in game.pose.bones:
        if b.name in rig.pose.bones:
            c = b.constraints.new('COPY_TRANSFORMS')
            c.target, c.subtarget = rig, b.name
    return game, parents


def take_strips(ctx, game):
    """One empty-action strip per clip on the game rig over the clip's sequential range: exporters bake one animation
    per strip while the source rig and the shape keys play their own sequential strips."""
    ad = game.animation_data_create()
    cursor = 1
    for cid, clip in ctx.clips.items():
        n = clip['end'] - clip['start']
        act = bpy.data.actions.new(f'{game.name}.{cid}')
        act.use_frame_range, act.frame_start, act.frame_end = True, cursor, cursor + n
        slot = act.slots.new(id_type='OBJECT', name=game.name)
        track = ad.nla_tracks.new()
        track.name = cid
        strip = track.strips.new(cid, cursor, act)
        strip.action_slot = slot
        cursor += n + 1 + CLIP_GAP


class GameRig:
    """Context manager: export objects bound to game skeletons instead of their source rigs (skin modifiers swapped,
    bone-parented parts moved to the matching game bone), all restored and the game rigs deleted on exit."""

    def __init__(self, ctx, obs, actions):
        self.ctx, self.obs, self.actions = ctx, obs, actions

    def __enter__(self):
        self.games = {}
        for rig in [ob for ob in self.obs if ob.type == 'ARMATURE']:
            self.games[rig] = game_skeleton(rig)
        self.mods = [m for ob in self.obs if ob.type == 'MESH' for m in ob.modifiers
                     if m.type == 'ARMATURE' and m.object in self.games]
        for m in self.mods:
            m.object = self.games[m.object][0]
        self.parented = []
        bpy.context.view_layer.update()
        for ob in self.obs:
            if ob.parent in self.games and ob.parent_type == 'BONE':
                game, parents = self.games[ob.parent]
                bone = ob.parent_bone if ob.parent_bone in game.data.bones else self.game_bone(ob.parent, ob.parent_bone)
                self.parented.append((ob, ob.parent, ob.parent_bone, ob.matrix_parent_inverse.copy(), ob.matrix_basis.copy()))
                mw = ob.matrix_world.copy()
                ob.parent, ob.parent_bone = game, bone
                bpy.context.view_layer.update()
                ob.matrix_world = mw
        if self.actions:
            for game, _ in self.games.values():
                take_strips(self.ctx, game)
        return [ob for ob in self.obs if ob not in self.games] + [g for g, _ in self.games.values()]

    def game_bone(self, rig, name):
        """Game bone for a non-deform source bone: its ORG twin's deform bone or the nearest deform ancestor's."""
        game, _ = self.games[rig]
        b = rig.data.bones[name]
        while b:
            for n in (b.name, 'DEF-' + b.name[4:] if b.name.startswith('ORG-') else None):
                if n and n in game.data.bones:
                    return n
            b = b.parent
        return GAME_ROOT if GAME_ROOT in game.data.bones else game.data.bones[0].name

    def __exit__(self, *exc):
        for ob, parent, bone, inv, basis in self.parented:
            ob.parent, ob.parent_bone = parent, bone
            ob.matrix_parent_inverse, ob.matrix_basis = inv, basis
        for m in self.mods:
            m.object = next(rig for rig, (game, _) in self.games.items() if game is m.object)
        for game, _ in self.games.values():
            acts = [s.action for t in game.animation_data.nla_tracks for s in t.strips] if game.animation_data else []
            data = game.data
            bpy.data.objects.remove(game)
            bpy.data.armatures.remove(data)
            for a in acts:
                bpy.data.actions.remove(a)


def run(ctx):
    opts = ctx.spec['export']
    if not opts.get('gltf'):
        return {'skipped': True}
    obs, skipped, carded = export_objects(ctx, opts.get('hair', 'cards'))
    limit = ctx.spec.get('asset', {}).get('max_influences', 4)
    meshes = [ob for ob in obs if ob.type == 'MESH']
    source_inf = {ob: influences(ob) for ob in meshes}
    proxies = {ob: bake_proxy(ob) for ob in meshes if source_inf[ob] > limit or ngons(ob)
               or any(m.show_viewport and m.type != 'ARMATURE' and m.type not in SIM for m in ob.modifiers)}
    split = sum(triangulate_ngons(px) for px in proxies.values())
    shipped_inf = max([limit_influences(px, limit) for px in proxies.values()]
                      + [n for ob, n in source_inf.items() if ob not in proxies], default=0)
    obs = [proxies.get(ob, ob) for ob in obs]
    actions = opts.get('actions', True) and bool(ctx.clips)
    saved = push_clips(ctx, obs, sequential=True) if actions else []
    path, fbx = ctx.out / f'{ctx.id}.glb', ctx.out / f'{ctx.id}.fbx'
    try:
        with GameRig(ctx, obs, actions) as sel:
            parents = unparent_skinned(sel)
            try:
                for ob in bpy.context.view_layer.objects:
                    ob.select_set(ob in sel)
                bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                                          export_apply=False, export_animations=actions,
                                          export_animation_mode='NLA_TRACKS', export_anim_slide_to_zero=True,
                                          export_morph=opts.get('morphs', True), export_morph_normal=MORPH_NORMALS,
                                          export_tangents=True, export_def_bones=True,
                                          export_cameras=False, export_lights=False)
                if opts.get('fbx'):
                    fbx_operator()
                    bpy.ops.export_scene.fbx(filepath=str(fbx), use_selection=True, object_types={'ARMATURE', 'MESH'},
                                             use_mesh_modifiers=False, add_leaf_bones=False,
                                             use_armature_deform_only=True, bake_anim=actions,
                                             bake_anim_use_nla_strips=True, bake_anim_use_all_actions=False,
                                             bake_anim_force_startend_keying=True, bake_anim_simplify_factor=0.0,
                                             path_mode='STRIP')
            finally:
                reparent(parents)
    finally:
        pop_clips(saved)
        for src, px in proxies.items():
            drop_proxy(src, px)
    g = glb_json(path)
    anims = sorted(a['name'] for a in g.get('animations', []))
    if actions and anims != sorted(ctx.clips):
        raise RuntimeError(f'export: animations {anims} != clips {sorted(ctx.clips)}')
    ctx.files['glb'] = str(path)
    if opts.get('fbx'):
        ctx.files['fbx'] = str(fbx)
    targets = max((len(p.get('targets', [])) for m in g.get('meshes', []) for p in m['primitives']), default=0)
    joints = {j for s in g.get('skins', []) for j in s['joints']}
    parent = {c for n in g.get('nodes', []) for c in n.get('children', [])}
    up = {c: i for i, n in enumerate(g.get('nodes', [])) for c in n.get('children', [])}
    return {'mb': round(path.stat().st_size / 1e6, 3), 'animations': anims, 'morph_targets': targets,
            'meshes': len(g.get('meshes', [])), 'joints': len(joints),
            'root_joints': sum(1 for j in joints if j not in parent or up[j] not in joints),
            'fbx_mb': round(fbx.stat().st_size / 1e6, 3) if opts.get('fbx') else None, 'proxies': len(proxies),
            'max_influences': shipped_inf, 'source_influences': max(source_inf.values(), default=0),
            'ngons_split': split,
            'skipped': skipped, 'as_cards': carded}
