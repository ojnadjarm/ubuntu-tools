#!/usr/bin/env bash
# uv + bake: placeholder spec with a Cycles bake under a held CHAR3D_LOCK; UV overlap, texel, normal bias and
# back-facing texels, coverage, maps.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d); trap 'kill %1 2>/dev/null || true; rm -rf "$out"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

python3 - "$here/specs/placeholder.json" "$out/v.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s['uv'] = {'default_set': 'main', 'margin_px': 4, 'sets': [{'id': 'main', 'size': 512, 'parts': [], 'texel_px_cm': 0.3}]}
s['bake'] = {'mode': 'cycles', 'size': {'draft': 64}, 'samples': {'ao': 4}, 'cage_m': 0.01}
json.dump(s, open(sys.argv[2], 'w'))
PY

export CHAR3D_LOCK=$out/render.lock
flock "$CHAR3D_LOCK" sleep 25 &
"$here/scripts/char3d" build "$out/v.json" --out "$out/p" --draft --until bake >/dev/null || fail "build until bake"

python3 - "$out/p/build.json" <<'PY' || fail "uv/bake metrics"
import json, sys
from PIL import Image
import numpy as np
b = json.load(open(sys.argv[1]))
u, k = b['stages']['uv'], b['stages']['bake']
assert not u['stub'] and u['overlap_faces'] == 0 and u['texel_px_cm_min'] >= 0.3 and u['texel_ok'], u
assert u['texel_head_hands_min'] >= u['texel_head_hands_floor'], u
assert not k['stub'] and k['mode'] == 'cycles' and k['normal_bias'] <= 0.02 and k['normal_bias_cover'] > 0.9, k
assert k['normal_back_pct'] <= 1.0 and all(v > 10 for v in k['cover_pct'].values()), k
assert k['lock_wait_s'] >= 2, f"bake did not wait for the held lock: {k['lock_wait_s']}"
for sid, t in b['textures'].items():
    assert not t['stub'] and t['baked_size'] == 64, t
    px = {m: np.asarray(Image.open(t[m]).convert('RGB'), np.float32) / 255 for m in ('albedo', 'normal', 'orm', 'emissive', 'curvature')}
    assert all(v.shape == (64, 64, 3) for v in px.values()), {m: v.shape for m, v in px.items()}
    n = px['normal'].reshape(-1, 3).mean(axis=0)
    assert abs(n[0] - 0.5) < 0.05 and abs(n[1] - 0.5) < 0.05 and n[2] > 0.85, n
    assert len(np.unique(px['albedo'].reshape(-1, 3).round(2), axis=0)) > 3, 'albedo is flat'
    assert 0.05 < px['orm'][..., 0].mean() <= 1 and px['orm'][..., 1].std() > 0.01, 'ORM AO/roughness not baked'
    assert px['emissive'].max() > 0.2, 'crystal emission not baked'
print('ok', {s: t['baked_size'] for s, t in b['textures'].items()}, 'bias', k['normal_bias'], 'back%', k['normal_back_pct'],
      'cover%', k['cover_pct'], 'head/hands', u['texel_head_hands'], 'wait', k['lock_wait_s'])
PY
echo "PASS bake"
