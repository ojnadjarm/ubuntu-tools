#!/usr/bin/env bash
# Materials + texture lanes: kind shaders and albedo bands, tiling detail normals, forced swap of the baked set
# materials (SSS/sheen kept, eyes untouched), glTF normalTexture is the baked map, painterly gradient; ~60 s idle.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
c3d=$here/scripts/char3d
spec=$here/specs/darksaddler.json
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

o=$tmp/ds
"$c3d" build "$spec" --out "$o" --draft --until texture >/dev/null || fail build
python3 - "$o" <<'PY' || fail "metrics"
import json, sys
import numpy as np
from PIL import Image
b = json.load(open(sys.argv[1] + '/build.json')); m, t = b['stages']['materials'], b['stages']['texture']
assert not m.get('stub') and m['materials'] >= 20 and m['curvature_parts'] >= 5, m
lo, hi = m['albedo_srgb']['dielectric']; mlo, mhi = m['albedo_srgb']['metal_lum']
assert 30 <= lo < hi <= 240 and 170 <= mlo < mhi <= 250 and m['albedo_clamped'] == 0, m
assert (lo, hi) != (30, 240), ('authored range sits on the clamp limits', lo, hi)
assert not t['stub'] and t['built'] == len(b['textures']) and t['variants'] > t['built'], t
assert t['detail_normals'] == len(b['spec']['textures']['detail_normals']), t
assert all(s['material'] in s['materials'].values() for s in b['textures'].values()), b['textures']
assert b['textures']['face']['material'].endswith('.skin') and 'mouth' in b['textures']['face']['materials'], b['textures']['face']
assert set(t['albedo_baked']) == {k for k, s in b['textures'].items() if not s.get('stub')}, t['albedo_baked']
assert all(a['out_pct'] < 1.0 for a in t['albedo_baked'].values()), ('baked albedo out of band', t['albedo_baked'])
for kind, path in t['detail_maps'].items():
    n = np.asarray(Image.open(path).convert('RGB'), np.float32) / 255
    seam = np.abs(n[0] - n[-1]).mean() + np.abs(n[:, 0] - n[:, -1]).mean()
    inner = np.abs(n[1:] - n[:-1]).mean() + np.abs(n[:, 1:] - n[:, :-1]).mean()
    assert seam < 2 * inner, (kind, 'not tiling', seam, inner)
    assert n[..., 2].mean() > 0.85 and abs(n[..., 0].mean() - 0.5) < 0.03 and abs(n[..., 1].mean() - 0.5) < 0.03, kind
    assert n[..., :2].std() > 0.03, (kind, 'flat')
PY
echo "ok metrics: materials, albedo bands, tiling detail normals"

cat >"$tmp/probe.py" <<'PY'
import json, struct, sys
from pathlib import Path
import bpy
sys.path.insert(0, sys.argv[-2])
from c3d.context import Context
from c3d.stages import texture
out = Path(sys.argv[-1])
spec = json.loads((out / 'build.json').read_text())['spec']
ctx = Context.load(out, spec, True)
ob = lambda pid: bpy.data.objects[ctx.parts[pid]['object']]
trim = ob('robe.trim').data.attributes.get('c3d_curv')
assert trim and max(abs(v.value) for v in trim.data) > 0.01, 'no curvature on the gold trim'
iris_before = [s.name for s in ob('iris.L').data.materials]
for t in ctx.textures.values():
    t['stub'] = False
r = texture.run(ctx)
assert r['swapped'] >= 10, r
body = ob('body').data.materials[0]
pb = body.node_tree.nodes['Principled BSDF']
assert body.name.startswith('_c3d_tex_body.skin') and pb.inputs['Subsurface Weight'].default_value == 1.0 \
    and pb.subsurface_method == 'RANDOM_WALK_SKIN', body.name
robe = ob('robe').data.materials[0]
rb = robe.node_tree.nodes['Principled BSDF']
assert rb.inputs['Sheen Weight'].default_value > 0 and not rb.inputs['Metallic'].is_linked, robe.name
trim = next(s for s in ob('robe.trim').data.materials if s.name.startswith('_c3d_tex_'))
assert trim.node_tree.nodes['Principled BSDF'].inputs['Metallic'].is_linked, trim.name
assert sum(n.type == 'GROUP' for n in robe.node_tree.nodes) == 1, 'robe weave detail missing'
assert [s.name for s in ob('iris.L').data.materials] == iris_before, 'eye swapped'
bpy.ops.object.select_all(action='DESELECT')
for pid in ('robe', 'staff.shaft'):
    ob(pid).select_set(True)
glb = out / 'probe.glb'
bpy.ops.export_scene.gltf(filepath=str(glb), use_selection=True, export_format='GLB')
raw = glb.read_bytes()
g = json.loads(raw[20:20 + struct.unpack('<I', raw[12:16])[0]])
names = {m['name']: g['images'][g['textures'][m['normalTexture']['index']]['source']]['name']
         for m in g['materials'] if 'normalTexture' in m}
assert any(k.startswith('_c3d_tex_robe.robe') and v == 'robe_normal' for k, v in names.items()), names
assert not any(v.startswith('detail_') for v in names.values()), names
mat = texture.set_material('robe', ctx.textures['robe'], 'robe', spec['materials']['robe'], [], {}, 'gradient', 1.8)
link = mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].links[0]
assert link.from_node.type == 'VECT_MATH' and link.from_node.operation == 'MAXIMUM', 'gradient not wired'
print('PROBE OK', r['swapped'], names)
PY
heavy run --ticket T1032 -- blender -b --factory-startup -noaudio "$o/darksaddler.blend" --python-exit-code 1 \
  --python "$tmp/probe.py" -- "$here/scripts" "$o" >"$tmp/probe.log" 2>&1 || { tail -20 "$tmp/probe.log"; fail "swap probe"; }
grep -q "PROBE OK" "$tmp/probe.log" || fail "probe silent"
echo "ok swap: SSS/sheen kept, eyes untouched, glTF normal = baked map, gradient option"
echo "PASS texture"
