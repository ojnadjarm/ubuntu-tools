"""Stage secondary: robe cloth on a sim cage (loop crossfade), garment verts embedded in it and pushed out of the body and
ground, delivered by PC2 driver meshes + Surface Deform; spring chains; emissive pulses."""
import math
import struct
import time
from contextlib import contextmanager

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

from .. import bpyutil as bu

NAME = 'secondary'
COL = 'char3d_sim'
SUBSTEPS = 4
XFADE = 8
SETTLE_S = 1.0
PREROLL_S = 2.0
ROOT_FRAC = 0.3
PUSH_M = 0.004
CLEAR_M = 0.002
REACH_M = 0.06
FORCE_SIGMA_S = 0.1
GRID_SMOOTH = 4
DRIVE_TOL_M = 0.0005
BIND_SHIFT = np.array([1.0, 2.0, 3.0]) / math.sqrt(14) * 1e-4
LEVER_MIN_M = 0.05
FRAME_PROP, PULSE_PROP = 'c3d_cloth_frame', 'c3d_pulse_w'


# ---------- numpy core (no bpy) ----------

def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def frame_accels(rots, pos, fps, loop):
    """Angular and linear acceleration per sample, in the sample's local frame; (n+1) samples, the last = frame end+1."""
    n = len(rots) - 1
    om = np.array([_rotvec(rots[i + 1] @ rots[i].T) for i in range(n)]) * fps
    vel = np.diff(pos, axis=0) * fps
    if loop:
        alpha, acc = (om - np.roll(om, 1, 0)) * fps, (vel - np.roll(vel, 1, 0)) * fps
        alpha, acc = np.vstack([alpha, alpha[:1]]), np.vstack([acc, acc[:1]])
    else:
        z = np.zeros((1, 3))
        alpha, acc = np.diff(np.vstack([z, om, z]), axis=0) * fps, np.diff(np.vstack([z, vel, z]), axis=0) * fps
    return np.einsum('fji,fj->fi', rots, alpha), np.einsum('fji,fj->fi', rots, acc)


def smooth_series(x, sigma, loop):
    """Gaussian low-pass along axis 0 (sigma in samples); periodic for loops (last sample = first), edge-held otherwise."""
    if sigma <= 0:
        return x
    r = int(math.ceil(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    body = x[:-1] if loop else x
    pad = np.concatenate([body[-r:], body, body[:r]]) if loop else np.concatenate([body[:1].repeat(r, 0), body, body[-1:].repeat(r, 0)])
    out = sum(w * pad[i:i + len(body)] for i, w in enumerate(k))
    return np.vstack([out, out[:1]]) if loop else out


def _rotvec(m):
    c = np.clip((np.trace(m) - 1) / 2, -1, 1)
    ang = math.acos(c)
    w = np.array([m[2, 1] - m[1, 2], m[0, 2] - m[2, 0], m[1, 0] - m[0, 1]])
    s = np.linalg.norm(w)
    return w / s * ang if s > 1e-12 else w / 2


def spring_chain(alpha, acc, dirs, levers, k, c, fps, loop, periods):
    """Damped angular springs, each bone relative to its parent, forced by the parent frame's motion.

    Returns (samples, bones, 3) rotation vectors in the attach frame and the last-period error (rad, loops only)."""
    n = len(alpha) - 1 if loop else len(alpha)
    ext = -alpha[:, None, :] - np.cross(dirs[None], acc[:, None, :]) / levers[None, :, None]
    h = 1.0 / fps / SUBSTEPS
    a, v = np.zeros_like(dirs), np.zeros_like(dirs)
    reps = periods + 1 if loop else 1
    out = np.empty((reps * n, len(dirs), 3))
    for f in range(reps * n):
        i = f % n if loop else f
        e0, e1 = ext[i], ext[i + 1] if i + 1 < len(ext) else ext[i]
        for s in range(SUBSTEPS):
            t = s / SUBSTEPS
            rhs = -k * a - c * v + e0 * (1 - t) + e1 * t
            v += np.diff(rhs, axis=0, prepend=np.zeros((1, 3))) * h
            a += v * h
        out[f] = a
    if not loop:
        return out, 0.0
    out = out.reshape(reps, n, len(dirs), 3)
    return np.vstack([out[-1], out[-1][:1]]), float(np.abs(out[-1] - out[-2]).max())


def chain_points(V, root_hint, nb):
    """Chain joints along a part: slab centroids from the root region (nearest the attach joint) to the far tip."""
    d = np.linalg.norm(V - root_hint, axis=1)
    near = V[d <= np.quantile(d, 0.15)].mean(0)
    dn = np.linalg.norm(V - near, axis=1)
    far = V[dn >= np.quantile(dn, 0.95)].mean(0)
    axis = (far - near) / np.linalg.norm(far - near)
    s = (V - near) @ axis
    s0, s1 = ROOT_FRAC * s.max(), s.max()
    half = (s1 - s0) / nb / 2
    joints = []
    for j in range(nb + 1):
        sj = s0 + (s1 - s0) * j / nb
        sel = np.abs(s - sj) < half
        joints.append(V[sel].mean(0) if sel.sum() >= 3 else near + axis * sj)
    return np.array(joints), (s - s0) / (s1 - s0) * nb


def chain_weights(x, nb):
    """(verts, nb) bone weights from the chain coordinate x (0 at the root joint, nb at the tip) and the attach weight."""
    total = smoothstep(x / 0.5)
    y = np.clip(x - 0.5, 0, nb - 1)
    b = np.floor(y).astype(int)
    f = y - b
    w = np.zeros((len(x), nb))
    w[np.arange(len(x)), b] = (1 - f) * total
    nxt = np.minimum(b + 1, nb - 1)
    w[np.arange(len(x)), nxt] += f * total * (b + 1 < nb)
    return w, 1 - total


def loop_crossfade(A, nxt, k=XFADE):
    """Spread the seam offset (next cycle start - this cycle start) over the last k frames, smoothstep."""
    E = nxt - A[0]
    L = A.copy()
    for i in range(k):
        L[len(A) - k + i] -= smoothstep(np.array((i + 1) / k)) * E
    return L


def grid_frames(G):
    """Orthonormal frame per cage grid vertex, (rings, seg, 3, 3); columns: around, along the surface, outward normal."""
    tv = np.roll(G, -1, 1) - np.roll(G, 1, 1)
    tu = np.gradient(G, axis=0)
    e1 = tv / np.maximum(np.linalg.norm(tv, axis=-1, keepdims=True), 1e-9)
    n = np.cross(tu, e1)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
    return np.stack([e1, np.cross(n, e1), n], -1)


def smooth_grid(G, iters=GRID_SMOOTH):
    """Laplacian smoothing of a lathe grid (periodic around, held ends along): offsets carried on it cannot fold."""
    G = G.copy()
    for _ in range(iters):
        nb = np.roll(G, 1, 1) + np.roll(G, -1, 1)
        nb[1:-1] += G[:-2] + G[2:]
        nb[1:-1] /= 4
        nb[[0, -1]] /= 2
        G += 0.5 * (nb - G)
    return G


def embed(P, G, centre):
    """Bind points to a lathe grid (rings top to bottom, seg around centre): 4 corner ids, bilinear weights, local offsets."""
    R, S = G.shape[:2]
    zt, zb = G[0, :, 2].mean(), G[-1, :, 2].mean()
    u = np.clip((zt - P[:, 2]) / (zt - zb) * (R - 1), 0, R - 1 - 1e-9)
    v = np.arctan2(P[:, 1] - centre[1], P[:, 0] - centre[0]) / (2 * np.pi) % 1 * S
    i0, j0 = u.astype(int), v.astype(int) % S
    fu, fv = u - i0, v - np.floor(v)
    i1, j1 = np.minimum(i0 + 1, R - 1), (j0 + 1) % S
    ids = np.stack([i0 * S + j0, i0 * S + j1, i1 * S + j0, i1 * S + j1], 1)
    w = np.stack([(1 - fu) * (1 - fv), (1 - fu) * fv, fu * (1 - fv), fu * fv], 1)
    g, f = G.reshape(-1, 3), grid_frames(G).reshape(-1, 3, 3)
    off = np.einsum('ncji,ncj->nci', f[ids], P[:, None] - g[ids])
    return ids, w, off


def unembed(bind, G):
    """Points from a deformed grid: bilinear blend of each corner's moved frame carrying its rest offset."""
    ids, w, off = bind
    g, f = G.reshape(-1, 3), grid_frames(G).reshape(-1, 3, 3)
    return np.einsum('nc,nci->ni', w, g[ids] + np.einsum('ncij,ncj->nci', f[ids], off))


def cloth_share(P, profile, centre, hz):
    """1 on the skirt (below the pinned waist, near the cage), 0 on the waist and on sleeves hanging outside it."""
    off = np.hypot(P[:, 0] - centre[0], P[:, 1] - centre[1]) - profile_radius(profile, P[:, 2])
    near = (1 - smoothstep((off - 0.04) / 0.04)) * (1 - smoothstep((-off - 0.10) / 0.05))
    return (1 - smoothstep((P[:, 2] - (hz - 0.12)) / 0.14)) * near


def profile_radius(profile, z):
    r, zz = np.array(profile).T
    return np.interp(z, zz[::-1], r[::-1])


def split_concave(V, faces):
    """Concave quads split through their reflex corner (Surface Deform refuses concave target polygons)."""
    out = []
    for f in faces:
        if len(f) == 4:
            P = V[list(f)]
            n = np.cross(P[2] - P[0], P[3] - P[1])
            turn = [np.dot(np.cross(P[(i + 1) % 4] - P[i], P[(i + 2) % 4] - P[(i + 1) % 4]), n) for i in range(4)]
            if min(turn) < 0:
                r = (int(np.argmin(turn)) + 1) % 4
                out += [(f[r], f[(r + 1) % 4], f[(r + 2) % 4]), (f[r], f[(r + 2) % 4], f[(r + 3) % 4])]
                continue
        out.append(f)
    return out


def write_pc2(path, frames):
    frames = np.ascontiguousarray(frames, np.float32)
    with open(path, 'wb') as f:
        f.write(struct.pack('<12siiffi', b'POINTCACHE2\0', 1, frames.shape[1], 0.0, 1.0, frames.shape[0]))
        f.write(frames.tobytes())


# ---------- bpy helpers ----------

def _np(m):
    return np.array(m, dtype=np.float64)


def _xf(M, P):
    return P @ M[:3, :3].T + M[:3, 3]


def rest_verts(ob):
    return _xf(_np(ob.matrix_world), np.array([v.co for v in ob.data.vertices], np.float64).reshape(-1, 3))


def pose_world(arm, bone):
    return _np(arm.matrix_world @ arm.pose.bones[bone].matrix)


def skin_modifier(ob):
    return next((m for m in ob.modifiers if m.type == 'ARMATURE' and m.object), None)


@contextmanager
def rest_pose(arm):
    old = arm.data.pose_position
    arm.data.pose_position = 'REST'
    bpy.context.view_layer.update()
    try:
        yield
    finally:
        arm.data.pose_position = old
        bpy.context.view_layer.update()


@contextmanager
def only_evaluate(keep):
    """Hide every other object from the depsgraph while sampling or baking."""
    keep, todo = set(), list(keep)
    while todo:
        ob = todo.pop()
        if ob and ob not in keep:
            keep.add(ob)
            todo += [ob.parent] + [m.object for m in ob.modifiers if getattr(m, 'object', None)]
    hidden = [ob for ob in bpy.context.scene.objects if ob not in keep and not ob.hide_viewport]
    for ob in hidden:
        ob.hide_viewport = True
    try:
        yield
    finally:
        for ob in hidden:
            ob.hide_viewport = False


def follow(ob, src, arm, rigid=False):
    """Make ob move like src: copy its skin weights (nearest vertex), else its parent relation (rigid: parent to src)."""
    mw = ob.matrix_world.copy()
    mod = skin_modifier(src)
    if mod and src.vertex_groups:
        bones = set(mod.object.data.bones.keys())
        groups = {g.index: g.name for g in src.vertex_groups if g.name in bones}
        kd = KDTree(len(src.data.vertices))
        for i, co in enumerate(rest_verts(src)):
            kd.insert(co, i)
        kd.balance()
        vgs = {name: ob.vertex_groups.get(name) or ob.vertex_groups.new(name=name) for name in groups.values()}
        for v, co in zip(ob.data.vertices, rest_verts(ob)):
            for g in src.data.vertices[kd.find(co)[1]].groups:
                if g.group in groups and g.weight > 0:
                    vgs[groups[g.group]].add([v.index], g.weight, 'REPLACE')
        ob.parent = src.parent
        m = ob.modifiers.new('Armature', 'ARMATURE')
        m.object = mod.object
    elif rigid or src.parent is None:
        ob.parent = src
    else:
        ob.parent, ob.parent_type = src.parent, src.parent_type
        if src.parent_type == 'BONE':
            ob.parent_bone = src.parent_bone
    bpy.context.view_layer.update()
    ob.matrix_world = mw


def sim_object(name, verts, faces):
    ob = bu.mesh_object(name, verts, faces, col=COL)
    ob.hide_render = True
    ob.display_type = 'WIRE'
    return ob


def shells_mesh(name, shells):
    """One object from closed shells [(verts, faces)], faces wound outward; returns the object and per-shell face lists."""
    verts, faces, ranges = [], [], []
    for sv, sf in shells:
        sv = np.asarray(sv, np.float64)
        vol = sum(np.dot(sv[f[0]], np.cross(sv[f[i]], sv[f[i + 1]])) for f in sf for i in range(1, len(f) - 1))
        sf = [tuple(reversed(f)) if vol < 0 else tuple(f) for f in sf]
        base = len(verts)
        verts += [tuple(v) for v in sv]
        faces += [tuple(i + base for i in f) for f in sf]
        ranges.append((base, len(verts), [tuple(i + base for i in f) for f in sf]))
    return sim_object(name, verts, faces), ranges


def tube(rings, seg):
    """Closed tube: rings [(centre, x_axis*rx, y_axis*ry)] with fan caps."""
    verts, faces = [], []
    for c, ax, ay in rings:
        for s in range(seg):
            a = 2 * math.pi * s / seg
            verts.append(np.asarray(c) + math.cos(a) * np.asarray(ax) + math.sin(a) * np.asarray(ay))
    for r in range(len(rings) - 1):
        for s in range(seg):
            i, j = r * seg + s, r * seg + (s + 1) % seg
            faces.append((i, j, j + seg, i + seg))
    for r, sign in ((0, 1), (len(rings) - 1, -1)):
        verts.append(np.asarray(rings[r][0]))
        ci = len(verts) - 1
        for s in range(seg):
            i, j = r * seg + s, r * seg + (s + 1) % seg
            faces.append((ci, j, i) if sign > 0 else (ci, i, j))
    return verts, faces


def _perp(d):
    a = np.cross(d, (1, 0, 0) if abs(d[0]) < 0.9 else (0, 1, 0))
    a /= np.linalg.norm(a)
    return a, np.cross(d, a)


# ---------- springs ----------

def chain_parts(ctx, target):
    ids = [pid for pid in ctx.parts if pid == target or pid.startswith(target + '.') or pid.startswith(target + ':')]
    return [bpy.data.objects[ctx.parts[pid]['object']] for pid in ids], ids


def build_chain(ctx, arm, spring):
    obs, ids = chain_parts(ctx, spring['target'])
    meshes = [ob for ob in obs if ob.type == 'MESH' and len(ob.data.vertices) >= 8]
    if not meshes:
        return None
    attach = next(ctx.parts[i]['attach'] for i in ids if ctx.parts[i]['attach'])
    abone = ctx.bones[attach]
    nb = spring.get('bones', 4)
    main = max(meshes, key=lambda o: len(o.data.vertices))
    joints, _ = chain_points(rest_verts(main), np.array(ctx.landmarks[attach]), nb)
    inv = _np(arm.matrix_world.inverted())
    names = [f'SEC-{spring["target"]}.{i:03d}' for i in range(nb)]
    bpy.context.view_layer.objects.active = arm
    hidden, arm.hide_viewport = arm.hide_viewport, False
    bpy.ops.object.mode_set(mode='EDIT')
    eb_parent = arm.data.edit_bones[abone]
    for i, nm in enumerate(names):
        eb = arm.data.edit_bones.get(nm) or arm.data.edit_bones.new(nm)
        eb.head, eb.tail = Vector(_xf(inv, joints[i])), Vector(_xf(inv, joints[i + 1]))
        eb.parent, eb.use_connect, eb.use_deform = eb_parent, i > 0, True
        eb_parent = eb
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.hide_viewport = hidden
    for ob in meshes:
        bind_chain(ob, arm, abone, names, joints)
    curves = [ob for ob in obs if ob.type == 'CURVES']
    for ob in curves:
        deform_curves(ob, arm, abone, names, joints)
    A = arm.data.bones[abone].matrix_local
    Ainv = _np(A.inverted())
    J = _xf(Ainv @ inv, joints)
    seg = np.linalg.norm(np.diff(J, axis=0), axis=1)
    remain = np.cumsum(seg[::-1])[::-1]
    dirs = (J[-1] - J[:-1]) / np.maximum(remain, 1e-6)[:, None]
    rel = [_np((A.inverted() @ arm.data.bones[nm].matrix_local).to_3x3()) for nm in names]
    unbound = sum(ob.type not in ('MESH', 'CURVES') for ob in obs)
    return {'attach': abone, 'names': names, 'dirs': dirs, 'levers': np.maximum(remain / 2, LEVER_MIN_M), 'rel': rel,
            'k': spring['k'], 'c': spring['c'], 'periods': spring.get('preroll_periods', 3),
            'bound': len(meshes) + len(curves), 'unbound': unbound}


def chain_coord(V, joints):
    axis = joints[-1] - joints[0]
    return np.clip((V - joints[0]) @ axis / (axis @ axis) * (len(joints) - 1), -1, len(joints) - 1)


def bind_chain(ob, arm, abone, names, joints):
    """Weight ob to the chain by its coordinate along the joints; existing skin weights scale by the attach share."""
    V = rest_verts(ob)
    nb = len(names)
    w, keep = chain_weights(chain_coord(V, joints), nb)
    mod = skin_modifier(ob)
    if mod is None:
        mw = ob.matrix_world.copy()
        ob.parent, ob.parent_type = arm, 'OBJECT'
        bpy.context.view_layer.update()
        ob.matrix_world = mw
        mod = ob.modifiers.new('Armature', 'ARMATURE')
        mod.object = arm
        while ob.modifiers.find(mod.name) > 0:
            ob.modifiers.move(ob.modifiers.find(mod.name), 0)
        vg = ob.vertex_groups.get(abone) or ob.vertex_groups.new(name=abone)
        for i in range(len(V)):
            vg.add([i], float(keep[i]), 'REPLACE')
    else:
        for v in ob.data.vertices:
            for g in v.groups:
                g.weight *= float(keep[v.index])
    for b, nm in enumerate(names):
        vg = ob.vertex_groups.get(nm) or ob.vertex_groups.new(name=nm)
        for i in np.nonzero(w[:, b] > 1e-4)[0]:
            vg.add([int(i)], float(w[i, b]), 'REPLACE')


def deform_curves(ob, arm, abone, names, joints):
    """Hair curves: a GN modifier blends each point by the spring-only motion of its chain bones (bone / attach bone)."""
    attr = ob.data.attributes['position']
    pos = np.empty(len(attr.data) * 3)
    attr.data.foreach_get('vector', pos)
    x = chain_coord(_xf(_np(ob.matrix_world), pos.reshape(-1, 3)), joints)
    ca = ob.data.attributes.get('c3d_chain') or ob.data.attributes.new('c3d_chain', 'FLOAT', 'POINT')
    ca.data.foreach_set('value', x.astype(np.float32))
    empties = []
    for bone in [abone] + names:
        e = bpy.data.objects.new(f'c3d_ref.{ob.name}.{bone}', None)
        bu.collection(COL).objects.link(e)
        e.matrix_world = ob.matrix_world.copy()
        e.hide_render = True
        bu.parent_to_bone(e, arm, bone)
        empties.append(e)
    ng = bpy.data.node_groups.new(f'c3d_chain.{ob.name}', 'GeometryNodeTree')
    ng.interface.new_socket('Geometry', in_out='INPUT', socket_type='NodeSocketGeometry')
    ng.interface.new_socket('Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
    N, link = ng.nodes, ng.links.new

    def node(kind, op=None, **inputs):
        n = N.new(kind)
        if op:
            n.operation = op
        for k, v in inputs.items():
            sock = n.inputs[int(k[1:])] if k[0] == '_' else n.inputs[k]
            if isinstance(v, bpy.types.NodeSocket):
                link(v, sock)
            else:
                sock.default_value = v
        return n

    gin, gout = N.new('NodeGroupInput'), N.new('NodeGroupOutput')
    xn = N.new('GeometryNodeInputNamedAttribute')
    xn.data_type = 'FLOAT'
    xn.inputs['Name'].default_value = 'c3d_chain'
    xs = xn.outputs['Attribute']
    p = N.new('GeometryNodeInputPosition').outputs['Position']
    total = node('ShaderNodeMapRange', Value=xs, _1=0.0, _2=0.5, _3=0.0, _4=1.0)
    total.interpolation_type = 'SMOOTHSTEP'
    y = node('ShaderNodeClamp', Value=node('ShaderNodeMath', 'SUBTRACT', _0=xs, _1=0.5).outputs[0], Min=0.0,
             Max=float(len(names) - 1)).outputs[0]
    ref = node('GeometryNodeObjectInfo', Object=empties[0])
    ref.transform_space = 'RELATIVE'
    inv = node('FunctionNodeInvertMatrix', Matrix=ref.outputs['Transform']).outputs['Matrix']
    acc = None
    for b, e in enumerate(empties[1:]):
        info = node('GeometryNodeObjectInfo', Object=e)
        info.transform_space = 'RELATIVE'
        mat = node('FunctionNodeMatrixMultiply', _0=info.outputs['Transform'], _1=inv).outputs[0]
        moved = node('FunctionNodeTransformPoint', Vector=p, Transform=mat).outputs[0]
        delta = node('ShaderNodeVectorMath', 'SUBTRACT', _0=moved, _1=p).outputs[0]
        tent = node('ShaderNodeMath', 'ABSOLUTE', _0=node('ShaderNodeMath', 'SUBTRACT', _0=y, _1=float(b)).outputs[0])
        w = node('ShaderNodeMath', 'MAXIMUM', _0=node('ShaderNodeMath', 'SUBTRACT', _0=1.0, _1=tent.outputs[0]).outputs[0], _1=0.0)
        w = node('ShaderNodeMath', 'MULTIPLY', _0=w.outputs[0], _1=total.outputs[0])
        part = node('ShaderNodeVectorMath', 'SCALE', _0=delta, Scale=w.outputs[0]).outputs[0]
        acc = part if acc is None else node('ShaderNodeVectorMath', 'ADD', _0=acc, _1=part).outputs[0]
    setp = node('GeometryNodeSetPosition', Geometry=gin.outputs[0], Offset=acc)
    link(setp.outputs[0], gout.inputs[0])
    ob.modifiers.new('c3d_chain', 'NODES').node_group = ng


def bake_chain(ctx, arm, ch, clip, act):
    fps, s, e = clip['fps'], clip['start'], clip['end']
    rots, pos = [], []
    for f in range(s, e + 2):
        bpy.context.scene.frame_set(f)
        M = pose_world(arm, ch['attach'])
        rots.append(M[:3, :3] / np.linalg.norm(M[:3, :3], axis=0))
        pos.append(M[:3, 3])
    alpha, acc = frame_accels(np.array(rots), np.array(pos), fps, clip['loop'])
    alpha, acc = (smooth_series(x, FORCE_SIGMA_S * fps, clip['loop']) for x in (alpha, acc))
    ang, err = spring_chain(alpha, acc, ch['dirs'], ch['levers'], ch['k'], ch['c'], fps, clip['loop'], ch['periods'])
    frames = np.arange(s, s + len(ang), dtype=np.float64)
    for b, nm in enumerate(ch['names']):
        local = ang[:, b] @ ch['rel'][b]
        quats = np.array([Matrix.Rotation(np.linalg.norm(r), 3, Vector(r / np.linalg.norm(r))).to_quaternion() if np.linalg.norm(r) > 1e-12
                          else (1, 0, 0, 0) for r in local], np.float64)
        arm.pose.bones[nm].rotation_mode = 'QUATERNION'
        for i in range(4):
            fc = act.fcurve_ensure_for_datablock(arm, f'pose.bones["{nm}"].rotation_quaternion', index=i, group_name=nm)
            fc.keyframe_points.clear()
            fc.keyframe_points.add(len(frames))
            fc.keyframe_points.foreach_set('co', np.column_stack([frames, quats[:, i]]).ravel())
            fc.update()
    return {'err': err, 'peak': float(np.linalg.norm(ang, axis=2).max()),
            'step': float(np.linalg.norm(np.diff(ang, axis=0), axis=2).max()) if len(ang) > 1 else 0.0}


# ---------- cloth ----------

def cage_profile(V, centre, rings):
    """Radial profile [(r, z)] top to bottom: median radius of the garment's rest verts per z slab."""
    z0, z1 = V[:, 2].max(), V[:, 2].min()
    r = np.hypot(V[:, 0] - centre[0], V[:, 1] - centre[1])
    zs = np.linspace(z0, z1, rings)
    dz = abs(z0 - z1) / rings
    prof = []
    for z in zs:
        sel = np.abs(V[:, 2] - z) < dz
        prof.append(np.median(r[sel]) if sel.sum() >= 3 else np.nan)
    prof = np.array(prof)
    ok = ~np.isnan(prof)
    prof = np.interp(zs, zs[ok][::-1], prof[ok][::-1])
    return list(zip(prof, zs))


def body_proxy(ctx, body, profile, centre):
    """Low-poly legged collider: elliptic torso, two legs, two feet, radii measured from the rest body, kept inside the cage."""
    lm = {k: np.array(v, np.float64) for k, v in ctx.landmarks.items()}
    V = rest_verts(body) if body else np.zeros((0, 3))
    hz = lm['hips'][2]
    shells = []
    rings = []
    for z in np.linspace(hz - 0.14, lm['chest'][2], 8):
        sel = (np.abs(V[:, 2] - z) < 0.04) & (np.hypot(V[:, 0] - centre[0], V[:, 1] - centre[1]) < 0.25)
        rx = np.quantile(np.abs(V[sel, 0] - centre[0]), 0.9) if sel.sum() > 8 else 0.15
        ry = np.quantile(np.abs(V[sel, 1] - centre[1]), 0.9) if sel.sum() > 8 else 0.11
        lim = profile_radius(profile, z) - 0.03
        rx, ry = min(max(rx, 0.08), lim), min(max(ry, 0.06), lim)
        rings.append(((centre[0], centre[1], z), (rx, 0, 0), (0, ry, 0)))
    shells.append(tube(rings, 16))
    for side in ('L', 'R'):
        foot, toe = lm[f'foot.{side}'], lm[f'toe.{side}']
        top = np.array([foot[0], foot[1], hz - 0.04])
        d = foot - top
        L = np.linalg.norm(d)
        d /= L
        ax, ay = _perp(d)
        rings = []
        for t in np.linspace(0, 1, 9):
            c = top + d * L * t
            rel = V - c
            along = rel @ d
            radial = np.linalg.norm(rel - np.outer(along, d), axis=1)
            sel = (np.abs(along) < 0.04) & (radial < 0.12) & (np.sign(V[:, 0] - centre[0]) == np.sign(foot[0] - centre[0]))
            r = np.quantile(radial[sel], 0.9) if sel.sum() > 8 else 0.075 - 0.03 * t
            r = max(0.02, min(max(r, 0.04), 0.1, profile_radius(profile, c[2]) - 0.03 - np.hypot(*(c[:2] - centre[:2]))))
            rings.append((c, ax * r, ay * r))
        shells.append(tube(rings, 12))
        fd = toe - foot
        fd[2] = 0
        fl = max(np.linalg.norm(fd), 0.05)
        fd /= fl
        ax, ay = _perp(fd)
        rings = [(foot + fd * (fl * t - 0.04), ax * 0.045, ay * 0.045) for t in np.linspace(0, 1.15, 4)]
        shells.append(tube(rings, 8))
    return shells_mesh('c3d_body_proxy', shells)


def staff_collider(shaft):
    V = rest_verts(shaft)
    c = V.mean(0)
    d = np.linalg.svd(V - c)[2][0]
    t = (V - c) @ d
    r = np.quantile(np.linalg.norm((V - c) - np.outer(t, d), axis=1), 0.95) + 0.004
    ax, ay = _perp(d)
    rings = [(c + d * tt, ax * r, ay * r) for tt in np.linspace(t.min(), t.max(), 6)]
    ob, _ = shells_mesh(f'c3d_collider.{shaft.name}', [tube(rings, 8)])
    return ob


def collider(ob, thickness):
    ob.modifiers.new('Collision', 'COLLISION')
    ob.collision.thickness_outer = thickness
    ob.collision.cloth_friction = 5.0


def setup_cloth(ctx, arm, spec):
    robe = bpy.data.objects[ctx.parts[spec['garment']]['object']]
    attach = ctx.parts[spec['garment']]['attach'] or 'hips'
    centre = np.array(ctx.landmarks[attach], np.float64)
    V = rest_verts(robe)
    target = spec.get('cage_verts', 2500)
    height = np.ptp(V[:, 2])
    rad = np.median(np.hypot(V[:, 0] - centre[0], V[:, 1] - centre[1]))
    seg = max(12, int(round(math.sqrt(target * 2 * math.pi * rad / height))))
    profile = cage_profile(V, centre, max(4, target // seg))
    cage = bu.lathe('c3d_cage.' + spec['garment'], [(r, z) for r, z in profile], segments=seg, col=COL)
    cage.location = (centre[0], centre[1], 0)
    cage.hide_render, cage.display_type = True, 'WIRE'
    bpy.context.view_layer.update()
    hz = ctx.landmarks['hips'][2]
    C = rest_verts(cage)
    pin = smoothstep((C[:, 2] - (hz - 0.12)) / 0.14)
    vg = cage.vertex_groups.new(name='c3d_pin')
    for i, w in enumerate(pin):
        vg.add([i], float(w), 'REPLACE')
    body = bpy.data.objects[ctx.parts['body']['object']] if 'body' in ctx.parts else None
    follow(cage, robe if skin_modifier(robe) or robe.parent or not body else body, arm)
    proxy, shells = body_proxy(ctx, body, profile, centre)
    if body:
        follow(proxy, body, arm)
    collider(proxy, 0.015)
    cols = [proxy]
    for p in ctx.spec.get('props', []):
        for part in p['parts']:
            pid = f'{p["id"]}.{part["id"]}'
            if part['kind'] == 'shaft' and pid in ctx.parts:
                shaft = bpy.data.objects[ctx.parts[pid]['object']]
                col = staff_collider(shaft)
                follow(col, shaft, arm, rigid=True)
                collider(col, 0.01)
                cols.append(col)
    ground = sim_object('c3d_ground_collider', [(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [(0, 1, 2, 3)])
    collider(ground, 0.005)
    cols.append(ground)
    cl = cage.modifiers.new('Cloth', 'CLOTH')
    s, cs = cl.settings, cl.collision_settings
    s.quality, s.mass, s.air_damping = spec.get('quality', 5), 0.4, spec.get('air_damping', 10)
    s.tension_stiffness = s.compression_stiffness = 20
    s.tension_damping = s.compression_damping = 25
    s.bending_stiffness = 2.0
    s.vertex_group_mass, s.pin_stiffness = 'c3d_pin', 1.0
    cs.collision_quality, cs.distance_min = spec.get('collision_quality', 2), 0.01
    cs.use_self_collision = spec.get('self_collision', False)
    G = smooth_grid(rest_verts(cage).reshape(-1, seg, 3))
    parts = []
    for pid, ob, own in driven_parts(ctx, spec['garment'], hz):
        P = rest_verts(ob)
        w = cloth_share(P, profile, centre, hz) if own else np.zeros(len(P))
        parts.append({'id': pid, 'ob': ob, 'bind': embed(P, G, centre), 'w': w, 'own': own, 'moved': 0.0,
                      'margin': inner_extent(ob) + CLEAR_M, 'under': outer_extent(ob) + inner_extent(robe) + CLEAR_M,
                      'ground': inner_extent(ob) + outer_extent(ob) + CLEAR_M})
    host, tubes = tube_faces(robe)
    return {'robe': robe, 'cage': cage, 'cloth': cl, 'proxy': proxy, 'shells': shells, 'colliders': cols,
            'seg': seg, 'parts': parts, 'body': body, 'garment': spec['garment'], 'uppers': upper_layers(ctx, spec['garment']),
            'faces': [tuple(f.vertices) for f in robe.data.polygons], 'host': host, 'tubes': tubes,
            'tube_margin': 2 * outer_extent(robe) + CLEAR_M}


def tube_faces(ob):
    """(host vertex ids, tube faces): the garment's largest island is the host (robe body), the smaller ones are tubes
    (sleeves) the host must stay outside of."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    isl, k = np.full(len(bm.faces), -1), 0
    for f in bm.faces:
        if isl[f.index] >= 0:
            continue
        isl[f.index], stack = k, [f]
        while stack:
            for e in stack.pop().edges:
                for g in e.link_faces:
                    if isl[g.index] < 0:
                        isl[g.index] = k
                        stack.append(g)
        k += 1
    big = np.bincount(isl).argmax() if k else 0
    host = sorted({v.index for f in bm.faces if isl[f.index] == big for v in f.verts})
    tubes = [tuple(v.index for v in f.verts) for f in bm.faces if isl[f.index] != big]
    bm.free()
    return np.array(host, int), tubes


def driven_parts(ctx, garment, hz):
    """(id, object, own): the cloth garment and its trims/decals (own: carried by the cloth), plus other garments on the
    same bone hanging below the pinned waist (kept on their skin, only pushed out of the body and ground)."""
    attach = ctx.parts[garment]['attach']
    out = []
    for pid, q in ctx.parts.items():
        ob = bpy.data.objects[q['object']]
        if ob.type != 'MESH' or q['stage'] != 'garments':
            continue
        own = pid == garment or pid.startswith(garment + '.')
        if own or (q['attach'] == attach and rest_verts(ob)[:, 2].min() < hz - 0.12):
            out.append((pid, ob, own))
    return out


def inner_extent(ob):
    """How far Solidify pushes the shell inward from the base surface, metres."""
    m = next((m for m in ob.modifiers if m.type == 'SOLIDIFY'), None)
    return m.thickness * (1 - m.offset) / 2 if m else 0.0


def cover_tree(V, faces):
    return BVHTree.FromPolygons(V.tolist(), faces), V.min(0) - REACH_M, V.max(0) + REACH_M


def upper_layers(ctx, garment):
    """(object, faces, inner shell + clearance) of the sheet garments (robe, mantle kinds) layered over this cloth garment."""
    gs = {g['id']: g for g in ctx.spec.get('garments', [])}
    lay = gs[garment].get('layer', 0)
    out = []
    for gid, g in gs.items():
        if g['kind'] in ('robe', 'mantle') and g.get('layer', 0) > lay and gid in ctx.parts:
            ob = bpy.data.objects[ctx.parts[gid]['object']]
            out.append((ob, [tuple(f.vertices) for f in ob.data.polygons], inner_extent(ob) + CLEAR_M))
    return out


def outer_extent(ob):
    """How far Solidify pushes the shell outward from the base surface, metres."""
    m = next((m for m in ob.modifiers if m.type == 'SOLIDIFY'), None)
    return m.thickness * (1 + m.offset) / 2 if m else 0.0


def bake_clip(ctx, arm, sim, clip, act):
    """Bake the cage over settle + pre-roll cycles of the clip (NLA repeat, root drift carried); return body-local frames."""
    sc, anim = bpy.context.scene, arm.animation_data
    fps, s, e, loop = clip['fps'], clip['start'], clip['end'], clip['loop']
    n = e - s + 1
    hips = ctx.bones['hips']
    anim.action = act
    sc.frame_set(e + 1)
    p1 = pose_world(arm, hips)[:3, 3]
    sc.frame_set(s)
    drift = (p1 - pose_world(arm, hips)[:3, 3]) * (1, 1, 0) if loop else np.zeros(3)
    settle = round(SETTLE_S * fps)
    reps = (max(1, math.ceil(PREROLL_S * fps / n)) + 1) if loop else 1
    last = settle + reps * n + 1
    anim.action = None
    track = anim.nla_tracks.new()
    strip = track.strips.new('c3d_bake', settle + 1, act)
    strip.action_frame_start, strip.action_frame_end = s, e + 1
    strip.repeat = reps
    base = arm.location.copy()
    if drift.any():
        for c in range(reps):
            arm.location = base + Vector(drift * c)
            arm.keyframe_insert('location', frame=settle + 1 + c * n)
        for fc in bu_fcurves(arm.animation_data.action):
            for kp in fc.keyframe_points:
                kp.interpolation = 'CONSTANT'
    cl = sim['cloth']
    cl.point_cache.frame_start, cl.point_cache.frame_end = 1, last
    old_range = sc.frame_start, sc.frame_end
    sc.frame_start, sc.frame_end = 1, last
    with bpy.context.temp_override(scene=sc, active_object=sim['cage'], point_cache=cl.point_cache):
        bpy.ops.ptcache.free_bake()
        bpy.ops.ptcache.bake(bake=True)
    first = settle + 1 + (reps - 1) * n
    keep = range(first, first + n + 1)
    dg = bpy.context.evaluated_depsgraph_get()
    frames = []
    for f in keep:
        sc.frame_set(f)
        frames.append(_xf(np.linalg.inv(pose_world(arm, hips)), bu.world_verts(sim['cage'], dg)))
    with bpy.context.temp_override(scene=sc, active_object=sim['cage'], point_cache=cl.point_cache):
        bpy.ops.ptcache.free_bake()
    tmp = anim.action
    anim.action = None
    if tmp:
        bpy.data.actions.remove(tmp)
    arm.location = base
    anim.nla_tracks.remove(track)
    anim.action = act
    sc.frame_start, sc.frame_end = old_range
    L = np.array(frames)
    if not loop:
        return L, {}
    nat = float(np.linalg.norm(np.diff(L[:n], axis=0), axis=2).max())
    raw = float(np.linalg.norm(L[n] - L[0], axis=1).max())
    out = loop_crossfade(L[:n], L[n])
    out = np.vstack([out, out[:1]])
    return out, {'seam_raw_mm': raw * 1000, 'seam_mm': float(np.linalg.norm(out[n - 1] - out[0], axis=1).max()) * 1000,
                 'natural_step_mm': nat * 1000}


def bu_fcurves(act):
    if act is None:
        return []
    return [fc for layer in act.layers for strip in layer.strips for cb in strip.channelbags for fc in cb.fcurves]


def proxy_hits(shells, P, W):
    """{vert index: (surface point, normal)} for verts of W inside any body-proxy shell."""
    hits = {}
    for lo, hi, faces in shells:
        sv = P[lo:hi]
        cand = np.nonzero(np.all((W > sv.min(0) - 0.01) & (W < sv.max(0) + 0.01), axis=1))[0]
        if not len(cand):
            continue
        bvh = BVHTree.FromPolygons([tuple(v) for v in sv], [tuple(i - lo for i in f) for f in faces])
        for j in cand:
            co, nrm, _, _ = bvh.find_nearest(Vector(W[j]))
            if co is not None and (Vector(W[j]) - co).dot(nrm) < 0:
                hits[int(j)] = (co, nrm)
    return hits


def resolve_frames(ctx, arm, sim, clip, act, L):
    """Per clip frame: cage out of the proxy and above ground, garment verts from the cage blended with their skin,
    then pushed out of the real body and above the ground. Returns per-part arm-local frames + metrics."""
    sc = bpy.context.scene
    arm.animation_data.action = act
    dg = bpy.context.evaluated_depsgraph_get()
    to_arm = np.linalg.inv(_np(arm.matrix_world))
    out = {p['id']: [] for p in sim['parts']}
    inside, pushed = set(), 0
    for i in range(len(L)):
        sc.frame_set(clip['start'] + i)
        W = _xf(pose_world(arm, ctx.bones['hips']), L[i])
        Pp = bu.world_verts(sim['proxy'], dg)
        for _ in range(2):
            for j, (co, nrm) in proxy_hits(sim['shells'], Pp, W).items():
                W[j] = np.array(co + nrm * PUSH_M)
        W[:, 2] = np.maximum(W[:, 2], 0.002)
        G = smooth_grid(W.reshape(-1, sim['seg'], 3))
        body = mesh_tree(sim['body'], dg) if sim['body'] else None
        Ps = {}
        for p in sim['parts']:
            S = bu.world_verts(p['ob'], dg)
            w = p['w'][:, None]
            Ps[p['id']] = S, S + w * (unembed(p['bind'], G) - S)
        uppers = [(cover_tree(bu.world_verts(ob, dg), faces), pad) for ob, faces, pad in sim['uppers']]
        cover = None
        for p in sorted(sim['parts'], key=lambda p: not p['own']):
            S, P = Ps[p['id']]
            if not p['own']:
                cover = cover or cover_tree(Ps[sim['garment']][1], sim['faces'])
            behind = [(t, pad + outer_extent(p['ob'])) for t, pad in uppers] + ([(cover, p['under'])] if cover else [])
            for t, margin in behind:
                pushed += push_behind(P, t, margin)
            if p['id'] == sim['garment'] and sim['tubes']:
                pushed += push_off_tubes(P, sim['host'], sim['tubes'], sim['tube_margin'])
            if body:
                pushed += push_out(P, body, p['margin'])
                inside.update((p['id'], int(j)) for j in np.nonzero(depth_below(P, body) > 0.0005)[0])
            for t, margin in behind:
                pushed += push_behind(P, t, margin)
            low = P[:, 2] < p['ground']
            pushed += int(low.sum())
            P[low, 2] = p['ground']
            p['moved'] = max(p['moved'], float(np.linalg.norm(P - S, axis=1).max()))
            out[p['id']].append(_xf(to_arm, P))
    return {k: np.array(v, np.float32) for k, v in out.items()}, inside, pushed


def push_off_tubes(P, host, tubes, margin):
    """Host verts inside a tube (a sleeve skinned to the arm) or nearer than margin to its wall, straight off a face, go to
    margin outside that wall: the arm presses the robe body in instead of the sleeve cutting through it."""
    t = (BVHTree.FromPolygons(P.tolist(), tubes), P.min(0) - REACH_M, P.max(0) + REACH_M)
    H = P[host]
    n = 0
    for j, loc, nrm, s, dist in list(_near(H, t)):
        if s < margin - 1e-6 and abs(s) >= 0.9 * dist:
            P[host[j]] = np.array(loc + nrm * margin)
            n += 1
    return n


def mesh_tree(ob, dg):
    """BVH of an evaluated mesh in world space, plus its bounds."""
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    V = _xf(_np(ob.matrix_world), np.array([v.co for v in me.vertices], np.float64).reshape(-1, 3))
    polys = [tuple(p.vertices) for p in me.polygons]
    ev.to_mesh_clear()
    return BVHTree.FromPolygons(V.tolist(), polys), V.min(0) - REACH_M, V.max(0) + REACH_M


def _near(P, body):
    tree, lo, hi = body
    for j in np.nonzero(np.all((P > lo) & (P < hi), axis=1))[0]:
        loc, nrm, _, dist = tree.find_nearest(Vector(P[j]), REACH_M)
        if loc is not None:
            yield j, loc, nrm, (Vector(P[j]) - loc).dot(nrm), dist


def push_out(P, body, margin):
    """Move verts inside the body, or nearer than margin along the face normal, onto surface + margin."""
    n = 0
    for _ in range(2):
        for j, loc, nrm, s, dist in list(_near(P, body)):
            if s < margin - 1e-6 and abs(s) >= 0.9 * dist:
                P[j] = np.array(loc + nrm * margin)
                n += 1
    return n


def push_behind(P, cover, margin):
    """Move verts lying straight under a face of the covering garment, nearer than margin behind it (or in front of it),
    to margin behind that face; gaps such as a front opening have no face straight above and keep their verts."""
    n = 0
    for j, loc, nrm, s, dist in list(_near(P, cover)):
        if s > -margin and abs(s) >= 0.9 * dist:
            P[j] = np.array(loc - nrm * margin)
            n += 1
    return n


def depth_below(P, body):
    """Per vert depth behind the body surface (QA garment_depth rule: straight behind a face), metres."""
    d = np.zeros(len(P))
    for j, loc, nrm, s, dist in _near(P, body):
        if s < 0 and -s >= 0.9 * dist:
            d[j] = dist
    return d


@contextmanager
def base_surface(obs):
    """Only Armature (and earlier deforms) on: Solidify, Subdivision and later modifiers off while sampling skins."""
    off = [m for ob in obs for m in ob.modifiers if m.type in ('SOLIDIFY', 'SUBSURF', 'SURFACE_DEFORM') and m.show_viewport]
    for m in off:
        m.show_viewport = False
    try:
        yield
    finally:
        for m in off:
            m.show_viewport = True


def drive_part(arm, ob, frames, path):
    """Same-topology driver mesh on the rig playing the PC2 frames; Surface Deform after the skin copies it exactly.
    When a corner-exact bind fails (Surface Deform's degenerate-angle checks), the driver moves BIND_SHIFT off."""
    to_arm = np.linalg.inv(_np(arm.matrix_world))
    me = bpy.data.meshes.new('c3d_drive.' + ob.name)
    V = _xf(to_arm, rest_verts(ob))
    me.from_pydata([tuple(v) for v in V], [], split_concave(V, [tuple(p.vertices) for p in ob.data.polygons]))
    d = bpy.data.objects.new(me.name, me)
    bu.collection(COL).objects.link(d)
    d.parent = arm
    d.hide_render, d.display_type = True, 'WIRE'
    best = (None, float('inf'))
    for shift in (np.zeros(3), BIND_SHIFT):
        err = bind_driver(arm, ob, d, V, frames, path, shift)
        if err < best[1]:
            best = (shift, err)
        if err <= DRIVE_TOL_M:
            break
    if best[0] is None:
        cache_part(arm, ob, d, frames, path)
        return False, 0.0
    if best[0] is not shift:
        bind_driver(arm, ob, d, V, frames, path, best[0])
    return True, best[1]


def cache_part(arm, ob, d, frames, path):
    """No Surface Deform bind holds (concave target polygons): the garment plays its own object-space PC2 frames through a
    Mesh Cache (overwrite) right after the skin; the driver mesh goes."""
    if 'c3d_cloth' in ob.modifiers:
        ob.modifiers.remove(ob.modifiers['c3d_cloth'])
    me = d.data
    bpy.data.objects.remove(d)
    bpy.data.meshes.remove(me)
    write_pc2(path, _xf(_np(ob.matrix_world.inverted() @ arm.matrix_world), frames))
    mc = frame_driver(arm, ob, path)
    mc.name, mc.deform_mode = 'c3d_cloth', 'OVERWRITE'
    arms = [i for i, m in enumerate(ob.modifiers) if m.type == 'ARMATURE']
    ob.modifiers.move(len(ob.modifiers) - 1, arms[-1] + 1 if arms else 0)


def bind_driver(arm, ob, d, V, frames, path, shift):
    """(Re)bind ob to the driver placed at V - shift playing frames - shift; returns the reproduction error, metres."""
    if 'c3d_cloth' in ob.modifiers:
        ob.modifiers.remove(ob.modifiers['c3d_cloth'])
    d.animation_data_clear()
    d.modifiers.clear()
    d.data.vertices.foreach_set('co', (V - shift).astype(np.float32).ravel())
    d.data.update()
    if not surface_bind(ob, d):
        return float('inf')
    write_pc2(path, frames - shift)
    frame_driver(arm, d, path)
    bpy.context.view_layer.update()
    return drive_error(ob, d, shift)


def drive_error(ob, d, shift):
    """Largest gap between the garment's deformed base surface and its driver (+ shift) at the current frame, metres."""
    off = [m for m in ob.modifiers if m.type in ('SOLIDIFY', 'SUBSURF') and m.show_viewport]
    for m in off:
        m.show_viewport = False
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    err = float(np.linalg.norm(bu.world_verts(ob, dg) - bu.world_verts(d, dg) - shift, axis=1).max())
    for m in off:
        m.show_viewport = True
    return err


def surface_bind(ob, target):
    """Surface Deform onto target right after the skin (bound in the current pose); removed again if the bind fails."""
    caches = [m for m in target.modifiers if m.show_viewport]
    for m in caches:
        m.show_viewport = False
    arms = [i for i, m in enumerate(ob.modifiers) if m.type == 'ARMATURE']
    sd = ob.modifiers.new('c3d_cloth', 'SURFACE_DEFORM')
    sd.target = target
    ob.modifiers.move(len(ob.modifiers) - 1, arms[-1] + 1 if arms else 0)
    bpy.context.view_layer.update()
    with bpy.context.temp_override(object=ob, active_object=ob):
        bpy.ops.object.surfacedeform_bind(modifier=sd.name)
    ok = sd.is_bound
    if not ok:
        ob.modifiers.remove(sd)
    for m in caches:
        m.show_viewport = True
    return ok


def frame_driver(arm, ob, cache_path):
    mc = ob.modifiers.new('c3d_cloth_cache', 'MESH_CACHE')
    mc.cache_format, mc.filepath, mc.play_mode, mc.time_mode = 'PC2', str(cache_path), 'CUSTOM', 'FRAME'
    fcu = ob.driver_add(f'modifiers["{mc.name}"].eval_frame')
    d = fcu.driver
    d.type = 'SCRIPTED'
    var = d.variables.new()
    var.name, var.type = 'f', 'SINGLE_PROP'
    var.targets[0].id, var.targets[0].data_path = arm, f'["{FRAME_PROP}"]'
    d.expression = 'f'
    return mc


def key_prop(arm, act, prop, frames, values):
    arm.animation_data.action = act
    fc = act.fcurve_ensure_for_datablock(arm, f'["{prop}"]')
    fc.keyframe_points.clear()
    fc.keyframe_points.add(len(frames))
    fc.keyframe_points.foreach_set('co', np.column_stack([frames, values]).astype(np.float64).ravel())
    for kp in fc.keyframe_points:
        kp.interpolation = 'LINEAR'
    fc.update()


def run_cloth(ctx, arm, specs, clips):
    sims, seams = [], []
    metrics = {'cloth_penetration_verts': 0, 'cloth_pushed_vert_frames': 0, 'cage_verts': 0, 'bake_frames': 0,
               'cloth_parts': 0, 'drive_bound': 0, 'bake_s': 0.0, 'resolve_s': 0.0}
    for spec in specs:
        if spec['garment'] not in ctx.parts:
            continue
        with rest_pose(arm):
            sim = setup_cloth(ctx, arm, spec)
        t = time.perf_counter()
        with only_evaluate([arm, sim['cage']] + sim['colliders']):
            sim['local'] = {}
            for cid, clip, act in clips:
                sim['local'][cid], seam = bake_clip(ctx, arm, sim, clip, act)
                seams.append(seam)
                metrics['bake_frames'] += sim['cloth'].point_cache.frame_end
        metrics['bake_s'] += round(time.perf_counter() - t, 2)
        metrics['cage_verts'] += len(sim['cage'].data.vertices)
        metrics['proxy_verts'] = len(sim['proxy'].data.vertices)
        sims.append(sim)
    offset = 0
    for cid, clip, act in clips:
        n = clip['end'] - clip['start'] + 2
        key_prop(arm, act, FRAME_PROP, np.arange(clip['start'], clip['start'] + n), np.arange(offset, offset + n))
        offset += n
    (ctx.out / 'cache').mkdir(parents=True, exist_ok=True)
    for sim in sims:
        obs = [p['ob'] for p in sim['parts']]
        data, inside, t = {p['id']: [] for p in sim['parts']}, set(), time.perf_counter()
        ups = [ob for ob, _, _ in sim['uppers']]
        with only_evaluate([arm, sim['proxy']] + ([sim['body']] if sim['body'] else []) + obs + ups), base_surface(obs + ups):
            for cid, clip, act in clips:
                frames, hit, pushed = resolve_frames(ctx, arm, sim, clip, act, sim['local'][cid])
                for k, v in frames.items():
                    data[k].append(v)
                inside |= hit
                metrics['cloth_pushed_vert_frames'] += pushed
        metrics['resolve_s'] += round(time.perf_counter() - t, 2)
        metrics['cloth_penetration_verts'] += len(inside)
        cid, clip, act = clips[0]
        arm.animation_data.action = act
        bpy.context.scene.frame_set((clip['start'] + clip['end']) // 2)
        errs = []
        with rest_pose(arm):
            for p in sim['parts']:
                if not p['own'] and p['moved'] < DRIVE_TOL_M:
                    continue
                path = ctx.out / 'cache' / f'{p["id"]}.pc2'
                ok, err = drive_part(arm, p['ob'], np.concatenate(data[p['id']]), path)
                ctx.files[f'cloth:{p["id"]}'] = str(path)
                metrics['cloth_parts'] += 1
                metrics['drive_bound'] += ok
                errs.append(err)
        metrics['drive_err_mm'] = round(max(errs, default=0.0) * 1000, 3)
        for ob in {sim['cage'], sim['proxy'], *sim['colliders']}:
            me = ob.data
            bpy.data.objects.remove(ob)
            bpy.data.meshes.remove(me)
    metrics.update(run_push(ctx, arm, clips, {p['id'] for sim in sims for p in sim['parts']}))
    loops = [s for s in seams if s]
    if loops:
        metrics.update({k: round(max(s[k] for s in loops), 2) for k in loops[0]})
    return metrics


def run_push(ctx, arm, clips, done):
    """Garments outside the cloth sims (mantle, belt, pouches, hat; not boots): every clip frame, skinned verts nearer the
    body than their shell are pushed out to it; a trim or decal moves with its garment's nearest vertex first. Parts that
    move get the same PC2 delivery as the cloth."""
    body = bpy.data.objects[ctx.parts['body']['object']] if 'body' in ctx.parts else None
    pids = [pid for pid, q in ctx.parts.items() if q['stage'] == 'garments' and pid not in done
            and bpy.data.objects[q['object']].type == 'MESH' and not str(q['attach'] or '').startswith('foot')]
    if not body or not pids:
        return {'push_parts': 0}
    obs = {pid: bpy.data.objects[ctx.parts[pid]['object']] for pid in pids}
    host = {pid: pid.split('.')[0] for pid in pids if '.' in pid and pid.split('.')[0] in obs}
    near = {}
    for pid, h in host.items():
        kd = KDTree(len(obs[h].data.vertices))
        for i, co in enumerate(rest_verts(obs[h])):
            kd.insert(co, i)
        kd.balance()
        near[pid] = np.array([kd.find(co)[1] for co in rest_verts(obs[pid])])
    order = sorted(pids, key=lambda pid: pid in host)
    data, moved, inside = {pid: [] for pid in pids}, {pid: 0.0 for pid in pids}, 0
    sc, t = bpy.context.scene, time.perf_counter()
    with only_evaluate([arm, body] + list(obs.values())), base_surface(list(obs.values())):
        to_arm = np.linalg.inv(_np(arm.matrix_world))
        for cid, clip, act in clips:
            arm.animation_data.action = act
            for f in range(clip['start'], clip['end'] + 2):
                sc.frame_set(f)
                dg = bpy.context.evaluated_depsgraph_get()
                tree_ = mesh_tree(body, dg)
                shift = {}
                for pid in order:
                    S = bu.world_verts(obs[pid], dg)
                    P = S + shift[host[pid]][near[pid]] if pid in host else S.copy()
                    push_out(P, tree_, inner_extent(obs[pid]) + CLEAR_M)
                    inside += int((depth_below(P, tree_) > 0.0005).sum())
                    shift[pid] = P - S
                    moved[pid] = max(moved[pid], float(np.linalg.norm(P - S, axis=1).max()))
                    data[pid].append(_xf(to_arm, P))
    m = {'push_parts': 0, 'push_moved_mm': {}, 'push_inside_vert_frames': inside,
         'push_s': round(time.perf_counter() - t, 2)}
    cid, clip, act = clips[0]
    arm.animation_data.action = act
    sc.frame_set((clip['start'] + clip['end']) // 2)
    with rest_pose(arm):
        for pid in pids:
            if moved[pid] < DRIVE_TOL_M:
                continue
            path = ctx.out / 'cache' / f'{pid}.pc2'
            drive_part(arm, obs[pid], np.array(data[pid], np.float32), path)
            ctx.files[f'cloth:{pid}'] = str(path)
            m['push_parts'] += 1
            m['push_moved_mm'][pid] = round(moved[pid] * 1000, 1)
    return m


# ---------- pulses ----------

def run_pulses(ctx, arm, pulses, clips):
    vals, made = [], 0
    for p in pulses:
        mspec = ctx.spec['materials'][p['material']]
        em = mspec.get('emission', {'base': 1.0, 'amp': 0.0, 'period_s': 2.0})
        base, amp = em['base'], em.get('amp', 0.0)
        obs = [bpy.data.objects[q['object']] for q in ctx.parts.values() if q['material'] == p['material']]
        mats = {s.material for ob in obs for s in ob.material_slots if s.material and s.material.node_tree}
        expr = f'{base} + {amp} * sin(w * frame)'
        inputs = []
        for mat in mats:
            for node in mat.node_tree.nodes:
                for name in ('Emission Strength', 'Strength'):
                    inp = node.inputs.get(name)
                    if inp is not None and (node.type == 'EMISSION' or name == 'Emission Strength'):
                        _driver(inp.driver_add('default_value'), arm, expr)
                        inputs.append(inp)
                        made += 1
        prefixes = {pid.split('.')[0] for pid, q in ctx.parts.items() if q['material'] == p['material']}
        lights = [bpy.data.objects[q['object']] for pid, q in ctx.parts.items()
                  if pid.split('.')[0] in prefixes and bpy.data.objects[q['object']].type == 'LIGHT']
        scale = f'{p.get("light_w", 0) / max(base + amp, 1e-6)} * ({expr})'
        for lob in lights:
            _driver(lob.data.driver_add('energy'), arm, scale)
        if obs and p.get('light_w') and not lights:
            light = bpy.data.lights.new(f'c3d_pulse.{p["material"]}', 'POINT')
            light.color = tuple(_lin(mspec['color']))
            light.shadow_soft_size = 0.03
            lob = bpy.data.objects.new(light.name, light)
            bu.collection('char3d').objects.link(lob)
            lob.location = Vector(rest_verts(obs[0]).mean(0)) if obs[0].type == 'MESH' else obs[0].matrix_world.translation
            bpy.context.view_layer.update()
            mw = lob.matrix_world.copy()
            lob.parent = obs[0]
            bpy.context.view_layer.update()
            lob.matrix_world = mw
            _driver(light.driver_add('energy'), arm, scale)
            lights.append(lob)
        period = em.get('period_s', 2.0)
        for cid, clip, act in clips:
            n = clip['end'] - clip['start'] + 1
            cycles = max(1, round(n / (period * clip['fps']))) if clip['loop'] else n / (period * clip['fps'])
            key_prop(arm, act, PULSE_PROP, [clip['start']], [2 * math.pi * cycles / n])
        if inputs:
            cid, clip, act = clips[0]
            arm.animation_data.action = act
            for f in range(clip['start'], clip['end'] + 2):
                bpy.context.scene.frame_set(f)
                vals.append(inputs[0].default_value)
    return {'pulse_drivers': made, 'pulse_lights': len(lights) if pulses else 0, 'pulse_range': round(max(vals) - min(vals), 4) if vals else 0.0}


def _driver(fcu, arm, expr):
    d = fcu.driver
    d.type = 'SCRIPTED'
    var = d.variables.new()
    var.name, var.type = 'w', 'SINGLE_PROP'
    var.targets[0].id, var.targets[0].data_path = arm, f'["{PULSE_PROP}"]'
    d.expression = expr


def _lin(hexcol):
    c = [int(hexcol[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


# ---------- stage ----------

def run(ctx):
    sec = ctx.spec.get('secondary', {})
    arm = bpy.data.objects[ctx.parts['rig']['object']]
    arm.animation_data_create()
    active = arm.animation_data.action
    arm[FRAME_PROP], arm[PULSE_PROP] = 0.0, 0.0
    clips = [(cid, c, bpy.data.actions[c['action']]) for cid, c in ctx.clips.items()]
    m = {'stub': False}
    chains = []
    with rest_pose(arm):
        for sp in sec.get('springs', []):
            ch = build_chain(ctx, arm, sp)
            if ch:
                chains.append(ch)
    errs, peaks, steps, t = [], [], {}, time.perf_counter()
    with only_evaluate([arm]):
        for cid, clip, act in clips:
            arm.animation_data.action = act
            for ch in chains:
                r = bake_chain(ctx, arm, ch, clip, act)
                if clip['loop']:
                    errs.append(r['err'])
                peaks.append(r['peak'])
                tgt = ch['names'][0][4:].rsplit('.', 1)[0]
                steps[tgt] = round(max(steps.get(tgt, 0.0), r['step']), 4)
    m.update(springs=len(chains), spring_bones=sum(len(c['names']) for c in chains),
             spring_unbound_parts=sum(c['unbound'] for c in chains),
             spring_period_err_rad=float(f'{max(errs, default=0.0):.3g}'),
             spring_peak_rad=round(max(peaks, default=0.0), 4), spring_max_step_rad=max(steps.values(), default=0.0), spring_step_rad=steps,
             springs_s=round(time.perf_counter() - t, 2))
    m.update(run_cloth(ctx, arm, sec.get('cloth', []), clips))
    m.update(run_pulses(ctx, arm, sec.get('pulses', []), clips))
    arm.animation_data.action = active
    bpy.context.scene.frame_set(1)
    return m
