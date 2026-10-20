#!/usr/bin/env bash
# glb-info.test.sh: glb-info and lib/glb.py on anim-hero.glb (2 clips, channels by path), a synthetic strided 1-triangle glb with normalized colours, a non-glb (rc 2, one line), and the callers' lib import through symlinks (T994).
set -uo pipefail
A=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
BIN=$A/bin/glb-info
HERO=$A/skills/motion-video/tests/fixtures/anim-hero.glb
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
has() { grep -qE "$2" <<<"$1" && echo 1 || echo 0; }

o=$("$BIN" "$HERO" 2>&1); rc=$?
ok "$([[ $rc == 0 ]] && echo 1 || echo 0)" "anim-hero: rc 0 (got $rc)"
ok "$(has "$o" '^meshes 1, primitives 1, triangles 972$')" "anim-hero: 972 triangles"
ok "$(has "$o" '^  skin Armature: 2 joints$')" "anim-hero: skin with 2 joints"
ok "$(has "$o" '^clips 2$')" "anim-hero: 2 clips"
ok "$(has "$o" '^  clip Bend: 1\.00 s, 6 channels \(rotation 2, scale 2, translation 2\), 35 keys$')" "anim-hero: Bend channels by path, 35 keys"
ok "$(has "$o" '^  clip Still: 1\.00 s, 6 channels \(rotation 2, scale 2, translation 2\), 12 keys$')" "anim-hero: Still channels by path, 12 keys"
ok "$(has "$o" '^bbox min \[-0\.35, 0\.75, -0\.35\] max \[0\.35, 2\.25, 0\.35\]')" "anim-hero: bounding box"
j=$("$BIN" --json "$HERO")
ok "$([[ $(jq -c '[.clips[].paths.rotation, (.clips | length), .triangles]' <<<"$j") == '[2,2,2,972]' ]] && echo 1 || echo 0)" "anim-hero --json: clips, paths, triangles"

python3 -I - "$TMP/tri.glb" <<'PY'
import json, struct, sys
rows = [(0, 0, 0, (255, 0, 128, 255)), (1, 0, 0, (0, 255, 0, 255)), (0, 1, 0, (0, 0, 255, 255))]
blob = b"".join(struct.pack("<3f4B", x, y, z, *c) for x, y, z, c in rows)
g = {"asset": {"version": "2.0", "generator": "glb-info.test"}, "scene": 0, "scenes": [{"nodes": [0]}],
     "nodes": [{"name": "Tri", "mesh": 0, "translation": [10, 0, 0]}],
     "meshes": [{"name": "Tri", "primitives": [{"attributes": {"POSITION": 0, "COLOR_0": 1}}]}],
     "buffers": [{"byteLength": len(blob)}], "bufferViews": [{"buffer": 0, "byteLength": len(blob), "byteStride": 16}],
     "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
                   {"bufferView": 0, "byteOffset": 12, "componentType": 5121, "normalized": True, "count": 3, "type": "VEC4"}]}
js = json.dumps(g).encode()
js += b" " * (-len(js) % 4)
open(sys.argv[1], "wb").write(b"glTF" + struct.pack("<II", 2, 28 + len(js) + len(blob)) + struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + blob)
PY
o=$("$BIN" "$TMP/tri.glb" 2>&1); rc=$?
ok "$( [[ $rc == 0 && $(has "$o" '^meshes 1, primitives 1, triangles 1$')$(has "$o" '^clips 0$') == 11 ]] && echo 1 || echo 0)" "1-triangle glb: rc 0, 1 triangle, 0 clips (rc $rc)"
ok "$(has "$o" '^bbox min \[10, 0, 0\] max \[11, 1, 0\]')" "1-triangle glb: strided positions, node translation in the bbox"
c=$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import glb; g, b = glb.load(sys.argv[2]); print([round(v, 3) for v in glb.accessor(g, b, 1)[0]])' "$A/lib" "$TMP/tri.glb")
ok "$([[ $c == '[1.0, 0.0, 0.502, 1.0]' ]] && echo 1 || echo 0)" "lib accessor: byteStride + normalized ubyte ($c)"

printf 'not a model\n' >"$TMP/x.glb"
o=$("$BIN" "$TMP/x.glb" 2>&1); rc=$?
ok "$( [[ $rc == 2 && $(wc -l <<<"$o") == 1 && $o == "glb-info: $TMP/x.glb: "* ]] && echo 1 || echo 0)" "non-glb: rc 2, one line (rc $rc: $o)"

mkdir "$TMP/l"
ln -s "$A/skills/motion-video/scripts/mv-layout" "$TMP/l/mv-layout"
ln -s "$A/skills/gamedev/scripts/asset_quality.py" "$TMP/l/aq.py"
ok "$("$TMP/l/mv-layout" --help >/dev/null 2>&1 && echo 1 || echo 0)" "mv-layout through a symlink finds lib/glb.py"
ok "$(python3 -I "$TMP/l/aq.py" --help >/dev/null 2>&1 && echo 1 || echo 0)" "asset_quality.py through a symlink finds lib/glb.py"

echo "glb-info: $((n - bad))/$n"
((bad == 0))
