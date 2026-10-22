"""Stage face: layered eyes, lid shells, brows, lashes, teeth, tongue, ARKit-52 shape keys, presets, gaze/blink timing."""
import importlib
import math
import random

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

from .. import bpyutil as bu

NAME = 'face'
ARKIT = [f'{p}{s}' for p in ('eyeBlink', 'eyeLookDown', 'eyeLookIn', 'eyeLookOut', 'eyeLookUp', 'eyeSquint', 'eyeWide')
         for s in ('Left', 'Right')] + [
    'jawForward', 'jawLeft', 'jawRight', 'jawOpen', 'mouthClose', 'mouthFunnel', 'mouthPucker', 'mouthLeft',
    'mouthRight', 'mouthRollLower', 'mouthRollUpper', 'mouthShrugLower', 'mouthShrugUpper', 'browInnerUp', 'cheekPuff',
    'tongueOut'] + [f'{p}{s}' for p in ('mouthSmile', 'mouthFrown', 'mouthDimple', 'mouthStretch', 'mouthPress',
                                         'mouthLowerDown', 'mouthUpperUp', 'browDown', 'browOuterUp', 'cheekSquint',
                                         'noseSneer') for s in ('Left', 'Right')]
EYE_R = 0.0122                        # eyeball radius at 1.78 m
LIMBUS_DEG, CORNEA_APEX, OCC_R = 29.0, 1.06, 1.09
LID_IN, LID_OUT = 1.14, 1.24
OPEN_DEPTH, LID_TUCK_DEG = 0.78, 5.0
LIDS = {'upper': {'open': 24.0, 'closed': -13.0, 'far': 105.0}, 'lower': {'open': -30.0, 'closed': -5.0, 'far': -105.0}}
JAW_OPEN_DEG = 22.0
BROW_KEYS = ('browDown', 'browInnerUp', 'browOuterUp', 'eyeWide', 'eyeSquint', 'noseSneer', 'cheekSquint')
LID_KEYS = ('eyeBlink', 'eyeLook', 'eyeSquint', 'eyeWide', 'cheekSquint', 'browDown', 'browInnerUp', 'browOuterUp')
SACCADE_DIRS = ((0, .1554), (45, .0646), (90, .1769), (135, .0744), (180, .1680), (225, .0789), (270, .2038), (315, .0779))


def hinge(r, theta, phi):
    """Eye-local point on a sphere hinged about X: theta = pitch (lid travel), phi = across the eye; forward is -Y."""
    t, p = math.radians(theta), math.radians(phi)
    return (r * math.sin(p), -r * math.cos(p) * math.cos(t), r * math.cos(p) * math.sin(t))


def polar(r, alpha, beta):
    """Eye-local point with the pole forward: alpha from the gaze axis, beta around it."""
    a, b = math.radians(alpha), math.radians(beta)
    return (r * math.sin(a) * math.cos(b), -r * math.cos(a), r * math.sin(a) * math.sin(b))


def grid_faces(rows, cols, wrap=False):
    n = cols if wrap else cols - 1
    return [(i * cols + j, i * cols + (j + 1) % cols, (i + 1) * cols + (j + 1) % cols, (i + 1) * cols + j)
            for i in range(rows - 1) for j in range(n)]


def build(name, verts, faces, loc, flip_ref=None):
    """Mesh object at loc; faces flipped so the first face's normal agrees with flip_ref (eye-local)."""
    verts = np.asarray(verts, float)
    if flip_ref is not None:
        f = faces[0]
        n = np.cross(verts[f[1]] - verts[f[0]], verts[f[2]] - verts[f[0]])
        if np.dot(n, flip_ref) < 0:
            faces = [tuple(reversed(f)) for f in faces]
    ob = bu.mesh_object(name, verts, faces)
    ob.location = loc
    ob.data.polygons.foreach_set('use_smooth', [True] * len(ob.data.polygons))
    return ob


def srgb(hexcol, k=1.0):
    c = [int(hexcol[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return [min(1.0, k * (x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4)) for x in c] + [1.0]


def material(name, color, rough=0.5, alpha=None, blended=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes['Principled BSDF']
    p.inputs['Base Color'].default_value = color
    p.inputs['Roughness'].default_value = rough
    if alpha is not None:
        p.inputs['Alpha'].default_value = alpha
    if blended or alpha is not None:
        m.surface_render_method = 'BLENDED'
    return m, p


def iris_material(eyes, r_rim):
    m, p = material('c3d_iris', srgb(eyes['iris']), 0.6)
    p.inputs['Specular IOR Level'].default_value = 0.0
    nt, n = m.node_tree, m.node_tree.nodes
    tc, sep = n.new('ShaderNodeTexCoord'), n.new('ShaderNodeSeparateXYZ')
    nt.links.new(tc.outputs['Object'], sep.inputs[0])
    rad = n.new('ShaderNodeVectorMath')
    rad.operation = 'LENGTH'
    comb = n.new('ShaderNodeCombineXYZ')
    nt.links.new(sep.outputs['X'], comb.inputs['X'])
    nt.links.new(sep.outputs['Z'], comb.inputs['Y'])
    nt.links.new(comb.outputs[0], rad.inputs[0])
    div = n.new('ShaderNodeMath')
    div.operation, div.inputs[1].default_value = 'DIVIDE', r_rim
    nt.links.new(rad.outputs['Value'], div.inputs[0])
    rn = n.new('ShaderNodeValToRGB')
    ramp = rn.color_ramp
    pupil, iris, outer = eyes.get('pupil', 0.35), eyes['iris'], eyes.get('iris_outer', eyes['iris'])
    collar = [0.6 * a + 0.4 * b for a, b in zip(srgb(iris, 0.5), (0.12, 0.08, 0.04, 1))]
    stops = [(0.0, [0.004, 0.004, 0.006, 1]), (pupil - 0.01, [0.004, 0.004, 0.006, 1]), (pupil + 0.02, collar),
             (pupil + 0.14, srgb(iris, 0.5)), (0.8, srgb(iris, 0.4)), (0.9, srgb(outer, 0.3)),
             (1.0, srgb(outer, 0.1))]
    ramp.elements[0].position, ramp.elements[0].color = stops[0]
    ramp.elements[1].position, ramp.elements[1].color = stops[-1]
    for pos, col in stops[1:-1]:
        ramp.elements.new(pos).color = col
    nt.links.new(div.outputs[0], rn.inputs[0])
    ang = n.new('ShaderNodeMath')
    ang.operation = 'ARCTAN2'
    nt.links.new(sep.outputs['Z'], ang.inputs[0])
    nt.links.new(sep.outputs['X'], ang.inputs[1])
    fib = n.new('ShaderNodeCombineXYZ')
    nt.links.new(ang.outputs[0], fib.inputs['X'])
    nt.links.new(div.outputs[0], fib.inputs['Y'])
    stretch = n.new('ShaderNodeVectorMath')
    stretch.operation, stretch.inputs[1].default_value = 'MULTIPLY', (9.0, 0.8, 1.0)
    nt.links.new(fib.outputs[0], stretch.inputs[0])
    noise = n.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value, noise.inputs['Detail'].default_value = 5.0, 8.0
    nt.links.new(stretch.outputs[0], noise.inputs['Vector'])
    mul = n.new('ShaderNodeMix')
    mul.data_type, mul.blend_type = 'RGBA', 'MULTIPLY'
    mul.inputs['Factor'].default_value = 0.8
    nt.links.new(rn.outputs['Color'], mul.inputs['A'])
    nt.links.new(noise.outputs['Color'], mul.inputs['B'])
    hsv = n.new('ShaderNodeHueSaturation')
    hsv.inputs['Saturation'].default_value = 0.7
    nt.links.new(mul.outputs['Result'], hsv.inputs['Color'])
    nt.links.new(hsv.outputs['Color'], p.inputs['Base Color'])
    return m


def sclera_material(hexcol, r):
    """Wet elder sclera: off-white at the limbus, warmer and darker toward the canthi, fine red veins at the edges."""
    m, p = material('c3d_sclera', srgb(hexcol), 0.12)
    nt, n = m.node_tree, m.node_tree.nodes
    tc, sep, edge = n.new('ShaderNodeTexCoord'), n.new('ShaderNodeSeparateXYZ'), n.new('ShaderNodeMapRange')
    nt.links.new(tc.outputs['Object'], sep.inputs[0])
    edge.inputs['From Min'].default_value, edge.inputs['From Max'].default_value = -0.85 * r, -0.25 * r
    nt.links.new(sep.outputs['Y'], edge.inputs['Value'])
    warm = n.new('ShaderNodeMix')
    warm.data_type = 'RGBA'
    warm.inputs['A'].default_value, warm.inputs['B'].default_value = srgb(hexcol, 0.92), (0.55, 0.42, 0.33, 1)
    fac = n.new('ShaderNodeMath')
    fac.operation, fac.inputs[1].default_value = 'MULTIPLY', 0.6
    nt.links.new(edge.outputs['Result'], fac.inputs[0])
    nt.links.new(fac.outputs[0], warm.inputs['Factor'])
    vn = n.new('ShaderNodeTexNoise')
    vn.inputs['Scale'].default_value, vn.inputs['Detail'].default_value = 0.25 / r, 6.0
    nt.links.new(tc.outputs['Object'], vn.inputs['Vector'])
    ridge = n.new('ShaderNodeValToRGB')
    el = ridge.color_ramp.elements
    el[0].position, el[0].color, el[1].position, el[1].color = 0.47, (0, 0, 0, 1), 0.53, (0, 0, 0, 1)
    el.new(0.5).color = (0.55, 0.55, 0.55, 1)
    nt.links.new(vn.outputs['Fac'], ridge.inputs[0])
    vf = n.new('ShaderNodeMath')
    vf.operation = 'MULTIPLY'
    nt.links.new(ridge.outputs['Color'], vf.inputs[0])
    nt.links.new(edge.outputs['Result'], vf.inputs[1])
    vein = n.new('ShaderNodeMix')
    vein.data_type = 'RGBA'
    vein.inputs['B'].default_value = (0.5, 0.07, 0.05, 1)
    nt.links.new(vf.outputs[0], vein.inputs['Factor'])
    nt.links.new(warm.outputs['Result'], vein.inputs['A'])
    nt.links.new(vein.outputs['Result'], p.inputs['Base Color'])
    return m


def cornea_material(kind):
    if kind == 'refract':
        m, p = material('c3d_cornea', [1, 1, 1, 1], 0.0)
        p.inputs['Transmission Weight'].default_value, p.inputs['IOR'].default_value = 1.0, 1.376
        m.surface_render_method, m.use_raytrace_refraction = 'DITHERED', True
        return m
    m = bpy.data.materials.new('c3d_cornea')
    m.use_nodes = True
    nt, n = m.node_tree, m.node_tree.nodes
    n.remove(n['Principled BSDF'])
    tr, gl, fr, mx = (n.new(t) for t in ('ShaderNodeBsdfTransparent', 'ShaderNodeBsdfGlossy', 'ShaderNodeFresnel',
                                          'ShaderNodeMixShader'))
    gl.inputs['Roughness'].default_value = 0.0 if kind == 'fresnel_gloss' else 0.06
    fr.inputs['IOR'].default_value = 1.376
    nt.links.new(fr.outputs[0], mx.inputs[0])
    nt.links.new(tr.outputs[0], mx.inputs[1])
    nt.links.new(gl.outputs[0], mx.inputs[2])
    nt.links.new(mx.outputs[0], n['Material Output'].inputs['Surface'])
    m.surface_render_method = 'BLENDED'
    return m


def occlusion_material(r):
    m, p = material('c3d_eye_occlusion', [0.02, 0.012, 0.012, 1], 0.9, alpha=0.0)
    nt, n = m.node_tree, m.node_tree.nodes
    tc, sep, rng = n.new('ShaderNodeTexCoord'), n.new('ShaderNodeSeparateXYZ'), n.new('ShaderNodeMapRange')
    nt.links.new(tc.outputs['Object'], sep.inputs[0])
    rng.inputs['From Min'].default_value, rng.inputs['From Max'].default_value = 0.1 * r, 0.75 * r
    rng.inputs['To Min'].default_value, rng.inputs['To Max'].default_value = 0.1, 0.85
    nt.links.new(sep.outputs['Z'], rng.inputs['Value'])
    nt.links.new(rng.outputs['Result'], p.inputs['Alpha'])
    return m


def eye_parts(side, center, r, mats):
    """Sclera (pole forward, open at the limbus), concave iris, bulged cornea, occlusion shell."""
    seg, rings = 32, 14
    alphas = [LIMBUS_DEG + (180 - LIMBUS_DEG) * i / rings for i in range(rings)]
    verts = [polar(r, a, 360 * j / seg) for a in alphas for j in range(seg)] + [(0, r, 0)]
    faces = grid_faces(rings, seg, wrap=True) + [((rings - 1) * seg + j, (rings - 1) * seg + (j + 1) % seg, rings * seg)
                                                 for j in range(seg)]
    eye = build(f'eye.{side}', verts, faces, center, flip_ref=polar(1, alphas[0], 0))
    rim, depth = r * math.sin(math.radians(LIMBUS_DEG)), r * math.cos(math.radians(LIMBUS_DEG))
    n_ir = 8
    iverts = [(rim * (1 - k / n_ir) * math.cos(2 * math.pi * j / seg), -depth + 0.08 * r * (1 - (1 - k / n_ir) ** 2),
               rim * (1 - k / n_ir) * math.sin(2 * math.pi * j / seg)) for k in range(n_ir) for j in range(seg)]
    iverts.append((0, -depth + 0.08 * r, 0))
    ifaces = grid_faces(n_ir, seg, wrap=True) + [((n_ir - 1) * seg + j, (n_ir - 1) * seg + (j + 1) % seg, n_ir * seg)
                                                 for j in range(seg)]
    iris = build(f'iris.{side}', iverts, ifaces, center, flip_ref=(0, -1, 0))
    edge, n_c = LIMBUS_DEG + 6, 10
    cverts = [polar(r * (1.003 + (CORNEA_APEX - 1.003) * (1 - (a / edge) ** 2)), a, 360 * j / seg)
              for a in [edge * (1 - k / n_c) for k in range(n_c)] for j in range(seg)] + [(0, -r * CORNEA_APEX, 0)]
    cfaces = grid_faces(n_c, seg, wrap=True) + [((n_c - 1) * seg + j, (n_c - 1) * seg + (j + 1) % seg, n_c * seg)
                                                for j in range(seg)]
    cornea = build(f'cornea.{side}', cverts, cfaces, center, flip_ref=(0, -1, 0))
    overts = [polar(OCC_R * r, a, 360 * j / seg) for a in np.linspace(0, 75, 9)[1:] for j in range(seg)]
    occ = build(f'eye_occlusion.{side}', [(0, -OCC_R * r, 0)] + overts,
                [(0, 1 + j, 1 + (j + 1) % seg) for j in range(seg)] + [tuple(1 + i for i in f) for f in
                                                                       grid_faces(8, seg, wrap=True)],
                center, flip_ref=(0, -1, 0))
    for ob, m in ((eye, mats['sclera']), (iris, mats['iris']), (cornea, mats['cornea']), (occ, mats['occlusion'])):
        ob.data.materials.append(m)
    for ob in (cornea, occ):
        ob.visible_shadow = False
    return {'eye': eye, 'iris': iris, 'cornea': cornea, 'occlusion': occ}


def lid_parts(side, which, center, r, open_deg):
    """Lid shell hinged about the eye centre (inner radius > cornea apex), its edge tucked just behind the skin margin."""
    cfg = LIDS[which]
    sign = 1 if cfg['far'] > cfg['open'] else -1
    t0, t1, m, phis = open_deg, cfg['far'], 10, np.linspace(-89, 89, 29)
    loop = [(t0 + (t1 - t0) * k / m, LID_IN) for k in range(m + 1)] + [(t1 - (t1 - t0) * k / m, LID_OUT) for k in
                                                                       range(m + 1)] + [(t0 - 4 * sign, 0.5 * (LID_IN + LID_OUT))]
    verts = [hinge(rr * r, th, ph) for ph in phis for th, rr in loop]
    lid = build(f'lid.{which}.{side}', verts, grid_faces(len(phis), len(loop), wrap=True), center, flip_ref=None)
    _orient_lid(lid, len(loop))
    return lid


def skin_hit(body, origin, direction, dg):
    """World (location, normal) of the first hit on the evaluated (masked) skin, or None."""
    ev = body.evaluated_get(dg)
    mi = body.matrix_world.inverted()
    hit, loc, nrm, _ = ev.ray_cast(mi @ Vector(origin), (mi.to_3x3() @ Vector(direction)).normalized())
    if not hit:
        return None
    return np.array(body.matrix_world @ loc), np.array((mi.to_3x3().transposed() @ nrm).normalized())


def lid_margins(body, c, r, dg, step=0.00025):
    """Skin lid margins seen from the front: {'upper'|'lower': [(point, normal)] by x}; open = ray passes deep."""
    def probe(x, z):
        h = skin_hit(body, (x, c[1] - 0.3, z), (0, 1, 0), dg)
        return h, h is None or c[1] - h[0][1] < OPEN_DEPTH * r
    out = {'upper': [], 'lower': []}
    zs = np.arange(c[2] + 0.7 * r, c[2] - 0.9 * r, -step)
    for x in np.linspace(c[0] - 1.45 * r, c[0] + 1.45 * r, 41):
        col = [probe(x, z) for z in zs]
        rows = [i for i, (_, op) in enumerate(col) if op]
        if not rows or rows[0] == 0 or rows[-1] == len(zs) - 1:
            continue
        out['upper'].append(col[rows[0] - 1][0])
        out['lower'].append(col[rows[-1] + 1][0])
    return out


def margin_angles(c, r, margins):
    """Pitch (deg) of each margin at the column nearest the eye centre."""
    res = {}
    for which, pts in margins.items():
        p = min(pts, key=lambda h: abs(h[0][0] - c[0]))[0]
        res[which] = math.degrees(math.asin(max(-1.0, min(1.0, (p[2] - c[2]) / (LID_IN * r)))))
    return res


def lash_cards(side, which, c, r, pts, n):
    """Lashes rooted on the skin margin: upper long and curled up, lower short and sparse, corners shorter."""
    up = 1.0 if which == 'upper' else -1.0
    s = 1 if side == 'L' else -1
    rng = random.Random(f'lash{side}{which}')
    roots = np.array([p for p, _ in pts])
    seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(roots, axis=0), axis=1))]
    length, half_w = (0.6 * r, 0.007 * r) if which == 'upper' else (0.28 * r, 0.005 * r)
    verts, faces = [], []
    for i in range(n):
        u = (i + rng.uniform(0.1, 0.9)) / n
        root = np.array([np.interp(u * seg[-1], seg, roots[:, k]) for k in range(3)])
        root = root + (c - root) / np.linalg.norm(c - root) * 0.0003
        mid = 1 - abs(2 * u - 1)
        L = length * (0.45 + 0.55 * mid ** 0.6) * rng.uniform(0.8, 1.15)
        outer = s * np.sign(root[0] - c[0]) * abs(root[0] - c[0]) / r
        d0 = np.array([0.25 * s * outer, -1.0, 0.15 * up])
        curl = np.array([0.0, 0.3, 0.6 * up])
        side_v = np.cross(d0, [0, 0, 1.0])
        side_v = side_v / np.linalg.norm(side_v) * half_w
        base = len(verts)
        for k, t in enumerate((0.0, 0.35, 0.7, 1.0)):
            pnt = root + L * (t * d0 / np.linalg.norm(d0) + 0.55 * t * t * curl)
            w = 1.0 - 0.8 * k / 3
            verts += [tuple(pnt - w * side_v - c), tuple(pnt + w * side_v - c)]
        faces += [(base + 2 * k, base + 2 * k + 1, base + 2 * k + 3, base + 2 * k + 2) for k in range(3)]
    return build(f'lashes.{which}.{side}', verts, faces, tuple(c))


def tear_strip(side, which, c, r, pts):
    """Wet meniscus strip from the skin margin down onto the eyeball."""
    verts = []
    for p, _ in pts:
        q = c + (p - c) / np.linalg.norm(p - c) * r * 1.004
        verts += [tuple(p + (c - p) * 0.02 - c), tuple(q - c)]
    ob = build(f'tearline.{which}.{side}', verts, grid_faces(len(pts), 2), tuple(c))
    ob.visible_shadow = False
    return ob


def _orient_lid(ob, loop_n):
    """Inner shell normals face the eye; the loop sweep keeps the rest consistent."""
    me = ob.data
    p = me.polygons[0]
    if Vector(p.normal).dot(Vector(p.center)) > 0:
        me.flip_normals()


def surface_hit(body, x, z):
    """World (location, normal) of the first skin hit of a ray cast from the front along +Y, or None."""
    return skin_hit(body, (x, -3.0, z), (0, 1, 0), bpy.context.evaluated_depsgraph_get())


def brow_cards(side, center, r, style, body):
    """Bushy elder brow: thin tapered strands rooted on the brow-ridge skin, combed outward, outer third drooping."""
    s = 1 if side == 'L' else -1
    n, lmin, lmax = (320, 0.55, 1.5) if style == 'bushy' else (160, 0.35, 0.8)
    rng = random.Random(f'brow{side}')
    c = np.array(center)
    verts, faces = [], []
    for i in range(n):
        u = rng.random() ** 0.85
        x = c[0] + s * (-1.75 + 4.0 * u) * r
        z = c[2] + (1.55 + 0.55 * math.sin(math.pi * min(1.0, 0.25 + u)) - 0.35 * u * u + rng.gauss(0, 0.16)) * r
        hit = surface_hit(body, x, z)
        if hit is None:
            continue
        root, nrm = hit
        comb = np.array([s * (0.35 + 0.65 * u), 0.0, 0.7 - 1.1 * u])
        comb = comb - nrm * (comb @ nrm)
        comb /= np.linalg.norm(comb)
        lift = 0.25 + 0.35 * rng.random()
        L = r * rng.uniform(lmin, lmax) * (1.0 + 0.6 * u) * (1.8 if rng.random() < 0.06 else 1.0)
        twist = rng.gauss(0, 0.25)
        side_t = np.cross(nrm, comb)
        comb = comb + twist * side_t
        comb /= np.linalg.norm(comb)
        root = root - 0.4e-3 * nrm
        droop = np.array([0, 0, -1.0]) * (0.1 + 0.6 * u * u)
        w = 0.016 * r
        wv = np.cross(comb, nrm)
        wv /= np.linalg.norm(wv)
        base = len(verts)
        for t in (0.0, 0.3, 0.65, 1.0):
            p = root + L * (t * comb + lift * t * (1 - 0.6 * t) * nrm + t * t * droop)
            verts += [tuple(p - wv * w * (1 - 0.8 * t) - c), tuple(p + wv * w * (1 - 0.8 * t) - c)]
        faces += [(base + 2 * k, base + 2 * k + 1, base + 2 * k + 3, base + 2 * k + 2) for k in range(3)]
    return build(f'brow.{side}', verts, faces, center)


def surface_y(body, x, z, fallback):
    """Front skin depth at (x, z): first hit of a ray cast from the front along +Y."""
    mi = body.matrix_world.inverted()
    o, d = mi @ Vector((x, -3.0, z)), (mi.to_3x3() @ Vector((0, 1, 0))).normalized()
    hit, loc, _, _ = body.ray_cast(o, d)
    return (body.matrix_world @ loc).y if hit else fallback


# Per side, front to back (mm at s = 1): width, crown height, labio-lingual depth; arch half-width/depth (m), lingual shift.
TEETH = {'upper': {'w': (8.5, 6.6, 7.6, 7.0), 'h': (10.0, 8.6, 9.6, 8.0), 'd': (6.8, 6.0, 7.8, 8.6),
                   'arch': (0.022, 0.018), 'back': 0.0},
         'lower': {'w': (5.2, 5.8, 6.8, 7.0), 'h': (8.6, 9.0, 10.4, 7.6), 'd': (5.8, 6.2, 7.4, 7.6),
                   'arch': (0.0195, 0.016), 'back': 0.0022}}
TOOTH_KINDS = ('incisor', 'incisor', 'canine', 'premolar')
ARCH_BACK = 0.0105                    # arch centre line behind the lip front at the seam (m at s = 1)


def loft(rings, cap=True):
    """Quad tube through rings of equal size (first ring open, last ring capped by a centre fan)."""
    n, seg = len(rings), len(rings[0])
    verts = [tuple(p) for ring in rings for p in ring]
    faces = grid_faces(n, seg, wrap=True)
    if cap:
        verts.append(tuple(np.mean(rings[-1], axis=0)))
        faces += [((n - 1) * seg + j, (n - 1) * seg + (j + 1) % seg, n * seg) for j in range(seg)]
    return verts, faces


def section(a, b, seg=12, p=2.8):
    """Superellipse cross-section (half-axes a along the arch, b labio-lingual)."""
    ph = np.linspace(0, 2 * math.pi, seg, endpoint=False)
    c, sn = np.cos(ph), np.sin(ph)
    return np.stack([a * np.sign(c) * np.abs(c) ** (2 / p), b * np.sign(sn) * np.abs(sn) ** (2 / p)], 1)


def crown(kind, w, h, d, t):
    """Half-axes (a, b) and incisal lift of a crown section at t (0 gum line .. 1 incisal edge)."""
    if kind == 'incisor':
        return 0.5 * w * (0.78 + 0.22 * t), 0.5 * d * (1 - 0.72 * t)
    if kind == 'canine':
        return 0.5 * w * (0.95 - 0.6 * max(0.0, (t - 0.55) / 0.45)), 0.5 * d * (1 - 0.45 * t)
    return 0.5 * w * (0.92 + 0.08 * t), 0.5 * d * (0.95 - 0.12 * t)


def arch_curve(W, D, y0, z, tmax=1.55, n=600):
    """Dental arch x = W sin t, y = y0 + D (1 - cos t): points, unit tangents, labial normals, arc length (t >= 0)."""
    t = np.linspace(0, tmax, n)
    pts = np.stack([W * np.sin(t), y0 + D * (1 - np.cos(t)), np.full(n, z)], 1)
    tan = np.stack([W * np.cos(t), D * np.sin(t), np.zeros(n)], 1)
    tan /= np.linalg.norm(tan, axis=1, keepdims=True)
    lab = np.stack([tan[:, 1], -tan[:, 0], np.zeros(n)], 1)
    arc = np.r_[0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
    return pts, tan, lab, arc


def dentition(which, yf, zm, s):
    """Teeth (lofted incisors, canines, premolars, both sides) and the gum ridge of one jaw as (verts, faces) pairs."""
    cfg, up = TEETH[which], 1.0 if which == 'upper' else -1.0
    W, D = (v * s for v in cfg['arch'])
    edge_z = zm - 0.0008 * s if up > 0 else zm + 0.0004 * s
    pts, tan, lab, arc = arch_curve(W, D, yf + (ARCH_BACK + cfg['back']) * s, edge_z)
    ws = np.array(cfg['w']) * 1e-3 * s
    k = min(1.0, arc[-1] / ws.sum())
    crowns, cum = [], 0.0
    for kind, w, h, d in zip(TOOTH_KINDS, ws * k, np.array(cfg['h']) * 1e-3 * s, np.array(cfg['d']) * 1e-3 * s):
        i = int(np.searchsorted(arc, cum + w / 2))
        cum += w
        for sx in (1, -1):
            c, T, V = pts[i] * [sx, 1, 1], tan[i] * [sx, 1, 1], lab[i] * [sx, 1, 1]
            rings = []
            for t in np.linspace(-0.15, 1.0, 7):
                a, b = crown(kind, w * 0.96, h, d, max(0.0, t))
                z = edge_z + up * h * (1 - t) - (0.0006 * s * up if kind == 'canine' and t >= 1 else 0.0)
                rings.append([c + x * T + y * V + (0, 0, z - c[2]) for x, y in section(a, b)])
            crowns.append(loft(rings))
    gum_h = up * np.mean(cfg['h']) * 1e-3 * s * 0.95
    rv, rz = 0.5 * np.mean(cfg['d']) * 1e-3 * s + 0.0005 * s, 0.0024 * s
    j_end = int(np.searchsorted(arc, cum)) - 1
    ph = np.linspace(0, 2 * math.pi, 10, endpoint=False)
    gum = []
    for i, sx in [(i, -1) for i in range(j_end, 0, -8)] + [(i, 1) for i in range(0, j_end + 1, 8)]:
        c, V = pts[i] * [sx, 1, 1], lab[i] * [sx, 1, 1]
        gum.append([c + (rv * math.cos(a) - 0.0005 * s) * V + (0, 0, gum_h + up * 0.0012 * s + rz * math.sin(a)) for a in ph])
    return crowns, [loft(gum, cap=False)]


def merged(name, parts):
    """One mesh object from (verts, faces) pairs, normals recalculated outward."""
    import bmesh
    verts, faces = [], []
    for v, f in parts:
        faces += [tuple(i + len(verts) for i in face) for face in f]
        verts += v
    ob = bu.mesh_object(name, verts, faces)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.polygons.foreach_set('use_smooth', [True] * len(ob.data.polygons))
    return ob


def tongue_mesh(yf, zm, s):
    """Tapered tongue with a median groove, local origin mid-tongue; tongueOut slides the front half forward."""
    rings = []
    for u in np.linspace(1.0, 0.0, 9):
        a, b = 0.0145 * s * min(1.0, 0.4 + 0.9 * u ** 0.5), 0.0045 * s * (0.55 + 0.45 * u)
        sec = section(a, b, 16, 2.4)
        groove = -0.0009 * s * np.exp(-(sec[:, 0] / (0.3 * a)) ** 2) * (sec[:, 1] > 0)
        y = -0.018 * s + 0.044 * s * u
        rings.append([(x, y, z + g) for (x, z), g in zip(sec, groove)])
    ob = merged('tongue', [loft(rings)])
    ob.location = (0, yf + 0.03 * s, zm - 0.009 * s)
    ob.shape_key_add(name='Basis')
    k = ob.shape_key_add(name='tongueOut')
    for v, kv in zip(ob.data.vertices, k.data):
        kv.co = v.co + Vector((0, -0.032 * s * max(0.0, -v.co.y / (0.026 * s) + 0.6), 0))
    return ob


def lip_seam(body, e0, s):
    """Midline lip seam z from the jawOpen key: between the lowest still vert and the highest moving vert, or None."""
    kb = body.data.shape_keys.key_blocks if body.data.shape_keys else {}
    if 'jawOpen' not in kb:
        return None
    n, mw = len(body.data.vertices), np.array(body.matrix_world)
    a, b = np.empty(n * 3), np.empty(n * 3)
    kb[0].data.foreach_get('co', a)
    kb['jawOpen'].data.foreach_get('co', b)
    a, b = (x.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3] for x in (a, b))
    vg = body.vertex_groups.get('body')
    skin = np.ones(n, bool)
    if vg:
        skin[:] = False
        skin[[v.index for v in body.data.vertices if any(g.group == vg.index for g in v.groups)]] = True
    sel = skin & (np.abs(a[:, 0]) < 0.004 * s) & (a[:, 2] < e0[2] - 0.035 * s) & (a[:, 2] > e0[2] - 0.11 * s) \
        & (a[:, 1] < e0[1])
    if sel.sum() < 4:
        return None
    d = np.linalg.norm(b - a, axis=1)[sel]
    z = a[sel, 2]
    still, moving = z[d < 0.25 * d.max()], z[d > 0.5 * d.max()]
    if not len(still) or not len(moving):
        return None
    top, bottom = still.min(), moving.max()
    return float(0.5 * (top + bottom)) if top >= bottom - 0.004 * s else None


def mouth_parts(body, e0, s, y_fb):
    """Upper/lower dentition (crowns + gum ridge) and a tongue behind the lips, seated on the measured lip seam."""
    seam = lip_seam(body, e0, s)
    zm = seam if seam is not None else e0[2] - 0.068 * s
    yf = min(surface_y(body, 0.0, zm + dz * s, y_fb) for dz in (-0.003, 0.003))
    out = {}
    for which in ('upper', 'lower'):
        crowns, gum = dentition(which, yf, zm, s)
        out[which] = merged(f'teeth.{which}', crowns)
        out[f'gums_{which}'] = merged(f'gums.{which}', gum)
    out['tongue'] = tongue_mesh(yf, zm, s)
    return out, {'mouth_z': zm, 'mouth_front_y': yf, 'seam': 'jawOpen' if seam is not None else 'fixed'}


def anchors(body, e0, s, y_fb):
    """Face landmarks for procedural keys, snapped to the skin by front ray casts."""
    rel = {'corner': (0.025, -0.072), 'lip_up': (0, -0.064), 'lip_lo': (0, -0.080), 'lip_mid': (0.011, -0.072),
           'chin': (0, -0.105), 'cheek': (0.042, -0.035), 'brow_in': (0.012, 0.024), 'brow_mid': (0.032, 0.03),
           'brow_out': (0.052, 0.024), 'nose': (0.016, -0.040), 'lid_up': (0.032, 0.010), 'lid_lo': (0.032, -0.012)}
    a = {}
    for k, (dx, dz) in rel.items():
        for sgn, suf in ((1, 'L'), (-1, 'R')):
            x, z = e0[0] + sgn * dx * s, e0[2] + dz * s
            a[f'{k}.{suf}'] = np.array([x, surface_y(body, x, z, y_fb), z])
    return a


def key_terms(a, s):
    """ARKit name -> [(anchor, radius m, displacement m)] (Left = character's left, +X)."""
    up, fwd = np.array([0, 0, 1.0]), np.array([0, -1.0, 0])
    T = {}
    for suf, S, sx in (('Left', 'L', 1), ('Right', 'R', -1)):
        out = np.array([sx, 0, 0.0])

        def t(name, *terms):
            T.setdefault(name + suf, []).extend(terms)
        t('eyeBlink', (f'lid_up.{S}', 0.012, -0.009 * up), (f'lid_lo.{S}', 0.008, 0.002 * up))
        t('eyeLookDown', (f'lid_up.{S}', 0.012, -0.003 * up))
        t('eyeLookUp', (f'lid_up.{S}', 0.012, 0.002 * up), (f'brow_mid.{S}', 0.015, 0.001 * up))
        t('eyeLookIn', (f'lid_up.{S}', 0.014, -0.0015 * out))
        t('eyeLookOut', (f'lid_up.{S}', 0.014, 0.0015 * out))
        t('eyeSquint', (f'lid_lo.{S}', 0.01, 0.003 * up), (f'cheek.{S}', 0.015, 0.002 * up))
        t('eyeWide', (f'lid_up.{S}', 0.012, 0.003 * up), (f'brow_mid.{S}', 0.015, 0.002 * up))
        t('mouthSmile', (f'corner.{S}', 0.014, 0.007 * up + 0.004 * out), (f'cheek.{S}', 0.02, 0.003 * up))
        t('mouthFrown', (f'corner.{S}', 0.014, -0.006 * up))
        t('mouthDimple', (f'corner.{S}', 0.012, 0.004 * out - 0.002 * fwd))
        t('mouthStretch', (f'corner.{S}', 0.014, 0.006 * out - 0.002 * up))
        t('mouthPress', (f'lip_mid.{S}', 0.009, -0.0015 * up - 0.001 * fwd))
        t('mouthLowerDown', (f'lip_mid.{S}', 0.01, -0.005 * up))
        t('mouthUpperUp', (f'lip_mid.{S}', 0.01, 0.004 * up))
        t('browDown', (f'brow_in.{S}', 0.014, -0.005 * up - 0.002 * out), (f'brow_mid.{S}', 0.016, -0.004 * up))
        t('browOuterUp', (f'brow_out.{S}', 0.016, 0.006 * up))
        t('cheekSquint', (f'cheek.{S}', 0.016, 0.004 * up))
        t('noseSneer', (f'nose.{S}', 0.01, 0.004 * up), (f'brow_in.{S}', 0.012, -0.002 * up))
        T.setdefault('jawLeft' if sx > 0 else 'jawRight', []).append(('chin.L', 0.035, 0.006 * out))
        T.setdefault('mouthLeft' if sx > 0 else 'mouthRight', []).extend(
            [('corner.L', 0.02, 0.007 * out), ('corner.R', 0.02, 0.007 * out)])
    both = lambda k, rad, v: [(f'{k}.L', rad, v), (f'{k}.R', rad, v)]  # noqa: E731
    T['jawForward'] = both('chin', 0.035, 0.006 * fwd) + both('lip_lo', 0.015, 0.004 * fwd)
    T['mouthClose'] = both('lip_lo', 0.012, 0.004 * up) + both('lip_up', 0.012, -0.002 * up)
    T['mouthFunnel'] = both('lip_up', 0.014, 0.006 * fwd) + both('lip_lo', 0.014, 0.006 * fwd)
    T['mouthPucker'] = [('corner.L', 0.012, np.array([-0.008, 0, 0])), ('corner.R', 0.012, np.array([0.008, 0, 0]))] \
        + both('lip_up', 0.012, 0.004 * fwd)
    T['mouthRollLower'] = both('lip_lo', 0.01, -0.004 * fwd + 0.002 * up)
    T['mouthRollUpper'] = both('lip_up', 0.01, -0.004 * fwd - 0.002 * up)
    T['mouthShrugLower'] = both('lip_lo', 0.012, 0.004 * up) + both('chin', 0.02, 0.003 * up)
    T['mouthShrugUpper'] = both('lip_up', 0.012, 0.003 * up)
    T['browInnerUp'] = both('brow_in', 0.015, 0.006 * up)
    T['cheekPuff'] = [('cheek.L', 0.02, np.array([0.006, -0.003, 0])), ('cheek.R', 0.02, np.array([-0.006, -0.003, 0]))]
    T['tongueOut'] = both('lip_lo', 0.01, -0.002 * up)
    T['jawOpen'] = []
    return {k: [(a[n], rad * s, v * s) for n, rad, v in terms] for k, terms in T.items()}


def procedural_keys(ob, names, a, s, jaw_pivot, mouth_z, e0):
    """Add the missing ARKit keys as Gaussian region moves (jawOpen: a weighted rotation about the jaw pivot)."""
    me = ob.data
    if not me.shape_keys:
        ob.shape_key_add(name='Basis')
    mw = np.array(ob.matrix_world)
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    wco = co @ mw[:3, :3].T + mw[:3, 3]
    inv = np.linalg.inv(mw[:3, :3])
    front = np.clip((e0[1] + 0.03 * s - wco[:, 1]) / (0.02 * s), 0, 1)
    terms = key_terms(a, s)
    for name in names:
        if name == 'jawOpen':
            w = np.clip((mouth_z + 0.002 * s - wco[:, 2]) / (0.014 * s), 0, 1) * front
            w *= np.exp(-(wco[:, 0] / (0.07 * s)) ** 2) * (np.linalg.norm(wco - jaw_pivot, axis=1) < 0.16 * s)
            ang = math.radians(JAW_OPEN_DEG) * w
            rel = wco - jaw_pivot
            c, sn = np.cos(ang), np.sin(ang)
            new = wco.copy()
            new[:, 1] = jaw_pivot[1] + rel[:, 1] * c - rel[:, 2] * sn
            new[:, 2] = jaw_pivot[2] + rel[:, 1] * sn + rel[:, 2] * c
            d = new - wco
        else:
            d = np.zeros_like(wco)
            for anc, rad, vec in terms.get(name, []):
                d += np.exp(-(np.linalg.norm(wco - anc, axis=1) / rad) ** 2)[:, None] * front[:, None] * vec
        k = ob.shape_key_add(name=name, from_mix=False)
        k.data.foreach_set('co', (co + d @ inv.T).ravel())


def mpfb_keys(ob, packs):
    """Load MPFB face targets (CC0 packs) onto an MPFB basemesh; returns False when MPFB is not available."""
    try:
        fs = importlib.import_module('bl_ext.user_default.mpfb.services.faceservice').FaceService
    except ImportError:
        return False
    fs.load_targets(ob, load_microsoft_visemes='visemes01' in packs, load_meta_visemes='visemes02' in packs,
                    load_arkit_faceunits='faceunits01' in packs)
    fs.interpolate_targets(ob)
    return True


def follow_keys(dst, src, names, k=6, anchors=None):
    """Copy src shape-key deltas onto dst by the nearest visible skin verts (to each vertex, or to its anchor point)
    and drive dst keys from the src values."""
    sk = src.data.shape_keys.key_blocks
    names = [n for n in names if n in sk]
    if not names:
        return 0
    mw, n = np.array(src.matrix_world), len(src.data.vertices)
    basis = np.empty(n * 3)
    sk[0].data.foreach_get('co', basis)
    basis = basis.reshape(-1, 3)
    wb = basis @ mw[:3, :3].T + mw[:3, 3]
    vg = src.vertex_groups.get('body')
    skin = [v.index for v in src.data.vertices if any(g.group == vg.index for g in v.groups)] if vg else range(n)
    kd = KDTree(len(skin))
    for i in skin:
        kd.insert(wb[i], i)
    kd.balance()
    dw = np.array(dst.matrix_world)
    dco = np.empty(len(dst.data.vertices) * 3)
    dst.data.vertices.foreach_get('co', dco)
    dco = dco.reshape(-1, 3)
    look = dco @ dw[:3, :3].T + dw[:3, 3] if anchors is None else np.asarray(anchors)
    near = [kd.find_n(Vector(v), k) for v in look]
    idx = np.array([[i for _, i, _ in nn] for nn in near])
    wts = np.array([[1 / (d + 1e-4) for _, _, d in nn] for nn in near])
    wts /= wts.sum(1, keepdims=True)
    to_dst = np.linalg.inv(dw[:3, :3]) @ mw[:3, :3]
    if not dst.data.shape_keys:
        dst.shape_key_add(name='Basis')
    for name in names:
        kc = np.empty(n * 3)
        sk[name].data.foreach_get('co', kc)
        delta = (kc.reshape(-1, 3) - basis)[idx]
        d = (delta * wts[..., None]).sum(1) @ to_dst.T
        kb = dst.shape_key_add(name=name, from_mix=False)
        kb.data.foreach_set('co', (dco + d).ravel())
        drive(kb, 'value', src.data.shape_keys, f'key_blocks["{name}"].value', 'KEY')
    return len(names)


def drive(owner, path, src_id, src_path, id_type, expr='v', index=-1):
    """Simple-expression driver owner.path = expr(v), v = src_id[src_path]."""
    fc = owner.driver_add(path, index) if index >= 0 else owner.driver_add(path)
    dr = fc.driver
    dr.type, dr.expression = 'SCRIPTED', expr
    var = dr.variables.new()
    var.name, var.type = 'v', 'SINGLE_PROP'
    var.targets[0].id_type, var.targets[0].id, var.targets[0].data_path = id_type, src_id, src_path
    dr.is_valid = True
    return fc


def run(ctx):
    face, spec = ctx.spec['face'], ctx.spec
    body = bpy.data.objects[ctx.parts['body']['object']]
    eL, eR = np.array(ctx.landmarks['eye.L']), np.array(ctx.landmarks['eye.R'])
    e0 = (eL + eR) / 2
    s = np.linalg.norm(eL - eR) / 0.064
    r = EYE_R * spec['body']['height_m'] / 1.78
    eyes = face['eyes']
    mats = {'sclera': sclera_material(eyes.get('sclera', '#e6e9f0'), r),
            'iris': iris_material(eyes, r * math.sin(math.radians(LIMBUS_DEG))),
            'cornea': cornea_material(eyes.get('cornea', 'fresnel_gloss')), 'occlusion': occlusion_material(r)}
    tear_mat = material('c3d_tearline', [0.9, 0.85, 0.85, 1], 0.03, alpha=0.35)[0]
    skin_id, brows = spec['body']['skin'], face.get('brows', {'style': 'none'})
    hair_id = brows.get('material', skin_id)
    out = {'eyes': [], 'lid_parts': {}, 'eye_radius_m': r, 'lid_angles': {}, 'lid_radius_m': LID_IN * r}
    dg = bpy.context.evaluated_depsgraph_get()
    followers, aperture = [], {}
    for side, c in (('L', eL), ('R', eR)):
        ep = eye_parts(side, tuple(c), r, mats)
        for key, ob in ep.items():
            ctx.add_part(ob.name, ob.name, NAME, None, 'head' if key == 'occlusion' else f'eye.{side}')
        out['eyes'].append(ep['eye'].name)
        margins = lid_margins(body, c, r, dg)
        if len(margins['upper']) < 3:
            margins = {w: [(np.array(hinge(LID_IN * r, LIDS[w]['open'], ph)) + c, np.array([0, -1.0, 0]))
                           for ph in np.linspace(-60, 60, 21)] for w in LIDS}
        ang = margin_angles(c, r, margins)
        aperture[side] = round((ang['upper'] - ang['lower']), 1)
        for which, n_l in (('upper', 60), ('lower', 22)):
            lashes = lash_cards(side, which, c, r, margins[which], n_l)
            tear = tear_strip(side, which, c, r, margins[which])
            tear.data.materials.append(tear_mat)
            ctx.add_part(lashes.name, lashes.name, NAME, hair_id, 'head')
            ctx.add_part(tear.name, tear.name, NAME, None, 'head')
            roots = np.array([tuple(v.co) for v in lashes.data.vertices])[::8] + c
            followers += [(lashes, np.repeat(roots, 8, axis=0)), (tear, None)]
            if face.get('lids', 'bones') == 'bones':
                tuck = LID_TUCK_DEG if which == 'upper' else -LID_TUCK_DEG
                open_deg = ang[which] + tuck
                lid = lid_parts(side, which, tuple(c), r, open_deg)
                ctx.add_part(lid.name, lid.name, NAME, skin_id, 'head')
                out['lid_angles'][f'{which}.{side}'] = {**LIDS[which], 'open': round(open_deg, 2)}
                out['lid_parts'][f'{which}.{side}'] = [lid.name, lashes.name, tear.name]
        if brows.get('style', 'none') != 'none':
            b = brow_cards(side, tuple(c), r, brows['style'], body)
            ctx.add_part(b.name, b.name, NAME, hair_id, 'head')
    y_fb = e0[1] - 1.5 * r
    mouth, mouth_info = mouth_parts(body, e0, s, y_fb)
    tm, tm_b = material('c3d_teeth', [0.74, 0.68, 0.55, 1], 0.22)
    tm_b.inputs['Subsurface Weight'].default_value, tm_b.inputs['Subsurface Radius'].default_value = 0.15, (1.0, 0.8, 0.5)
    tp = material('c3d_tongue', [0.5, 0.16, 0.17, 1], 0.35)[0]
    gm = material('c3d_gums', [0.48, 0.15, 0.15, 1], 0.3)[0]
    for key, ob in mouth.items():
        ob.data.materials.append(tp if key == 'tongue' else gm if key.startswith('gums') else tm)
        ctx.add_part(ob.name, ob.name, NAME, None, 'head' if key.endswith('upper') else 'jaw')
    keys0 = set(body.data.shape_keys.key_blocks.keys()) if body.data.shape_keys else set()
    source = 'body'
    if not set(ARKIT) <= keys0 and spec['body'].get('base') == 'mpfb' and mpfb_keys(body, face.get('shape_packs', [])):
        source = 'mpfb'
    have = set(body.data.shape_keys.key_blocks.keys()) if body.data.shape_keys else set()
    missing = [n for n in ARKIT if n not in have]
    if missing:
        procedural_keys(body, missing, anchors(body, e0, s, y_fb), s, np.array(ctx.landmarks['jaw']),
                        mouth_info['mouth_z'], e0)
        source = 'procedural' if len(missing) == len(ARKIT) else source + '+procedural'
    keyset = set(body.data.shape_keys.key_blocks.keys())
    followed = sum(follow_keys(bpy.data.objects[f'brow.{sd}'], body,
                               [n for n in ARKIT if n.startswith(BROW_KEYS)])
                   for sd in 'LR' if f'brow.{sd}' in bpy.data.objects)
    lid_followed = sum(follow_keys(ob, body, [n for n in ARKIT if n.startswith(LID_KEYS)], 3, anc)
                       for ob, anc in followers)
    drive(mouth['tongue'].data.shape_keys.key_blocks['tongueOut'], 'value', body.data.shape_keys,
          'key_blocks["tongueOut"].value', 'KEY')
    unmapped = sorted({k for group in ('expressions', 'visemes') for p in face[group].values() for k in p
                       if k not in keyset})
    if unmapped:
        raise ValueError(f'face presets use keys missing on the body: {unmapped}')
    out.update(shape_key_object=body.name, expressions=sorted(face['expressions']), visemes=sorted(face['visemes']),
               arkit=[n for n in ARKIT if n in keyset], mouth=mouth_info, jaw_open_deg=JAW_OPEN_DEG,
               teeth_lower=mouth['lower'].name, gums_lower=mouth['gums_lower'].name, tongue=mouth['tongue'].name)
    ctx.face = out
    return {'stub': False, 'expressions': len(face['expressions']), 'visemes': len(face['visemes']),
            'shape_keys': len(keyset) - 1, 'arkit': len(out['arkit']), 'key_source': source,
            'procedural_keys': len(missing), 'brow_follow_keys': followed, 'lid_follow_keys': lid_followed,
            'aperture_deg': aperture, 'eye_radius_mm': round(r * 1000, 2), 'mouth_seam': mouth_info['seam'],
            'parts': sum(1 for p in ctx.parts.values() if p['stage'] == NAME)}


def weights(face_spec, expression=None, viseme=None, amount=1.0, viseme_amount=1.0):
    """ARKit weights for an expression blended with a viseme (viseme wins on mouth/jaw keys)."""
    w = {k: v * amount for k, v in face_spec['expressions'].get(expression or 'neutral', {}).items()}
    for k, v in face_spec['visemes'].get(viseme or 'sil', {}).items():
        w[k] = max(w.get(k, 0.0) * (1 - viseme_amount), v * viseme_amount) if k.startswith(('jaw', 'mouth', 'tongue')) \
            else w.get(k, 0.0) + v * viseme_amount
    return {k: min(1.0, v) for k, v in w.items()}


def apply_weights(arm, w, frame=None):
    """Set (and key, when frame is given) the rig's ARKit properties; names absent from w go to 0, blinks untouched."""
    for name in ARKIT:
        if name in arm.keys() and not name.startswith('eyeBlink'):
            arm[name] = w.get(name, 0.0)
            if frame is not None:
                arm.keyframe_insert(f'["{name}"]', frame=frame)


def saccade_seconds(amp_deg):
    """Main-sequence duration (Eyes Alive): 2.2 ms/deg + 21 ms."""
    return 0.021 + 0.0022 * amp_deg


def saccade_amplitude(rng, cap=15.0):
    """Eyes Alive magnitude fit A = -6.9 ln(P/15.7), P uniform; median about 4 deg."""
    return min(cap, -6.9 * math.log(rng.uniform(0.05, 15.0) / 15.7))


def gaze_track(seconds, fps, saccades_per_s=2.0, mode='talk', seed=0, cap_deg=15.0):
    """Per-frame (yaw, pitch) deg: holds plus saccades that cover 80 % of the move in their first frame."""
    rng, n = random.Random(seed), max(1, round(seconds * fps))
    p_return = 0.5 if mode == 'talk' else 0.7
    cur, out, f, events = (0.0, 0.0), [], 0, []
    while len(out) < n:
        hold = max(0.15, rng.expovariate(saccades_per_s)) if saccades_per_s > 0 else seconds
        out += [cur] * max(1, round(hold * fps))
        if cur != (0.0, 0.0) and rng.random() < p_return:
            nxt = (0.0, 0.0)
        else:
            d = math.radians(rng.choices([a for a, _ in SACCADE_DIRS], [w for _, w in SACCADE_DIRS])[0])
            a = saccade_amplitude(rng, cap_deg)
            nxt = tuple(max(-cap_deg, min(cap_deg, v)) for v in (a * math.cos(d), 0.6 * a * math.sin(d)))
        amp = math.dist(cur, nxt)
        k = max(1, round(saccade_seconds(amp) * fps))
        events.append((len(out), amp))
        for i in range(1, k + 1):
            t = 0.8 + 0.2 * (i - 1) / max(1, k - 1) if k > 1 else 1.0
            out.append(tuple(c + (x - c) * t for c, x in zip(cur, nxt)))
        cur = nxt
    return out[:n], [e for e in events if e[0] < n]


def blink_track(seconds, fps, blinks_per_s=0.4, seed=0, forced=()):
    """Per-frame lid closure 0..1: 100 ms close, 1 frame shut, 200 ms open; gaps >= 1.2 s plus forced blinks."""
    rng, n = random.Random(seed + 7), max(1, round(seconds * fps))
    starts, t = set(int(f) for f in forced), rng.uniform(0.3, 1.5)
    while blinks_per_s > 0 and t * fps < n:
        starts.add(round(t * fps))
        t += max(1.2, rng.expovariate(blinks_per_s))
    close, opn = max(2, round(0.1 * fps)), max(3, round(0.2 * fps))
    shape = [(i + 1) / close for i in range(close)] + [1.0] + [1 - ((i + 1) / opn) ** 0.7 for i in range(opn)]
    out = [0.0] * n
    for s0 in sorted(starts):
        for i, v in enumerate(shape):
            if 0 <= s0 + i < n:
                out[s0 + i] = max(out[s0 + i], v)
    return out


def gaze_blink(gaze_spec, seconds, fps, mode='talk', seed=0, big_deg=12.0):
    """Gaze and blink tracks together; saccades above big_deg force a blink."""
    g = gaze_spec or {}
    track, events = gaze_track(seconds, fps, g.get('saccades_per_s', 2.0), mode, seed)
    blink = blink_track(seconds, fps, g.get('blinks_per_s', 0.4), seed, [f for f, a in events if a >= big_deg])
    return {'yaw': [y for y, _ in track], 'pitch': [p for _, p in track], 'blink': blink,
            'saccades': len(events), 'lid_follow': g.get('lid_follow', 0.5)}
