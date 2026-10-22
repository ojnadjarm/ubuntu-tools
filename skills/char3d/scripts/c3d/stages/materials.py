"""Stage materials: AAA procedural PBR per material kind; the draft look and the source the bake reads."""
import math

import bpy
import numpy as np

NAME = 'materials'
EYE_SUBS = ('cornea', 'iris', 'sclera', 'tearline', 'occlusion')
DIELECTRIC = (30.0, 240.0)
METAL = (170.0, 250.0)
CURV = 'c3d_curv'
MICRO = 'c3d_micro'
WEAR_KINDS = {'metal', 'leather', 'wood'}
SEEN = {'dielectric': [255.0, 0.0], 'metal_lum': [255.0, 0.0]}
CLAMPED = [0]
GRIME = '#4a3b2a'


def srgb(hexcol):
    return [int(hexcol[i:i + 2], 16) for i in (1, 3, 5)]


def linear(c255):
    c = [x / 255 for x in c255]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1.0]


def srgb_to_linear(hexcol):
    return linear(srgb(hexcol))


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def note(key, vals, band):
    """Log authored (pre-clamp) sRGB values and count the ones outside the band."""
    seen = SEEN[key]
    seen[:] = [min(seen[0], *vals), max(seen[1], *vals)]
    CLAMPED[0] += sum(not band[0] <= v <= band[1] for v in vals)


def albedo(hexcol, mult=(1, 1, 1), metal=False):
    """Linear albedo of a tinted spec colour; out-of-band values (sRGB 30-240, metal luminance 170-250) are counted, then clamped."""
    c = [x * k for x, k in zip(srgb(hexcol), mult)]
    if metal:
        note('metal_lum', [lum(c)], METAL)
        CLAMPED[0] += max(c) > METAL[1]
        c = [min(x * min(max(lum(c), METAL[0]), METAL[1]) / max(lum(c), 1e-6), METAL[1]) for x in c]
    else:
        note('dielectric', c, DIELECTRIC)
        c = [min(max(x, DIELECTRIC[0]), DIELECTRIC[1]) for x in c]
    return linear(c)


def darker(hexcol, k):
    """Uniform dielectric shade k, raised as far as needed to keep the darkest channel inside the band."""
    k = max(k, (DIELECTRIC[0] + 1) / max(min(srgb(hexcol)), 1))
    return albedo(hexcol, (k, k, k))


def metal_stop(hexcol, k):
    """Uniform metal tint k kept inside the luminance band and the channel cap (polish is roughness, not albedo)."""
    c = srgb(hexcol)
    k = min(max(k, (METAL[0] + 1) / lum(c)), (METAL[1] - 1) / max(c), (METAL[1] - 1) / lum(c))
    return albedo(hexcol, (k, k, k), True)


def principled(name, color, rough=0.5, **inputs):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = color
    b.inputs['Roughness'].default_value = rough
    for k, v in inputs.items():
        b.inputs[k].default_value = v
    return mat, b


def node(nt, kind, **values):
    n = nt.nodes.new(kind)
    for k, v in values.items():
        n.inputs[k].default_value = v
    return n


def response(m):
    """Kind-level BSDF inputs (no colour): shared by the procedural shaders and the baked set materials."""
    k = m['kind']
    if k == 'skin':
        return {'Subsurface Weight': 1.0, 'Subsurface Radius': (1.0, 0.37, 0.18), 'Subsurface Scale': 0.005,
                'Subsurface Anisotropy': 0.8, 'IOR': 1.4, 'Specular IOR Level': 0.4}
    if k == 'cloth':
        c = srgb(m['color'])
        return {'Sheen Weight': m.get('sheen', 0.4), 'Sheen Roughness': 0.3,
                'Sheen Tint': linear([min(x * 1.6, 255.0) for x in c]), 'Specular IOR Level': 0.2}
    if k == 'hair':
        return {'Sheen Weight': 0.3, 'Sheen Roughness': 0.3, 'Specular IOR Level': 0.35}
    if k == 'leather':
        return {'Coat Weight': 0.15, 'Coat Roughness': 0.3}
    if k == 'emissive':
        return {'Emission Color': srgb_to_linear(m['color']), 'Emission Strength': m.get('emission', {}).get('base', 3.0),
                'Coat Weight': 1.0, 'Coat Roughness': 0.02}
    if k == 'glass':
        return {'Transmission Weight': 1.0}
    return {}


def finish(mat, b, m):
    """Apply the kind response (and the skin SSS method) to a Principled node."""
    for k, v in response(m).items():
        b.inputs[k].default_value = v
    if m['kind'] == 'skin':
        b.subsurface_method = 'RANDOM_WALK_SKIN'
    if m['kind'] == 'glass':
        mat.use_raytrace_refraction = True


def ramp(nt, fac, stops):
    """Colour ramp over a factor socket; stops = [(position, linear rgba)] in rising order."""
    r = nt.nodes.new('ShaderNodeValToRGB')
    els = r.color_ramp.elements
    els[0].position, els[0].color = stops[0]
    els[1].position, els[1].color = stops[-1]
    for pos, col in stops[1:-1]:
        els.new(pos).color = col
    nt.links.new(fac, r.inputs['Fac'])
    return r.outputs['Color']


def maprange(nt, src, a, b, lo=0.0, hi=1.0, smooth=True):
    n = node(nt, 'ShaderNodeMapRange', **{'From Min': a, 'From Max': b, 'To Min': lo, 'To Max': hi})
    if smooth:
        n.interpolation_type = 'SMOOTHSTEP'
    nt.links.new(src, n.inputs['Value'])
    return n.outputs['Result']


def math_op(nt, op, a, b=None):
    n = nt.nodes.new('ShaderNodeMath')
    n.operation = op
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def coords(nt, scale=(1, 1, 1)):
    tc = nt.nodes.new('ShaderNodeTexCoord')
    if scale == (1, 1, 1):
        return tc.outputs['Object']
    mp = node(nt, 'ShaderNodeMapping', Scale=scale)
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    return mp.outputs['Vector']


def tex(nt, kind, vec, out='Fac', **values):
    n = node(nt, kind, **values)
    nt.links.new(vec, n.inputs['Vector'])
    return n, n.outputs[out]


def ao(nt, distance=0.04):
    n = node(nt, 'ShaderNodeAmbientOcclusion', Distance=distance)
    return n.outputs['AO']


def curvature(nt):
    """Signed curvature attribute (convex > 0, flat 0, cavity < 0) written by this stage."""
    n = nt.nodes.new('ShaderNodeAttribute')
    n.attribute_type, n.attribute_name = 'GEOMETRY', CURV
    return n.outputs['Fac']


def bumps(nt, bsdf, layers):
    """Chain bump layers [(height socket, strength, distance m)] into the BSDF normal."""
    prev = None
    for height, strength, dist in layers:
        b = node(nt, 'ShaderNodeBump', Strength=strength, Distance=dist)
        nt.links.new(height, b.inputs['Height'])
        if prev is not None:
            nt.links.new(prev, b.inputs['Normal'])
        prev = b.outputs['Normal']
    nt.links.new(prev, bsdf.inputs['Normal'])


def rough_map(nt, bsdf, base, terms):
    """Roughness = base + sum(weight * factor), clamped to 0.05-1."""
    out = base
    for fac, w in terms:
        out = math_op(nt, 'ADD', math_op(nt, 'MULTIPLY', fac, w), out)
    nt.links.new(math_op(nt, 'MAXIMUM', math_op(nt, 'MINIMUM', out, 1.0), 0.05), bsdf.inputs['Roughness'])


def near(nt, height, far=2.5):
    """Fade a sub-millimetre height with camera depth; zero until the texture stage sets the view-layer flag MICRO, so
    the bake leaves it to the tiling detail normals instead of aliasing it into the baked normal."""
    cam = nt.nodes.new('ShaderNodeCameraData')
    flag = nt.nodes.new('ShaderNodeAttribute')
    flag.attribute_type, flag.attribute_name = 'VIEW_LAYER', MICRO
    return math_op(nt, 'MULTIPLY', math_op(nt, 'MULTIPLY', height, flag.outputs['Fac']),
                   maprange(nt, cam.outputs['View Z Depth'], far, 0.6))


def blend(nt, fac, a, b):
    """RGBA mix: a socket or colour (A) towards b (B) by a factor socket."""
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    nt.links.new(fac, mix.inputs['Factor'])
    for sock, v in ((mix.inputs['A'], a), (mix.inputs['B'], b)):
        if isinstance(v, list):
            sock.default_value = v
        else:
            nt.links.new(v, sock)
    return mix.outputs['Result']


def zones(nt, ctx):
    """Facial flush mask (nose, both cheeks, 0-1) placed from the eye landmarks; the face looks down -Y."""
    l, r = ctx.landmarks.get('eye.L'), ctx.landmarks.get('eye.R')
    if not (l and r):
        return None
    mid = [(a + b) / 2 for a, b in zip(l, r)]
    pos = nt.nodes.new('ShaderNodeNewGeometry').outputs['Position']
    total = None
    for c, rad in (((mid[0], mid[1] - 0.03, mid[2] - 0.035), 0.022),
                   ((l[0] * 1.15, l[1] - 0.005, l[2] - 0.04), 0.026), ((r[0] * 1.15, r[1] - 0.005, r[2] - 0.04), 0.026)):
        d = nt.nodes.new('ShaderNodeVectorMath')
        d.operation = 'DISTANCE'
        d.inputs[1].default_value = c
        nt.links.new(pos, d.inputs[0])
        g = math_op(nt, 'EXPONENT', math_op(nt, 'MULTIPLY', math_op(nt, 'POWER', math_op(nt, 'DIVIDE', d.outputs['Value'], rad), 2.0), -1.0))
        total = g if total is None else math_op(nt, 'ADD', total, g)
    return math_op(nt, 'MINIMUM', total, 1.0)


def skin(mid, m, ctx):
    """SSS skin (random-walk skin): cool-to-flushed mottling, red nose/cheek blotches, brown age spots, pores, fine lines."""
    rough = m.get('roughness', 0.5)
    out = {}
    tone = lambda tint, k: albedo(m['color'], [t * x for t, x in zip(tint, k)])  # noqa: E731
    for name, tint, r in ((mid, (1, 1, 1), rough), (f'{mid}.lips', (0.9, 0.62, 0.62), rough - 0.12),
                          (f'{mid}.nails', (1.05, 1.0, 0.95), 0.3)):
        mat, b = principled(name, albedo(m['color'], tint), r)
        finish(mat, b, m)
        nt = mat.node_tree
        _, blotch = tex(nt, 'ShaderNodeTexNoise', coords(nt), Scale=14.0, Detail=6.0, Roughness=0.6)
        _, cool = tex(nt, 'ShaderNodeTexNoise', coords(nt), Scale=4.0, Detail=3.0)
        _, spots = tex(nt, 'ShaderNodeTexVoronoi', coords(nt), out='Distance', Scale=30.0, Randomness=1.0)
        red = maprange(nt, blotch, 0.45, 0.75)
        face = zones(nt, ctx) if name == mid else None
        if face is not None:
            red = math_op(nt, 'MINIMUM', math_op(nt, 'ADD', math_op(nt, 'MULTIPLY', face, math_op(nt, 'ADD', red, 0.5)), red), 1.0)
        fac = math_op(nt, 'SUBTRACT', math_op(nt, 'ADD', math_op(nt, 'MULTIPLY', red, 0.6), 0.4),
                      math_op(nt, 'MULTIPLY', maprange(nt, cool, 0.5, 0.7), 0.4))
        col = ramp(nt, fac, [(0.0, tone(tint, (0.94, 0.97, 1.06))), (0.4, albedo(m['color'], tint)),
                             (1.0, tone(tint, (0.98, 0.74, 0.7)))])
        age = math_op(nt, 'MULTIPLY', maprange(nt, spots, 0.12, 0.05), maprange(nt, cool, 0.45, 0.6))
        col = blend(nt, math_op(nt, 'MULTIPLY', age, 0.6), col, tone(tint, (0.78, 0.66, 0.56)))
        nt.links.new(col, b.inputs['Base Color'])
        _, pore = tex(nt, 'ShaderNodeTexVoronoi', coords(nt), out='Distance', Scale=1000.0, Randomness=0.9)
        pores = maprange(nt, pore, 0.0, 0.32)
        _, lines = tex(nt, 'ShaderNodeTexWave', coords(nt), Scale=55.0, Distortion=9.0, Detail=4.0,
                       **{'Detail Scale': 2.0})
        _, micro = tex(nt, 'ShaderNodeTexNoise', coords(nt), Scale=700.0, Detail=3.0)
        bumps(nt, b, [(near(nt, pores), 0.4, 0.0003), (lines, 0.08, 0.0005), (near(nt, micro), 0.08, 0.0002)])
        rough_map(nt, b, r, [(math_op(nt, 'SUBTRACT', 1.0, pores), 0.15), (micro, 0.08), (red, 0.06)])
        out[name] = mat
    return out


VARIANTS = {'lips': 'lips', 'nail': 'nails'}


def cloth(mid, m, ctx):
    """Wool cloth: hue-tinted sheen, over-under weave (1.6 mm pitch) with per-thread heather, AO fold grime, faded tops."""
    rough = m.get('roughness', 0.8)
    mat, b = principled(mid, albedo(m['color']), rough)
    finish(mat, b, m)
    nt = mat.node_tree
    pitch = 0.0016
    _, wx = tex(nt, 'ShaderNodeTexWave', coords(nt), Scale=2 * math.pi / (20 * pitch), Distortion=0.3, Detail=0.0)
    _, wz = tex(nt, 'ShaderNodeTexWave', coords(nt), Scale=2 * math.pi / (20 * pitch), Distortion=0.3, Detail=0.0)
    wz.node.bands_direction = 'Z'
    _, chk = tex(nt, 'ShaderNodeTexChecker', coords(nt), Scale=1.0 / pitch)
    over = nt.nodes.new('ShaderNodeMix')
    nt.links.new(chk, over.inputs['Factor'])
    nt.links.new(wx, over.inputs['A'])
    nt.links.new(wz, over.inputs['B'])
    weave = over.outputs['Result']
    _, fade = tex(nt, 'ShaderNodeTexNoise', coords(nt), Scale=3.0, Detail=4.0)
    _, heather = tex(nt, 'ShaderNodeTexNoise', coords(nt, (1, 1, 0.08)), Scale=0.5 / pitch, Detail=1.0)
    _, fibre = tex(nt, 'ShaderNodeTexNoise', coords(nt, (1, 1, 30)), Scale=900.0, Detail=2.0)
    fac = math_op(nt, 'ADD', math_op(nt, 'ADD', math_op(nt, 'MULTIPLY', ao(nt, 0.06), 0.4),
                                     math_op(nt, 'MULTIPLY', fade, 0.25)),
                  math_op(nt, 'ADD', math_op(nt, 'MULTIPLY', weave, 0.2), math_op(nt, 'MULTIPLY', heather, 0.25)))
    col = ramp(nt, fac, [(0.3, albedo(m['color'], (0.82, 0.8, 0.86))), (0.72, albedo(m['color'])),
                         (1.0, albedo(m['color'], (1.12, 1.1, 1.08)))])
    nt.links.new(col, b.inputs['Base Color'])
    bumps(nt, b, [(near(nt, weave), 0.35, 0.0005), (near(nt, fibre), 0.08, 0.0002)])
    rough_map(nt, b, rough, [(weave, -0.06), (fade, 0.06)])
    return {mid: mat}


def metal(mid, m, ctx):
    """Metal with curvature-driven edge wear: polished brighter edges, dielectric grime in cavities, fine scratches."""
    rough = m.get('roughness', 0.3)
    mat, b = principled(mid, albedo(m['color'], metal=True), rough, Metallic=1.0)
    nt = mat.node_tree
    curv = curvature(nt)
    edge = maprange(nt, curv, 0.02, 0.15)
    cav = math_op(nt, 'MAXIMUM', maprange(nt, curv, -0.02, -0.15), maprange(nt, ao(nt, 0.02), 0.85, 0.35))
    _, mott = tex(nt, 'ShaderNodeTexNoise', coords(nt), Scale=40.0, Detail=5.0)
    _, scr = tex(nt, 'ShaderNodeTexNoise', coords(nt, (60, 1.5, 1.5)), Scale=30.0, Detail=6.0, Roughness=0.7)
    scratches = maprange(nt, scr, 0.6, 0.66)
    f = math_op(nt, 'ADD', math_op(nt, 'MULTIPLY', edge, 0.6), math_op(nt, 'MULTIPLY', mott, 0.4))
    col = ramp(nt, f, [(0.0, metal_stop(m['color'], 0.86)), (0.35, albedo(m['color'], metal=True)),
                       (0.9, metal_stop(m['color'], 1.1))])
    grime = math_op(nt, 'MULTIPLY', cav, 0.85)
    nt.links.new(blend(nt, maprange(nt, grime, 0.2, 0.6, 0.0, 0.85), col, albedo(GRIME)), b.inputs['Base Color'])
    nt.links.new(maprange(nt, grime, 0.15, 0.25, 1.0, 0.0), b.inputs['Metallic'])
    bumps(nt, b, [(near(nt, math_op(nt, 'SUBTRACT', 1.0, scratches)), 0.05, 0.0002), (mott, 0.03, 0.0004)])
    rough_map(nt, b, rough, [(cav, 0.35), (edge, -0.12), (scratches, 0.12), (mott, 0.1)])
    return {mid: mat}


def hair(mid, m, ctx):
    mat, b = principled(mid, albedo(m['color']), m.get('roughness', 0.45))
    finish(mat, b, m)
    nt = mat.node_tree
    info = nt.nodes.new('ShaderNodeObjectInfo')
    _, n = tex(nt, 'ShaderNodeTexNoise', coords(nt), Scale=60.0, Detail=2.0)
    fac = math_op(nt, 'ADD', math_op(nt, 'MULTIPLY', info.outputs['Random'], 0.3), math_op(nt, 'MULTIPLY', n, 0.7))
    nt.links.new(ramp(nt, fac, [(0.2, albedo(m['color'], (0.84, 0.82, 0.76))), (0.8, albedo(m['color']))]),
                 b.inputs['Base Color'])
    return {mid: mat}


def wood(mid, m, ctx):
    """Carved wood: ring grain along the long axis, pore streaks, dirt in cavities and hand-polished edges."""
    rough = m.get('roughness', 0.6)
    mat, b = principled(mid, albedo(m['color']), rough)
    nt = mat.node_tree
    w, grain = tex(nt, 'ShaderNodeTexWave', coords(nt), Scale=7.0, Distortion=6.0, Detail=4.0,
                   **{'Detail Scale': 1.5})
    w.wave_type, w.rings_direction = 'RINGS', 'Z'
    _, pores = tex(nt, 'ShaderNodeTexNoise', coords(nt, (40, 40, 2)), Scale=8.0, Detail=6.0)
    edge = maprange(nt, curvature(nt), 0.03, 0.25)
    dirt = maprange(nt, ao(nt, 0.03), 0.95, 0.4)
    f = math_op(nt, 'ADD', math_op(nt, 'MULTIPLY', grain, 0.55), math_op(nt, 'MULTIPLY', pores, 0.25))
    f = math_op(nt, 'SUBTRACT', math_op(nt, 'ADD', f, math_op(nt, 'MULTIPLY', edge, 0.3)),
                math_op(nt, 'MULTIPLY', dirt, 0.35))
    col = ramp(nt, f, [(0.0, albedo(m['color'], (0.64, 0.62, 0.64))), (0.45, albedo(m['color'])),
                       (0.9, albedo(m['color'], (1.3, 1.22, 1.12)))])
    nt.links.new(col, b.inputs['Base Color'])
    bumps(nt, b, [(grain, 0.12, 0.0006), (pores, 0.1, 0.0003)])
    rough_map(nt, b, rough, [(grain, -0.1), (edge, -0.15), (dirt, 0.15)])
    return {mid: mat}


def leather(mid, m, ctx):
    """Leather: pebbled grain cells with creases, scuffed lighter convex wear, darker cavities."""
    rough = m.get('roughness', 0.5)
    mat, b = principled(mid, albedo(m['color']), rough)
    finish(mat, b, m)
    nt = mat.node_tree
    v, cells = tex(nt, 'ShaderNodeTexVoronoi', coords(nt), out='Distance', Scale=450.0, Randomness=1.0)
    v.feature = 'DISTANCE_TO_EDGE'
    crease = maprange(nt, cells, 0.0, 0.12)
    _, mott = tex(nt, 'ShaderNodeTexNoise', coords(nt), Scale=12.0, Detail=5.0)
    edge = maprange(nt, curvature(nt), 0.03, 0.25)
    dirt = maprange(nt, ao(nt, 0.03), 0.95, 0.4)
    f = math_op(nt, 'ADD', math_op(nt, 'MULTIPLY', mott, 0.35), math_op(nt, 'MULTIPLY', edge, 0.4))
    f = math_op(nt, 'SUBTRACT', math_op(nt, 'ADD', f, math_op(nt, 'MULTIPLY', crease, 0.2)),
                math_op(nt, 'MULTIPLY', dirt, 0.35))
    col = ramp(nt, math_op(nt, 'ADD', f, 0.2), [(0.0, albedo(m['color'], (0.9, 0.88, 0.9))), (0.45, albedo(m['color'])),
                                                 (1.0, albedo(m['color'], (1.45, 1.38, 1.3)))])
    nt.links.new(col, b.inputs['Base Color'])
    bumps(nt, b, [(near(nt, crease, 4.0), 0.3, 0.0005), (mott, 0.05, 0.001)])
    rough_map(nt, b, rough, [(edge, 0.15), (crease, -0.08), (dirt, 0.1)])
    return {mid: mat}


def emissive(mid, m, ctx):
    """Glowing crystal: faceted inner variation on the emission colour; Emission Strength stays a plain value (pulse)."""
    mat, b = principled(mid, albedo(m['color'], (0.92, 0.92, 0.92)), m.get('roughness', 0.05))
    finish(mat, b, m)
    nt = mat.node_tree
    _, cells = tex(nt, 'ShaderNodeTexVoronoi', coords(nt), out='Distance', Scale=60.0)
    em = srgb_to_linear(m['color'])
    col = ramp(nt, cells, [(0.0, [c * 1.25 for c in em[:3]] + [1]), (0.6, em), (1.0, [c * 0.55 for c in em[:3]] + [1])])
    nt.links.new(col, b.inputs['Emission Color'])
    return {mid: mat}


def glass(mid, m, ctx):
    mat, b = principled(mid, albedo(m['color']), m.get('roughness', 0.02))
    finish(mat, b, m)
    return {mid: mat}


def iris_fibres(nt, tc, hexes):
    """Radial iris fibres and crypts by angle about the local -Y pupil axis; returns the mix (A = layer below)."""
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(tc, sep.inputs[0])
    vec = nt.nodes.new('ShaderNodeCombineXYZ')
    nt.links.new(math_op(nt, 'MULTIPLY', math_op(nt, 'ARCTAN2', sep.outputs['X'], sep.outputs['Z']), 9.0), vec.inputs['X'])
    nt.links.new(math_op(nt, 'MULTIPLY', sep.outputs['Y'], 60.0), vec.inputs['Y'])
    _, fib = tex(nt, 'ShaderNodeTexNoise', vec.outputs['Vector'], Scale=1.6, Detail=6.0, Roughness=0.65)
    col = ramp(nt, fib, [(0.3, darker(hexes['outer'], 0.6)), (0.5, albedo(hexes['iris'])),
                         (0.75, albedo(hexes['iris'], (1.35, 1.35, 1.35)))])
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.inputs['Factor'].default_value = 0.65
    nt.links.new(col, mix.inputs['B'])
    return mix, sep


def eye(mid, m, ctx):
    """Layered eyeball: veined sclera, dark limbal ring, fibrous iris, pupil, under a Fresnel coat; plus sub-materials."""
    e = ctx.spec['face'].get('eyes', {})
    hexes = {'sclera': e.get('sclera', '#e6e9f0'), 'iris': e.get('iris', m['color']),
             'outer': e.get('iris_outer', e.get('iris', m['color']))}
    sclera, iris, outer = albedo(hexes['sclera'], (0.97, 0.97, 0.97)), albedo(hexes['iris']), albedo(hexes['outer'])
    pupil = e.get('pupil', 0.35)
    mat, b = principled(mid, sclera, 0.3, **{'Coat Weight': 1.0, 'Coat Roughness': 0.02, 'Coat IOR': 1.376,
                                              'Subsurface Weight': 0.3, 'Subsurface Radius': (1.0, 0.4, 0.3),
                                              'Subsurface Scale': 0.002})
    nt = mat.node_tree
    tc = nt.nodes.new('ShaderNodeTexCoord').outputs['Object']
    fib, sep = iris_fibres(nt, tc, hexes)
    length = nt.nodes.new('ShaderNodeVectorMath')
    length.operation = 'LENGTH'
    nt.links.new(tc, length.inputs[0])
    cosang = math_op(nt, 'DIVIDE', math_op(nt, 'MULTIPLY', sep.outputs['Y'], -1.0), length.outputs['Value'])
    iris_cos, pupil_cos = math.cos(math.radians(29)), math.cos(math.radians(29 * pupil))
    black = albedo('#222222')
    stops = [(0.0, albedo(hexes['sclera'], (0.97, 0.83, 0.81))), (0.5, sclera), (iris_cos - 0.03, sclera),
             (iris_cos - 0.006, darker(hexes['outer'], 0.62)), (iris_cos + 0.004, outer),
             (pupil_cos - 0.006, iris), (pupil_cos, black)]
    nt.links.new(ramp(nt, cosang, stops), fib.inputs['A'])
    in_iris = math_op(nt, 'MULTIPLY', maprange(nt, cosang, iris_cos, iris_cos + 0.01),
                      maprange(nt, cosang, pupil_cos - 0.006, pupil_cos - 0.012))
    nt.links.new(math_op(nt, 'MULTIPLY', in_iris, 0.7), fib.inputs['Factor'])
    nt.links.new(fib.outputs['Result'], b.inputs['Base Color'])
    subs = {mid: mat}
    subs[f'{mid}.sclera'] = principled(f'{mid}.sclera', sclera, 0.3, **{'Coat Weight': 1.0, 'Coat Roughness': 0.02})[0]
    im, ib = principled(f'{mid}.iris', iris, 0.45)
    ifib, _ = iris_fibres(im.node_tree, im.node_tree.nodes.new('ShaderNodeTexCoord').outputs['Object'], hexes)
    ifib.inputs['A'].default_value = iris
    im.node_tree.links.new(ifib.outputs['Result'], ib.inputs['Base Color'])
    subs[f'{mid}.iris'] = im
    subs[f'{mid}.cornea'] = cornea(f'{mid}.cornea')
    subs[f'{mid}.tearline'] = principled(f'{mid}.tearline', albedo('#ebebeb'), 0.0, Alpha=0.15)[0]
    subs[f'{mid}.occlusion'] = principled(f'{mid}.occlusion', black, 1.0, Alpha=0.35)[0]
    for k in ('tearline', 'occlusion'):
        subs[f'{mid}.{k}'].surface_render_method = 'BLENDED'
    return subs


def cornea(name):
    """Transparent + glossy mixed by Fresnel (IOR 1.376), blended: iris stays readable and the catchlight is sharp."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.remove(nt.nodes['Principled BSDF'])
    fr = node(nt, 'ShaderNodeFresnel', IOR=1.376)
    tr = nt.nodes.new('ShaderNodeBsdfTransparent')
    gl = node(nt, 'ShaderNodeBsdfGlossy', Roughness=0.02)
    mix = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(fr.outputs[0], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(gl.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes['Material Output'].inputs['Surface'])
    mat.surface_render_method = 'BLENDED'
    return mat


KINDS = {'skin': skin, 'cloth': cloth, 'metal': metal, 'hair': hair, 'wood': wood, 'leather': leather,
         'emissive': emissive, 'glass': glass, 'eye': eye}


def write_curvature(ob):
    """Signed per-vertex convexity (mean normal-to-edge sine, one smoothing pass) as a point attribute."""
    me = ob.data
    n, ne = len(me.vertices), len(me.edges)
    if not n or not ne:
        return
    co = np.empty(n * 3, np.float32)
    me.vertices.foreach_get('co', co)
    nr = np.empty(n * 3, np.float32)
    me.vertex_normals.foreach_get('vector', nr)
    e = np.empty(ne * 2, np.int32)
    me.edges.foreach_get('vertices', e)
    co, nr, e = co.reshape(-1, 3), nr.reshape(-1, 3), e.reshape(-1, 2)
    d = co[e[:, 1]] - co[e[:, 0]]
    d /= np.linalg.norm(d, axis=1, keepdims=True) + 1e-9
    cnt = np.maximum(np.bincount(e[:, 0], minlength=n) + np.bincount(e[:, 1], minlength=n), 1)
    k = (np.bincount(e[:, 0], -(nr[e[:, 0]] * d).sum(1), n) + np.bincount(e[:, 1], (nr[e[:, 1]] * d).sum(1), n)) / cnt
    k = 0.5 * k + 0.5 * (np.bincount(e[:, 0], k[e[:, 1]], n) + np.bincount(e[:, 1], k[e[:, 0]], n)) / cnt
    attr = me.attributes.get(CURV) or me.attributes.new(CURV, 'FLOAT', 'POINT')
    attr.data.foreach_set('value', k.astype(np.float32))


def adopt(name, mat):
    """Swap a placeholder material named after a spec id (any slot, any object) for the lookdev one."""
    old = bpy.data.materials.get(name)
    if old is not None and old != mat:
        old.user_remap(mat)
        bpy.data.materials.remove(old)
    mat.name = name


def build_materials(ctx):
    mats = {}
    for mid, m in ctx.spec['materials'].items():
        for name, mat in KINDS[m['kind']](mid, m, ctx).items():
            mat.name = f'_c3d_{name}'
            mats[name] = mat
    for name, mat in mats.items():
        adopt(name, mat)
    curved = 0
    for part in ctx.parts.values():
        ob = bpy.data.objects[part['object']]
        mid = part['material']
        if not mid or ob.type not in ('MESH', 'CURVES', 'CURVE'):
            continue
        if not ob.data.materials:
            ob.data.materials.append(mats[mid])
        for i, slot in enumerate(ob.data.materials):
            if slot is None or slot.name not in mats:
                ob.data.materials[i] = mats.get(variant(mid, slot), mats[mid])
        kinds = {ctx.spec['materials'][s.name.split('.')[0]]['kind'] for s in ob.data.materials
                 if s and s.name.split('.')[0] in ctx.spec['materials']}
        if ob.type == 'MESH' and kinds & WEAR_KINDS:
            write_curvature(ob)
            curved += 1
    return mats, curved


def guard(ctx, mats):
    """Clamp the Base Color of the other stages' dielectric Principled materials on the parts (eyes, mouth) to sRGB 30-240."""
    lo, hi = (linear([v] * 3)[:3] for v in (DIELECTRIC[0] + 0.5, DIELECTRIC[1] - 0.5))
    seen, n = set(mats.values()), 0
    for part in ctx.parts.values():
        for mat in getattr(bpy.data.objects[part['object']].data, 'materials', []):
            if mat is None or mat in seen or not mat.use_nodes:
                continue
            seen.add(mat)
            nt = mat.node_tree
            b = next((x for x in nt.nodes if x.type == 'BSDF_PRINCIPLED'), None)
            if b is None or b.inputs['Metallic'].is_linked or b.inputs['Metallic'].default_value > 0.5:
                continue
            sock = b.inputs['Base Color']
            if sock.is_linked:
                src = sock.links[0].from_socket
                for op, v in (('MINIMUM', hi), ('MAXIMUM', lo)):
                    vm = nt.nodes.new('ShaderNodeVectorMath')
                    vm.operation = op
                    vm.inputs[1].default_value = v
                    nt.links.new(src, vm.inputs[0])
                    src = vm.outputs['Vector']
                nt.links.new(src, sock)
            else:
                c = sock.default_value
                sock.default_value = [min(max(c[i], lo[i]), hi[i]) for i in range(3)] + [c[3]]
            n += 1
    return n


def variant(mid, foreign):
    """Map a foreign slot (e.g. MPFB Human.lips) onto the spec material's sub-variant when one exists."""
    name = foreign.name.lower() if foreign else ''
    return next((f'{mid}.{v}' for k, v in VARIANTS.items() if k in name), mid)


def run(ctx):
    SEEN.update(dielectric=[255.0, 0.0], metal_lum=[255.0, 0.0])
    CLAMPED[0] = 0
    mats, curved = build_materials(ctx)
    return {'stub': False, 'materials': len(mats), 'curvature_parts': curved, 'albedo_guarded': guard(ctx, mats),
            'albedo_srgb': {k: [round(v, 1) for v in r] for k, r in SEEN.items() if r[0] <= r[1]},
            'albedo_clamped': CLAMPED[0]}
