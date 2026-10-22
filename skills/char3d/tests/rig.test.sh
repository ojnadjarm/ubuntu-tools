#!/usr/bin/env bash
# Rig lane: darksaddler built --until rig; Rigify bar (bones, <= 4 influences, game skeleton, rigid pieces, ground) at
# rest and in 5 test poses; prop follows the hand; hard pieces stay rigid; arms down: <= 1 % of an outer garment layer's
# near vertices pass through the layer under it.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
spec=${1:-$here/specs/darksaddler.json}
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

"$here/scripts/char3d" build "$spec" --out "$out" --draft --until rig >/dev/null || fail build
python3 - "$out/build.json" <<'PY' || fail "build.json rig metrics"
import json, sys
b = json.load(open(sys.argv[1])); m = b['stages']['rig']
assert not m.get('stub') and m['bones'] >= 700 and m['unweighted_verts'] == 0 and m['rest_min_z_mm'] >= -1, m
assert m['max_influences'] <= 4, ('glTF keeps 4 influences', m['max_influences'])
g = m['game']; assert g['roots'] == ['DEF-ground'] and 40 <= g['bones'] <= 120, ('game skeleton: one root, DEF only', g)
assert m['bound']['rigid'] >= 3, ('rigid-bound hard pieces (hat, buckle, cards)', m['bound'])
assert len(b['bones']) == 15 and 'foot.L' in b['controls'] and all(f'prop:{p["id"]}' in b['controls'] for p in b['spec']['props']), b['controls']
print('rig', {k: m[k] for k in ('bones', 'def_bones', 'unweighted_verts', 'max_influences', 'rest_min_z_mm', 'cache', 'seconds')}, g)
PY
cat > "$out/pose.py" <<'PY'
import json, sys
import bpy
import numpy as np
from mathutils import Vector
b = json.load(open(bpy.path.abspath('//build.json')))
rig = bpy.data.objects[b['parts']['rig']['object']]
pb, ctl = rig.pose.bones, b['controls']
meshes = [bpy.data.objects[p['object']] for p in b['parts'].values() if bpy.data.objects[p['object']].type == 'MESH']
prop = next((v for k, v in ctl.items() if k.startswith('prop:')), None)
hand = pb[b['bones']['hand.L']]


def move(name, d):
    pb[name].location = pb[name].bone.matrix_local.to_3x3().inverted() @ Vector(d)


def min_z():
    dg = bpy.context.evaluated_depsgraph_get()
    out = []
    for ob in meshes:
        me = ob.evaluated_get(dg).to_mesh()
        if len(me.vertices):
            co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get('co', co)
            m = np.array(ob.matrix_world)
            out.append((co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3])[:, 2].min())
        ob.evaluated_get(dg).to_mesh_clear()
    return 1000 * min(out)


def layer_signs(outer, inner):
    """Signed offset (m) of each evaluated outer-layer vertex from the inner layer's nearest surface point."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    v = {}
    for ob in (outer, inner):
        me = ob.evaluated_get(dg).to_mesh()
        v[ob] = ([ob.matrix_world @ x.co for x in me.vertices], [tuple(f.vertices) for f in me.polygons])
        ob.evaluated_get(dg).to_mesh_clear()
    tree = BVHTree.FromPolygons(*v[inner])
    out = []
    for co in v[outer][0]:
        loc, n, _, _ = tree.find_nearest(co)
        out.append((co - loc).dot(n))
    return np.array(out)


LAYERS = [(o, i) for o, i in (('mantle', 'robe'), ('robe', 'inner_robe')) if o in b['parts'] and i in b['parts']]
layers0 = {(o, i): layer_signs(*(bpy.data.objects[b['parts'][x]['object']] for x in (o, i))) for o, i in LAYERS}
rel0 = (hand.matrix.inverted() @ pb[prop].matrix) if prop else None
poses = {'stride': [(ctl['foot.L'], (0, -0.17, 0)), (ctl['foot.R'], (0, 0.17, 0)), (ctl['torso'], (0, 0, -0.03))],
         'step_up': [(ctl['foot.L'], (0, -0.2, 0.12)), (ctl['torso'], (0.02, -0.03, -0.02))],
         'reach': [(ctl['hand.L'], (-0.05, -0.3, 0.35)), (ctl['hand.R'], (0.1, -0.25, 0.1))],
         'crouch': [(ctl['torso'], (0, 0.03, -0.12))],
         'arms_down': [(ctl['hand.L'], (-0.22, 0.11, -0.15)), (ctl['hand.R'], (0.22, 0.11, -0.15))]}
res = {}
for name, moves in poses.items():
    for p in pb:
        p.location = (0, 0, 0)
    for n, d in moves:
        move(n, d)
    bpy.context.view_layer.update()
    drift = 0.0
    if prop:
        rel = hand.matrix.inverted() @ pb[prop].matrix
        drift = 1000 * max((rel.translation - rel0.translation).length, *((rel.col[i].xyz - rel0.col[i].xyz).length for i in range(3)))
    res[name] = {'min_z_mm': round(min_z(), 2), 'prop_drift_mm': round(drift, 3)}
    if name == 'arms_down':
        for (o, i), s0 in layers0.items():
            s1 = layer_signs(*(bpy.data.objects[b['parts'][x]['object']] for x in (o, i)))
            near = (s0 > 0.002) & (s0 < 0.03)
            res[name][f'through:{o}>{i}'] = round(float((near & (s1 < -0.002)).sum() / max(near.sum(), 1)), 4)
hard = [pid for pid in b['parts'] if pid.endswith(('.buckle', '.cards'))]
for pid in hard:
    ob = bpy.data.objects[b['parts'][pid]['object']]
    defs = {g.index for g in ob.vertex_groups if g.name.startswith('DEF-')}
    multi = sum(1 for v in ob.data.vertices if sum(1 for g in v.groups if g.group in defs and g.weight > 1e-6) != 1)
    res['rigid:' + pid] = {'min_z_mm': 0.0, 'prop_drift_mm': 0.0, 'multi_bone_verts': multi}
print('POSES ' + json.dumps(res))
PY
log=$(heavy run --ticket "${CHAR3D_TICKET:-T1032}" -- blender -b --factory-startup -noaudio "$out/$(python3 -c "import json;print(json.load(open('$out/build.json'))['spec']['id'])").blend" \
      --python-exit-code 1 --python "$out/pose.py" 2>&1) || { echo "$log" | tail -20; fail "pose script"; }
python3 - "$(echo "$log" | grep '^POSES ' | cut -c7-)" <<'PY' || fail "pose checks"
import json, sys
r = json.loads(sys.argv[1]); print('poses', r)
bad = {k: v for k, v in r.items() if v['min_z_mm'] < -1 or v['prop_drift_mm'] > 0.1 or v.get('multi_bone_verts')
       or any(x > 0.01 for q, x in v.items() if q.startswith('through:'))}
assert any(k.startswith('rigid:') for k in r), 'no rigid pieces checked'
assert not bad, bad
PY
echo "PASS rig"
