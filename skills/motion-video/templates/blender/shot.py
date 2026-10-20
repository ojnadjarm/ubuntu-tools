"""Procedural 5 s product-style shot: bevelled blocks and glossy sphere (or the extruded brand logo, MV_LOGO, or a glTF hero model, MV_MODEL, playing clip MV_MODEL_ANIM), kinetic 3D title (MV_TITLE from MV_TITLE_CUE in MV_CUES), emissive ring (behind the logo; MV_RING=0 hides it), camera move (MV_CAMERA dolly|orbit|crane|push|handheld), compositor look (MV_LOOK none|soft|filmic), volumetric haze with backlit light shafts (MV_FOG density); renders MV_DEPTH 16|8-bit PNG frames; MV_DRAFT=1: look off, 8-bit, 4 spp, small shadow pool, persistent data."""
import glob
import json
import math
import os
import subprocess
import sys

import bpy

from bpy_extras import anim_utils
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = args[0] if args and not args[0].startswith("--") else "/tmp/mv-blender/frame_"
dump_camera = args[args.index("--dump-camera") + 1] if "--dump-camera" in args else ""
camera_move = os.environ.get("MV_CAMERA", "dolly")
camera_ease = os.environ.get("MV_CAMERA_EASE", "ease")
engine = os.environ.get("MV_ENGINE", "EEVEE")
fps = int(os.environ.get("MV_FPS", "60"))
seconds = float(os.environ.get("MV_SECONDS", "5"))
width, height = (int(v) for v in os.environ.get("MV_SIZE", "1920x1080").split("x"))
samples = os.environ.get("MV_SAMPLES", "auto")
samples = int(samples) if samples != "auto" else 32 if engine == "CYCLES" else 16
draft = os.environ.get("MV_DRAFT") == "1"
shutter = 0.0 if draft else float(os.environ.get("MV_SHUTTER", "0.5"))
if draft:
    samples = 4
hdri = os.environ.get("MV_HDRI", "")
catcher = os.environ.get("MV_GROUND") == "catcher"
brand_file = os.environ.get("MV_BRAND", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "brand.json"))
brand = json.load(open(brand_file)) if os.path.isfile(brand_file) else {}
model = os.environ.get("MV_MODEL", "")
model_height = float(os.environ.get("MV_MODEL_HEIGHT", "2.0"))
model_anim = os.environ.get("MV_MODEL_ANIM", "")
model_anim_speed = float(os.environ.get("MV_MODEL_ANIM_SPEED", "1.0"))
logo = "" if model else os.environ.get("MV_LOGO") or (os.path.join(os.path.dirname(brand_file), brand["logo"]) if brand.get("logo") else "")
logo_depth = float(os.environ.get("MV_LOGO_DEPTH", "0.35"))
show_ring = os.environ.get("MV_RING", "1") != "0"
title = os.environ.get("MV_TITLE", "")
depth = os.environ.get("MV_DEPTH", "16")
look = os.environ.get("MV_LOOK", "none")
vignette = float(os.environ.get("MV_VIGNETTE", "0.15"))
fog = float(os.environ.get("MV_FOG", "0"))
if look not in ("none", "soft", "filmic") or depth not in ("8", "16"):
    sys.exit("shot.py: MV_LOOK none|soft|filmic, MV_DEPTH 8|16")
if draft:
    look, depth = "none", "8"

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
eevee_ids = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
scene.render.engine = "CYCLES" if engine == "CYCLES" else next(e for e in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT") if e in eevee_ids)
if engine == "CYCLES":
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
else:
    scene.eevee.taa_render_samples = samples
    scene.eevee.use_raytracing = os.environ.get("MV_RAYTRACE", "0") == "1" and not draft
    if draft:
        scene.eevee.shadow_pool_size, scene.eevee.shadow_resolution_scale = "16", 0.25
        scene.eevee.shadow_ray_count = scene.eevee.shadow_step_count = scene.eevee.volumetric_samples = 1
scene.render.use_persistent_data = draft
scene.render.use_motion_blur = shutter > 0
scene.render.motion_blur_shutter = shutter or 0.5
scene.render.fps = fps
scene.frame_start, scene.frame_end = 1, int(fps * seconds)
scene.render.resolution_x, scene.render.resolution_y = width, height
scene.render.resolution_percentage = 50 if draft else 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_depth = depth
scene.render.filepath = out
scene.render.use_overwrite = os.environ.get("MV_RESUME") != "1"
scene.render.use_placeholder = not scene.render.use_overwrite
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
if logo or model:
    scene.view_settings.view_transform = "Khronos PBR Neutral"



def hdri_path(ref):
    """Return a local .hdr/.exr: the file itself, or a Poly Haven slug fetched once (CC0, licence logged)."""
    if os.path.isfile(ref):
        return ref
    lib = os.path.expanduser("~/.local/share/motion-video/hdri")
    hits = glob.glob(f"{lib}/polyhaven/{ref}/*.hdr")
    if not hits:
        fetch = os.path.expanduser("~/agents/skills/gamedev/scripts/cc0-fetch.sh")
        subprocess.run(["bash", fetch, "polyhaven", ref, lib, "--res", "2k"], check=True)
        hits = glob.glob(f"{lib}/polyhaven/{ref}/*.hdr")
    return hits[0]


world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.012, 0.014, 0.022, 1)
if hdri:
    wn, wl = world.node_tree.nodes, world.node_tree.links
    env = wn.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(hdri_path(hdri))
    mapping = wn.new("ShaderNodeMapping")
    mapping.inputs["Rotation"].default_value[2] = math.radians(float(os.environ.get("MV_HDRI_ROT", "0")))
    wl.new(wn.new("ShaderNodeTexCoord").outputs["Generated"], mapping.inputs["Vector"])
    wl.new(mapping.outputs["Vector"], env.inputs["Vector"])
    wl.new(env.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = float(os.environ.get("MV_HDRI_STRENGTH", "1.0"))


def shadow_catcher_compositor(tree, layers):
    """EEVEE catcher: alpha = max(object alpha, 1 - shadow pass) over the held-out floor; returns the image socket."""
    scene.view_layers[0].use_pass_shadow = True
    n, ln = tree.nodes, tree.links
    lit = n.new("CompositorNodeSeparateColor")
    shade = n.new("ShaderNodeMath")
    shade.operation = "SUBTRACT"
    shade.inputs[0].default_value = 1.0
    alpha = n.new("ShaderNodeMath")
    alpha.operation = "MAXIMUM"
    set_alpha = n.new("CompositorNodeSetAlpha")
    set_alpha.inputs["Type"].default_value = "Replace Alpha"
    ln.new(layers.outputs["Shadow"], lit.inputs[0])
    ln.new(lit.outputs[0], shade.inputs[1])
    ln.new(shade.outputs[0], alpha.inputs[0])
    ln.new(layers.outputs["Alpha"], alpha.inputs[1])
    ln.new(layers.outputs["Image"], set_alpha.inputs["Image"])
    ln.new(alpha.outputs[0], set_alpha.inputs["Alpha"])
    return set_alpha.outputs[0]


def look_compositor(tree, image):
    """Soft: bloom; filmic: fog glow + lens dispersion 0.01; both glow above 1.0 and darken the corners by MV_VIGNETTE; returns the image socket."""
    n, ln = tree.nodes, tree.links
    glare = n.new("CompositorNodeGlare")
    glare.inputs["Type"].default_value = "Bloom" if look == "soft" else "Fog Glow"
    glare.inputs["Threshold"].default_value = 1.0
    glare.inputs["Strength"].default_value = 0.5 if look == "soft" else 1.0
    glare.inputs["Size"].default_value = 0.1
    ln.new(image, glare.inputs["Image"])
    image = glare.outputs["Image"]
    if look == "filmic":
        lens = n.new("CompositorNodeLensdist")
        lens.inputs["Dispersion"].default_value = 0.01
        lens.inputs["Fit"].default_value = True
        ln.new(image, lens.inputs["Image"])
        image = lens.outputs["Image"]
    if vignette <= 0:
        return image
    ellipse = n.new("CompositorNodeEllipseMask")
    ellipse.inputs["Size"].default_value = (1.0, 1.0)
    blur = n.new("CompositorNodeBlur")
    blur.inputs["Size"].default_value = (0.2 * width, 0.2 * height)
    blur.inputs["Type"].default_value = "Fast Gaussian"
    gain = n.new("ShaderNodeMapRange")
    gain.inputs["To Min"].default_value = 1.0 - vignette
    mix = n.new("ShaderNodeMix")
    mix.data_type, mix.blend_type = "RGBA", "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    ln.new(ellipse.outputs["Mask"], blur.inputs["Image"])
    ln.new(blur.outputs["Image"], gain.inputs["Value"])
    ln.new(image, mix.inputs[6])
    ln.new(gain.outputs["Result"], mix.inputs[7])
    return mix.outputs[2]


def material(name, color, metallic=0.0, rough=0.35, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*color, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


floor_mat = material("Floor", (0.02, 0.022, 0.03), rough=0.18)
bpy.ops.mesh.primitive_plane_add(size=40)
floor = bpy.context.object
floor.data.materials.append(floor_mat)
if catcher:
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = "RGBA"
    if engine == "CYCLES":
        floor.is_shadow_catcher = True
    else:
        floor.is_holdout = True


def srgb(hex_colour):
    """Linear RGB of an sRGB hex colour."""
    c = [int(hex_colour.lstrip("#")[k:k + 2], 16) / 255 for k in (0, 2, 4)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


if not logo and not model:
    palette = [(1.0, 0.18, 0.08), (1.0, 0.62, 0.05), (0.09, 0.25, 1.0)]
    for i, c in enumerate(palette):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(-2.2 + i * 2.2, 0, 0.5))
        o = bpy.context.object
        o.scale = (1, 1, 1 + i * 0.6)
        o.location.z = o.scale.z / 2
        o.modifiers.new("Bevel", "BEVEL").width = 0.06
        o.modifiers["Bevel"].segments = 4
        o.data.materials.append(material(f"Block{i}", c, rough=0.25))
        o.rotation_euler.z = 0
        o.keyframe_insert("rotation_euler", frame=1)
        o.rotation_euler.z = math.radians(90 + i * 30)
        o.keyframe_insert("rotation_euler", frame=scene.frame_end)
        bpy.ops.object.shade_smooth()

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.7, segments=96, ring_count=48, location=(0, -1.8, 0.7))
    bpy.context.object.data.materials.append(material("Chrome", (0.9, 0.9, 0.92), metallic=1.0, rough=0.08))
    bpy.ops.object.shade_smooth()

ring_mat = material("Ring", (1.0, 0.75, 0.35), emit=12.0)
ring = None
if show_ring and not logo and not model:
    bpy.ops.mesh.primitive_torus_add(major_radius=3.2, minor_radius=0.03, location=(0, 0, 1.6))
    ring = bpy.context.object
    ring.data.materials.append(ring_mat)
    ring.rotation_euler = (math.radians(75), 0, 0)
    ring.keyframe_insert("rotation_euler", frame=1)
    ring.rotation_euler = (math.radians(75), math.radians(40), math.radians(180))
    ring.keyframe_insert("rotation_euler", frame=scene.frame_end)

bpy.ops.object.light_add(type="AREA", location=(4, -4, 6))
key = bpy.context.object
key.data.energy, key.data.size = 1500, 4
key.rotation_euler = (math.radians(45), 0, math.radians(45))
bpy.ops.object.light_add(type="AREA", location=(-5, 3, 3))
rim = bpy.context.object
rim.data.energy, rim.data.size, rim.data.color = 900, 3, (0.4, 0.55, 1.0)
rim.rotation_euler = (math.radians(70), 0, math.radians(-120))
rim.data.use_shadow = not catcher


def fog_volume(density):
    """World Principled Volume of the given density, forward-scattering, plus a volume-only spot behind the hero whose occluded beams read as light shafts."""
    wn = world.node_tree.nodes
    vol = wn.new("ShaderNodeVolumePrincipled")
    vol.inputs["Density"].default_value = density
    vol.inputs["Anisotropy"].default_value = 0.6
    world.node_tree.links.new(vol.outputs[0], wn["World Output"].inputs["Volume"])
    scene.eevee.volumetric_tile_size, scene.eevee.volumetric_samples = "4", 64
    bpy.ops.object.light_add(type="SPOT", location=(1, 8, 6))
    shaft = bpy.context.object
    shaft.data.energy, shaft.data.spot_size, shaft.data.shadow_soft_size = 20000, math.radians(50), 0.05
    shaft.data.diffuse_factor = shaft.data.specular_factor = 0.0
    shaft.rotation_euler = (Vector((-3, -6, 0)) - shaft.location).to_track_quat("-Z", "Y").to_euler()


if fog > 0:
    fog_volume(fog)

bpy.ops.object.empty_add(location=(0, 0, 1))
target = bpy.context.object
bpy.ops.object.camera_add()
cam = bpy.context.object
scene.camera = cam
cam.data.lens = float(os.environ.get("MV_LENS", "40"))
cam.data.dof.use_dof = True
cam.data.dof.focus_object = target
cam.data.dof.aperture_fstop = float(os.environ.get("MV_FSTOP", "2.8"))
track = cam.constraints.new("TRACK_TO")
track.target = target

CAMERA_MOVES = {
    "dolly": ((-7, -9, 2.2), (6, -8.5, 3.6)),
    "crane": ((0.5, -8, 0.4), (0.5, -6.5, 6.5)),
    "push": ((-4.5, -11, 3.0), (-2.25, -5.5, 2.0)),
    "handheld": ((-3, -8, 2.0), (-2.4, -6.8, 1.9)),
}


def ease_keys(obj):
    """Set every key of obj to the MV_CAMERA_EASE curve: linear, ease (Bezier auto-clamped) or expo in-out."""
    ad = obj.animation_data
    fcurves = anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot).fcurves
    for fc in fcurves:
        for k in fc.keyframe_points:
            k.interpolation = {"linear": "LINEAR", "expo": "EXPO"}.get(camera_ease, "BEZIER")
            k.easing = "EASE_IN_OUT"
            k.handle_left_type = k.handle_right_type = "AUTO_CLAMPED"
    return fcurves


if camera_move == "orbit":
    bpy.ops.object.empty_add(location=target.location)
    pivot = bpy.context.object
    cam.parent = pivot
    cam.location = (0, -10, 1.6)
    for f, deg in ((1, -40), (scene.frame_end, 80)):
        pivot.rotation_euler.z = math.radians(deg)
        pivot.keyframe_insert("rotation_euler", index=2, frame=f)
    ease_keys(pivot)
else:
    for f, loc in zip((1, scene.frame_end), CAMERA_MOVES[camera_move]):
        cam.location = loc
        cam.keyframe_insert("location", frame=f)
    for axis, fc in enumerate(ease_keys(cam)):
        if camera_move == "handheld":
            shake = fc.modifiers.new("NOISE")
            shake.scale, shake.strength, shake.phase = fps * 0.6, 0.12, 7 + axis * 13
            shake.use_restricted_range = True
            shake.frame_start, shake.frame_end = scene.frame_start, scene.frame_end
            shake.blend_out = 0.4 * (scene.frame_end - scene.frame_start)


def frame_scale(w, h):
    """World units per unit of a w x h shape that fills 75 % x 55 % of the frame at the camera's closest approach."""
    dist = []
    for f in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(f)
        dist.append((cam.matrix_world.translation - target.location).length)
    scene.frame_set(scene.frame_start)
    wide = 2 * min(dist) * math.tan(cam.data.angle / 2)
    short = wide * min(width, height) / max(width, height)
    frame_w, frame_h = (wide, short) if width >= height else (short, wide)
    return min(0.75 * frame_w / w, 0.55 * frame_h / h)


def logo_hero(svg):
    """Import svg, join its curves, scale to frame, extrude MV_LOGO_DEPTH with a bevel; caps brand accent[0] (primary), sides accent[1]; stands on the floor at the target."""
    accents = brand.get("palette", {}).get("accent", ["#ff5a36", "#ffc233"])
    bpy.ops.import_curve.svg(filepath=svg)
    curves = [o for o in scene.objects if o.type == "CURVE"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in curves:
        o.select_set(True)
    bpy.context.view_layer.objects.active = curves[0]
    bpy.ops.object.join()
    o = bpy.context.object
    k = frame_scale(o.dimensions.x, o.dimensions.y) * (0.65 if title else 1.0)
    o.scale = (k,) * 3
    o.data.bevel_depth = logo_depth * 0.12 / k
    o.data.extrude = logo_depth / 2 / k - o.data.bevel_depth
    o.data.bevel_resolution = 3
    bpy.ops.object.convert(target="MESH")
    o.data.materials.clear()
    o.data.materials.append(material("LogoPrimary", srgb(accents[0]), rough=0.3))
    o.data.materials.append(material("LogoAccent", srgb(accents[1 % len(accents)]), metallic=0.6, rough=0.22))
    for f in o.data.polygons:
        f.material_index = 0 if abs(f.normal.z) > 0.999 else 1
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    o.location = (0, 0, o.dimensions.y / 2 + 0.15)
    target.location.z = o.location.z
    o.rotation_euler = (math.radians(90), 0, math.radians(-12))
    o.keyframe_insert("rotation_euler", frame=1)
    o.rotation_euler.z = math.radians(12)
    o.keyframe_insert("rotation_euler", frame=scene.frame_end)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    return o


def scale_move(s, pivot):
    """Scale the camera path by s about pivot and carry it onto the target."""
    if cam.parent:
        cam.parent.location = target.location
        cam.location *= s
        return
    for fc in ease_keys(cam):
        for p in fc.keyframe_points:
            p.co.y = target.location[fc.array_index] + (p.co.y - pivot[fc.array_index]) * s
        fc.update()


def play_clip(parts, actions):
    """Clear the imported animation (rest pose) or, with MV_MODEL_ANIM=<clip|first>, put that clip on one looping NLA strip per animated part, MV_MODEL_ANIM_SPEED x, time-scaled to whole loops so one ends on MV_MODEL_ANIM_CUE (default MV_TITLE_CUE, else the shot end)."""
    animated = [o for o in parts if o.animation_data]
    first = next((o.animation_data.action for o in animated if o.animation_data.action), None)
    for o in animated:
        o.animation_data.action = None
        for t in list(o.animation_data.nla_tracks):
            o.animation_data.nla_tracks.remove(t)
    if not model_anim:
        return
    act = first if model_anim == "first" else next((a for a in actions if a.name == model_anim), None)
    if act is None:
        sys.exit(f"shot.py: MV_MODEL_ANIM {model_anim} not in {sorted(a.name for a in actions)}")
    loop = act.frame_range[1] - act.frame_range[0]
    cue = os.environ.get("MV_MODEL_ANIM_CUE", os.environ.get("MV_TITLE_CUE", ""))
    span = cue_seconds(cue) * fps if cue else scene.frame_end - scene.frame_start
    loops = max(1, round(span * model_anim_speed / loop))
    for o in animated:
        o.animation_data.action = act
        slot = o.animation_data.action_slot
        o.animation_data.action = None
        if slot is None:
            continue
        strip = o.animation_data.nla_tracks.new().strips.new(act.name, scene.frame_start, act)
        strip.action_slot = slot
        strip.scale = span / (loops * loop)
        strip.repeat = max(loops, math.ceil((scene.frame_end - scene.frame_start) / (loop * strip.scale)))
        strip.extrapolation = "HOLD"


def model_hero(path):
    """Import a glTF/GLB with its materials under one empty, MV_MODEL_HEIGHT tall, centred on the floor, animated by play_clip; the camera path is scaled about it until its bounding box spans 10-90 % of the frame at the tightest frame."""
    before, before_actions = set(scene.objects), set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    parts = [o for o in scene.objects if o not in before]
    play_clip(parts, [a for a in bpy.data.actions if a not in before_actions])
    bpy.ops.object.empty_add()
    root = bpy.context.object
    for o in parts:
        if o.parent is None:
            o.parent = root
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in parts if o.type == "MESH" for c in o.bound_box]
    lo = Vector([min(c[i] for c in corners) for i in range(3)])
    hi = Vector([max(c[i] for c in corners) for i in range(3)])
    k = model_height / (hi.z - lo.z)
    root.scale = (k,) * 3
    root.location = (-k * (lo.x + hi.x) / 2, -k * (lo.y + hi.y) / 2, -k * lo.z)
    pivot = target.location.copy()
    target.location = (0, 0, model_height / 2)
    scale_move(1.0, pivot)
    box = [Vector((k * (x - (lo.x + hi.x) / 2), k * (y - (lo.y + hi.y) / 2), k * (z - lo.z))) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    for _ in range(3):
        worst = 0.0
        for f in range(scene.frame_start, scene.frame_end + 1):
            scene.frame_set(f)
            for c in box:
                uv = world_to_camera_view(scene, cam, c)
                worst = max(worst, abs(uv.x - 0.5), abs(uv.y - 0.5))
        scale_move(worst / 0.4, target.location.copy())
    scene.frame_set(scene.frame_start)
    return root


def logo_ring(o):
    """Emissive ring concentric with the logo, parented behind its back face, radius 1.3 x its half-diagonal so it never crosses the letters."""
    k = o.scale.x
    radius = 1.3 * math.hypot(o.dimensions.x, o.dimensions.y) / 2
    bpy.ops.mesh.primitive_torus_add(major_radius=radius / k, minor_radius=0.03 / k, major_segments=96)
    r = bpy.context.object
    r.data.materials.append(ring_mat)
    r.parent = o
    r.location = (0, 0, -(o.dimensions.z / 2 + 0.1) / k)
    return r


def cue_seconds(name):
    """Seconds of mark `name` in the MV_CUES cues.json (clips.*.marks), 0 when MV_TITLE_CUE is unset."""
    if not name:
        return 0.0
    cues = json.load(open(os.environ["MV_CUES"]))
    marks = {n: t for clip in cues.get("clips", {}).values() for n, t in (clip.get("marks") or {}).items()}
    if name not in marks:
        sys.exit(f"shot.py: MV_TITLE_CUE {name} not in {os.environ['MV_CUES']}")
    return float(marks[name])


def title_hero(text, logo_obj):
    """MV_TITLE as extruded, bevelled brand-font letters above the logo (or the blocks), turned to the camera, each rising and fading in 40 ms after the last from MV_TITLE_CUE."""
    family = brand.get("fonts", {}).get("display", "Inter")
    font_file = subprocess.run(["fc-match", "-f", "%{file}", f"{family}:bold"], capture_output=True, text=True).stdout
    colour = srgb(brand.get("palette", {}).get("paper", "#f4f1ea"))
    bpy.ops.object.empty_add()
    root = bpy.context.object
    if logo_obj:
        k = logo_obj.scale.x
        root.parent, root.scale = logo_obj, (1 / k,) * 3
        logo_h, logo_w = logo_obj.dimensions.y, logo_obj.dimensions.x
    else:
        root.location, root.rotation_euler = (0, 0.5, 3.0), (math.radians(90), 0, 0)
        logo_h, logo_w = 2.0, 5.0
    face = root.constraints.new("LOCKED_TRACK")
    face.target, face.track_axis, face.lock_axis = cam, "TRACK_Z", "LOCK_Y"
    bpy.ops.object.text_add()
    t = bpy.context.object
    t.data.body = text
    t.data.font = bpy.data.fonts.load(font_file)
    t.data.align_x = "CENTER"
    t.data.space_character = 1.15
    t.data.extrude, t.data.bevel_depth, t.data.bevel_resolution = 0.08, 0.012, 2
    t.parent = root
    for i in range(len(text)):
        t.data.materials.append(material(f"Title{i}", colour, metallic=0.3, rough=0.28))
        t.data.materials[i]["char"] = i
        t.data.body_format[i].material_index = i
    bpy.context.view_layer.update()
    t.data.size *= min(0.3 * logo_h / t.dimensions.y, 1.3 * logo_w / t.dimensions.x)
    bpy.ops.object.select_all(action="DESELECT")
    t.select_set(True)
    bpy.context.view_layer.objects.active = t
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    letters = sorted((o for o in bpy.context.selected_objects if o.data.polygons), key=lambda o: o.data.materials[o.data.polygons[0].material_index]["char"])
    bottom = min(v.co.y for o in letters for v in o.data.vertices)
    height = max(v.co.y for o in letters for v in o.data.vertices) - bottom
    lift = (logo_h / 2 + 0.25 * logo_h - bottom) if logo_obj else 0.0
    start = scene.frame_start + cue_seconds(os.environ.get("MV_TITLE_CUE", "")) * fps
    for rank, o in enumerate(letters):
        m = o.data.materials[o.data.polygons[0].material_index]
        o.data.materials.clear()
        o.data.materials.append(m)
        alpha = m.node_tree.nodes["Principled BSDF"].inputs["Alpha"]
        f0 = start + rank * 0.04 * fps
        for f, y, a in ((f0, lift - 0.3 * height, 0.0), (f0 + 0.5 * fps, lift, 1.0)):
            o.location.y, alpha.default_value = y, a
            o.keyframe_insert("location", index=1, frame=f)
            alpha.keyframe_insert("default_value", frame=f)
    if logo_obj:
        target.location.z = logo_obj.location.z + (lift + height - logo_h / 2) / 2
    return letters


hero = logo_hero(logo) if logo else model_hero(model) if model else None
if logo and show_ring:
    ring = logo_ring(hero)
title_letters = title_hero(title, hero if logo else None) if title else []

if dump_camera:
    path = []
    for f in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(f)
        path.append([round(v, 5) for v in cam.matrix_world.translation])
    scene.frame_set(scene.frame_start)
    with open(dump_camera, "w") as fh:
        json.dump({"move": camera_move, "ease": camera_ease, "lens": cam.data.lens, "fstop": cam.data.dof.aperture_fstop,
                   "target": list(target.location), "frames": path}, fh)

eevee_catcher = catcher and engine != "CYCLES"
if eevee_catcher or look != "none":
    comp = bpy.data.node_groups.new("Compositor", "CompositorNodeTree")
    scene.compositing_node_group = comp
    comp.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    layers = comp.nodes.new("CompositorNodeRLayers")
    img = shadow_catcher_compositor(comp, layers) if eevee_catcher else layers.outputs["Image"]
    img = look_compositor(comp, img) if look != "none" else img
    comp.links.new(img, comp.nodes.new("NodeGroupOutput").inputs[0])

bpy.ops.render.render(animation=True)
