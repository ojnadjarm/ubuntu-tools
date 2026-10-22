#!/usr/bin/env bash
# Hair + haircards + props: zero-strand spec builds (no segfault), DarkSaddler atlas channels, card and prop budgets; ~2 min.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
c3d=$here/scripts/char3d
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

python3 - "$here/specs/placeholder.json" "$tmp/zero.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); s['hair'][0]['strands'] = 0; json.dump(s, open(sys.argv[2], 'w'))
PY
"$c3d" build "$tmp/zero.json" --out "$tmp/z" --draft --until haircards >/dev/null || fail "strands 0 build"
python3 - "$tmp/z/build.json" <<'PY' || fail "strands 0 metrics"
import json, sys
b = json.load(open(sys.argv[1])); h, c = b['stages']['hair'], b['stages']['haircards']
assert h['beard_strands'] == 0 and h['beard_guides'] >= 12 and 'cards' not in b['parts']['beard'], h
assert not c['stub'] and c['cards_tris']['beard'] > 0, c
PY

"$c3d" build "$here/specs/darksaddler.json" --out "$tmp/d" --draft --until haircards >/dev/null || fail "darksaddler build"
python3 - "$tmp/d/build.json" <<'PY' || fail "darksaddler metrics"
import json, os, sys
import numpy as np
from PIL import Image
b = json.load(open(sys.argv[1])); s = b['stages']; h, c, p = s['hair'], s['haircards'], s['props']
assert h['beard_strands'] == 4000 and h['moustache_strands'] == 800 and h['scalp_guides'] >= 60, h
assert not c['stub'] and c['todo'] == [] and set(c['atlas_files']) == {'beard', 'moustache', 'scalp'}, c
assert c['drape']['covered'] == 0 and c['drape']['moved']['beard'] > 0, c['drape']
assert 0 < sum(c['cards_tris'].values()) <= 12000, c['cards_tris']
assert c['texture_set'] == 'hair' and b['textures']['hair']['material'] == 'beard.cards', b['textures']['hair']
assert all(v >= 25 for v in c['alpha_cover_pct'].values()), c['alpha_cover_pct']
grooms = b['textures']['hair']['grooms']
assert len(grooms) == 3 and all(os.path.exists(g[m]) for g in grooms.values() for m in ('albedo', 'normal', 'orm', 'emissive')), grooms
for hid, f in c['atlas_files'].items():
    a = np.asarray(Image.open(f), float)
    a /= a.max()
    on = a[..., 3] > 0.5
    assert a.shape[2] == 4 and 0.1 < on.mean() < 0.8, (hid, on.mean())
    rows = [a[i, :, 0][on[i]].mean() for i in range(4, a.shape[0] // 2, a.shape[0] // 16) if on[i].any()]
    assert np.all(np.diff(rows) > 0), (hid, 'root-tip must grow down the tile', rows)
    assert a[..., 1][on].std() > 0.15 and a[..., 2][on].std() > 0.1, (hid, 'id / depth channels flat')
assert not p['stub'] and p['todo'] == [] and p['parts'] == 6 and 0 < p['tris'] <= 8000, p
for part in ('shaft', 'ferrule', 'binding', 'knob', 'claws', 'crystal'):
    assert f'staff.{part}' in b['parts'], part
PY
echo "PASS hair"
