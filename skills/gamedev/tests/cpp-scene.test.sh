#!/usr/bin/env bash
# cpp-vulkan glTF scene on a throwaway copy of the template (real build, Iris Xe under headless weston): a draw per node primitive with its own KTX2 material, AABB frustum culling, LOD by screen size.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
GP=${GLTFPACK:-$HOME/opt/gamedev/gltfpack-1.3/gltfpack}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
P=$T/game
"$G/scripts/new-cpp-game" "$P" > /dev/null || { echo "FAIL new-cpp-game"; exit 1; }
"$G/scripts/cpp-ci" --stages "configure build" "$P" > "$T/ci.log" 2>&1 || { echo "FAIL build"; cat "$T/ci.log" "$P"/ci/logs/*.log | tail -40; exit 1; }
# LOD 0 and 1: red, green, blue boxes; LOD 2 paints the centre box yellow.
for l in 0:0,255,0 1:0,255,0 2:255,255,0; do
	python3 "$G/tests/fixtures/make_scene_glb.py" "$T/src.glb" 255,0,0 "${l#*:}" 0,0,255 \
		&& "$GP" -i "$T/src.glb" -o "$T/model_lod${l%%:*}.glb" -tc -noq > /dev/null 2>&1 || { echo "FAIL fixture lod${l%%:*}"; exit 1; }
done
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; tail -15 "$T/run.log"; fails=$((fails + 1)); }
run() {  # capture-png game-args...
	local png=$1; shift
	"$G/scripts/cpp-vk-run.sh" --frames 3 "$P/build/ci-release/game" --model "$T/model_lod0.glb" --capture 1 "$png" "$@" > "$T/run.log" 2>&1
}
field() { sed -n "s/^DONE .* $1=\([0-9/]*\).*/\1/p" "$T/run.log"; }
# PNG X-FRACTION Y-FRACTION -> dominant channel r|g|b|y (yellow) or dark
colour() {
	python3 -I -c '
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
r, g, b = im.getpixel((int(float(sys.argv[2]) * (im.width - 1)), int(float(sys.argv[3]) * (im.height - 1))))
hi = max(r, g, b)
if hi < 60:
    print("dark")
elif min(r, g) > 0.6 * hi and b < 0.5 * hi:
    print("y")
else:
    print("rgb"[(r, g, b).index(hi)] if sorted((r, g, b))[1] * 2 < hi else "mix")
' "$@"
}

run "$T/near.png" --camera first
mats=$(grep -c '^MATERIAL base_color=\(bc7\|etc2\|rgba8\):' "$T/run.log")
if grep -q '^SCENE lods=3 materials=4 draws_lod0=3$' "$T/run.log" && [ "$mats" = 4 ] && grep -q '^DONE .*validation_errors=0 ' "$T/run.log"; then
	ok "scene: 3 LODs, 4 KTX2 materials (LOD 1 shares LOD 0's), 3 draws in LOD 0, 0 validation errors"
else bad "scene lines: $(grep -E '^(SCENE|DONE)' "$T/run.log" | tr '\n' ' ') ktx2 materials=$mats"; fi
got="$(colour "$T/near.png" 0.3 0.5) $(colour "$T/near.png" 0.5 0.5) $(colour "$T/near.png" 0.7 0.5)"
[ "$got" = "r g b" ] && ok "3 materials render 3 colours at known pixels" || bad "pixels '$got' want 'r g b'"
d=$(field draws); c=$(field culled)
[ "${d:-0}" -ge 3 ] && [ "${c:-0}" -ge 1 ] && ok "default camera draws=$d culled=$c" || bad "default camera draws=$d culled=$c"

run "$T/away.png" --camera 0,0.8,-3.2,0,0
d=$(field draws); c=$(field culled)
sky=$(colour "$T/away.png" 0.02 0.02); centre=$(colour "$T/away.png" 0.5 0.5)
[ "$d" = 0 ] && [ "${c:-0}" -ge 3 ] && [ "$centre" = "$sky" ] && ok "camera facing away: draws=0 culled=$c, centre is sky" || bad "facing away draws=$d culled=$c centre=$centre sky=$sky"

run "$T/far.png" --camera 0,0.8,8.5,0,-0.0938
l=$(field lods); centre=$(colour "$T/far.png" 0.5 0.47)  # the scene rests on y = 0 (T693): its centre box sits just above the frame centre
[ "${l##*/}" -ge 1 ] && [ "$centre" = y ] && ok "far camera picks LOD 2 (lods=$l, centre box yellow)" || bad "far camera lods=$l centre=$centre want LOD 2 yellow"

echo "cpp-scene.test: $fails failed"
exit $((fails > 0))
