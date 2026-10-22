#!/usr/bin/env bash
# Garments stage: DarkSaddler asset gate (budget, quads, sleeves, drape, pouches, hat, boots) + unknown kind -> todo; ~1 min.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
c3d=$here/scripts/char3d
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

"$c3d" build "$here/specs/darksaddler.json" --out "$out/d" --draft --until garments >/dev/null || fail "darksaddler build"
python3 - "$out/d/build.json" <<'PY' || fail "darksaddler garment metrics"
import json, sys
b = json.load(open(sys.argv[1]))
g = b['stages']['garments']
assert not g['stub'] and g['todo'] == [], g['todo']
assert g['tris_total'] <= 40000 and g['robe_tris'] <= 15000, (g['tris_total'], g['robe_tris'])
assert g['quads_pct'] >= 95 and g['sleeves'] == 2, (g['quads_pct'], g['sleeves'])
assert g['rest_penetration_verts'] == 0 and g['uv_missing'] == 0 and g['min_z_m'] >= 0, g
assert g['self_x'].get('robe', 0) <= 600 and g['self_x'].get('mantle', 0) <= 20, g['self_x']   # 1045 before the local exit
for gid in ('inner_robe', 'robe', 'mantle'):
    d = g['drape'][gid]
    assert d['verts'] > 0 and d['frames'] > 0 and d['mean_move_mm'] > 1 and d['settled'], (gid, d)
assert g['hat_crease_deg'] > 0 and g['hat_droop'] > 0 and g['hat_tip_angle_deg'] > 90, g
assert g['boot_heel_m'] > g['boot_sole_m'] > 0 and g['boot_cuff_m'] > 0, g
need = {'robe', 'robe.trim', 'robe.scroll', 'inner_robe', 'mantle', 'belt', 'belt.buckle', 'hat', 'hat.trim',
        'boots', 'boots.R'} | {f'{p}{s}' for p in ('pouch_l', 'pouch_r') for s in ('', '.flap', '.stud')}
miss = need - set(b['parts'])
assert not miss, miss
assert all(b['parts'][p]['stage'] == 'garments' for p in need)
PY

python3 - "$here/specs/placeholder.json" "$out/p.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s['garments'].append({'id': 'pad', 'kind': 'pauldron', 'material': 'cloth', 'attach': 'chest'})
json.dump(s, open(sys.argv[2], 'w'))
PY
"$c3d" build "$out/p.json" --out "$out/p" --draft --until garments >/dev/null || fail "placeholder build"
python3 -c "import json; g=json.load(open('$out/p/build.json'))['stages']['garments']
assert g['stub'] and g['todo'] == ['pad:pauldron'] and g['rest_penetration_verts'] == 0 and g['quads_pct'] >= 95, g" \
  || fail "unknown kind must be a todo, not a crash"
echo "PASS garments"
