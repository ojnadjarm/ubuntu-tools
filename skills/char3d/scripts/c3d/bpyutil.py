"""Small bpy helpers shared by every stage (object creation, lathe, parenting, evaluated geometry)."""
import math

import bpy
import numpy as np


def collection(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col


def mesh_object(name, verts, faces, col='char3d'):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    ob = bpy.data.objects.new(name, me)
    collection(col).objects.link(ob)
    return ob


def lathe(name, profile, segments=32, col='char3d'):
    """Revolve [(radius, z), ...] top to bottom around Z into an open quad tube."""
    verts, faces = [], []
    for r, z in profile:
        for s in range(segments):
            a = 2 * math.pi * s / segments
            verts.append((r * math.cos(a), r * math.sin(a), z))
    for i in range(len(profile) - 1):
        for s in range(segments):
            a, b = i * segments + s, i * segments + (s + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    return mesh_object(name, verts, faces, col)


def uv_sphere(name, radius, loc, scale=(1, 1, 1), col='char3d'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=radius, location=loc, scale=scale)
    return _adopt(name, col)


def cylinder(name, radius, depth, loc, col='char3d'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=depth, location=loc)
    return _adopt(name, col)


def cone(name, r1, r2, depth, loc, col='char3d'):
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=r1, radius2=r2, depth=depth, location=loc)
    return _adopt(name, col)


def _adopt(name, col):
    ob = bpy.context.active_object
    ob.name = ob.data.name = name
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    collection(col).objects.link(ob)
    return ob


def parent_to_bone(ob, arm, bone):
    """Parent keeping the world transform."""
    mw = ob.matrix_world.copy()
    ob.parent, ob.parent_type, ob.parent_bone = arm, 'BONE', bone
    bpy.context.view_layer.update()
    ob.matrix_world = mw


def world_verts(ob, depsgraph=None):
    """Evaluated world-space vertex positions as an (N, 3) array."""
    dg = depsgraph or bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3, np.float64)
    me.vertices.foreach_get('co', co)
    ev.to_mesh_clear()
    m = np.array(ob.matrix_world)
    co = co.reshape(-1, 3)
    return co @ m[:3, :3].T + m[:3, 3]


def bone_world_head(arm, bone):
    return np.array(arm.matrix_world @ arm.pose.bones[bone].head)



def mesh_parts(ctx):
    """(part id, object) for every registered part that is a mesh."""
    return [(pid, bpy.data.objects[p['object']]) for pid, p in ctx.parts.items()
            if bpy.data.objects[p['object']].type == 'MESH']


def tri_count(ob, depsgraph=None):
    """Triangles of the evaluated mesh (modifiers applied)."""
    dg = depsgraph or bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    ev.to_mesh_clear()
    return n


def quads_pct(ob):
    """Share of authored faces that are quads."""
    n = np.empty(len(ob.data.polygons), np.int32)
    ob.data.polygons.foreach_get('loop_total', n)
    return round(100 * float((n == 4).mean()), 2) if len(n) else 0.0
