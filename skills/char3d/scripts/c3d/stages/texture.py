"""Stage texture: per-set PBR materials from the baked maps (kind SSS/sheen kept, tiling detail normals, painterly option)."""
import bpy
import numpy as np

from .materials import DIELECTRIC, METAL, MICRO, finish, linear, lum, maprange, math_op, ramp, srgb

NAME = 'texture'
KEEP = {'eye', 'glass', 'hair'}
FALLBACK = {'kind': 'cloth', 'color': '#808080'}
FLAT = (0.5, 0.5, 1.0, 1.0)
OWNED_ID, OWNED = 'mouth', {'kind': 'skin', 'color': '#b89080', 'roughness': 0.3}


def grid(n):
    y, x = (np.mgrid[0:n, 0:n] + 0.5) / n
    return x, y


def band_noise(rng, n, freq, stretch=1.0):
    """Tileable band-limited noise (unit std) around `freq` cycles per tile; stretch > 1 elongates it along V."""
    f = np.fft.fftfreq(n) * n
    r = np.hypot(f[None, :], f[:, None] * stretch)
    h = np.real(np.fft.ifft2(np.fft.fft2(rng.standard_normal((n, n))) * np.exp(-((r - freq) / (0.5 * freq + 1)) ** 2)))
    return (h - h.mean()) / (h.std() + 1e-9)


def cells(rng, n, count):
    """Wrapped Voronoi F1, F2 distances (tile units) for `count` random sites."""
    x, y = grid(n)
    f1, f2 = np.full((n, n), 9.0), np.full((n, n), 9.0)
    for px, py in rng.random((count, 2)):
        dx, dy = x - px, y - py
        d = np.hypot(dx - np.round(dx), dy - np.round(dy))
        f2 = np.minimum(f2, np.maximum(f1, d))
        f1 = np.minimum(f1, d)
    return f1, f2


def weave(rng, n):
    """Plain over-under weave, 16 threads per tile, with fibre noise."""
    x, y = grid(n)
    fx, fy, ix, iy = (x * 16) % 1, (y * 16) % 1, np.floor(x * 16), np.floor(y * 16)
    ply = lambda f: np.sin(np.pi * f) * (0.8 + 0.2 * np.abs(np.sin(3 * np.pi * f)))
    warp, weft = ply(fx) * (0.6 + 0.4 * np.sin(np.pi * fy)), ply(fy) * (0.6 + 0.4 * np.sin(np.pi * fx))
    return np.where((ix + iy) % 2 == 0, warp, weft) + 0.04 * band_noise(rng, n, n / 6)


def pores(rng, n):
    """Pore dimples, two crossing sets of fine skin lines, soft micro relief."""
    f1, _ = cells(rng, n, 180)
    x, y = grid(n)
    warp = 0.6 * band_noise(rng, n, 3)
    lines = np.sin(2 * np.pi * (5 * x + 7 * y) + warp) + np.sin(2 * np.pi * (-6 * x + 4 * y) + warp)
    return -np.exp(-(f1 / 0.01) ** 2) + 0.03 * lines + 0.04 * band_noise(rng, n, 40)


def leather(rng, n):
    """Pebbled grain: raised cells split by creases, plus mottling."""
    f1, f2 = cells(rng, n, 90)
    return np.clip((f2 - f1) / 0.02, 0, 1) + 0.15 * band_noise(rng, n, 20)


def wood(rng, n):
    """Grain streaks along V with pore lines."""
    return band_noise(rng, n, 12, 10.0) + 0.3 * band_noise(rng, n, 60, 12.0)


def scratches(rng, n):
    """Random fine scratches (wrapped segments) over faint polishing noise."""
    x, y = grid(n)
    h = 0.05 * band_noise(rng, n, 30)
    for _ in range(50):
        p, a, length = rng.random(2), rng.random() * np.pi, 0.05 + 0.25 * rng.random()
        d = np.array([np.cos(a), np.sin(a)])
        dx, dy = x - p[0], y - p[1]
        dx, dy = dx - np.round(dx), dy - np.round(dy)
        s = np.clip(dx * d[0] + dy * d[1], -length / 2, length / 2)
        h -= rng.uniform(0.3, 1.0) * np.exp(-(np.hypot(dx - s * d[0], dy - s * d[1]) * n / 0.9) ** 2)
    return h


def hammered(rng, n):
    """Hammer dents: a concave dish per Voronoi cell."""
    f1, _ = cells(rng, n, 40)
    return (f1 / f1.max()) ** 2


DETAIL = {'weave': weave, 'pores': pores, 'leather': leather, 'wood': wood, 'scratches': scratches, 'hammered': hammered}


def to_normal(h):
    """Tangent-space (OpenGL, +Y up) normal map of a tiling height field; 95th-percentile slope tilts ~35 deg."""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / 2
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / 2
    k = 0.7 / (np.percentile(np.hypot(gx, gy), 95) + 1e-9)
    nrm = np.dstack([-k * gx, -k * gy, np.ones_like(h)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    return nrm * 0.5 + 0.5


def detail_map(folder, kind, n):
    """Write <out>/textures/detail_<kind>.png (Non-Color, tiling) and return the image."""
    rgb = to_normal(DETAIL[kind](np.random.default_rng(sorted(DETAIL).index(kind)), n))
    img = bpy.data.images.new(f'detail_{kind}', n, n, alpha=False)
    img.colorspace_settings.name = 'Non-Color'
    img.pixels.foreach_set(np.dstack([rgb, np.ones((n, n))]).astype(np.float32).ravel())
    img.filepath_raw, img.file_format = str(folder / f'detail_{kind}.png'), 'PNG'
    img.save()
    return img


def rnm_group():
    """Node group: reoriented normal mapping of a tangent-space detail colour onto a base one (Base path first)."""
    ng = bpy.data.node_groups.get('c3d_rnm')
    if ng:
        return ng
    ng = bpy.data.node_groups.new('c3d_rnm', 'ShaderNodeTree')
    for name, kind in (('Base', 'NodeSocketColor'), ('Detail', 'NodeSocketColor'), ('Strength', 'NodeSocketFloat')):
        ng.interface.new_socket(name=name, in_out='INPUT', socket_type=kind)
    ng.interface.new_socket(name='Color', in_out='OUTPUT', socket_type='NodeSocketColor')
    gi, go = ng.nodes.new('NodeGroupInput'), ng.nodes.new('NodeGroupOutput')

    def vm(op, a, b=None, c=None):
        n = ng.nodes.new('ShaderNodeVectorMath')
        n.operation = op
        for i, v in ((0, a), (1, b), (2, c)):
            if v is None:
                continue
            if isinstance(v, tuple):
                n.inputs[i].default_value = v
            else:
                ng.links.new(v, n.inputs[i])
        return n

    mix = ng.nodes.new('ShaderNodeMix')
    mix.data_type = 'VECTOR'
    mix.inputs['A'].default_value = FLAT[:3]
    ng.links.new(gi.outputs['Strength'], mix.inputs['Factor'])
    ng.links.new(gi.outputs['Detail'], mix.inputs['B'])
    t = vm('MULTIPLY_ADD', gi.outputs['Base'], (2.0, 2.0, 2.0), (-1.0, -1.0, 0.0)).outputs['Vector']
    u = vm('MULTIPLY_ADD', mix.outputs['Result'], (-2.0, -2.0, 2.0), (1.0, 1.0, -1.0)).outputs['Vector']
    dot = vm('DOT_PRODUCT', t, u).outputs['Value']
    tz = ng.nodes.new('ShaderNodeSeparateXYZ')
    ng.links.new(t, tz.inputs[0])
    a = vm('SCALE', t)
    ng.links.new(dot, a.inputs['Scale'])
    c = vm('SCALE', u)
    ng.links.new(tz.outputs['Z'], c.inputs['Scale'])
    r = vm('NORMALIZE', vm('SUBTRACT', a.outputs['Vector'], c.outputs['Vector']).outputs['Vector'])
    out = vm('MULTIPLY_ADD', r.outputs['Vector'], (0.5, 0.5, 0.5), (0.5, 0.5, 0.5))
    ng.links.new(out.outputs['Vector'], go.inputs['Color'])
    return ng


def image(nt, path_or_img, colourspace):
    n = nt.nodes.new('ShaderNodeTexImage')
    n.image = path_or_img if isinstance(path_or_img, bpy.types.Image) else bpy.data.images.load(path_or_img, check_existing=True)
    n.image.colorspace_settings.name = colourspace
    return n


def detail_layer(nt, base, img, d):
    """Tile the detail map `scale` times per UV unit and RNM-blend it over the base normal colour at `strength`."""
    uv = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    s = d.get('scale', 100.0)
    mp.inputs['Scale'].default_value = (s, s, 1.0)
    nt.links.new(uv.outputs['UV'], mp.inputs['Vector'])
    tile = image(nt, img, 'Non-Color')
    nt.links.new(mp.outputs['Vector'], tile.inputs['Vector'])
    g = nt.nodes.new('ShaderNodeGroup')
    g.node_tree = rnm_group()
    nt.links.new(base, g.inputs['Base'])
    nt.links.new(tile.outputs['Color'], g.inputs['Detail'])
    g.inputs['Strength'].default_value = d.get('strength', 0.3)
    return g.outputs['Color']


def gradient(nt, alb, occ, m, top):
    """Painterly gradient map: albedo tinted cool-violet in occluded, low areas and warm on lit, high ones, re-clamped."""
    metal = m['kind'] == 'metal'
    pos = nt.nodes.new('ShaderNodeNewGeometry')
    z = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(pos.outputs['Position'], z.inputs[0])
    f = math_op(nt, 'MULTIPLY', occ, maprange(nt, z.outputs['Z'], 0.0, top, 0.55, 1.0, smooth=False))
    floor = min(1.0, 170.0 / max(lum(srgb(m['color'])), 1.0)) if metal else 0.0
    shadow = [max(c, floor) for c in (0.55, 0.5, 0.72)]
    tint = ramp(nt, f, [(0.0, shadow + [1.0]), (0.55, [1.0, 1.0, 1.0, 1.0]), (1.0, [1.12, 1.06, 0.94, 1.0])])
    out = alb
    for op, val in (('MULTIPLY', None), ('MINIMUM', linear([250 if metal else 240] * 3)[:3]),
                    ('MAXIMUM', linear([0 if metal else 30] * 3)[:3])):
        n = nt.nodes.new('ShaderNodeVectorMath')
        n.operation = op
        nt.links.new(out, n.inputs[0])
        if val is None:
            nt.links.new(tint, n.inputs[1])
        else:
            n.inputs[1].default_value = val
        out = n.outputs['Vector']
    return out


def set_material(sid, t, mid, m, details, maps, paint, top):
    """Principled fed by the set's albedo, ORM (R AO, G rough, B metal: metal kinds only), normal (+ detail RNM), emissive."""
    mat = bpy.data.materials.new(f'_c3d_tex_{sid}.{mid}')
    mat.use_nodes = True
    nt = mat.node_tree
    b = nt.nodes['Principled BSDF']
    orm = nt.nodes.new('ShaderNodeSeparateColor')
    nt.links.new(image(nt, t['orm'], 'Non-Color').outputs['Color'], orm.inputs['Color'])
    alb = image(nt, t['albedo'], 'sRGB').outputs['Color']
    if paint == 'gradient':
        alb = gradient(nt, alb, orm.outputs['Red'], m, top)
    nt.links.new(alb, b.inputs['Base Color'])
    nt.links.new(orm.outputs['Green'], b.inputs['Roughness'])
    if m['kind'] == 'metal':
        nt.links.new(orm.outputs['Blue'], b.inputs['Metallic'])
    else:
        b.inputs['Metallic'].default_value = 0.0
    col = image(nt, t['normal'], 'Non-Color').outputs['Color']
    for d in details:
        col = detail_layer(nt, col, maps[d['kind']], d)
    nm = nt.nodes.new('ShaderNodeNormalMap')
    nt.links.new(col, nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'], b.inputs['Normal'])
    nt.links.new(image(nt, t['emissive'], 'sRGB').outputs['Color'], b.inputs['Emission Color'])
    b.inputs['Emission Strength'].default_value = 1.0
    finish(mat, b, m)
    return mat


def base_id(mat, mats):
    """Spec material id behind a slot (skin.lips, _c3d_tex_body.skin -> skin), or None for a stage-owned material."""
    if mat is None:
        return None
    name = mat.name.split('.', 1)[-1] if mat.name.startswith('_c3d_tex_') else mat.name
    head = name.split('.')[0]
    return head if head in mats else None


def set_mids(ctx, t, mats):
    """Spec materials on the set's parts, first the one the bake used (first part material)."""
    out = [ctx.parts[p]['material'] for p in t['parts'] if ctx.parts[p]['material'] in mats
           and mats[ctx.parts[p]['material']]['kind'] not in KEEP][:1]
    for pid in t['parts']:
        ob = bpy.data.objects[ctx.parts[pid]['object']]
        for mat in getattr(ob.data, 'materials', []):
            mid = base_id(mat, mats)
            if mid and mid not in out and mats[mid]['kind'] not in KEEP:
                out.append(mid)
    return out


def swap(ctx, t, variants):
    """Point every slot of the set's parts that shows a spec material at that material's set variant."""
    n = 0
    for pid in t['parts']:
        ob = bpy.data.objects[ctx.parts[pid]['object']]
        slots = getattr(ob.data, 'materials', [])
        for i, mat in enumerate(slots):
            mid = base_id(mat, variants)
            if mid:
                slots[i] = variants[mid]
                n += 1
    return n


def stage_owned(ctx, t, mats):
    """Opaque stage-owned slots (teeth, gums, tongue) of the set's parts, not on an eye bone: (object, slot index)."""
    out = []
    for pid in t['parts']:
        if (ctx.parts[pid].get('attach') or '').startswith('eye'):
            continue
        ob = bpy.data.objects[ctx.parts[pid]['object']]
        for i, mat in enumerate(getattr(ob.data, 'materials', [])):
            b = mat and mat.node_tree and mat.node_tree.nodes.get('Principled BSDF')
            if b and base_id(mat, mats) is None and not mat.name.startswith('_c3d_tex_') \
                    and not b.inputs['Alpha'].is_linked and b.inputs['Alpha'].default_value >= 1.0 \
                    and mat.surface_render_method != 'BLENDED':
                out.append((ob, i))
    return out


def measure(t):
    """Baked albedo over covered texels (black = empty gutter): sRGB p1-p99 of dielectric channels (ORM blue < 0.1) and
    of metal luminance (> 0.9), the % of covered texels outside 30-240 / 170-250, and the % of mixed metal-edge texels."""
    def px(key):
        img = bpy.data.images.load(t[key], check_existing=True)
        a = np.empty(len(img.pixels), np.float32)
        img.pixels.foreach_get(a)
        return a.reshape(-1, img.channels)[:, :3]

    rgb, metal = np.round(px('albedo') * 255), px('orm')[:, 2]
    cov = rgb.max(1) > 0.5
    die, met = rgb[cov & (metal < 0.1)], lum((rgb[cov & (metal > 0.9)]).T)
    out = ((die < DIELECTRIC[0]) | (die > DIELECTRIC[1])).any(1).sum() + ((met < METAL[0]) | (met > METAL[1])).sum()
    band = lambda v: [round(float(x), 1) for x in np.percentile(v, (1, 99))] if v.size else None  # noqa: E731
    return {'covered_pct': round(100 * float(cov.mean()), 1), 'dielectric': band(die), 'metal_lum': band(met),
            'out_pct': round(100 * float(out) / max(int(cov.sum()), 1), 2),
            'mixed_pct': round(100 * float((cov & (metal >= 0.1) & (metal <= 0.9)).sum()) / max(int(cov.sum()), 1), 2)}


def run(ctx):
    tx = ctx.spec.get('textures', {})
    mats = ctx.spec['materials']
    bpy.context.scene[MICRO] = 1.0
    dns = [d for d in tx.get('detail_normals', []) if d['material'] in mats]
    folder = ctx.out / 'textures'
    folder.mkdir(parents=True, exist_ok=True)
    size = 512 if ctx.draft else 1024
    maps = {k: detail_map(folder, k, size) for k in sorted({d['kind'] for d in dns})}
    paint, top = tx.get('paint', 'none'), ctx.landmarks.get('head', [0, 0, 1.7])[2] + 0.15
    built = swapped = 0
    wired, variants_n, albedo = set(), 0, {}
    for sid, t in ctx.textures.items():
        if 'albedo' not in t:
            continue
        mids = set_mids(ctx, t, mats)
        variants = {}
        for mid in mids or [None]:
            details = [d for d in dns if d['material'] == mid]
            wired |= {id(d) for d in details}
            variants[mid] = set_material(sid, t, mid or 'default', mats.get(mid, FALLBACK), details, maps, paint, top)
        owned = stage_owned(ctx, t, mats) if mids and not t.get('stub') and tx.get('use_baked', True) else []
        if owned:
            variants[OWNED_ID] = set_material(sid, t, OWNED_ID, OWNED, [], maps, paint, top)
            for ob, i in owned:
                ob.data.materials[i] = variants[OWNED_ID]
            swapped += len(owned)
        t['material'] = variants[(mids or [None])[0]].name
        t['materials'] = {k or 'default': v.name for k, v in variants.items()}
        built, variants_n = built + 1, variants_n + len(variants)
        if not t.get('stub'):
            albedo[sid] = measure(t)
        if t.get('stub') or not tx.get('use_baked', True):
            continue
        swapped += swap(ctx, t, {k: v for k, v in variants.items() if k in mats and mats[k]['kind'] not in KEEP})
    return {'stub': False, 'built': built, 'variants': variants_n, 'swapped': swapped, 'detail_normals': len(wired),
            'detail_maps': {k: str(folder / f'detail_{k}.png') for k in maps}, 'detail_px': size, 'paint': paint,
            'albedo_baked': albedo}
