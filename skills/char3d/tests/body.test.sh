#!/usr/bin/env bash
# Body stage: MPFB elder from darksaddler.json (cache miss then hit), 7.5-8 heads, 30 finger bones, landmarks, hide-under,
# bad target; ~30 s.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
c3d=$here/scripts/char3d
spec=$here/specs/darksaddler.json
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export CHAR3D_CACHE=$tmp/cache
fail() { echo "FAIL: $*"; exit 1; }

"$here/scripts/char3d-setup" --check || fail "MPFB sandbox missing: run char3d-setup"
for run in miss hit; do
  "$c3d" build "$spec" --out "$tmp/o" --draft --until body >/dev/null || fail "build ($run)"
  python3 - "$tmp/o/build.json" "$run" <<'PY' || fail "metrics ($run)"
import json, sys
b = json.load(open(sys.argv[1])); m = b['stages']['body']; lm = b['landmarks']
assert m['cache'] == sys.argv[2], m['cache']
assert not m.get('stub') and m['verts'] >= 15000 and m['quads_pct'] == 100 and m['uv_layers'] >= 1, m
assert 7.5 <= m['heads_tall'] <= 8.0 and abs(m['heads_tall'] - b['spec']['body']['heads_tall']) < 0.05, m
assert m['finger_bones'] >= 30, m
assert m['shape_keys'] >= 67 and m['packs'] == {'faceunits01': 52, 'visemes02': 15}, m
assert m['hidden_verts'] > 1000 and m['visible_verts'] < m['verts'], m
assert len(lm) == 15 and lm['eye.L'][0] > 0 > lm['eye.L'][1] and lm['eye.R'][0] < 0, lm
assert abs(lm['head'][2] - 1.62) < 0.1 and lm['root'][2] == 0 and 0 < lm['toe.L'][2] < lm['foot.L'][2], lm
assert m['seconds'] < 60 and b['parts']['body']['object'] == 'body', m
PY
done
python3 - "$spec" "$tmp/bad.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); s['body']['targets'] = {'nope': 0.5}; json.dump(s, open(sys.argv[2], 'w'))
PY
if "$c3d" build "$tmp/bad.json" --out "$tmp/bad" --until body 2>/dev/null; then fail "unknown target accepted"; fi
grep -q "unknown target 'nope'" "$tmp/bad/logs/build.log" || fail "unknown target not named in the log"
echo "PASS body"
