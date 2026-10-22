"""Stage detail: high-poly twin `<part>.high` per part, one Geometry Nodes builder per layer kind; the bake source."""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector

from .. import bpyutil as bu

NAME = 'detail'
HIGH = 'char3d_high'
KEEP = {'MASK', 'SOLIDIFY'}
AFTER = {'SOLIDIFY'}
TILING = {'weave'}
MIN_RATIO = 4
MAX_LEVEL = 6
FACET_DEG = 20
HIGH_TRIS = {'robe': 3_500_000}
TAU = 2 * math.pi
SCALE = {'folds': 6.0, 'weave': 400.0, 'embroidery': 40.0, 'seams': 20.0, 'stitches': 200.0, 'wear': 30.0,
         'pores': 900.0, 'wrinkles': 60.0, 'carve': 25.0, 'grain': 80.0, 'facets': 10.0}
DEPTH = {'folds': 0.012, 'embroidery': 0.0015, 'seams': 0.001, 'stitches': 0.0005, 'wear': 0.0005, 'pores': 0.0002,
         'wrinkles': 0.0015, 'carve': 0.002, 'grain': 0.0005, 'facets': 0.0}


class G:
    """A Geometry Nodes group under construction: each helper adds one node and returns its output socket."""

    def __init__(self, name, frame, marks):
        self.ng = bpy.data.node_groups.new(name, 'GeometryNodeTree')
        self.ng.interface.new_socket('Geometry', in_out='INPUT', socket_type='NodeSocketGeometry')
        self.ng.interface.new_socket('Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
        self.geo = self.add('NodeGroupInput').outputs[0]
        self.pos = self.add('GeometryNodeInputPosition').outputs[0]
        self.marks = marks
        self.c, self.z0, self.z1 = frame
        self.x, self.y, self.z = self.sep(self.pos)
        lx, ly = self.m('SUBTRACT', self.x, self.c[0]), self.m('SUBTRACT', self.y, self.c[1])
        self.theta = self.m('ARCTAN2', ly, lx)
        self.rho = self.m('SQRT', self.m('ADD', self.m('MULTIPLY', lx, lx), self.m('MULTIPLY', ly, ly)))
        self.zn = self.m('DIVIDE', self.m('SUBTRACT', self.z, self.z0), max(self.z1 - self.z0, 1e-6))
        self._bd = None

    def add(self, kind, inputs=None, **props):
        n = self.ng.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        for k, v in (inputs or {}).items():
            if isinstance(v, bpy.types.NodeSocket):
                self.ng.links.new(v, n.inputs[k])
            else:
                n.inputs[k].default_value = v
        return n

    def m(self, op, a, b=0.0, c=0.0):
        return self.add('ShaderNodeMath', {0: a, 1: b, 2: c}, operation=op).outputs[0]

    def sum(self, *terms):
        out = terms[0]
        for t in terms[1:]:
            out = self.m('ADD', out, t)
        return out

    def vm(self, op, a, b=(0.0, 0.0, 0.0), out=0):
        return self.add('ShaderNodeVectorMath', {0: a, 1: b}, operation=op).outputs[out]

    def sep(self, v):
        n = self.add('ShaderNodeSeparateXYZ', {0: v})
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def vec(self, x, y, z):
        return self.add('ShaderNodeCombineXYZ', {0: x, 1: y, 2: z}).outputs[0]

    def sin(self, a, freq=1.0, phase=0.0):
        return self.m('SINE', self.m('MULTIPLY_ADD', a, freq, phase))

    def gauss(self, x, w):
        q = self.m('DIVIDE', x, w)
        return self.m('EXPONENT', self.m('MULTIPLY', self.m('MULTIPLY', q, q), -1.0))

    def smooth(self, x, a, b):
        return self.add('ShaderNodeMapRange', {0: x, 1: a, 2: b, 3: 0.0, 4: 1.0}, interpolation_type='SMOOTHSTEP').outputs[0]

    def noise(self, v, scale, detail=2.0, rough=0.5, kind='FBM'):
        return self.add('ShaderNodeTexNoise', {'Vector': v, 'Scale': scale, 'Detail': detail, 'Roughness': rough},
                        noise_type=kind).outputs[0]

    def voronoi(self, v, scale, feature='F1'):
        return self.add('ShaderNodeTexVoronoi', {'Vector': v, 'Scale': scale}, feature=feature).outputs['Distance']

    def stretch(self, sx, sy, sz):
        return self.vm('MULTIPLY', self.pos, (sx, sy, sz))

    def dist(self, p):
        return self.vm('DISTANCE', self.pos, tuple(p), out=1)

    def angle_off(self, deg):
        """Arc length (m) from the meridian at `deg` around the frame axis."""
        a = self.m('WRAP', self.m('SUBTRACT', self.theta, math.radians(deg)), math.pi, -math.pi)
        return self.m('MULTIPLY', self.m('ABSOLUTE', a), self.rho)

    @property
    def boundary(self):
        """Distance (m) to the nearest open edge of the input mesh; 10 m on a closed mesh."""
        if self._bd is None:
            fc = self.add('GeometryNodeInputMeshEdgeNeighbors').outputs[0]
            inner = self.m('GREATER_THAN', self.m('ABSOLUTE', self.m('SUBTRACT', fc, 1.0)), 0.5)
            rim = self.add('GeometryNodeDeleteGeometry', {0: self.geo, 1: inner}, domain='EDGE', mode='EDGE_FACE')
            px = self.add('GeometryNodeProximity', {0: rim.outputs[0]}, target_element='EDGES')
            self._bd = self.m('ADD', px.outputs['Distance'], self.m('MULTIPLY', self.m('SUBTRACT', 1.0, px.outputs['Is Valid']), 10.0))
        return self._bd

    def finish(self, d, kind, flat=False):
        """Store the layer as point attribute `c3d_<kind>` and push the surface along its normal by it."""
        nrm = self.add('GeometryNodeInputNormal').outputs[0]
        st = self.add('GeometryNodeStoreNamedAttribute', {0: self.geo, 'Name': f'c3d_{kind}', 'Value': d},
                      data_type='FLOAT', domain='POINT')
        off = self.add('ShaderNodeVectorMath', {0: nrm, 3: d}, operation='SCALE').outputs[0]
        sp = self.add('GeometryNodeSetPosition', {0: st.outputs[0], 'Offset': off})
        out = sp.outputs[0]
        if flat:
            ang = self.add('GeometryNodeInputMeshEdgeAngle').outputs['Unsigned Angle']
            soft = self.m('LESS_THAN', ang, math.radians(FACET_DEG))
            out = self.add('GeometryNodeSetShadeSmooth', {0: out, 'Shade Smooth': True}, domain='FACE').outputs[0]
            out = self.add('GeometryNodeSetShadeSmooth', {0: out, 'Shade Smooth': soft}, domain='EDGE').outputs[0]
        self.ng.links.new(out, self.add('NodeGroupOutput').inputs[0])
        return self.ng


def folds(g, ly, P):
    """Heavy cloth: meandering gravity tubes with pinched valleys deepening to the hem, gathers up top, hem breaks, creases, hip ripples."""
    s = ly.get('scale', SCALE['folds'])
    warp = g.m('SUBTRACT', g.noise(g.stretch(1, 1, 0.3), 0.5 * s, 3.0), 0.5)
    w = g.m('MULTIPLY_ADD', g.theta, P.get('count', 20), g.m('MULTIPLY', warp, 5.0))
    tube = g.m('MULTIPLY_ADD', g.m('POWER', g.m('ABSOLUTE', g.sin(w, 0.5)), 0.7), 2.0, -1.0)
    down = g.add('ShaderNodeMath', {0: 1.0, 1: g.zn}, operation='SUBTRACT', use_clamp=True).outputs[0]
    fade = g.m('MULTIPLY_ADD', g.smooth(g.noise(g.stretch(1, 1, 0.2), 0.7 * s, 2.0), 0.3, 0.6), 0.65, 0.35)
    drape = g.m('MULTIPLY', g.m('MULTIPLY', tube, g.m('POWER', down, 0.8)), g.m('MULTIPLY', fade, 0.42))
    gather = g.m('MULTIPLY', g.sin(w, 2.0, 1.1), g.m('MULTIPLY', g.m('SUBTRACT', 1.0, down), 0.16))
    hem = g.m('MULTIPLY', g.gauss(g.m('SUBTRACT', g.zn, 0.03), 0.035), g.m('MULTIPLY', g.sin(g.m('MULTIPLY_ADD', warp, 0.27, g.z), TAU / 0.045), 0.28))
    crease = g.m('SUBTRACT', g.noise(g.stretch(1, 1, 0.35), 2.5 * s, 3.0, 0.55, 'RIDGED_MULTIFRACTAL'), 0.6)
    terms = [drape, gather, hem, g.m('MULTIPLY', crease, 0.24)]
    if 'hips' in g.marks:
        zh = g.marks['hips'][2]
        ripple = g.sin(g.m('MULTIPLY_ADD', warp, 0.4, g.z), TAU / P.get('ripple_m', 0.035))
        terms.append(g.m('MULTIPLY', g.gauss(g.m('SUBTRACT', g.z, zh), 0.07), g.m('MULTIPLY', ripple, 0.32)))
    return g.sum(*terms)


def seam_lines(P):
    """Panel seam meridians (deg about the frame axis): the sides and the centre back; the front stays open."""
    return P.get('angles_deg', [0, 180, 90])


def seams(g, ly, P):
    """Rolled hems along every open edge with a sewn groove behind them, welted seams down the panel meridians."""
    w = P.get('width_m', 0.006)
    bd = g.boundary
    terms = [g.gauss(bd, w), g.m('MULTIPLY', g.gauss(g.m('SUBTRACT', bd, 2.5 * w), 0.6 * w), -0.6)]
    for a in seam_lines(P):
        da = g.angle_off(a)
        terms += [g.m('MULTIPLY', g.gauss(da, 0.5 * w), -1.0), g.m('MULTIPLY', g.gauss(g.m('SUBTRACT', da, 1.2 * w), 0.6 * w), 0.5)]
    return g.sum(*terms)


def stitches(g, ly, P):
    """Dashed running stitches a few mm inside every open edge and beside every panel seam (raised thread, sunk gaps)."""
    off, per, tw = P.get('offset_m', 0.006), P.get('period_m', 0.004), P.get('thread_m', 0.0007)
    arc = g.m('MULTIPLY', g.theta, g.rho)
    dash = g.smooth(g.m('COSINE', g.m('MULTIPLY', arc, TAU / per)), -0.2, 0.6)
    lines = [g.m('MULTIPLY', g.gauss(g.m('SUBTRACT', g.boundary, off), tw), g.m('MULTIPLY_ADD', dash, 1.5, -0.5))]
    vdash = g.smooth(g.m('COSINE', g.m('MULTIPLY', g.z, TAU / per)), -0.2, 0.6)
    for a in seam_lines(P):
        line = g.gauss(g.m('SUBTRACT', g.angle_off(a), 0.6 * off), tw)
        lines.append(g.m('MULTIPLY', line, g.m('MULTIPLY_ADD', vdash, 1.5, -0.5)))
    return g.sum(*lines)


def embroidery(g, ly, P):
    """Couched thread along curves: border rails, an interlaced double vine and spiral curls per band, built as GN curves."""
    R, tw = P.get('radius_m', 0.3), P.get('thread_m', 0.004)
    curves = []
    for band in P.get('bands', [{'zn': 0.06, 'height_m': 0.07}]):
        h = band['height_m']
        v0 = g.z0 + band['zn'] * (g.z1 - g.z0)
        k = max(3, round(TAU * R / band.get('period_m', 0.09)))
        for dv in (-0.5 * h, 0.5 * h):
            curves.append(g.add('GeometryNodeCurvePrimitiveLine', {'Start': (-math.pi * R, v0 + dv, 0), 'End': (math.pi * R, v0 + dv, 0)}).outputs[0])
        f = g.add('GeometryNodeSplineParameter').outputs['Factor']
        for sign in (1.0, -1.0):
            line = g.add('GeometryNodeCurvePrimitiveLine', {'Start': (0, 0, 0), 'End': (1, 0, 0)}).outputs[0]
            line = g.add('GeometryNodeResampleCurve', {'Curve': line, 'Count': 24 * k}).outputs[0]
            u = g.m('MULTIPLY_ADD', f, TAU * R, -math.pi * R)
            v = g.m('MULTIPLY_ADD', g.sin(f, TAU * k), sign * 0.28 * h, v0)
            curves.append(g.add('GeometryNodeSetPosition', {0: line, 'Position': g.vec(u, v, 0.0)}).outputs[0])
        spiral = g.add('GeometryNodeCurveSpiral', {'Resolution': 24, 'Rotations': 1.25, 'Start Radius': 0.2 * h,
                                                   'End Radius': 0.03 * h, 'Height': 0.0}).outputs[0]
        pts = g.add('GeometryNodeMeshLine', {'Count': 2 * k, 'Start Location': (-math.pi * R + 0.25 * TAU * R / k, v0, 0),
                                             'Offset': (math.pi * R / k, 0, 0)}).outputs[0]
        inst = g.add('GeometryNodeInstanceOnPoints', {'Points': pts, 'Instance': spiral}).outputs[0]
        curves.append(g.add('GeometryNodeRealizeInstances', {0: inst}).outputs[0])
    join = g.add('GeometryNodeJoinGeometry')
    for c in reversed(curves):
        g.ng.links.new(c, join.inputs[0])
    edges = g.add('GeometryNodeCurveToMesh', {'Curve': join.outputs[0]}).outputs[0]
    sample = g.vec(g.m('MULTIPLY', g.theta, R), g.z, 0.0)
    d = g.add('GeometryNodeProximity', {0: edges, 'Sample Position': sample}, target_element='EDGES').outputs['Distance']
    q = g.m('DIVIDE', d, tw)
    raised = g.m('SQRT', g.add('ShaderNodeMath', {0: 1.0, 1: g.m('MULTIPLY', q, q)}, operation='SUBTRACT', use_clamp=True).outputs[0])
    satin = g.m('MULTIPLY_ADD', g.sin(g.m('ADD', g.m('MULTIPLY', g.theta, R), g.z), TAU / 0.0012), 0.15, 0.85)
    return g.m('MULTIPLY', raised, satin)


def wear(g, ly, P):
    """Trim wear: chips and scratches where edges are convex or open, the surface worn away there."""
    s = ly.get('scale', SCALE['wear'])
    conv = g.add('ShaderNodeMath', {0: g.add('GeometryNodeInputMeshEdgeAngle').outputs['Signed Angle'], 1: 3.0}, operation='MULTIPLY', use_clamp=True).outputs[0]
    rim = g.gauss(g.boundary, P.get('rim_m', 0.012))
    mask = g.m('MAXIMUM', g.m('MAXIMUM', conv, rim), 0.15)
    chips = g.smooth(g.noise(g.pos, s, 4.0, 0.6), 0.55, 0.72)
    scratch = g.m('SUBTRACT', 1.0, g.smooth(g.voronoi(g.stretch(1, 1, 0.2), 0.5 * s, 'DISTANCE_TO_EDGE'), 0.0, 0.04))
    return g.m('MULTIPLY', g.m('MULTIPLY', mask, g.m('MULTIPLY_ADD', scratch, 0.4, chips)), -1.0)


def pores(g, ly, P):
    """Skin pores (voronoi pits) and fine cross-hatched micro-cracks, denser on the face."""
    s = ly.get('scale', SCALE['pores'])
    pit = g.m('SUBTRACT', 1.0, g.smooth(g.voronoi(g.pos, s), 0.0, 0.3))
    crack = g.m('SUBTRACT', 1.0, g.smooth(g.voronoi(g.pos, 0.5 * s, 'DISTANCE_TO_EDGE'), 0.0, 0.04))
    face = g.m('MULTIPLY_ADD', g.gauss(g.dist(g.marks['head']), 0.11), 0.8, 0.6) if 'head' in g.marks else 1.0
    return g.m('MULTIPLY', g.m('MULTIPLY_ADD', crack, 0.2, g.m('MULTIPLY', pit, face)), -1.0)


def groove(g, s, sharp=6.0):
    """A thin sunk line where the wave s peaks."""
    return g.m('MULTIPLY', g.m('POWER', g.m('MULTIPLY_ADD', s, 0.5, 0.5), sharp), -1.0)


def wrinkles(g, ly, P):
    """Age wrinkles from the landmarks: forehead lines, crow's feet, under-eye lines, nasolabial folds, neck rings, knuckles."""
    s, mk = ly.get('scale', SCALE['wrinkles']), g.marks
    jitter = g.m('MULTIPLY', g.m('SUBTRACT', g.noise(g.pos, s * 0.5, 2.0), 0.5), 3.0)
    terms = [g.m('MULTIPLY', g.m('SUBTRACT', g.noise(g.pos, s, 3.0, 0.6, 'RIDGED_MULTIFRACTAL'), 0.7), -0.25)]
    if 'eye.L' in mk and 'eye.R' in mk:
        eL, eR = Vector(mk['eye.L']), Vector(mk['eye.R'])
        mid, iod = (eL + eR) / 2, max((eL - eR).length, 0.04)
        front = g.smooth(g.m('SUBTRACT', mid.y + 0.03, g.y), 0.0, 0.02)
        fz = mid.z + 0.75 * iod
        brow = g.m('MULTIPLY', g.gauss(g.m('SUBTRACT', g.x, mid.x), 0.9 * iod), g.gauss(g.m('SUBTRACT', g.z, fz), 0.35 * iod))
        terms.append(g.m('MULTIPLY', g.m('MULTIPLY', brow, front), groove(g, g.sin(g.m('ADD', g.z, g.m('MULTIPLY', jitter, 0.002)), TAU / (0.17 * iod)))))
        for e in (eL, eR):
            sx = 1.0 if e.x >= mid.x else -1.0
            c = e + Vector((sx * 0.45 * iod, 0.15 * iod, 0.0))
            qx, qz = g.m('MULTIPLY', g.m('SUBTRACT', g.x, c.x), sx), g.m('SUBTRACT', g.z, c.z)
            r = g.dist(c)
            fan = g.m('MULTIPLY', g.gauss(g.m('SUBTRACT', r, 0.35 * iod), 0.2 * iod), g.smooth(qx, -0.1 * iod, 0.1 * iod))
            terms.append(g.m('MULTIPLY', fan, groove(g, g.sin(g.m('ADD', g.m('ARCTAN2', qz, qx), g.m('MULTIPLY', jitter, 0.15)), 9.0))))
            bag = g.m('MULTIPLY', g.gauss(g.dist(e + Vector((0, 0, -0.3 * iod))), 0.25 * iod), front)
            terms.append(g.m('MULTIPLY', g.m('MULTIPLY', bag, 0.6), groove(g, g.sin(g.dist(e), TAU / (0.09 * iod)))))
            a = mid + Vector((sx * 0.3 * iod, 0, -0.75 * iod))
            b = mid + Vector((sx * 0.6 * iod, 0, -1.35 * iod))
            ab = Vector((b.x - a.x, 0, b.z - a.z))
            t = g.add('ShaderNodeMath', {0: g.m('DIVIDE', g.m('ADD', g.m('MULTIPLY', g.m('SUBTRACT', g.x, a.x), ab.x),
                                                                   g.m('MULTIPLY', g.m('SUBTRACT', g.z, a.z), ab.z)), ab.length_squared)},
                      operation='ADD', use_clamp=True).outputs[0]
            dx = g.m('SUBTRACT', g.x, g.m('MULTIPLY_ADD', t, ab.x, a.x))
            dz = g.m('SUBTRACT', g.z, g.m('MULTIPLY_ADD', t, ab.z, a.z))
            dseg = g.m('SQRT', g.m('ADD', g.m('MULTIPLY', dx, dx), g.m('MULTIPLY', dz, dz)))
            terms.append(g.m('MULTIPLY', g.m('MULTIPLY', g.gauss(dseg, 0.06 * iod), front), -1.2))
    if 'neck' in mk:
        n = Vector(mk['neck'])
        ring = g.m('MULTIPLY', g.gauss(g.m('SUBTRACT', g.z, n.z + 0.02), 0.05), g.gauss(g.dist(n), 0.11))
        terms.append(g.m('MULTIPLY', ring, groove(g, g.sin(g.m('ADD', g.z, g.m('MULTIPLY', jitter, 0.003)), TAU / 0.016))))
    for hand in ('hand.L', 'hand.R'):
        if hand in mk:
            knuckle = g.m('SUBTRACT', g.noise(g.pos, 4 * s, 3.0, 0.6, 'RIDGED_MULTIFRACTAL'), 0.6)
            terms.append(g.m('MULTIPLY', g.gauss(g.dist(mk[hand]), 0.07), g.m('MULTIPLY', knuckle, -1.0)))
    return g.sum(*terms)


def carve(g, ly, P):
    """Carving: staggered rows of overlapping talon scales (crisp lower lip, sloping top, sunk outline), twisted round flutes between."""
    k, pitch = P.get('scales', 10), P.get('scale_m', 0.014)
    u = g.m('MULTIPLY', g.theta, k / TAU)
    v = g.m('DIVIDE', g.z, pitch)
    row = g.m('FLOOR', v)
    fu = g.m('SUBTRACT', g.m('FRACT', g.m('MULTIPLY_ADD', g.m('MODULO', row, 2.0), 0.5, u)), 0.5)
    arc = g.m('MULTIPLY', g.m('MULTIPLY', fu, fu), 1.6)
    s = g.m('FRACT', g.m('ADD', v, arc))
    shingle = g.m('MULTIPLY', g.smooth(s, 0.0, 0.12), g.m('MULTIPLY_ADD', s, -0.7, 1.0))
    outline = g.m('MULTIPLY', g.gauss(g.m('SUBTRACT', g.m('ABSOLUTE', fu), 0.5), 0.05), -0.5)
    tw = g.m('MULTIPLY_ADD', g.z, P.get('twist', 30.0), g.m('MULTIPLY', g.theta, P.get('flutes', 8)))
    flute = g.m('POWER', g.m('MULTIPLY_ADD', g.m('SINE', tw), 0.5, 0.5), 3.0)
    return g.sum(shingle, outline, g.m('MULTIPLY', flute, -0.25))


def grain(g, ly, P):
    """Wood grain: long fibres along the axis and wavy growth lines."""
    s, st = ly.get('scale', SCALE['grain']), P.get('stretch', 12.0)
    q = g.stretch(1, 1, 1 / st)
    fib = g.m('SUBTRACT', g.noise(q, s, 6.0, 0.6, 'RIDGED_MULTIFRACTAL'), 0.6)
    lines = g.sin(g.m('MULTIPLY', g.noise(q, 0.25 * s, 3.0), 4.0), TAU)
    return g.sum(g.m('MULTIPLY', fib, 0.7), g.m('MULTIPLY', lines, 0.3))


def facets(g, ly, P):
    """Crystal: crisp facets (simple subdivision, smooth inside a facet, sharp across its edges) with conchoidal chips along them."""
    s = ly.get('scale', SCALE['facets'])
    edge = g.smooth(g.add('GeometryNodeInputMeshEdgeAngle').outputs['Unsigned Angle'], 0.2, 0.6)
    chip = g.smooth(g.voronoi(g.pos, s), 0.15, 0.6)
    return g.m('MULTIPLY', g.m('MULTIPLY', edge, g.m('SUBTRACT', 1.0, chip)), -1.0)


KINDS = {'folds': folds, 'seams': seams, 'stitches': stitches, 'embroidery': embroidery, 'wear': wear, 'pores': pores,
         'wrinkles': wrinkles, 'carve': carve, 'grain': grain, 'facets': facets}


def matches(pid, key):
    return pid == key or pid.startswith(key + '.')


def frames(parts):
    """Shared field frame per root id (robe and robe.trim fold together): world bbox centre and z range."""
    out = {}
    for pid, ob in parts.items():
        co = bu.world_verts(ob)
        lo, hi = co.min(0), co.max(0)
        r = pid.split('.')[0]
        if r in out:
            lo, hi = np.minimum(lo, out[r][0]), np.maximum(hi, out[r][1])
        out[r] = (lo, hi)
    return out


def local_frame(ob, root):
    mi = ob.matrix_world.inverted()
    lo, hi = root
    c = mi @ Vector((lo + hi) / 2)
    return c, (mi @ Vector(lo)).z, (mi @ Vector(hi)).z


def twin(ob, flat):
    """Copy keeping only masks (MPFB helpers, hidden-under faces) and solidify (simple offset: even offset spikes on displaced creases); hidden from renders."""
    hi = ob.copy()
    hi.data = ob.data.copy()
    hi.name = hi.data.name = f'{ob.name}.high'
    hi.parent = None
    hi.matrix_world = ob.matrix_world.copy()
    for m in list(hi.modifiers):
        if m.type not in KEEP:
            hi.modifiers.remove(m)
        elif m.type == 'SOLIDIFY':
            m.use_even_offset = False
    if hi.data.shape_keys:
        hi.shape_key_clear()
    bu.collection(HIGH).objects.link(hi)
    sub = hi.modifiers.new('detail_subdiv', 'SUBSURF')
    sub.subdivision_type = 'SIMPLE' if flat else 'CATMULL_CLARK'
    sub.levels = sub.render_levels = 0
    hi.modifiers.move(len(hi.modifiers) - 1, sum(m.type == 'MASK' for m in hi.modifiers))
    hi.hide_render = True
    return hi, sub


def densify(hi, sub, level, target):
    """Hit `target` tris between x4 levels: one level down if over, then split the lowest faces once (conforming, hem first)."""
    tris = bu.tri_count(hi)
    if tris > target and level > 1:
        level -= 1
        sub.levels = sub.render_levels = level
        tris = bu.tri_count(hi)
    extra = (target - tris) / (3 * tris)
    if extra > 0.01:
        bm = bmesh.new()
        bm.from_mesh(hi.data)
        faces = sorted(bm.faces, key=lambda f: f.calc_center_median().z)
        cut, need, got = [], extra * sum(len(f.verts) - 2 for f in faces), 0
        for f in faces:
            if got >= need:
                break
            cut.append(f)
            got += len(f.verts) - 2
        bmesh.ops.subdivide_edges(bm, edges=list({e for f in cut for e in f.edges}), cuts=1, use_grid_fill=True)
        bm.to_mesh(hi.data)
        bm.free()
        tris = bu.tri_count(hi)
    return level, tris


def subdivide(hi, sub, level, target=None):
    """Smallest level >= the spec level giving at least MIN_RATIO x the construction low's triangles, then `target` if set."""
    low = bu.tri_count(hi)
    while True:
        sub.levels = sub.render_levels = level
        tris = bu.tri_count(hi)
        if tris >= MIN_RATIO * low or level >= MAX_LEVEL:
            if target:
                level, tris = densify(hi, sub, level, target)
            return level, tris, low
        level += 1


def layer(hi, ly, frame, marks, flat):
    """Build the layer kind's node group and stack it before the shape modifiers."""
    params = ly.get('params', {})
    g = G(f'c3d_{ly["kind"]}.{hi.name}', frame, marks)
    d = g.m('MULTIPLY', KINDS[ly['kind']](g, ly, params), ly.get('depth_m', DEPTH[ly['kind']]))
    mod = hi.modifiers.new(f'detail_{ly["kind"]}', 'NODES')
    mod.node_group = g.finish(d, ly['kind'], flat and ly['kind'] == 'facets')
    keep = [i for i, m in enumerate(hi.modifiers) if m.type in AFTER]
    if keep:
        hi.modifiers.move(len(hi.modifiers) - 1, keep[0])


def displacement(hi, kinds):
    """Max |offset| in mm per layer kind, read back from the evaluated high's c3d_<kind> attributes."""
    ev = hi.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    out = {}
    for k in kinds:
        a = me.attributes.get(f'c3d_{k}')
        if a is not None and len(a.data):
            v = np.empty(len(a.data), np.float32)
            a.data.foreach_get('value', v)
            out[k] = round(float(np.abs(v).max()) * 1000, 3)
    ev.to_mesh_clear()
    return out


def run(ctx):
    d = ctx.spec.get('detail', {})
    level0 = d.get('subdiv', {}).get('draft' if ctx.draft else 'final', 1)
    layers = d.get('layers', [])
    targets = {} if ctx.draft else d.get('high_tris', HIGH_TRIS)
    parts = dict(bu.mesh_parts(ctx))
    keys = {p for ly in layers for p in ly['parts']}
    missing = sorted(k for k in keys if not any(matches(p, k) for p in parts))
    wanted = sorted(p for p in parts if any(matches(p, k) for k in keys))
    fr = frames({p: parts[p] for p in parts if p.split('.')[0] in {w.split('.')[0] for w in wanted}})
    tris, levels, ratio, disp, tiling = {}, {}, {}, {}, {}
    for pid in wanted:
        ob = parts[pid]
        mine = [ly for ly in layers if any(matches(pid, k) for k in ly['parts'])]
        flat = any(ly['kind'] == 'facets' for ly in mine)
        hi, sub = twin(ob, flat)
        levels[pid], tris[pid], low = subdivide(hi, sub, level0, targets.get(pid))
        ratio[pid] = round(tris[pid] / max(low, 1), 2)
        mi = ob.matrix_world.inverted()
        marks = {r: tuple(mi @ Vector(v)) for r, v in ctx.landmarks.items()}
        for ly in mine:
            if ly['kind'] in TILING:
                tiling.setdefault(ly['kind'], []).append(pid)
            else:
                layer(hi, ly, local_frame(ob, fr[pid.split('.')[0]]), marks, flat)
        ctx.parts[pid]['high'] = hi.name
        for k, v in displacement(hi, [ly['kind'] for ly in mine]).items():
            disp.setdefault(k, {})[pid] = v
    todo = [f'detail part {k}: no such part' for k in missing]
    return {'stub': False, 'todo': todo, 'level': level0, 'levels': levels, 'parts': len(wanted),
            'high_tris': sum(tris.values()), 'per_part': tris, 'ratio': ratio, 'disp_mm': disp, 'tiling': tiling}
