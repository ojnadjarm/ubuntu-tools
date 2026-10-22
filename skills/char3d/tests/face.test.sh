#!/usr/bin/env bash
# Face stage: build until facerig, render a lit close-up (key, fill, rim, specular-only eye light), classify eye pixels
# by camera rays, then assert a catchlight in both irises, iris mean luma > 0.2x sclera, sealed lids and the preset
# counts. FACE_STILL=<png> keeps the still; FACE_RES=1920 renders Full HD at 64 spp (default 960x540, 16 spp); ~70 s.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
c3d=$here/scripts/char3d
spec=$here/specs/darksaddler.json
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
lock=${CHAR3D_LOCK:-$HOME/agent-work/research/2026-10-20/T1032/render.lock}
fail() { echo "FAIL: $*"; exit 1; }

"$c3d" build "$spec" --out "$tmp/o" --draft --until facerig >/dev/null || fail "build until facerig"
cat > "$tmp/still.py" <<'PY'
import json, os, sys
import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

out, png = sys.argv[sys.argv.index('--') + 1:][:2]
b = json.load(open(os.path.join(out, 'build.json')))
sc = bpy.context.scene
full = os.environ.get('FACE_RES') == '1920'
W, H = (1920, 1080) if full else (960, 540)
sc.render.engine = 'BLENDER_EEVEE'
sc.eevee.taa_render_samples = 64 if full else 16
sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = W, H, 100
sc.view_settings.view_transform = 'AgX'
sc.render.image_settings.file_format = 'PNG'
for p in b['parts'].values():
    ob = bpy.data.objects.get(p['object'])
    if ob and p['stage'] in ('garments', 'props'):
        ob.hide_render = ob.hide_viewport = True
for o in [o for o in bpy.data.objects if o.type in ('LIGHT', 'CAMERA')]:
    bpy.data.objects.remove(o)
eL, eR = Vector(b['landmarks']['eye.L']), Vector(b['landmarks']['eye.R'])
target = (eL + eR) / 2 + Vector((0, 0, -0.035))
cam = bpy.data.objects.new('face_cam', bpy.data.cameras.new('face_cam'))
sc.collection.objects.link(cam)
sc.camera, cam.data.lens = cam, 85
cam.location = target + Vector((0.12, -0.62, 0.02))
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
for name, energy, off, size in (('key', 70, (-0.45, -0.9, 0.4), 0.25), ('fill', 12, (0.8, -0.7, 0.0), 1.0),
                                ('rim', 50, (0.5, 0.9, 0.4), 0.4)):
    lo = bpy.data.objects.new(name, bpy.data.lights.new(name, 'AREA'))
    lo.data.energy, lo.data.size, lo.data.shape = energy, size, 'DISK'
    lo.location = target + Vector(off)
    lo.rotation_euler = (target - lo.location).to_track_quat('-Z', 'Y').to_euler()
    sc.collection.objects.link(lo)
eye = bpy.data.objects.new('eye_light', bpy.data.lights.new('eye_light', 'AREA'))
eye.data.energy, eye.data.size, eye.data.shape, eye.data.diffuse_factor = 20, 0.1, 'DISK', 0.0
eye.location = target + Vector((0.06, -0.75, 0.14))
eye.rotation_euler = (target - eye.location).to_track_quat('-Z', 'Y').to_euler()
sc.collection.objects.link(eye)
w = bpy.data.worlds.new('face_w')
w.use_nodes = True
w.node_tree.nodes['Background'].inputs[0].default_value = (0.03, 0.03, 0.035, 1)
sc.world = w
sc.render.filepath = png
bpy.ops.render.render(write_still=True)

img = bpy.data.images.load(png)
px = np.array(img.pixels[:]).reshape(H, W, 4)[..., :3]
luma = px @ np.array([0.2126, 0.7152, 0.0722])
dg = bpy.context.evaluated_depsgraph_get()
tr, br, bl, tl = [cam.matrix_world @ v for v in cam.data.view_frame(scene=sc)]
see_through = ('cornea.', 'eye_occlusion.', 'tearline.')
res = {}
for s in 'LR':
    iris = bpy.data.objects[f'iris.{s}']
    rim = [world_to_camera_view(sc, cam, iris.matrix_world @ v.co) for v in iris.data.vertices]
    xs, ys = [r.x * W for r in rim], [r.y * H for r in rim]
    dia = max(max(xs) - min(xs), max(ys) - min(ys))
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    cls = {'iris': [], 'eye': []}
    for y in range(int(cy - 1.4 * dia), int(cy + 1.4 * dia)):
        for x in range(int(cx - 1.6 * dia), int(cx + 1.6 * dia)):
            d = (bl + (x + 0.5) / W * (br - bl) + (y + 0.5) / H * (tl - bl) - cam.location).normalized()
            o = cam.location.copy()
            for _ in range(6):
                hit, loc, _, _, ob, _ = sc.ray_cast(dg, o, d)
                if not hit or not ob.name.startswith(see_through):
                    break
                o = loc + d * 1e-5
            name = ob.name if hit else ''
            if name == f'iris.{s}':
                cls['iris'].append(luma[y, x])
            elif name == f'eye.{s}':
                cls['eye'].append(luma[y, x])
    ir, sc_ = np.array(cls['iris']), np.array(cls['eye'])
    res[s] = {'iris_px': len(ir), 'sclera_px': len(sc_), 'iris_mean': float(ir.mean()) if len(ir) else 0.0,
              'iris_median': float(np.median(ir)) if len(ir) else 0.0, 'iris_max': float(ir.max()) if len(ir) else 0.0,
              'sclera_mean': float(sc_.mean()) if len(sc_) else 0.0,
              'catch_px': int((ir >= max(0.8, np.median(ir) + 0.25)).sum()) if len(ir) else 0}
json.dump(res, open(os.path.join(out, 'face_still.json'), 'w'), indent=1)
PY
BLENDER_USER_RESOURCES=${CHAR3D_BLENDER_RES:-$HOME/.local/share/char3d/blender-res} heavy run --ticket T1032 -- \
  flock "$lock" "${CHAR3D_BLENDER:-blender}" -b --factory-startup -noaudio "$tmp/o/darksaddler.blend" \
  --python-exit-code 1 --python "$tmp/still.py" -- "$tmp/o" "$tmp/still.png" >"$tmp/still.log" 2>&1 \
  || { tail -20 "$tmp/still.log"; fail "close-up render"; }
[[ -n ${FACE_STILL:-} ]] && cp "$tmp/still.png" "$FACE_STILL"
python3 - "$tmp/o" <<'PY' || fail "eye read"
import json, sys
o = sys.argv[1]
b, r = json.load(open(o + '/build.json')), json.load(open(o + '/face_still.json'))
f, fr = b['stages']['face'], b['stages']['facerig']
print(json.dumps({s: {k: round(v, 3) if isinstance(v, float) else v for k, v in e.items()} for s, e in r.items()}))
assert f['expressions'] >= 8 and f['visemes'] >= 15 and f['arkit'] == 52, f
assert fr['lid_visible_pct'] == 0 and fr['lid_visible_open_pct'] > 50, fr
assert all(b['face']['controls'].get(f'blink.{s}') == f'["blink_{s}"]' for s in 'LR'), 'motion blink path unpublished'
assert fr['mouth_visible_pct'] >= 30 and fr['expr_reach_min_mm'] > 0, fr
for s, e in r.items():
    assert e['iris_px'] >= 60 and e['sclera_px'] >= 20, (s, e)
    assert e['catch_px'] >= 2, ('no catchlight', s, e)
    assert e['iris_mean'] > 0.2 * e['sclera_mean'], ('iris too dark', s, e)
PY
echo "PASS face"
