#!/usr/bin/env bash
# mv-model.test.sh: MV_MODEL glTF hero of the Blender shot - an off-centre fixture glb lands centred on the floor at MV_MODEL_HEIGHT, keeps base colour/normal/roughness, stays in frame on dolly/orbit/push; 1 draft frame: projected bbox and silhouette span 30-80 % of the frame. Asserts on fixtures/plates/mv-model (make.sh); Blender renders them on MV_BLENDER_FULL=1, Sundays or a stale/missing fixture.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
MV=$HERE/../scripts/mv-render
SHOT=$HERE/../templates/blender/shot.py
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }

cat >"$FX/make.py" <<'PY'
import os, bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
fx = os.environ["FX"]
bpy.ops.mesh.primitive_cube_add(size=1, location=(5, 2, 3))
o = bpy.context.object
o.scale = (3, 1, 1.5)
m = bpy.data.materials.new("Fixture")
m.use_nodes = True
n, ln = m.node_tree.nodes, m.node_tree.links
b = n["Principled BSDF"]
b.inputs["Roughness"].default_value = 0.6
for name, colour in (("base", (0.9, 0.3, 0.1, 1)), ("nor", (0.5, 0.5, 1, 1))):
    img = bpy.data.images.new(name, 8, 8)
    img.pixels = colour * 64
    img.filepath_raw, img.file_format = f"{fx}/{name}.png", "PNG"
    img.save()
    tex = n.new("ShaderNodeTexImage")
    tex.image = img
    if name == "base":
        ln.new(tex.outputs["Color"], b.inputs["Base Color"])
    else:
        img.colorspace_settings.name = "Non-Color"
        nm = n.new("ShaderNodeNormalMap")
        ln.new(tex.outputs["Color"], nm.inputs["Color"])
        ln.new(nm.outputs["Normal"], b.inputs["Normal"])
o.data.materials.append(m)
bpy.ops.export_scene.gltf(filepath=f"{fx}/fixture.glb", export_format="GLB")
PY
cat >"$FX/probe.py" <<'PY'
from bpy_extras.object_utils import world_to_camera_view
meshes = [o for o in hero.children_recursive if o.type == "MESH"]
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo3 = [min(p[i] for p in pts) for i in range(3)]
hi3 = [max(p[i] for p in pts) for i in range(3)]
b = meshes[0].material_slots[0].material.node_tree.nodes["Principled BSDF"]
tex = int(b.inputs["Base Color"].is_linked and b.inputs["Base Color"].links[0].from_node.type == "TEX_IMAGE")
nor = int(b.inputs["Normal"].is_linked and b.inputs["Normal"].links[0].from_node.type == "NORMAL_MAP")
lo, hi, span = 1.0, 0.0, 0.0
for f in range(scene.frame_start, scene.frame_end + 1):
    scene.frame_set(f)
    uv = [world_to_camera_view(scene, cam, p) for p in pts]
    xs, ys = [p.x for p in uv], [p.y for p in uv]
    lo, hi = min(lo, *xs, *ys), max(hi, *xs, *ys)
    if f == scene.frame_start:
        span = max(max(xs) - min(xs), max(ys) - min(ys))
print(f"PROBE {lo3[2]:.3f} {(lo3[0] + hi3[0]) / 2:.3f} {(lo3[1] + hi3[1]) / 2:.3f} {hi3[2] - lo3[2]:.3f} {tex} {nor} {b.inputs['Roughness'].default_value:.2f} {lo:.3f} {hi:.3f} {span:.3f}")
PY
probe() { MV_CAMERA=$1 MV_MODEL=$FX/fixture.glb MV_MODEL_HEIGHT=${2:-2.0} MV_FPS=12 MV_SECONDS=1 blender -b --factory-startup -P <(sed '$d' "$SHOT"; cat "$FX/probe.py") 2>/dev/null | grep '^PROBE'; }
. "$HERE/fixtures/plates/plates.sh"
plates mv-model
if ((BL)); then
  FX=$FX blender -b --factory-startup -P "$FX/make.py" >/dev/null 2>&1
  stat -c %s "$FX/fixture.glb" >"$P/glb-bytes" 2>/dev/null
  for m in dolly orbit push; do probe "$m" >"$P/probe-$m.txt"; done
  probe dolly 5 >"$P/probe-h5.txt"
  MV_MODEL=$FX/fixture.glb MV_GROUND=catcher MV_FPS=1 MV_SECONDS=1 MV_SIZE=640x360 "$MV" blender "$SHOT" "$FX/f" --draft >/dev/null 2>&1
  ls "$FX/f"/frame_*.png 2>/dev/null | wc -l >"$P/draft-frames"
  [[ -f $FX/f/frame_0001.png ]] && keep "$FX/f/frame_0001.png" "$P/f/frame_0001.png" A
fi

ok "$([[ $(val glb-bytes) -gt 0 ]] 2>/dev/null && echo 1 || echo 0)" "fixture glb exported ($(val glb-bytes) B)"
read -r _ bottom cx cy h tex nor rough lo hi span < <(val probe-dolly.txt)
ok "$(echo "${bottom:-1} > -0.01 && ${bottom:-1} < 0.01 && ${cx:-1}^2 < 0.0001 && ${cy:-1}^2 < 0.0001" | bc)" "centred on the floor (bottom $bottom, centre $cx,$cy)"
ok "$(echo "${h:-0} > 1.99 && ${h:-0} < 2.01" | bc)" "scaled to MV_MODEL_HEIGHT 2.0 ($h)"
ok "$([[ ${tex:-0}${nor:-0} == 11 && ${rough:-0} == 0.60 ]] && echo 1 || echo 0)" "materials kept: base colour texture $tex, normal map $nor, roughness $rough"
ok "$(echo "${span:-0} >= 0.30 && ${span:-1} <= 0.80" | bc)" "dolly frame 1: projected bbox spans $span of the frame (0.30-0.80)"
for m in dolly orbit push; do
  read -r _ _ _ _ _ _ _ _ lo hi _ < <(val "probe-$m.txt")
  ok "$(echo "${lo:-0} > 0.01 && ${hi:-1} < 0.99" | bc)" "$m: model inside the frame on every frame (bbox $lo..$hi)"
done
read -r _ _ _ _ h _ _ _ lo hi _ < <(val probe-h5.txt)
ok "$(echo "${h:-0} > 4.99 && ${h:-0} < 5.01 && ${lo:-0} > 0.01 && ${hi:-1} < 0.99" | bc)" "MV_MODEL_HEIGHT=5: height $h, camera reframes ($lo..$hi)"

read -r cover < <(python3 -I - "$P/f/frame_0001.png" <<'PY'
import os, sys
import numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1])) > 200 if os.path.isfile(sys.argv[1]) else np.zeros((1, 1), bool)
ys, xs = np.nonzero(a)
print(f"{max((np.ptp(xs) + 1) / a.shape[1], (np.ptp(ys) + 1) / a.shape[0]) if xs.size else 0:.3f}")
PY
)
frames=$(val draft-frames)
ok "$(echo "${frames:-0} == 1 && ${cover:-0} >= 0.30 && ${cover:-1} <= 0.80" | bc)" "1 draft frame: model silhouette spans $cover of the frame (0.30-0.80)"

echo "mv-model.test: $((n - bad))/$n passed"
exit $((bad > 0))
