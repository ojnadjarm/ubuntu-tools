"""Collision surfaces (body skin, lower garment layers) as BVH trees with inside tests and pushes."""
from dataclasses import replace

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from ... import bpyutil as bu
from .geom import Geo

REACH = 0.8
EXIT_M = 0.04
HIDE_UNDER = 'hide_under'
RAYS = [np.array(v) / np.linalg.norm(v) for v in ((0.0123, 0.0217, 1.0), (0.31, -0.17, -0.93), (-0.57, 0.71, 0.41))]


class Surface:
    """BVH over world-space polygons with signed depth along the nearest face normal."""

    def __init__(self, verts, polys):
        self.V, self.F = [tuple(v) for v in verts], [tuple(p) for p in polys]
        self.bvh = BVHTree.FromPolygons(self.V, self.F)

    @classmethod
    def of_object(cls, ob):
        """The evaluated mesh with the body's garment mask (`hide_under`) off: the full skin."""
        mods = [m for m in ob.modifiers if m.name == HIDE_UNDER and m.show_viewport]
        for m in mods:
            m.show_viewport = False
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        polys = [tuple(p.vertices) for p in me.polygons]
        ev.to_mesh_clear()
        verts = bu.world_verts(ob, dg)
        for m in mods:
            m.show_viewport = True
        bpy.context.view_layer.update()
        return cls(verts, polys)

    @classmethod
    def of_sheets(cls, sheets):
        g = Geo()
        for sh, thick in sheets:
            g.sheet(replace(sh, P=sh.P + sh.N * thick))
        return cls(g.V, g.F)

    def depth(self, p, maxd=None):
        hit, n, _, _ = self.bvh.find_nearest(Vector(p)) if maxd is None else self.bvh.find_nearest(Vector(p), maxd)
        if hit is None:
            return None
        return (Vector(p) - hit).dot(n), np.array(n)

    def inside(self, p, near=0.06):
        """(inside?, nearest hit): ray parity, majority of up to three rays, for points near or behind the surface."""
        hit, n, _, dist = self.bvh.find_nearest(Vector(p))
        if hit is None:
            return False, None
        if dist > near and (Vector(p) - hit).dot(n) >= 0:
            return False, (np.array(hit), np.array(n), dist)
        votes = 0
        for k, d in enumerate(RAYS):
            votes += self.crossings(p, d) % 2
            if k == 1 and votes != 1:
                break
        return votes >= 2, (np.array(hit), np.array(n), dist)

    def crossings(self, p, d):
        o, d, count = Vector(p), Vector(d), 0
        for _ in range(64):
            hit = self.bvh.ray_cast(o, d)[0]
            if hit is None:
                break
            count += 1
            o = hit + d * 1e-5
        return count

    def push(self, p, nrm, c):
        """Move p to at least c outside the surface; from inside, exit along the garment normal, or to the nearest skin
        point when that exit is far (a ray across the chest or armpit folds the row over its neighbours)."""
        ins, near = self.inside(p, c + 0.05)
        if near is None:
            return p
        hit, n, dist = near
        if ins:
            exit_ = self.bvh.ray_cast(Vector(p), Vector(nrm))[0]
            if exit_ is not None and (exit_ - Vector(p)).length < 3 * dist + EXIT_M:
                return np.array(exit_) + nrm * c
            return hit + n * c
        if dist < c:
            out = p - hit
            return hit + (out / dist if dist > 1e-9 else n) * c
        return p

    def ray_in(self, origin, d, reach=REACH):
        """Outermost hit along origin + d, seen from outside within `reach`."""
        hit, n, _, _ = self.bvh.ray_cast(Vector(origin + d * reach), Vector(-d), reach)
        return None if hit is None else (np.array(hit), np.array(n))
