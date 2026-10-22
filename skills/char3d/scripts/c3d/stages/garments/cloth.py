"""Fitting and draping: push sheets outside the body and lower layers, cloth-simulate once, nudge out penetrations."""
import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree

from ... import bpyutil as bu
from .geom import smooth

CLEAR_LAYER = 0.005
TMP = 'c3d_garment_tmp'


def fit(sheets, body, below, clear, iters=8):
    """Push grid verts outside the body and lower layers; smoothing the push makes it drape instead of dent."""
    moved = 0
    for sh in sheets:
        P0 = sh.P.copy()
        P = P0.copy()
        N0, act = sh.N.reshape(-1, 3), sh.active().ravel()
        for it in range(iters):
            flat = P.reshape(-1, 3)
            for k in np.flatnonzero(act):
                flat[k] = body.push(flat[k], N0[k], clear)
                r = below.depth(flat[k], 0.15) if below else None
                if r and r[0] < CLEAR_LAYER:
                    flat[k] = flat[k] + r[1] * (CLEAR_LAYER - r[0])
            if it < iters - 3:
                P = P0 + smooth(P - P0, sh.closed, 3)
        moved += int((np.linalg.norm(P - P0, axis=-1) > 5e-4).sum())
        sh.P = P
        sh.update_normals()
    return moved


def temp_object(name, verts, faces):
    return bu.mesh_object(name, verts, faces, TMP)


def drape(sheets, pins, colliders, frames, s, settle_mm=1.0, max_frames=None):
    """Cloth-simulate the sheets once against the colliders and ground until no vert moves over `settle_mm` a frame."""
    V, F, W, n = [], [], [], 0
    for sh, w in zip(sheets, pins):
        R, C = sh.P.shape[:2]
        idx = np.arange(R * C).reshape(R, C) + n
        cols = C if sh.closed else C - 1
        i, j = np.meshgrid(np.arange(R - 1), np.arange(cols), indexing='ij')
        f = np.stack([idx[i, j], idx[i + 1, j], idx[i + 1, (j + 1) % C], idx[i, (j + 1) % C]], -1)
        F.append((f[sh.keep] if sh.keep is not None else f).reshape(-1, 4))
        V.append(sh.P.reshape(-1, 3))
        W.append(np.where(sh.active(), w, 1.0).ravel())
        n += R * C
    cloth = temp_object('c3d_drape', np.vstack(V), np.vstack(F))
    W = np.concatenate(W)
    vg = cloth.vertex_groups.new(name='pin')
    for k in np.flatnonzero(W > 1e-3):
        vg.add([int(k)], float(W[k]), 'REPLACE')
    obs = [cloth, temp_object('c3d_ground', [(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)], [(0, 1, 2, 3)])]
    obs += [temp_object(f'c3d_collider{k}', c.V, c.F) for k, c in enumerate(colliders)]
    for ob in obs[1:]:
        ob.modifiers.new('collision', 'COLLISION')
        ob.collision.thickness_outer, ob.collision.cloth_friction = 0.003 * s, 8.0
    m = cloth.modifiers.new('cloth', 'CLOTH')
    st = m.settings
    st.quality, st.mass, st.air_damping = 6, 0.6, 8.0
    st.tension_stiffness = st.compression_stiffness = 30.0
    st.shear_stiffness, st.bending_stiffness = 15.0, 2.0
    st.vertex_group_mass, st.pin_stiffness = 'pin', 1.0
    cs = m.collision_settings
    cs.collision_quality, cs.distance_min, cs.use_self_collision = 3, 0.004 * s, False
    max_frames = max_frames or 3 * frames
    sc = bpy.context.scene
    keep = sc.frame_start, sc.frame_end, sc.frame_current
    sc.frame_start, sc.frame_end = 1, max_frames
    m.point_cache.frame_start, m.point_cache.frame_end = 1, max_frames
    prev, step, f = bu.world_verts(cloth), float('inf'), 0
    while f < max_frames and (f < frames or step > settle_mm):
        f += 1
        sc.frame_set(f)
        co = bu.world_verts(cloth)
        step, prev = 1000 * float(np.linalg.norm(co - prev, axis=1).max()), co
    sc.frame_start, sc.frame_end = keep[0], keep[1]
    sc.frame_set(keep[2])
    rest = np.vstack(V)
    for sh in sheets:
        R, C = sh.P.shape[:2]
        sh.P, co = co[:R * C].reshape(R, C, 3).copy(), co[R * C:]
        sh.update_normals()
    remove(obs)
    bpy.data.collections.remove(bpy.data.collections[TMP])
    settled = np.vstack([sh.P.reshape(-1, 3) for sh in sheets])
    return {'verts': int(len(rest)), 'frames': f, 'mean_move_mm': round(1000 * float(np.linalg.norm(settled - rest, axis=1).mean()), 1),
            'last_frame_max_mm': round(step, 2), 'settled': step <= settle_mm}


def nudge(sheets, points, step):
    """Move the base verts nearest to penetrating evaluated points outward, with a little falloff."""
    flat = [(sh, i, j) for sh in sheets for i, j in np.ndindex(*sh.P.shape[:2])]
    tree = KDTree(len(flat))
    for k, (sh, i, j) in enumerate(flat):
        tree.insert(Vector(sh.P[i, j]), k)
    tree.balance()
    D = {id(sh): np.zeros_like(sh.P) for sh in sheets}
    for p in points:
        for _, k, _ in tree.find_n(Vector(p), 2):
            sh, i, j = flat[k]
            D[id(sh)][i, j] = sh.N[i, j] * step
    for sh in sheets:
        sh.P = sh.P + smooth(D[id(sh)], sh.closed, 1) * 2
        sh.update_normals()


def remove(objects):
    for ob in objects:
        me = ob.data
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(me)


def floor(sheets, z):
    for sh in sheets:
        sh.P[..., 2] = np.maximum(sh.P[..., 2], z)


def cut_joins(built, margin):
    """Hide host faces with a corner inside a joined tube sheet (sleeve) after the drape, `margin` past its rings, and the
    tube's shoulder-end faces buried in the host's rings, so the tube never cuts through the host; returns the previous
    keep masks for restoring once the garment is published."""
    saved = {}
    for host, key in built.joins:
        h, t = built.sheets[host], built.sheets[key]
        C = t.P.mean(1)
        r = np.linalg.norm(t.P - C[:, None], axis=-1).mean(1) + margin
        V = h.P.reshape(-1, 3)
        inside = np.zeros(len(V), bool)
        for i in range(len(C) - 1):
            ab = C[i + 1] - C[i]
            u = np.clip(((V - C[i]) @ ab) / max(ab @ ab, 1e-12), 0, 1)
            inside |= np.linalg.norm(V - (C[i] + u[:, None] * ab), axis=1) < r[i] + (r[i + 1] - r[i]) * u
        R, Cn = h.P.shape[:2]
        ins = inside.reshape(R, Cn)
        cols = Cn if h.closed else Cn - 1
        jn = (np.arange(cols) + 1) % Cn
        hit = ins[:-1, :cols] | ins[1:, :cols] | ins[:-1, jn] | ins[1:, jn]
        saved.setdefault(host, h.keep)
        h.keep = ~hit if h.keep is None else h.keep & ~hit
        P = t.P
        hr = np.interp(-P[..., 2], -h.C[:, 2], h.rad)
        hc = np.stack([np.interp(-P[..., 2], -h.C[:, 2], h.C[:, k]) for k in range(2)], -1)
        buried = (np.linalg.norm(P[..., :2] - hc, axis=-1) < hr + margin) & (np.arange(len(P)) < len(P) // 3)[:, None]
        if buried.any():
            saved.setdefault(key, t.keep)
            tc = P.shape[1] if t.closed else P.shape[1] - 1
            jt = (np.arange(tc) + 1) % P.shape[1]
            mask = ~(buried[:-1, :tc] | buried[1:, :tc] | buried[:-1, jt] | buried[1:, jt])
            t.keep = mask if t.keep is None else t.keep & mask
    return saved
