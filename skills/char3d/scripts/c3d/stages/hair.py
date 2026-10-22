"""Stage hair: groomed beard, moustache and scalp: guide curves, strands bound to the face surface, stand-in cards."""
import math

import bpy
import numpy as np
from mathutils.bvhtree import BVHTree

from .. import bpyutil as bu
from .. import envelope

NAME = 'hair'
UV = 'c3d_hair_uv'
DEFORM = 'c3d_deform_curves_on_surface'
REF_IOD = 0.0573
MOUSTACHE_SWEEP = (0.62, 0.3)  # lateral, down x length: sweeps out to the beard and leaves the lips readable
CLEAR_SKIN = {'beard': 0.004, 'moustache': 0.002, 'scalp': 0.003}
CLEAR_GARMENT = 0.04
RADIUS = {'beard': (0.0007, 0.00015), 'moustache': (0.0006, 0.00015)}
STRANDS_PER_CARD = 60
HANG, HANG_FROM = 0.85, 0.5
SCALP_CARDS = 110
BEARD_DEPTH = 0.045
FLYAWAY = 0.03
COMB_STEP = 0.004
COMB_TOP, COMB_LOW = (0.3, 1.0, 0.0), (0.05, 0.6, -1.0)
NAPE = 0.075
DRAPE_CLEAR = 0.006
DRAPE_REACH = 0.15
DRAPE_RAMP = 0.1


def _zone_beard(d, n, w):
    ax = np.abs(d[:, 0])
    top = np.minimum(-0.082 + 1.2 * np.maximum(ax - 0.025, 0), -0.02)
    back = 0.04 + 0.5 * np.maximum(ax - 0.04, 0)
    neck = (d[:, 2] < -0.115) & (d[:, 1] > 0.035)
    return (ax < w / 2) & (d[:, 2] < top) & (d[:, 2] > -0.135) & (d[:, 1] < back) & ~neck & (n[:, 1] < 0.3) & (n[:, 2] < 0.5)


def _zone_moustache(d, n, w):
    return ((np.abs(d[:, 0]) < min(w / 2, 0.03)) & (d[:, 2] > -0.072) & (d[:, 2] < -0.052) & (d[:, 1] < -0.01)
            & (n[:, 1] < -0.2) & (n[:, 2] < 0.4))


def _zone_scalp(d, n, w):
    """Sides and back above the ears plus the crown behind a receding hairline."""
    back = (d[:, 1] > 0.03) & ((np.abs(d[:, 0]) > 0.05) | (d[:, 1] > 0.09)) & (d[:, 2] < 0.06) & (n[:, 2] < 0.6)
    crown = (d[:, 1] > 0.0) & (d[:, 2] >= 0.03)
    return (back | crown) & (d[:, 2] > -0.03) & (d[:, 2] < 0.16) & (n[:, 1] > -0.3)


ZONES = {'beard': _zone_beard, 'moustache': _zone_moustache, 'scalp': _zone_scalp}


class Surface:
    """Rest-pose world triangles of the skin mesh with a per-polygon UV atlas the deform node can invert."""

    def __init__(self, ob):
        self.ob = ob
        me = ob.data
        me.calc_loop_triangles()
        m = np.array(ob.matrix_world)
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get('co', co)
        self.co = co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3]
        nt = len(me.loop_triangles)
        tv, tl = np.empty(nt * 3, np.int64), np.empty(nt * 3, np.int64)
        me.loop_triangles.foreach_get('vertices', tv)
        me.loop_triangles.foreach_get('loops', tl)
        self.tv, self.tl = tv.reshape(-1, 3), tl.reshape(-1, 3)
        self.uv = self._atlas(me)
        tri = self.co[self.tv]
        cr = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        self.area = np.linalg.norm(cr, axis=1) / 2
        self.normal = cr / np.maximum(2 * self.area, 1e-12)[:, None]
        self.centroid = tri.mean(1)
        vis = self._visible(ob)
        self.visible = vis[self.tv].all(1)
        polys = [tuple(p.vertices) for p in me.polygons if vis[list(p.vertices)].all()]
        self.bvh = BVHTree.FromPolygons(self.co.tolist(), polys)
        ob.add_rest_position_attribute = True

    @staticmethod
    def _visible(ob):
        """Vertices that survive the object's vertex-group Mask modifiers (MPFB helpers, hide-under)."""
        me = ob.data
        vis = np.ones(len(me.vertices), bool)
        for md in ob.modifiers:
            if md.type != 'MASK' or md.mode != 'VERTEX_GROUP' or md.vertex_group not in ob.vertex_groups:
                continue
            gi = ob.vertex_groups[md.vertex_group].index
            grp = np.array([any(g.group == gi and g.weight > md.threshold for g in v.groups) for v in me.vertices])
            vis &= ~grp if md.invert_vertex_group else grp
        return vis

    @staticmethod
    def _atlas(me):
        """Each polygon gets its own UV cell, so every UV point names exactly one triangle."""
        n_poly = len(me.polygons)
        start, total = np.empty(n_poly, np.int64), np.empty(n_poly, np.int64)
        me.polygons.foreach_get('loop_start', start)
        me.polygons.foreach_get('loop_total', total)
        poly = np.repeat(np.arange(n_poly), total)
        corner = np.arange(len(me.loops)) - np.repeat(start, total)
        g = math.ceil(math.sqrt(n_poly))
        a = 2 * np.pi * corner / np.repeat(total, total)
        uv = np.stack([(poly % g + 0.5 + 0.45 * np.cos(a)) / g, (poly // g + 0.5 + 0.45 * np.sin(a)) / g], 1)
        active = me.uv_layers.active.name if me.uv_layers.active else None
        layer = me.uv_layers.get(UV) or me.uv_layers.new(name=UV, do_init=False)
        layer.data.foreach_set('uv', uv.astype(np.float32).ravel())
        if active:
            me.uv_layers.active = me.uv_layers[active]
            me.uv_layers[active].active_render = True
        return uv

    def sample(self, mask, n, rng):
        """Area-weighted points on the masked triangles: positions, face normals, atlas UVs."""
        idx = np.flatnonzero(mask & self.visible)
        if not len(idx):
            raise ValueError('hair: root zone matched no skin triangles (check eye landmarks / surface)')
        tri = rng.choice(idx, n, p=self.area[idx] / self.area[idx].sum())
        r1, r2 = np.sqrt(rng.random(n)), rng.random(n)
        b = np.stack([1 - r1, r1 * (1 - r2), r1 * r2], 1)
        pos = np.einsum('nk,nkj->nj', b, self.co[self.tv[tri]])
        uv = np.einsum('nk,nkj->nj', b, self.uv[self.tl[tri]])
        return pos, self.normal[tri], uv

    def push_out(self, pts, clear):
        """Move points that are inside the skin, or closer than `clear`, onto the skin plus `clear`."""
        flat = pts.reshape(-1, 3).copy()
        for i, p in enumerate(flat):
            loc, nrm, _, dist = self.bvh.find_nearest(p)
            if loc is None:
                continue
            side = (p[0] - loc[0]) * nrm[0] + (p[1] - loc[1]) * nrm[1] + (p[2] - loc[2]) * nrm[2]
            if side < clear:
                flat[i] = (loc[0] + nrm[0] * clear, loc[1] + nrm[1] * clear, loc[2] + nrm[2] * clear)
        return flat.reshape(pts.shape)


def _bezier(p0, c1, c2, p3, k):
    t = np.linspace(0, 1, k)[None, :, None]
    return ((1 - t) ** 3 * p0[:, None] + 3 * (1 - t) ** 2 * t * c1[:, None] + 3 * (1 - t) * t ** 2 * c2[:, None]
            + t ** 3 * p3[:, None])


def _grow(kind, p0, n0, frame, h, rng, k):
    """Rest path per root: cubic Bezier from the skin out and down; shape per kind."""
    e, s = frame
    n = len(p0)
    down = np.array([0.0, 0.0, -1.0])
    if kind == 'beard':
        dx = (p0[:, 0] - e[0]) / s
        u = np.clip(dx / (h.get('width_m', 0.14) / 2), -1, 1)
        length = h.get('length_m', 0.4) * (1 - 0.55 * u ** 2) * rng.uniform(0.9, 1.05, n)
        tip = np.stack([e[0] + dx * s * 0.35, p0[:, 1] - 0.03 * s, e[2] - 0.11 * s - length], 1)
        c1 = p0 + n0 * 0.03 * s + down * 0.02 * s
        c2 = np.stack([tip[:, 0], tip[:, 1] - 0.01 * s, p0[:, 2] - (p0[:, 2] - tip[:, 2]) * 0.45], 1)
    elif kind == 'moustache':
        dx = p0[:, 0] - e[0]
        side = np.where(np.abs(dx) < 1e-3, rng.choice([-1.0, 1.0], n), np.sign(dx))
        length = h.get('length_m', 0.09) * rng.uniform(0.85, 1.05, n)
        lat = np.stack([side, np.zeros(n), np.zeros(n)], 1)
        tip = p0 + lat * (0.025 * s + MOUSTACHE_SWEEP[0] * length[:, None]) + np.array([0, -0.012 * s, 0]) \
            + down * MOUSTACHE_SWEEP[1] * length[:, None]
        c1 = p0 + n0 * 0.008 * s + lat * 0.018 * s
        c2 = tip - lat * 0.008 * s + np.array([0, -0.004 * s, 0.025 * s])
    return _bezier(p0, c1, c2, tip, k)


def _resample(line, k):
    """k points evenly spaced by arc length along a polyline."""
    arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(line, axis=0), axis=1))])
    t = np.linspace(0, arc[-1], k)
    return np.stack([np.interp(t, arc, line[:, i]) for i in range(3)], 1)


def _skull(pts):
    """Axis-aligned ellipsoid (centre, radii) fitted to scalp points: a smooth skull the comb walks on, so ears and
    inner head surfaces cannot catch a strand."""
    A = np.hstack([pts ** 2, pts])
    q = np.linalg.lstsq(A, np.ones(len(pts)), rcond=None)[0]
    c = -q[3:] / (2 * q[:3])
    g = 1 + (q[:3] * c ** 2).sum()
    return c, np.sqrt(g / q[:3])


def _comb(p0, pool, frame, h, rng, k):
    """Scalp rest path: walk a fitted skull, combed straight back on the crown and turning down below its equator,
    at a slowly growing lift; then fall from the nape."""
    e, s = frame
    step, nape = COMB_STEP * s, e[2] - NAPE * s
    c, R = _skull(pool)
    paths = []
    for p in p0:
        side = np.sign(p[0] - e[0]) if abs(p[0] - e[0]) > 0.01 * s else 0.0
        top, low = np.array(COMB_TOP) * [side, 1, 1], np.array(COMB_LOW) * [side, 1, 1]
        line, q, lift = [p], p, CLEAR_SKIN['scalp']
        for _ in range(int(0.3 / COMB_STEP)):
            u = (q - c) / R
            on = c + (q - c) / np.linalg.norm(u)
            nrm = (on - c) / R ** 2
            nrm /= np.linalg.norm(nrm)
            w = np.clip(1.5 * nrm[2] + 0.3, 0, 1)
            want = w * top + (1 - w) * low
            t = want - want.dot(nrm) * nrm
            if np.linalg.norm(t) < 0.25 or q[2] < nape or nrm[2] < -0.1:
                break
            q = on + nrm * lift + t / np.linalg.norm(t) * step
            lift = min(lift + 0.0002 * s, 0.009 * s)
            line.append(q)
        d = line[-1] - line[-2] if len(line) > 1 else np.array([0.0, 0.3, -1.0])
        d = d / max(np.linalg.norm(d), 1e-9)
        for _ in range(int(h.get('length_m', 0.12) * rng.uniform(0.85, 1.15) / step)):
            d = 0.85 * d + 0.15 * np.array([0.05 * side, 0.2, -1.0])
            d /= np.linalg.norm(d)
            line.append(line[-1] + d * step)
        paths.append(_resample(np.array(line), k))
    return np.array(paths)


def _relax(paths, surf, spec, clear_skin, iters=4, garment=True):
    """Keep strands outside skin and (unless `garment` is off) the spec's garment envelope with fixed segment lengths
    (follow-the-leader) and light smoothing."""
    seg = np.linalg.norm(np.diff(paths, axis=1), axis=2)
    for _ in range(iters):
        p = paths[:, 1:]
        rho = np.hypot(p[..., 0], p[..., 1])
        r = envelope.radius(spec, p[..., 2])
        need = (r > 0) & (rho < r + CLEAR_GARMENT) & garment
        p[..., :2] = np.where(need[..., None], p[..., :2] * ((r + CLEAR_GARMENT) / np.maximum(rho, 1e-9))[..., None],
                              p[..., :2])
        paths[:, 1:] = surf.push_out(p, clear_skin)
        paths[:, 1:-1] = 0.5 * paths[:, 1:-1] + 0.25 * (paths[:, :-2] + paths[:, 2:])
        for i in range(1, paths.shape[1]):
            d = paths[:, i] - paths[:, i - 1]
            paths[:, i] = paths[:, i - 1] + d * (seg[:, i - 1] / np.maximum(np.linalg.norm(d, axis=1), 1e-9))[:, None]
    return paths


def _seeds(pts, n, rng):
    """Farthest-point sample n indices for even clump spacing."""
    idx = [int(rng.integers(len(pts)))]
    dist = np.linalg.norm(pts - pts[idx[0]], axis=1)
    for _ in range(min(n, len(pts)) - 1):
        idx.append(int(dist.argmax()))
        dist = np.minimum(dist, np.linalg.norm(pts - pts[idx[-1]], axis=1))
    return np.array(idx)


def _wave(paths, frame_s, rng):
    """Slow lateral wave per lock, growing toward the tip."""
    t = np.linspace(0, 1, paths.shape[1])[None, :]
    phase, amp = rng.uniform(0, 2 * np.pi, (len(paths), 1)), rng.uniform(0.003, 0.007, (len(paths), 1)) * frame_s
    paths[..., 0] += amp * t * np.sin(2.4 * np.pi * t + phase)
    return paths


def _volume(guides, frame, h, rng):
    """Beard body: push each lock off the chest by a random depth, deepest mid-beard and mid-length, so the front
    rounds out instead of lying as one sheet on the robe."""
    e, s = frame
    k = guides.shape[1]
    t = np.linspace(0, 1, k)[None, :]
    u = np.clip((guides[:, 0, 0] - e[0]) / (s * h.get('width_m', 0.14) / 2), -1, 1)[:, None]
    depth = BEARD_DEPTH * s * (1 - 0.7 * u ** 2) * rng.uniform(0.1, 1.0, (len(guides), 1))
    radial = guides[..., :2] / np.maximum(np.linalg.norm(guides[..., :2], axis=2, keepdims=True), 1e-9)
    guides[..., :2] += radial * (depth * np.sin(np.pi * np.clip(t / 1.1, 0, 1)) ** 0.8 * t ** 0.5)[..., None]
    return guides


def _strands(guides, groots, roots, owner, rng):
    """Strands follow their lock's guide, pinched toward the tip, trimmed to varied lengths."""
    n, k = len(roots), guides.shape[1]
    t = np.linspace(0, 1, k)
    frac = rng.uniform(0.78, 1.0, n)
    tt = t[None, :] * frac[:, None] * (k - 1)
    i0 = np.minimum(np.floor(tt).astype(int), k - 2)
    w = (tt - i0)[..., None]
    g = guides[owner]
    path = g[np.arange(n)[:, None], i0] * (1 - w) + g[np.arange(n)[:, None], i0 + 1] * w
    offset = (roots - groots[owner])[:, None, :] * (1 - 0.75 * t[None, :, None] ** 0.8)
    stray = np.where(rng.random(n) < FLYAWAY, rng.uniform(3, 6, n), 1.0)[:, None, None]
    drift = (rng.normal(0, 0.0025, (n, 1, 3)) * stray + rng.normal(0, 0.0006, (n, k, 3))) * t[None, :, None] ** 1.5
    return path + offset + drift


def _deform_group():
    """Deform Curves on Surface, then blend each point from the root's full rotation (root) toward the root's
    translation only (tip), so long locks hang instead of swinging rigidly with a skin triangle."""
    ng = bpy.data.node_groups.get(DEFORM)
    if ng:
        return ng
    ng = bpy.data.node_groups.new(DEFORM, 'GeometryNodeTree')
    ng.interface.new_socket('Geometry', in_out='INPUT', socket_type='NodeSocketGeometry')
    ng.interface.new_socket('Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
    nd, ln = ng.nodes.new, ng.links.new
    gi, go = nd('NodeGroupInput'), nd('NodeGroupOutput')
    store = nd('GeometryNodeStoreNamedAttribute')
    store.data_type, store.domain = 'FLOAT_VECTOR', 'POINT'
    store.inputs['Name'].default_value = 'c3d_pre'
    ln(gi.outputs[0], store.inputs['Geometry'])
    ln(nd('GeometryNodeInputPosition').outputs[0], store.inputs['Value'])
    deform = nd('GeometryNodeDeformCurvesOnSurface')
    ln(store.outputs[0], deform.inputs[0])
    pre = nd('GeometryNodeInputNamedAttribute')
    pre.data_type = 'FLOAT_VECTOR'
    pre.inputs['Name'].default_value = 'c3d_pre'
    pos = nd('GeometryNodeInputPosition')
    first = nd('GeometryNodePointsOfCurve')
    ln(nd('GeometryNodeCurveOfPoint').outputs['Curve Index'], first.inputs['Curve Index'])

    def at_root(field):
        ev = nd('GeometryNodeFieldAtIndex')
        ev.data_type, ev.domain = 'FLOAT_VECTOR', 'POINT'
        ln(first.outputs['Point Index'], ev.inputs['Index'])
        ln(field, ev.inputs['Value'])
        return ev.outputs[0]

    def vmath(op, a, b):
        m = nd('ShaderNodeVectorMath')
        m.operation = op
        ln(a, m.inputs[0])
        ln(b, m.inputs[1 if op != 'SCALE' else 3])
        return m.outputs[0]

    delta = vmath('SUBTRACT', at_root(pos.outputs[0]), at_root(pre.outputs['Attribute']))
    hang = vmath('SUBTRACT', vmath('ADD', pre.outputs['Attribute'], delta), pos.outputs[0])
    ramp = nd('ShaderNodeMapRange')
    ramp.interpolation_type = 'SMOOTHSTEP'
    ramp.inputs['From Max'].default_value = HANG_FROM
    ramp.inputs['To Max'].default_value = HANG
    ln(nd('GeometryNodeSplineParameter').outputs['Factor'], ramp.inputs['Value'])
    setp = nd('GeometryNodeSetPosition')
    ln(deform.outputs[0], setp.inputs['Geometry'])
    ln(vmath('SCALE', hang, ramp.outputs['Result']), setp.inputs['Offset'])
    ln(setp.outputs[0], go.inputs[0])
    return ng


def _attr(data, name, kind, domain, values, field):
    a = data.attributes.get(name) or data.attributes.new(name, kind, domain)
    a.data.foreach_set(field, np.ascontiguousarray(values).ravel())


def make_curves(name, paths, uv, radius, resolution, surf):
    n, k = paths.shape[:2]
    hc = bpy.data.hair_curves.new(name)
    hc.add_curves([k] * n)
    hc.position_data.foreach_set('vector', paths.astype(np.float32).ravel())
    r0, r1 = radius
    _attr(hc, 'radius', 'FLOAT', 'POINT', np.tile(np.linspace(r0, r1, k), n).astype(np.float32), 'value')
    _attr(hc, 'surface_uv_coordinate', 'FLOAT2', 'CURVE', uv.astype(np.float32), 'vector')
    _attr(hc, 'resolution', 'INT', 'CURVE', np.full(n, resolution, np.int32), 'value')
    hc.surface, hc.surface_uv_map = surf.ob, UV
    ob = bpy.data.objects.new(name, hc)
    bu.collection('char3d').objects.link(ob)
    ob.parent = surf.ob
    ob.matrix_parent_inverse = surf.ob.matrix_world.inverted()
    ob.modifiers.new('deform_on_surface', 'NODES').node_group = _deform_group()
    return ob


def save_guides(name, guides, normals, widths, scale):
    """Guide set as an unlinked curves datablock (fake user) with root normal and lock width per curve."""
    m, k = guides.shape[:2]
    hc = bpy.data.hair_curves.new(name)
    hc.add_curves([k] * m)
    hc.position_data.foreach_set('vector', guides.astype(np.float32).ravel())
    _attr(hc, 'c3d_normal', 'FLOAT_VECTOR', 'CURVE', normals.astype(np.float32), 'vector')
    _attr(hc, 'c3d_width', 'FLOAT', 'CURVE', widths.astype(np.float32), 'value')
    hc['c3d_scale'] = float(scale)
    hc.use_fake_user = True
    return hc


def make_cards(name, guides, normals, widths):
    """Two crossed ribbons per lock along its guide, tapering to the tip; UV u across, v along."""
    m, k = guides.shape[:2]
    tan = np.gradient(guides, axis=1)
    tan /= np.maximum(np.linalg.norm(tan, axis=2, keepdims=True), 1e-9)
    side = np.cross(tan, normals[:, None, :])
    side /= np.maximum(np.linalg.norm(side, axis=2, keepdims=True), 1e-9)
    up = np.cross(side, tan)
    taper = (1 - 0.65 * np.linspace(0, 1, k))[None, :, None] * widths[:, None, None] / 2
    verts, faces, uvs = [], [], []
    for axis, scale in ((side, 1.0), (up, 0.45)):
        for c in range(m):
            base = len(verts)
            for i in range(k):
                verts += [guides[c, i] - axis[c, i] * taper[c, i] * scale, guides[c, i] + axis[c, i] * taper[c, i] * scale]
            for i in range(k - 1):
                a = base + 2 * i
                faces.append((a, a + 1, a + 3, a + 2))
                uvs += [(0, i / (k - 1)), (1, i / (k - 1)), (1, (i + 1) / (k - 1)), (0, (i + 1) / (k - 1))]
    ob = bu.mesh_object(name, verts, faces)
    ob.data.uv_layers.new(name='UVMap').data.foreach_set('uv', np.array(uvs, np.float32).ravel())
    ob.data.polygons.foreach_set('use_smooth', [True] * len(faces))
    return ob


def build(h, ctx, surf, frame, rng):
    """One spec hair item -> curves object (render 'curves') and its card twin; returns metrics."""
    kind = h['kind']
    if kind not in ZONES:
        raise ValueError(f'hair: kind {kind!r} not built yet (have {sorted(ZONES)})')
    e, s = frame
    d = (surf.centroid - e) / s
    mask = ZONES[kind](d, surf.normal, h.get('width_m', 0.14) / s)
    k = 10 if ctx.draft else 16
    n = h.get('strands', 0) if h.get('render', 'curves') == 'curves' else 0
    curves = n > 0
    n_cards = max(12, n // STRANDS_PER_CARD) if curves else SCALP_CARDS
    pool, pnorm, puv = surf.sample(mask, max(n, n_cards * 8), rng)
    seed = _seeds(pool, n_cards, rng)
    clear = CLEAR_SKIN.get(kind, 0.004)
    grown = (_comb(pool[seed], pool, frame, h, rng, k) if kind == 'scalp'
             else _grow(kind, pool[seed], pnorm[seed], frame, h, rng, k))
    guides = _wave(_relax(grown, surf, ctx.spec, clear, garment=kind != 'scalp'), s, rng)
    if kind == 'beard':
        guides = _volume(guides, frame, h, rng)
    owner = np.linalg.norm(pool[:, None] - pool[seed][None], axis=2).argmin(1)
    spread = np.array([np.sqrt(((pool[owner == c] - pool[seed[c]]) ** 2).sum(1).mean()) if (owner == c).any() else 0
                       for c in range(len(seed))])
    widths = np.clip(2.2 * spread, 0.006 * s, 0.03 * s)
    cards = make_cards(f'{h["id"]}.cards' if curves else h['id'], guides, pnorm[seed], widths)
    gset = save_guides(f'{h["id"]}.guides', guides, pnorm[seed], widths, s)
    out = {'cards': len(seed), 'card_tris': 2 * len(cards.data.polygons), 'zone_tris': int((mask & surf.visible).sum()),
           'guides': len(seed), 'strands': n}
    if curves:
        paths = _strands(guides, pool[seed], pool[:n], owner[:n], rng)
        paths[:, 1:] = surf.push_out(paths[:, 1:], clear * 0.5)
        ob = make_curves(h['id'], paths, puv[:n], RADIUS.get(kind, RADIUS['beard']), 2 if ctx.draft else 4, surf)
        cards.hide_render = True
        ctx.add_part(h['id'], ob.name, NAME, h['material'], None)
        ctx.parts[h['id']].update(surface=surf.ob.name, cards=cards.name)
        out.update(strands=n, points=int(n * k))
    ctx.add_part(cards.name, cards.name, NAME, h['material'], h['attach'])
    ctx.parts[cards.name]['guides'] = gset.name
    return out


def _garment_bvh(ctx):
    """World BVH of every garment mesh as evaluated now, the hat excluded (hair lies over the robe, under the hat)."""
    dg = bpy.context.evaluated_depsgraph_get()
    verts, polys = [], []
    for pid, part in ctx.parts.items():
        ob = bpy.data.objects.get(part['object'])
        if part['stage'] != 'garments' or pid.startswith('hat') or not ob or ob.type != 'MESH':
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        m = np.array(ob.matrix_world)
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get('co', co)
        base = len(verts)
        verts += (co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3]).tolist()
        polys += [tuple(base + i for i in p.vertices) for p in me.polygons]
        ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys) if polys else None


def _outside(pts, bvh, axis):
    """Move each point with cloth outside it (a horizontal ray away from the body axis hits a garment) just past
    the outermost hit; returns the moved count."""
    moved = 0
    for i, p in enumerate(pts):
        d = np.array([p[0] - axis[0], p[1] - axis[1], 0.0])
        d /= max(np.linalg.norm(d), 1e-9)
        o, last = p, None
        for _ in range(8):
            hit = bvh.ray_cast(o, d, DRAPE_REACH)[0]
            if hit is None:
                break
            last = np.array(hit)
            o = last + d * 1e-4
        if last is not None:
            pts[i] = last + d * DRAPE_CLEAR
            moved += 1
    return moved


def _settle(paths, bvh, axis, iters=3):
    """Drape paths over the cloth: each point's push-out also leans the points above it (fading over DRAPE_RAMP of
    arc), so a lock rises smoothly over a collar instead of stepping; segment lengths restored from the root."""
    seg = np.linalg.norm(np.diff(paths, axis=1), axis=2)
    arc = np.concatenate([np.zeros((len(paths), 1)), np.cumsum(seg, axis=1)], axis=1)
    fade = np.clip(1 - (arc[:, None, :] - arc[:, :, None]) / DRAPE_RAMP, 0, 1) * (arc[:, None, :] >= arc[:, :, None])
    moved = 0
    for _ in range(iters):
        flat = paths.reshape(-1, 3).copy()
        moved = max(moved, _outside(flat, bvh, axis))
        push = np.linalg.norm(flat.reshape(paths.shape) - paths, axis=2)
        lean = (fade * push[:, None, :]).max(2)
        out = paths.copy()
        out[..., 2] = 0
        out[..., :2] -= axis[:2]
        out /= np.maximum(np.linalg.norm(out, axis=2, keepdims=True), 1e-9)
        lean[:, 0] = 0
        paths = paths + out * lean[..., None]
        paths[:, 1:-1] = 0.5 * paths[:, 1:-1] + 0.25 * (paths[:, :-2] + paths[:, 2:])
        for i in range(1, paths.shape[1]):
            d = paths[:, i] - paths[:, i - 1]
            paths[:, i] = paths[:, i - 1] + d * (seg[:, i - 1] / np.maximum(np.linalg.norm(d, axis=1), 1e-9))[:, None]
    flat = paths[:, 1:].reshape(-1, 3)
    _outside(flat, bvh, axis)
    paths[:, 1:] = flat.reshape(len(paths), -1, 3)
    return paths, moved


def _curve_points(hc):
    pos = np.empty(len(hc.points) * 3, np.float32)
    hc.position_data.foreach_get('vector', pos)
    return pos.reshape(len(hc.curves), -1, 3).astype(float)


def drape(ctx):
    """Run once garments exist: every hair guide set and strand groom settles outside the cloth, so the beard falls
    over the robe front and the back hair over the collar; returns moved and still-covered point counts."""
    bvh = _garment_bvh(ctx)
    out = {'moved': {}, 'covered': 0}
    if bvh is None:
        return out
    axis = np.array(ctx.landmarks['chest'])
    for h in ctx.spec['hair']:
        part = ctx.parts.get(h['id'], {})
        targets = [bpy.data.hair_curves[ctx.parts[part.get('cards', h['id'])]['guides']]]
        ob = bpy.data.objects.get(part.get('object', ''))
        if ob is not None and ob.type == 'CURVES':
            targets.append(ob.data)
        out['moved'][h['id']] = 0
        for hc in targets:
            paths, moved = _settle(_curve_points(hc), bvh, axis)
            hc.position_data.foreach_set('vector', paths.astype(np.float32).ravel())
            hc.update_tag()
            out['moved'][h['id']] += moved
            out['covered'] += _outside(paths[:, 1:].reshape(-1, 3).copy(), bvh, axis)
    return out


def run(ctx):
    surf_name = ctx.face.get('shape_key_object') or ctx.parts['body']['object']
    surf = Surface(bpy.data.objects[surf_name])
    el, er = np.array(ctx.landmarks['eye.L']), np.array(ctx.landmarks['eye.R'])
    frame = ((el + er) / 2, np.linalg.norm(el - er) / REF_IOD)
    rng = np.random.default_rng(ctx.spec.get('seed', 1032))
    metrics = {'stub': False, 'surface': surf_name}
    for h in ctx.spec['hair']:
        for key, val in build(h, ctx, surf, frame, rng).items():
            metrics[f'{h["id"]}_{key}'] = val
    return metrics
