#!/usr/bin/env bash
# Smoke: spec validation, MPFB body build, placeholder spec through build -> render -> qa; ~10 s on an idle box.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
c3d=$here/scripts/char3d
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

python3 -c "import sys; sys.path.insert(0, '$here/scripts'); from c3d import spec
for f in ('darksaddler', 'placeholder'): spec.load('$here/specs/%s.json' % f)" || fail "shipped specs do not validate"
python3 - "$here" "$out/bad.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1] + '/specs/placeholder.json')); s['body']['base'] = 'nope'
json.dump(s, open(sys.argv[2], 'w'))
PY
if "$c3d" build "$out/bad.json" --out "$out/bad" 2>/dev/null; then fail "bad spec accepted"; fi

"$here/scripts/char3d-setup" --check >/dev/null || fail "MPFB sandbox missing: run char3d-setup"
"$c3d" build "$here/specs/darksaddler.json" --out "$out/d" --draft --until body >/dev/null || fail "mpfb body build"
python3 -c "import json; m=json.load(open('$out/d/build.json'))['stages']['body']
assert not m.get('stub') and m['verts'] >= 15000 and m['quads_pct'] == 100 and m['shape_keys'] >= 67, m" || fail "mpfb body metrics"

"$c3d" build "$here/specs/placeholder.json" --out "$out/p" --draft || fail build
for f in placeholder.blend placeholder.glb placeholder_LOD1.glb build.json textures/main_albedo.png; do test -s "$out/p/$f" || fail "missing $f"; done
python3 - "$out/p/build.json" "$here/scripts/char3d" <<'PY' || fail "build stages"
import json, re, sys
b = json.load(open(sys.argv[1]))
want = re.search(r"STAGES = \[(.*?)\]", open(sys.argv[2]).read(), re.S).group(1).replace("'", '').replace('\n', '').split(',')
assert list(b['stages']) == [w.strip() for w in want], list(b['stages'])
assert b['parts']['robe'].get('high') and b['textures']['main']['albedo'] and b['lods']['1']['tris'] < b['lods']['0']['tris'], b['lods']
PY
"$c3d" render "$here/specs/placeholder.json" --out "$out/p" --draft || fail render
test -s "$out/p/renders/turntable.mp4" || fail "no mp4"
[ -z "$(find "$out/p/frames" -name '*.png' 2>/dev/null)" ] || fail "PNG frames left behind"
"$c3d" qa "$here/specs/placeholder.json" --out "$out/p" || fail qa
python3 -c "import json; s=json.load(open('$out/p/qa.json'))['summary']; assert s['checks'] >= 5 and s['fail'] == 0, s" || fail "qa summary"
echo "PASS smoke"
