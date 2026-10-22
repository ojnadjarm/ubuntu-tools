#!/usr/bin/env bash
# Lane detail-retopo: GN detail layers on the high twins, per-part LOD0 budgets, the SDF retopo methods; ~60 s.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

python3 - "$here/specs/darksaddler.json" "$out/v.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s['retopo'] = {'default': 'construction', 'ratio': {'belt.buckle': 0.5},
               'parts': {'staff.knob': 'instant_meshes', 'staff.claws': 'quadriflow', 'belt.buckle': 'decimate'}}
json.dump(s, open(sys.argv[2], 'w'))
PY
"$here/scripts/char3d" build "$out/v.json" --out "$out/b" --draft --until retopo >/dev/null || fail "build until retopo"

python3 - "$out/b/build.json" <<'PY' || fail "detail/retopo metrics"
import json, sys
b = json.load(open(sys.argv[1]))
d, r, layers = b['stages']['detail'], b['stages']['retopo'], b['spec']['detail']['layers']
assert not d['stub'] and not d['todo'], d['todo']
match = lambda p, k: p == k or p.startswith(k + '.')
want = {p for l in layers for p in l['parts']}
cage = b['spec'].get('bake', {}).get('cage_m', 0.01) * 1000
assert want <= set(d['per_part']), want - set(d['per_part'])
for pid in d['per_part']:
    assert b['parts'][pid].get('high', '').endswith('.high'), pid
    assert d['ratio'][pid] >= 4, (pid, d['ratio'][pid])
assert 'weave' in d['tiling'] and 'weave' not in d['disp_mm'], 'weave must stay out of the unique bake'
for l in layers:
    if l['kind'] == 'weave' or not l.get('depth_m'):
        continue
    got = d['disp_mm'][l['kind']]
    parts = [p for p in d['per_part'] if any(match(p, k) for k in l['parts'])]
    assert set(parts) <= set(got), (l['kind'], set(parts) - set(got))
    dm = l['depth_m'] * 1000
    assert max(got.values()) >= 0.3 * dm, (l['kind'], 'too flat', got)
    assert max(got.values()) <= 4 * dm, (l['kind'], 'runaway', got)
    assert max(got.values()) <= cage, (l['kind'], 'outside the bake cage', cage, got)
assert not r['stub'] and 30000 <= r['lod0_tris'] <= 80000 and r['quads_pct'] >= 95, r
assert d['per_part']['robe'] >= 4 * r['per_part']['robe'], r
m = r['method']
assert m['belt.buckle'] == 'decimate', m['belt.buckle']
assert m['staff.claws'] in ('quadriflow', 'instant_meshes'), m['staff.claws']
assert m['staff.knob'] == ('instant_meshes' if r['instant_meshes'] else 'quadriflow:fallback'), m['staff.knob']
assert all(r['per_part'][p] <= r['budget'][p] * 2.5 for p in ('staff.knob', 'staff.claws', 'belt.buckle')), r['budget']
print('detail', d['high_tris'], 'retopo', r['lod0_tris'], r['quads_pct'], {p: m[p] for p in ('staff.knob', 'staff.claws', 'belt.buckle')})
PY

cat > "$out/inspect.py" <<'PY'
import json, sys
import bpy
import numpy as np
sys.path.insert(0, sys.argv[-2])
from c3d import bpyutil as bu
b = json.load(open(sys.argv[-1]))
bad = []
for pid, p in b['parts'].items():
    ob = bpy.data.objects.get(p['object'])
    if ob is None or ob.type != 'MESH':
        continue
    bad += [f'{pid}: viewport subsurf on' for m in ob.modifiers if m.type == 'SUBSURF' and m.show_viewport]
    bad += [f'{pid}: solidify even offset on' for m in ob.modifiers if m.type == 'SOLIDIFY' and m.use_even_offset]
    if p.get('high'):
        hi = bpy.data.objects[p['high']]
        kinds = {l['kind'] for l in b['spec']['detail']['layers'] if l['kind'] != 'weave'
                 and any(pid == k or pid.startswith(k + '.') for k in l['parts'])}
        mods = {m.name[len('detail_'):] for m in hi.modifiers if m.type == 'NODES'}
        bad += [f'{pid}.high: render visible'] if not hi.hide_render else []
        bad += [f'{pid}.high: not in char3d_high'] if 'char3d_high' not in [c.name for c in hi.users_collection] else []
        bad += [f'{pid}.high: missing GN layers {kinds - mods}'] if kinds - mods else []
        remeshed = b['stages']['retopo']['method'].get(pid, '').startswith(('quadriflow', 'instant', 'decimate'))
        if not remeshed and not any(m.type == 'MASK' for m in ob.modifiers):
            lo, hv = bu.world_verts(ob), bu.world_verts(hi)
            dev = np.abs(np.concatenate([hv.min(0) - lo.min(0), hv.max(0) - lo.max(0)])).max()
            bad += [f'{pid}.high: spike, bbox {dev * 1000:.0f} mm off its low'] if dev > 0.04 else []
print('BAD', bad) if bad else print('INSPECT OK')
sys.exit(1 if bad else 0)
PY
heavy run --ticket T1032 -- blender -b --factory-startup -noaudio "$out/b/darksaddler.blend" --python-exit-code 1 \
  --python "$out/inspect.py" -- "$here/scripts" "$out/b/build.json" 2>&1 | grep -E "INSPECT OK|BAD" || fail "blend inspection"
echo "PASS detail"
