"""The reference pass, inside Blender: a Scene at time t -> plain EEVEE render as five EXR passes and a JSON.

Run by `film ref`: blender -b --factory-startup --python-expr "...; from atelier import ref; ref.main()" -- SHOT OUT ...
Materials are flat colour times the `tone` attribute (no texture, no bump); ids go out as a colour AOV (ident_code).
"""
import argparse
import hashlib
import importlib
import json
import os
import sys
import time
from dataclasses import dataclass

import bpy
import mathutils
import numpy as np

from .scene import ident_code

PASSES = (("lit", "Image", "RGBA", "16"), ("albedo", "albedo", "RGBA", "16"), ("depth", "Depth", "FLOAT", "32"),
          ("normal", "Normal", "VECTOR", "16"), ("ident", "ident", "RGBA", "32"))


@dataclass
class RefCfg:
    scale: float = 1.0  # of the camera's size
    samples: int = 24
    pattern_shift: tuple = (0.0, 0.0)  # px: lens shift that moves EEVEE's screen-fixed sampling against the picture
    # EEVEE has no sampler seed (frame_set(1) and (2) render byte-equal): a seed pair is this shift, undone in refio
    vol_samples: int = 64
    vol_tile: str = "8"
    shadow_res: float = 0.04  # m; Blender's 1 mm default costs 4x here
    clip: tuple = (0.1, 200.0)


class _Stage:
    """The Blender scene the frames are rendered in: settings, world, materials, compositor; objects kept by name."""

    def __init__(self, scene, cfg):
        self.cfg = cfg
        sc = self.sc = bpy.context.scene
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o)
        sc.render.engine = "BLENDER_EEVEE"
        sc.render.resolution_percentage = 100
        sc.render.use_motion_blur = False
        e = sc.eevee
        e.taa_render_samples = cfg.samples
        e.use_taa_reprojection = False
        e.use_shadows = True
        e.shadow_ray_count, e.shadow_step_count = 1, 6
        e.volumetric_tile_size, e.volumetric_samples = cfg.vol_tile, cfg.vol_samples
        e.volumetric_start, e.volumetric_end = 0.3, 70.0
        e.use_volumetric_shadows = True
        e.use_raytracing = False
        vl = sc.view_layers[0]
        vl.use_pass_z = vl.use_pass_normal = True
        for name, kind in (("albedo", "COLOR"), ("ident", "COLOR"), ("identc", "VALUE")):
            a = vl.aovs.add()
            a.name, a.type = name, kind
        self.world(scene.world)
        self.mats = {m: self.material(m, d) for m, d in scene.materials.items()}
        self.unseen = {m: bool(d.get("unseen")) for m, d in scene.materials.items()}  # casts its shadow, is in no pass
        self.objs, self.hash, self.lights = {}, {}, []
        cd = bpy.data.cameras.new("cam")
        cd.clip_start, cd.clip_end, cd.sensor_fit = cfg.clip[0], cfg.clip[1], "HORIZONTAL"
        self.cam = bpy.data.objects.new("cam", cd)
        sc.collection.objects.link(self.cam)
        sc.camera = self.cam
        ng = bpy.data.node_groups.new("ref", "CompositorNodeTree")
        sc.compositing_node_group = ng
        rl = ng.nodes.new("CompositorNodeRLayers")
        self.out = ng.nodes.new("CompositorNodeOutputFile")
        self.out.format.media_type = "IMAGE"  # one file per pass: a multilayer file is multi-part
        for name, src, kind, depth in PASSES:
            it = self.out.file_output_items.new(kind, name)
            it.override_node_format = True
            f = it.format
            f.media_type, f.file_format, f.exr_codec, f.color_depth = "IMAGE", "OPEN_EXR", "ZIP", depth
            f.color_mode = {"FLOAT": "BW", "RGBA": "RGBA" if name == "ident" else "RGB"}.get(kind, "RGB")
            ng.links.new(rl.outputs[src], self.out.inputs[name])
        sep, comb = ng.nodes.new("CompositorNodeSeparateColor"), ng.nodes.new("CompositorNodeCombineColor")
        ng.links.new(rl.outputs["ident"], sep.inputs[0])  # the ident's bytes in RGB, its check in alpha
        for i in range(3):
            ng.links.new(sep.outputs[i], comb.inputs[i])
        ng.links.new(rl.outputs["identc"], comb.inputs[3])
        ng.links.new(comb.outputs[0], self.out.inputs["ident"])

    def world(self, d):
        w = bpy.data.worlds.new("w")
        self.sc.world = w
        w.use_nodes = True
        t = w.node_tree
        t.nodes.clear()
        out = t.nodes.new("ShaderNodeOutputWorld")
        bg = t.nodes.new("ShaderNodeBackground")
        bg.inputs[0].default_value = (*d.get("color", (0.0, 0.0, 0.0)), 1)
        bg.inputs[1].default_value = d.get("strength", 1.0)
        t.links.new(bg.outputs[0], out.inputs["Surface"])
        if d.get("haze", 0.0) > 0:
            vs = t.nodes.new("ShaderNodeVolumeScatter")
            vs.inputs["Color"].default_value = (*d.get("haze_color", (0.82, 0.9, 1.0)), 1)
            vs.inputs["Density"].default_value = d["haze"]
            vs.inputs["Anisotropy"].default_value = d.get("anisotropy", 0.0)
            em = t.nodes.new("ShaderNodeEmission")  # the far air: depth turns toward its colour
            em.inputs[0].default_value = (*d.get("air", (0.0, 0.0, 0.0)), 1)
            em.inputs[1].default_value = d.get("air_strength", 0.0)
            ad = t.nodes.new("ShaderNodeAddShader")
            t.links.new(vs.outputs[0], ad.inputs[0])
            t.links.new(em.outputs[0], ad.inputs[1])
            t.links.new(ad.outputs[0], out.inputs["Volume"])

    def material(self, name, d):
        """Flat colour times tone; emission of the same colour; AOVs albedo and ident."""
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        t = m.node_tree
        t.nodes.clear()
        if d.get("haze"):  # a body of air: it scatters light and has no surface (in no pass but the lit one)
            vs = t.nodes.new("ShaderNodeVolumeScatter")
            vs.inputs["Color"].default_value = (*d["color"], 1)
            vs.inputs["Density"].default_value = d["haze"]
            vs.inputs["Anisotropy"].default_value = d.get("anisotropy", 0.0)
            t.links.new(vs.outputs[0], t.nodes.new("ShaderNodeOutputMaterial").inputs["Volume"])
            return m
        tone = t.nodes.new("ShaderNodeAttribute")
        tone.attribute_name = "tone"
        idv, idc = t.nodes.new("ShaderNodeAttribute"), t.nodes.new("ShaderNodeAttribute")
        idv.attribute_name, idc.attribute_name = "identv", "identc"
        base = t.nodes.new("ShaderNodeVectorMath")
        base.operation = "SCALE"
        base.inputs[0].default_value = d["color"]
        t.links.new(tone.outputs["Fac"], base.inputs[3])
        b = t.nodes.new("ShaderNodeBsdfPrincipled")
        t.links.new(base.outputs[0], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = d.get("rough", 0.8)
        if d.get("layers"):
            self.layers(t, d, base, b)
        b.inputs["Metallic"].default_value = d.get("metal", 0.0)
        if d.get("emission", 0.0):
            t.links.new(base.outputs[0], b.inputs["Emission Color"])
            b.inputs["Emission Strength"].default_value = d["emission"]
        t.links.new(b.outputs[0], t.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
        for aov, sock, kind in (("albedo", base.outputs[0], "Color"), ("ident", idv.outputs["Vector"], "Color"),
                                ("identc", idc.outputs["Fac"], "Value")):
            o = t.nodes.new("ShaderNodeOutputAOV")
            o.aov_name = aov
            t.links.new(sock, o.inputs[kind])
        return m

    def layers(self, t, d, base, b):
        """The material's layers (stain, moss, lime, damp): each mixes the colour toward its own, and the roughness
        toward its "rough", where a noise of the world place (cycles a metre: "scale", a number or one an axis)
        passes "lo".."hi", times "amount"; with "up": only where the normal's z is between its two values."""
        N = t.nodes.new
        geo = N("ShaderNodeNewGeometry")
        up = N("ShaderNodeSeparateXYZ")
        t.links.new(geo.outputs["Normal"], up.inputs[0])
        col = N("ShaderNodeRGB")
        col.outputs[0].default_value = (*d["color"], 1)
        col, rough = col.outputs[0], None
        for i, ly in enumerate(d["layers"]):
            at = N("ShaderNodeVectorMath")
            at.operation = "MULTIPLY"
            t.links.new(geo.outputs["Position"], at.inputs[0])
            at.inputs[1].default_value = tuple(np.broadcast_to(np.asarray(ly.get("scale", 1.0), float), 3))
            off = N("ShaderNodeVectorMath")  # each layer its own place in the noise
            t.links.new(at.outputs[0], off.inputs[0])
            off.inputs[1].default_value = (17.3 * i + 3.1, 9.7 * i + 1.3, 23.9 * i + 7.7)
            nz = N("ShaderNodeTexNoise")
            nz.inputs["Scale"].default_value = 1.0
            nz.inputs["Detail"].default_value = ly.get("detail", 3.0)
            nz.inputs["Roughness"].default_value = ly.get("grain", 0.55)
            t.links.new(off.outputs[0], nz.inputs["Vector"])
            mask = self.ramp(t, nz.outputs[0], ly.get("lo", 0.45), ly.get("hi", 0.6), ly.get("amount", 1.0))
            if "up" in ly:
                m = N("ShaderNodeMath")
                m.operation = "MULTIPLY"
                t.links.new(mask, m.inputs[0])
                t.links.new(self.ramp(t, up.outputs["Z"], *ly["up"], 1.0), m.inputs[1])
                mask = m.outputs[0]
            mx = N("ShaderNodeMix")
            mx.data_type = "RGBA"
            t.links.new(mask, mx.inputs[0])
            t.links.new(col, mx.inputs[6])
            mx.inputs[7].default_value = (*ly["color"], 1)
            col = mx.outputs[2]
            if "rough" in ly:
                mr = N("ShaderNodeMix")
                mr.data_type = "FLOAT"
                t.links.new(mask, mr.inputs[0])
                if rough is None:
                    mr.inputs[2].default_value = d.get("rough", 0.8)
                else:
                    t.links.new(rough, mr.inputs[2])
                mr.inputs[3].default_value = ly["rough"]
                rough = mr.outputs[0]
        t.links.new(col, base.inputs[0])
        if rough is not None:
            t.links.new(rough, b.inputs["Roughness"])

    @staticmethod
    def ramp(t, sock, lo, hi, gain):
        """0 at lo, gain at hi, smooth between, clamped."""
        r = t.nodes.new("ShaderNodeMapRange")
        r.interpolation_type = "SMOOTHSTEP"
        t.links.new(sock, r.inputs["Value"])
        r.inputs["From Min"].default_value, r.inputs["From Max"].default_value = lo, hi
        r.inputs["To Min"].default_value, r.inputs["To Max"].default_value = 0.0, gain
        return r.outputs[0]

    def mesh(self, m):
        """Make or refresh the object of a Mesh; skip the upload when its data did not change."""
        V, F = np.ascontiguousarray(m.V, np.float32), np.ascontiguousarray(m.F, np.int32)
        tone = np.ascontiguousarray(m.attrs.get("tone", np.ones(len(V))), np.float32)
        ident = np.asarray(m.attrs.get("ident", np.zeros(len(V))), np.int64)
        h = hashlib.blake2b(digest_size=16)
        for a in (V, F, tone, ident, m.material.encode()):
            h.update(a if isinstance(a, bytes) else a.tobytes())
        o = self.objs.get(m.name)
        if o is None:
            o = self.objs[m.name] = bpy.data.objects.new(m.name, bpy.data.meshes.new(m.name))
            self.sc.collection.objects.link(o)
            o.visible_camera = not self.unseen.get(m.material, False)
        o.hide_render = False
        if self.hash.get(m.name) == h.digest():
            return
        self.hash[m.name] = h.digest()
        me = bpy.data.meshes.new(m.name)
        if len(F):
            me.vertices.add(len(V))
            me.vertices.foreach_set("co", V.ravel())
            me.loops.add(3 * len(F))
            me.loops.foreach_set("vertex_index", F.ravel())
            me.polygons.add(len(F))
            me.polygons.foreach_set("loop_start", np.arange(0, 3 * len(F), 3, dtype=np.int32))
            me.polygons.foreach_set("use_smooth", np.ones(len(F), bool))
            me.attributes.new("tone", "FLOAT", "POINT").data.foreach_set("value", tone)
            code = ident_code(ident)
            me.attributes.new("identv", "FLOAT_VECTOR", "POINT").data.foreach_set("vector", code[:, :3].ravel())
            me.attributes.new("identc", "FLOAT", "POINT").data.foreach_set("value", code[:, 3].copy())
            me.update()
        me.materials.append(self.mats[m.material])
        old = o.data
        o.data = me
        bpy.data.meshes.remove(old)

    def light(self, i, L):
        if i == len(self.lights):
            d = bpy.data.lights.new("light%d" % i, L.kind.upper())
            o = bpy.data.objects.new("light%d" % i, d)
            self.sc.collection.objects.link(o)
            self.lights.append(o)
        o = self.lights[i]
        if o.data.type != L.kind.upper():
            o.data.type = L.kind.upper()
        d = o.data
        if L.kind == "spot":
            d.spot_size, d.spot_blend = L.cone, L.blend
        d.color, d.energy, d.use_shadow, d.volume_factor = tuple(L.color), L.watts, L.shadow, L.haze
        d.shadow_maximum_resolution = self.cfg.shadow_res
        if L.kind in ("point", "spot"):
            d.shadow_soft_size = L.radius
        elif L.kind == "sun":
            d.angle = L.radius
        else:
            d.size = L.radius
        o.location, o.rotation_euler = tuple(L.pos), tuple(L.rot)
        o.hide_render = False


_STAGE = {}


def render(scene, t, prefix, cfg):
    """Render the scene at t to prefix.{lit,albedo,depth,normal,ident}.exr and prefix.json; print one log line."""
    t0 = time.time()
    st = _STAGE.get(id(scene))
    if st is None:
        st = _STAGE[id(scene)] = _Stage(scene, cfg)
    st.cfg = cfg
    st.sc.eevee.taa_render_samples = cfg.samples
    meshes = scene.meshes(t)
    names = {m.name for m in meshes}
    for name, o in st.objs.items():
        o.hide_render = name not in names
    for m in meshes:
        st.mesh(m)
    lights = scene.lights(t)
    for o in st.lights[len(lights):]:
        o.hide_render = True
    for i, L in enumerate(lights):
        st.light(i, L)
    cam = scene.camera(t)
    W, H = int(round(cam.size[0] * cfg.scale)), int(round(cam.size[1] * cfg.scale))
    st.sc.render.resolution_x, st.sc.render.resolution_y = W, H
    M = np.eye(4)
    M[:3, :3], M[:3, 3] = cam.R, cam.pos
    st.cam.matrix_world = mathutils.Matrix(M.tolist())
    st.cam.data.lens, st.cam.data.sensor_width = cam.lens_mm, cam.sensor_mm
    st.out.directory = os.path.dirname(os.path.abspath(prefix))
    st.out.file_name = os.path.basename(prefix) + "."
    t1 = time.time()
    st.cam.data.shift_x, st.cam.data.shift_y = cfg.pattern_shift[0] / W, cfg.pattern_shift[1] / W
    st.sc.frame_set(1)
    bpy.ops.render.render(write_still=False)
    t2 = time.time()
    cam.size = (W, H)
    meta = dict(t=t, scale=cfg.scale, samples=cfg.samples, pattern_shift=list(cfg.pattern_shift), clip=list(cfg.clip), camera=cam.to_json(),
                passes=[p[0] for p in PASSES], build_s=round(t1 - t0, 3), render_s=round(t2 - t1, 3))
    with open(prefix + ".json", "w") as fh:
        json.dump(meta, fh, indent=1)
    n = sum(os.path.exists("%s.%s.exr" % (prefix, p[0])) for p in PASSES)
    print("REF %s t=%.3f passes %d build %.2fs render %.2fs frame %.2fs" % (os.path.basename(prefix), t, n, t1 - t0, t2 - t1,
                                                                            time.time() - t0), flush=True)


def frames(spec):
    out = []
    for part in spec.split(","):
        lo, _, hi = part.partition("-")
        out += range(int(lo), int(hi or lo) + 1)
    return out


def main(argv=None):
    """SHOT OUT [--frames a-b,c] [--scale s] [--samples n] [--seed-pair]: render each frame (and its seed-pair twin)."""
    argv = sys.argv[sys.argv.index("--") + 1:] if argv is None else argv
    p = argparse.ArgumentParser(prog="atelier.ref")
    p.add_argument("shot")
    p.add_argument("out")
    p.add_argument("--frames", default="0")
    p.add_argument("--scale", type=float)
    p.add_argument("--samples", type=int)
    p.add_argument("--seed-pair", action="store_true", help="also render each frame with the pattern moved (2.5, 1.5) px, into OUT/seed2")
    a = p.parse_args(argv)
    with open(os.path.join(a.shot, "shot.json")) as fh:
        js = json.load(fh)
    rc = dict(js.get("ref", {}))
    if a.scale:
        rc["scale"] = a.scale
    if a.samples:
        rc["samples"] = a.samples
    cfg = RefCfg(**rc)
    sys.path.insert(0, os.path.abspath(a.shot))
    scene = importlib.import_module(js.get("scene", "shot")).scene()
    fps = js.get("fps", scene.fps)
    os.makedirs(a.out, exist_ok=True)
    for f in frames(a.frames):
        render(scene, f / fps, os.path.join(a.out, "f_%04d" % f), cfg)
        if a.seed_pair:
            os.makedirs(os.path.join(a.out, "seed2"), exist_ok=True)
            render(scene, f / fps, os.path.join(a.out, "seed2", "f_%04d" % f), RefCfg(**dict(rc, pattern_shift=(2.5, 1.5))))
