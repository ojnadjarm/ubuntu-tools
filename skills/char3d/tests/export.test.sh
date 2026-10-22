#!/usr/bin/env bash
# Export + LOD: an MPFB + Rigify + 92 shape-key fixture -> GLB 0/0, 4 clips, >= 52 morphs, < 30 MB, FBX with the game skeleton
# (<= 200 bones, one take per clip, shape keys); then the placeholder build with FBX and LOD1/LOD2 (0/0, skin + morphs kept).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
c3d=$here/scripts/char3d
fixture=${CHAR3D_EXPORT_FIXTURE:-$HOME/agent-work/research/2026-10-20/T1032/export-docs/fixture/mpfb_elder_face.blend}
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

check() {  # check GLB CLIPS MIN_TARGETS
  gltf_validator -o "$1" > "$1.val.json" 2>/dev/null || true
  python3 - "$1" "$2" "$3" <<'PY' || fail "glb checks $1"
import json, os, struct, sys
glb, clips, tmin = sys.argv[1], sorted(sys.argv[2].split(',')), int(sys.argv[3])
v = json.load(open(glb + '.val.json'))['issues']
d = open(glb, 'rb').read(); g = json.loads(d[20:20 + struct.unpack('<I', d[12:16])[0]])
anims = sorted(a['name'] for a in g.get('animations', []))
t = max((len(p.get('targets', [])) for m in g['meshes'] for p in m['primitives']), default=0)
mb = os.path.getsize(glb) / 1e6
print(f'export: {os.path.basename(glb)} errors {v["numErrors"]} warnings {v["numWarnings"]} anims {anims} targets {t} {mb:.1f} MB')
assert v['numErrors'] == 0 and v['numWarnings'] == 0, [m['code'] for m in v['messages'] if m['severity'] < 2]
assert anims == clips and t >= tmin and mb < 30, (anims, t, mb)
PY
}

fbx_check() {  # fbx_check FBX CLIPS MIN_KEYS: re-import, game skeleton <= 200 bones, one take per clip, shape keys
  cat > "$out/fbx.py" <<'PY'
import json, sys
import bpy
fbx, clips, kmin = sys.argv[sys.argv.index('--') + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
(bpy.ops.wm.fbx_import if hasattr(bpy.ops.wm, 'fbx_import') else bpy.ops.import_scene.fbx)(filepath=fbx)
bones = [len(o.data.bones) for o in bpy.data.objects if o.type == 'ARMATURE']
keys = max((len(o.data.shape_keys.key_blocks) - 1 for o in bpy.data.objects if o.type == 'MESH' and o.data.shape_keys), default=0)
takes = sorted({a.name.split('|')[-1] for a in bpy.data.actions})
print('fbx:', json.dumps({'bones': bones, 'takes': takes, 'shape_keys': keys}))
assert len(bones) == 1 and 0 < bones[0] <= 200 and takes == sorted(clips.split(',')) and keys >= int(kmin), (bones, takes, keys)
PY
  heavy run --ticket "${CHAR3D_TICKET:-T1032}" -- blender -b --factory-startup -noaudio --python-exit-code 1 \
    --python "$out/fbx.py" -- "$1" "$2" "$3" > "$out/fbx.log" 2>&1 || { tail -5 "$out/fbx.log"; fail "fbx $1"; }
  grep '^fbx:' "$out/fbx.log"
}

if [ -s "$fixture" ]; then
cat > "$out/drive.py" <<'PY'
import sys
from pathlib import Path
argv = sys.argv[sys.argv.index('--') + 1:]
sys.path.insert(0, argv[0])
import bpy
from c3d.context import Context
from c3d.stages import export
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and len(o.data.bones) > 500)
names = set(rig.data.bones.keys())
parts = {'rig': {'object': rig.name, 'stage': 'rig', 'material': None, 'attach': None}}
for ob in [o for o in bpy.data.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers)]:
    arms = [m for m in ob.modifiers if m.type == 'ARMATURE']
    for m in arms[1:]:
        ob.modifiers.remove(m)
    arms[0].object = rig
    for vg in ob.vertex_groups:
        if 'DEF-' + vg.name in names:
            vg.name = 'DEF-' + vg.name
    mw = ob.matrix_world.copy(); ob.parent = rig; ob.matrix_world = mw
    parts[ob.name] = {'object': ob.name, 'stage': 'body', 'material': None, 'attach': None}
for o in [o for o in bpy.data.objects if o.type == 'ARMATURE' and o is not rig]:
    bpy.data.objects.remove(o)
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.25, depth=0.8, location=(0, 0, 0.9), end_fill_type='NOTHING')
robe = bpy.context.active_object; robe.name = 'robe'
robe.vertex_groups.new(name='DEF-spine').add(range(len(robe.data.vertices)), 1.0, 'REPLACE')
for kind in ('SOLIDIFY', 'SUBSURF', 'CLOTH'):
    robe.modifiers.new(kind.lower(), kind)
robe.modifiers.new('arm', 'ARMATURE').object = rig; robe.parent = rig
parts['robe'] = {'object': 'robe', 'stage': 'garments', 'material': None, 'attach': 'hips'}
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.02, depth=1.6, location=(-0.3, 0, 0.8))
staff = bpy.context.active_object; staff.name = 'staff.shaft'
mw = staff.matrix_world.copy(); staff.parent, staff.parent_type, staff.parent_bone = rig, 'BONE', 'DEF-hand.R'
bpy.context.view_layer.update(); staff.matrix_world = mw
parts['staff.shaft'] = {'object': staff.name, 'stage': 'props', 'material': None, 'attach': 'hand.R'}
beard = bpy.data.objects.new('beard', bpy.data.hair_curves.new('beard')); rig.users_collection[0].objects.link(beard)
bpy.ops.mesh.primitive_plane_add(size=0.15, location=(0, -0.12, 1.45))
cards = bpy.context.active_object; cards.name = 'beard.cards'
cards.vertex_groups.new(name='DEF-spine').add(range(4), 1.0, 'REPLACE')
cards.modifiers.new('arm', 'ARMATURE').object = rig; cards.parent = rig
parts['beard'] = {'object': 'beard', 'stage': 'hair', 'material': None, 'attach': None, 'cards': 'beard.cards'}
parts['beard.cards'] = {'object': 'beard.cards', 'stage': 'hair', 'material': None, 'attach': 'jaw'}
keys = [o.data.shape_keys for o in bpy.data.objects if o.type == 'MESH' and o.data.shape_keys]
ctrl = [b for b in ('torso', 'head', 'chest') if b in names]
clips = {}
for cid, n in (('idle', 120), ('walk', 72), ('talk', 120), ('cast', 72)):
    act = bpy.data.actions.new(cid); act.use_fake_user = True
    rig.animation_data_create().action = act
    for f in range(1, n + 2):
        for b in ctrl:
            pb = rig.pose.bones[b]; pb.location = (0, 0, 0.02 * ((f % 20) / 20)); pb.keyframe_insert('location', frame=f)
    for k in keys:
        k.animation_data_create().action = act
        kb = k.key_blocks[min(5, len(k.key_blocks) - 1)]
        for f in (1, n // 2, n + 1):
            kb.value = float(f == n // 2); kb.keyframe_insert('value', frame=f)
    clips[cid] = {'action': act.name, 'start': 1, 'end': n, 'fps': 30, 'loop': True, 'contacts': []}
src_inf = {o: export.influences(o) for o in bpy.data.objects if o.type == 'MESH'}
key_names = {o.name: o.data.shape_keys.name for o in bpy.data.objects if o.type == 'MESH' and o.data.shape_keys}
ctx = Context(spec={'id': 'mpfb', 'export': {'gltf': True, 'morphs': True, 'actions': True, 'hair': 'cards', 'fbx': True}}, out=Path(argv[1]))
ctx.parts, ctx.clips = parts, clips
m = export.run(ctx)
print('char3d export metrics', m)
assert m['skipped'] == [] and m['as_cards'] == ['beard'] and m['proxies'] >= 6 and m['joints'] <= 200 and m['fbx_mb'] > 0, m
assert m['max_influences'] <= 4 and all(export.influences(o) == n for o, n in src_inf.items()), (m, src_inf)
after = {o.name: o.data.shape_keys.name for o in bpy.data.objects if o.type == 'MESH' and o.data.shape_keys}
assert after == key_names, (after, key_names)
left = [o.name for o in bpy.data.objects if o.name.endswith(('.src', '.game'))] + [t.name for t in rig.animation_data.nla_tracks]
assert not left and len(robe.modifiers) == 4 and robe.name == 'robe', ('scene not restored', left)
PY
heavy run --ticket "${CHAR3D_TICKET:-T1032}" -- blender -b --factory-startup -noaudio "$fixture" --python-exit-code 1 \
  --python "$out/drive.py" -- "$here/scripts" "$out/m" > "$out/m.log" 2>&1 || { tail -20 "$out/m.log"; fail "mpfb export"; }
grep 'char3d export metrics' "$out/m.log"
check "$out/m/mpfb.glb" "cast,idle,talk,walk" 52
fbx_check "$out/m/mpfb.fbx" "cast,idle,talk,walk" 52
else echo "SKIP mpfb fixture ($fixture missing)"; fi

python3 - "$here/specs/placeholder.json" "$out/p.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); s['export']['fbx'] = True; s.setdefault('asset', {})['lods'] = [0.5, 0.25]
json.dump(s, open(sys.argv[2], 'w'))
PY
"$c3d" build "$out/p.json" --out "$out/p" --draft >/dev/null || fail "placeholder build (an upstream stage failed, see its log)"
clips=$(python3 -c "import json; print(','.join(c['id'] for c in json.load(open('$out/p.json'))['motion']['clips']))")
check "$out/p/placeholder.glb" "$clips" 0
fbx_check "$out/p/placeholder.fbx" "$clips" 0
python3 - "$out/p/build.json" <<'PY' || fail "lods"
import json, sys
b = json.load(open(sys.argv[1])); L = b['lods']
print('lod:', {k: (v['tris'], v['joints'], v['morph_targets']) for k, v in L.items()})
for k, cap in (('1', 0.55), ('2', 0.30)):
    assert L[k]['tris'] <= cap * L['0']['tris'] and L[k]['joints'] == L['0']['joints'] > 0, (k, L[k])
    assert L[k]['morph_targets'] == L['0']['morph_targets'], (k, L[k])
PY
for k in 1 2; do
  gltf_validator -o "$out/p/placeholder_LOD$k.glb" 2>/dev/null | python3 -c "import json,sys; i=json.load(sys.stdin)['issues']; print('LOD$k', i['numErrors'], i['numWarnings']); assert i['numErrors'] == i['numWarnings'] == 0" || fail "LOD$k validator"
done
echo "PASS export"
