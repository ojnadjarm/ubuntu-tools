"""Stage lookdev: AAA look preset (grim, painterly, cinematic): reveal light rig with a face key, HDRI, backdrop, AgX, grade."""
import glob
import math
import os

import bpy
from mathutils import Vector

from .. import bpyutil as bu
from .materials import node, principled, srgb_to_linear

NAME = 'lookdev'
CAMERA = 'char3d_cam'
TARGET = 'char3d_target'
SET = 'char3d_set'
HDRI_DIR = os.path.expanduser(os.environ.get('CHAR3D_HDRI_DIR', '~/.local/share/motion-video/hdri/polyhaven'))
CATCHLIGHT = {'offset': (-0.12, 0.1, 0.0), 'energy': 6.0, 'size': 0.12}
POOL_M = (1.2, 4.5)
WHITE = 6.0
OVERRIDES = ('hdri', 'hdri_strength', 'contrast')

# Lights: (name, (x, y, z) in character heights from the root (x = its left, -y = its front), aim role, W, size m, rgb).
# Close shots reuse the rig aimed at the head, energies x close_gain, sizes x 2 so metal highlights do not clip.
# shade: per material kind, base colour (saturation, value) and sheen gain, so each look owns its material response.
LOOKS = {
    'grim': {
        'hdri': 'moonless_golf', 'hdri_strength': 0.25, 'contrast': 'High Contrast', 'practical': 0.35, 'close_gain': 0.7,
        'backdrop': '#4a535f', 'ground': '#1b1d21',
        'shade': {'cloth': (0.45, 0.5, 0.2), 'metal': (0.55, 0.55, 1.0), 'skin': (0.7, 0.85, 1.0), 'hair': (0.6, 0.8, 1.0),
                  'leather': (0.6, 0.6, 1.0), 'wood': (0.6, 0.6, 1.0)},
        'grade': {'saturation': 0.6, 'slope': (0.96, 1.0, 1.06), 'offset': (0.0, 0.0, 0.003), 'power': (1.12, 1.1, 1.06),
                  'bloom': 0.08, 'vignette': 0.45},
        'lights': [('key', (-0.9, -0.75, 1.75), 'head', 130, 0.15, (1.0, 0.86, 0.7)),
                   ('fill', (1.4, -1.0, 0.6), 'chest', 3, 3.0, (0.6, 0.72, 1.0)),
                   ('rim.L', (-1.0, 1.1, 1.35), 'head', 500, 0.4, (0.5, 0.7, 1.0)),
                   ('rim.R', (1.05, 1.0, 1.1), 'chest', 450, 0.4, (0.5, 0.7, 1.0)),
                   ('face_key', (-0.35, -0.8, 0.9), 'head', 22, 0.2, (1.0, 0.88, 0.76))]},
    'painterly': {
        'hdri': 'forest_slope', 'hdri_strength': 0.7, 'contrast': 'Punchy', 'practical': 1.0, 'close_gain': 0.6,
        'backdrop': '#4f7486', 'ground': '#4a3a2c',
        'shade': {'cloth': (1.35, 1.05, 0.8), 'metal': (1.2, 1.0, 1.0), 'skin': (1.15, 1.0, 1.0), 'hair': (1.0, 1.0, 1.0),
                  'leather': (1.2, 1.0, 1.0), 'wood': (1.2, 1.0, 1.0)},
        'grade': {'saturation': 1.2, 'slope': (1.04, 1.0, 0.95), 'offset': (0.004, 0.002, 0.0), 'power': (0.95, 0.95, 0.97),
                  'bloom': 0.35, 'vignette': 0.25},
        'lights': [('key', (-1.2, -1.2, 1.35), 'chest', 170, 3.0, (1.0, 0.78, 0.5)),
                   ('fill', (1.35, -1.0, 0.9), 'chest', 110, 3.0, (0.35, 0.65, 1.0)),
                   ('rim', (0.85, 1.3, 1.4), 'head', 300, 1.5, (0.45, 0.95, 1.0)),
                   ('bounce', (0.0, -1.0, 0.08), 'chest', 40, 3.0, (1.0, 0.6, 0.35)),
                   ('face_key', (-0.4, -0.7, 0.92), 'head', 40, 0.8, (1.0, 0.82, 0.62))]},
    'cinematic': {
        'hdri': 'studio_small_09', 'hdri_strength': 0.2, 'contrast': 'Medium High Contrast', 'practical': 3.0,
        'close_gain': 0.6, 'backdrop': '#3d3646', 'ground': '#221f26',
        'shade': {'cloth': (1.1, 0.75, 0.6), 'metal': (0.9, 0.85, 1.0), 'skin': (1.0, 0.95, 1.0), 'hair': (1.0, 0.95, 1.0),
                  'leather': (1.0, 0.9, 1.0), 'wood': (1.0, 0.9, 1.0)},
        'grade': {'saturation': 0.95, 'slope': (1.03, 1.0, 0.98), 'offset': (0.0, 0.001, 0.004), 'power': (1.0, 1.0, 1.0),
                  'bloom': 0.45, 'vignette': 0.45},
        'lights': [('key', (-0.95, -1.4, 1.5), 'head', 120, 1.8, (1.0, 0.9, 0.8)),
                   ('fill', (1.4, -1.2, 0.9), 'chest', 10, 3.0, (0.82, 0.86, 1.0)),
                   ('rim', (0.9, 1.2, 1.4), 'head', 380, 1.0, (0.8, 0.6, 1.0)),
                   ('kicker', (-1.2, 0.9, 1.0), 'chest', 120, 1.2, (0.62, 0.72, 1.0)),
                   ('face_key', (-0.35, -0.7, 0.92), 'head', 45, 0.6, (1.0, 0.9, 0.8))]},
}


def hdri_path(slug):
    hits = sorted(glob.glob(os.path.join(HDRI_DIR, slug, f'{slug}_*.hdr')))
    if not hits:
        raise FileNotFoundError(f'lookdev: HDRI {slug} not in {HDRI_DIR} (fetch it with gamedev cc0-fetch.sh)')
    return hits[-1]


def world(preset):
    """HDRI lights the scene; camera rays see the flat backdrop so exposure and framing stay controlled."""
    w = bpy.data.worlds.new('char3d_world')
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes['Background']
    env = nt.nodes.new('ShaderNodeTexEnvironment')
    env.image = bpy.data.images.load(hdri_path(preset['hdri']))
    nt.links.new(env.outputs['Color'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = preset['hdri_strength']
    back = node(nt, 'ShaderNodeBackground', Color=srgb_to_linear(preset['backdrop']), Strength=1.0)
    path = nt.nodes.new('ShaderNodeLightPath')
    mix = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(path.outputs['Is Camera Ray'], mix.inputs[0])
    nt.links.new(bg.outputs[0], mix.inputs[1])
    nt.links.new(back.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes['World Output'].inputs['Surface'])
    bpy.context.scene.world = w


def ground(preset):
    """Lit floor pool that fades into the backdrop colour, so no horizon line shows behind the character."""
    n = 64
    ob = bu.mesh_object('ground', [(POOL_M[1] * math.cos(2 * math.pi * i / n), POOL_M[1] * math.sin(2 * math.pi * i / n), 0)
                                   for i in range(n)], [tuple(range(n))], col=SET)
    mat, bsdf = principled('ground', srgb_to_linear(preset['ground']), 0.9, **{'Specular IOR Level': 0.1})
    nt = mat.node_tree
    coord = nt.nodes.new('ShaderNodeTexCoord')
    dist = node(nt, 'ShaderNodeVectorMath')
    dist.operation = 'LENGTH'
    fade = node(nt, 'ShaderNodeMapRange', **{'From Min': POOL_M[0], 'From Max': POOL_M[1]})
    fade.interpolation_type = 'SMOOTHSTEP'
    back = node(nt, 'ShaderNodeEmission', Color=srgb_to_linear(preset['backdrop']), Strength=1.0)
    mix = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(coord.outputs['Object'], dist.inputs[0])
    nt.links.new(dist.outputs['Value'], fade.inputs['Value'])
    nt.links.new(fade.outputs['Result'], mix.inputs[0])
    nt.links.new(bsdf.outputs[0], mix.inputs[1])
    nt.links.new(back.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes['Material Output'].inputs['Surface'])
    ob.data.materials.append(mat)


def area(name, loc, energy, size, color, aim=None, col=SET):
    light = bpy.data.lights.new(name, 'AREA')
    light.energy, light.size, light.color = energy, size, color
    ob = bpy.data.objects.new(name, light)
    bu.collection(col).objects.link(ob)
    ob.location = loc
    if aim is not None:
        ob.rotation_euler = (Vector(aim) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return ob


def rig_name(look, close=False):
    return f"{look}.{'close' if close else 'wide'}"


def rig_for(spec_look, shot_kind):
    """Rig render.py shows for a shot kind: the close variant for close-ups and stills."""
    return rig_name(spec_look['name'], shot_kind in ('closeup', 'still'))


def lights(ctx, look):
    """The look's rig twice (wide, close) in its own collections; apply_rig picks the one that renders."""
    h, preset = ctx.spec['body']['height_m'], LOOKS[look]
    for close in (False, True):
        col = f'char3d_rig_{rig_name(look, close)}'
        for name, (x, y, z), aim, energy, size, color in preset['lights']:
            role = 'head' if close else aim
            k = preset['close_gain'] if close else 1.0
            area(f'{rig_name(look, close)}.{name}', (x * h, y * h, z * h), energy * k, size * (2 if close else 1), color,
                 ctx.landmarks[role], col)
    apply_rig(rig_name(look))


def apply_rig(active):
    """Show one rig; scale practical lights (crystal: any light outside the rigs) by the look's factor (x close_gain close)."""
    look = active.split('.')[0]
    rigs = {c.name for c in bpy.data.collections if c.name.startswith('char3d_rig_')}
    for name in rigs:
        bpy.data.collections[name].hide_render = name != f'char3d_rig_{active}'
    preset = LOOKS[look]
    k = preset['practical'] * (preset['close_gain'] if active.endswith('.close') else 1.0)
    for ob in bpy.data.objects:
        if ob.type == 'LIGHT' and ob.name != 'catchlight' and not rigs & {c.name for c in ob.users_collection}:
            ob.data.diffuse_factor = ob.data.specular_factor = ob.data.volume_factor = k


def camera(ctx):
    """Camera tracking TARGET plus a specular-only catchlight riding beside the lens."""
    target = bpy.data.objects.new(TARGET, None)
    bu.collection(SET).objects.link(target)
    target.location = ctx.landmarks['chest']
    cam = bpy.data.objects.new(CAMERA, bpy.data.cameras.new(CAMERA))
    cam.data.sensor_fit = 'HORIZONTAL'
    bu.collection(SET).objects.link(cam)
    cam.constraints.new('TRACK_TO').target = target
    bpy.context.scene.camera = cam
    catch = area('catchlight', CATCHLIGHT['offset'], CATCHLIGHT['energy'], CATCHLIGHT['size'], (1, 1, 1))
    catch.data.diffuse_factor = 0.0
    catch.data.use_shadow = False
    catch.parent = cam
    return cam


def material_kind(ctx, mat):
    """Spec material kind of a character material (baked `_c3d_tex_<part>.<slot>`, source `<slot>`, `*.cards` = hair)."""
    if mat.name.endswith('.cards'):
        return 'hair'
    slot = mat.name.split('.')[-1] if mat.name.startswith('_c3d_tex_') else mat.name.split('.')[0]
    return ctx.spec.get('materials', {}).get(slot, {}).get('kind')


def shade(ctx, table):
    """HSV on every character Base Color (saturation, value) and a sheen gain, by material kind; returns materials hit."""
    hit = 0
    for mat in bpy.data.materials:
        kind = material_kind(ctx, mat) if mat.node_tree else None
        bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None) if kind in table else None
        if bsdf is None:
            continue
        sat, val, sheen = table[kind]
        nt, base = mat.node_tree, bsdf.inputs['Base Color']
        hsv = node(nt, 'ShaderNodeHueSaturation', Hue=0.5, Saturation=sat, Value=val)
        if base.is_linked:
            nt.links.new(base.links[0].from_socket, hsv.inputs['Color'])
        else:
            hsv.inputs['Color'].default_value = base.default_value
        nt.links.new(hsv.outputs['Color'], base)
        bsdf.inputs['Sheen Weight'].default_value *= sheen
        hit += 1
    return hit


def sock(n, name, kind):
    return next(s for s in n.inputs if s.name == name and s.type == kind)


def grade(g, width, height):
    """Scene-linear grade before AgX: bloom, CDL slope/offset, saturation, vignette, ceiling at WHITE (no clipped metal)."""
    sc = bpy.context.scene
    tree = bpy.data.node_groups.new('char3d_grade', 'CompositorNodeTree')
    sc.compositing_node_group = tree
    sc.render.use_compositing = True
    tree.interface.new_socket('Image', in_out='OUTPUT', socket_type='NodeSocketColor')
    n, ln = tree.nodes, tree.links
    img = n.new('CompositorNodeRLayers').outputs['Image']
    glare = n.new('CompositorNodeGlare')
    glare.inputs['Type'].default_value = 'Bloom'
    glare.inputs['Threshold'].default_value = 1.0
    glare.inputs['Strength'].default_value = g['bloom']
    glare.inputs['Size'].default_value = 0.5
    ln.new(img, glare.inputs['Image'])
    cdl = n.new('CompositorNodeColorBalance')
    cdl.inputs['Type'].default_value = 'Offset/Power/Slope (ASC-CDL)'
    sock(cdl, 'Slope', 'RGBA').default_value = (*g['slope'], 1)
    sock(cdl, 'Offset', 'RGBA').default_value = (*g['offset'], 1)
    sock(cdl, 'Power', 'RGBA').default_value = (*g['power'], 1)
    ln.new(glare.outputs['Image'], cdl.inputs['Image'])
    sat = n.new('CompositorNodeHueSat')
    sat.inputs['Saturation'].default_value = g['saturation']
    ln.new(cdl.outputs['Image'], sat.inputs['Image'])
    ellipse = n.new('CompositorNodeEllipseMask')
    ellipse.inputs['Size'].default_value = (1.0, 1.0)
    blur = n.new('CompositorNodeBlur')
    blur.inputs['Size'].default_value = (0.2 * width, 0.2 * height)
    blur.inputs['Type'].default_value = 'Fast Gaussian'
    gain = n.new('ShaderNodeMapRange')
    gain.inputs['To Min'].default_value = 1.0 - g['vignette']
    mix = n.new('ShaderNodeMix')
    mix.data_type, mix.blend_type = 'RGBA', 'MULTIPLY'
    mix.inputs['Factor'].default_value = 1.0
    ln.new(ellipse.outputs['Mask'], blur.inputs['Image'])
    ln.new(blur.outputs['Image'], gain.inputs['Value'])
    ln.new(sat.outputs['Image'], mix.inputs[6])
    ln.new(gain.outputs['Result'], mix.inputs[7])
    ceil = n.new('ShaderNodeVectorMath')
    ceil.operation = 'MINIMUM'
    ceil.inputs[1].default_value = (WHITE, WHITE, WHITE)
    ln.new(mix.outputs[2], ceil.inputs[0])
    ln.new(ceil.outputs[0], n.new('NodeGroupOutput').inputs[0])


def settings(ctx, look, preset):
    sc = bpy.context.scene
    tier = 'draft' if ctx.draft else 'final'
    sc.render.engine = look['engine']
    w, h = look.get('size', {}).get(tier, [960, 540] if ctx.draft else [1920, 1080])
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = w, h, 100
    samples = look.get('samples', {}).get(tier, 16 if ctx.draft else 32)
    if look['engine'] == 'CYCLES':
        sc.cycles.samples = samples
    else:
        sc.eevee.taa_render_samples = samples
        sc.eevee.use_raytracing = look.get('raytrace', False)
        sc.eevee.use_shadows = True
    sc.view_settings.view_transform = look.get('view', 'AgX')
    if sc.view_settings.view_transform == 'AgX':
        sc.view_settings.look = f"AgX - {preset['contrast']}"
    sc.render.film_transparent = False
    sc.render.motion_blur_shutter = 0.5
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    sc.render.image_settings.compression = 15
    return w, h, samples


def run(ctx):
    """The preset named by look.name owns rig, HDRI, backdrop, AgX look and grade; spec.look may override hdri, hdri_strength, contrast."""
    look = ctx.spec['look']
    preset = {**LOOKS[look['name']], **{k: look[k] for k in OVERRIDES if k in look}}
    world(preset)
    shaded = shade(ctx, preset['shade'])
    ground(preset)
    lights(ctx, look['name'])
    camera(ctx)
    w, h, samples = settings(ctx, look, preset)
    grade(preset['grade'], w, h)
    return {'stub': False, 'look': look['name'], 'rig': rig_name(look['name']),
            'rigs': [rig_name(look['name']), rig_name(look['name'], True)], 'hdri': preset['hdri'],
            'lights': len(preset['lights']) + 1, 'shaded': shaded, 'size': [w, h], 'samples': samples, 'grade': preset['grade'],
            'view': f'{bpy.context.scene.view_settings.view_transform} / {bpy.context.scene.view_settings.look}'}
