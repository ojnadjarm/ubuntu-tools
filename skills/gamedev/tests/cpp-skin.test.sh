#!/usr/bin/env bash
# T657/T691 skinned player on a throwaway copy of the template (real build, Iris Xe under headless weston): golden passes, the idle -> walk crossfade midpoint is a 50/50 per-joint blend (1e-4), the third-person character is drawn and moves with the replay, two replays give identical frames, the spring arm is not cut by the invisible arena walls, 0 validation errors, skinned GPU zone timed.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
P=$T/game
FIX=$G/tests/fixtures/cpp-play-input.json
"$G/scripts/new-cpp-game" "$P" > /dev/null || { echo "FAIL new-cpp-game"; exit 1; }
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
field() { sed -n "s/^DONE .* $2=\([0-9.]*\).*/\1/p" "$1"; }

"$G/scripts/cpp-ci" --stages "configure build golden" "$P" > "$T/ci.log" 2>&1
flip=$(jq -r '.stages.golden.flip_mean' "$P/ci/summary.json" 2>/dev/null)
[ "$(jq -r '.stages.golden.status' "$P/ci/summary.json" 2>/dev/null)" = pass ] && ok "template golden with the character passes (flip_mean=$flip <= 0.02)" \
	|| { bad "golden: $(jq -c '.stages.golden' "$P/ci/summary.json" 2>/dev/null)"; tail -20 "$T/ci.log"; }

g++ -std=c++20 -O1 -I"$P/src" -isystem "$P/build/ci-release/vcpkg_installed/x64-linux/include" \
	"$G/tests/fixtures/anim-blend-check.cpp" "$P/src/animation.cpp" -o "$T/blend" 2> "$T/blend.log" \
	&& "$T/blend" "$P/assets/character.glb" >> "$T/blend.log" 2>&1 && ok "crossfade: $(grep '^BLEND' "$T/blend.log")" \
	|| { bad "crossfade check"; tail -5 "$T/blend.log"; }

cap() {  # frame name game-args...: capture frame N, validation (sync + best practices) on
	local frame=$1 name=$2; shift 2
	"$G/scripts/cpp-vk-run.sh" --frames $((frame + 1)) "$P/build/ci-release/game" --capture "$frame" "$T/$name.png" "$@" > "$T/$name.log" 2>&1
	[ $? = 0 ] && [ "$(field "$T/$name.log" validation_errors)" = 0 ] && ok "$name: frame $frame, 0 validation errors" \
		|| { bad "$name: validation or run"; tail -15 "$T/$name.log"; }
}
cap 60 idle
cap 200 walk --replay "$FIX"
cap 200 walk2 --replay "$FIX"
cap 230 later --replay "$FIX"
mv "$P/assets/character.glb" "$T/character.glb"
cap 60 none

grep -q '^SKIN .* joints=14 idle=1.333/4 walk=0.667/7$' "$T/idle.log" && ok "SKIN: 14 joints, idle 4 + walk 7 channels" \
	|| bad "SKIN line: $(grep '^SKIN ' "$T/idle.log")"
skin=$(field "$T/idle.log" gpu_ms_p50_skin)
awk -v s="${skin:-0}" 'BEGIN {exit !(s > 0)}' && ok "skinned draw timed: gpu_ms_p50_skin=$skin" || bad "gpu_ms_p50_skin='$skin'"
cmp -s "$T/walk.png" "$T/walk2.png" && ok "replay deterministic: frame 200 identical twice" || bad "replay frames differ"

# Character mask = pixels the character (and its shadow) changes at frame 60; the walking body half a second later.
read -r mask later < <(python3 -I -c '
import sys
from PIL import Image, ImageChops
idle, none, walk, later = (Image.open(p).convert("L") for p in sys.argv[1:])
def moved(x, y):
    return ImageChops.difference(x, y).point(lambda v: 255 if v > 24 else 0)
print(moved(idle, none).histogram()[255], moved(walk, later).histogram()[255])
' "$T/idle.png" "$T/none.png" "$T/walk.png" "$T/later.png")
awk -v m="${mask:-0}" 'BEGIN {exit !(m >= 20000)}' && ok "third-person character covers $mask px at spawn" || bad "character mask $mask px"
awk -v m="${later:-0}" 'BEGIN {exit !(m >= 20000)}' && ok "walking: $later px change in 30 frames" || bad "walking changed $later px"

# The replay ends by the +x/+z corner looking away from it: the invisible arena walls do not cut the arm, so it stays 2 m long.
"$G/scripts/cpp-vk-run.sh" --frames 100000 --size 320x180 "$P/build/ci-release/game" --replay "$FIX" > "$T/end.log" 2>&1
cam=$(sed -n 's/^CAMERA third x=\(\S*\) y=\(\S*\) z=\(\S*\)$/\1 \2 \3/p' "$T/end.log")
eye=$(sed -n 's/^GAME pose x=\(\S*\) y=\(\S*\) z=\(\S*\) .*/\1 \2 \3/p' "$T/end.log")
arm=$(awk -v c="${cam:-0 0 0}" -v e="${eye:-0 0 0}" 'BEGIN {split(c, p); split(e, q); printf "%.3f", sqrt((p[1]-q[1])^2 + (p[2]-q[2])^2 + (p[3]-q[3])^2)}')
awk -v a="$arm" 'BEGIN {exit !(a > 1.95 && a < 2.05)}' && ok "spring arm 2 m past the invisible walls at the end: $arm m" || bad "spring arm $arm m, want 2"
echo "cpp-skin.test: $fails failed"
exit $((fails > 0))
