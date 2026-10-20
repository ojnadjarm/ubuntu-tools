#!/usr/bin/env bash
# cpp-vulkan image-based lighting on a throwaway copy of the template (real build, Iris Xe under headless weston): first run bakes (GPU <= 200 ms) and writes the KTX2 caches, the second loads them and draws the same frame, an edited .hdr re-bakes, --no-ibl turns it off, a smooth metal sphere differs from --no-ibl by mean ꟻLIP >= 0.1, 0 validation errors.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
FLIP=${CPPCI_FLIP:-$HOME/opt/gamedev/flip-venv/bin/flip}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl CCACHE_BASEDIR=$T CCACHE_NOHASHDIR=1 OMP_NUM_THREADS=1
P=$T/game
"$G/scripts/new-cpp-game" "$P" > /dev/null || { echo "FAIL new-cpp-game"; exit 1; }
"$G/scripts/cpp-ci" --stages "configure build" "$P" > "$T/ci.log" 2>&1 || { echo "FAIL build"; cat "$T/ci.log" "$P"/ci/logs/*.log | tail -40; exit 1; }
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
run() {  # name game-args...: frame 60 to $T/name.png, validation on; IBL line in $ibl
	local name=$1; shift
	"$G/scripts/cpp-vk-run.sh" --frames 61 "$P/build/ci-release/game" --capture 60 "$T/$name.png" "$@" > "$T/$name.log" 2>&1
	local rc=$?
	ibl=$(grep -m1 '^IBL ' "$T/$name.log")
	[ $rc = 0 ] && grep -q '^DONE .*validation_errors=0 ' "$T/$name.log" || { bad "$name: rc=$rc or validation"; tail -15 "$T/$name.log"; }
}
flip_mean() { "$FLIP" -r "$1" -t "$2" -v 1 -d "$T/flip" 2>&1 | sed -n 's/^ *Mean: *\([0-9.e+-]*\).*/\1/p' | tail -1; }
A=$P/assets/environment.hdr

run bake
ms=$(sed -n 's/.* bake_gpu_ms=\([0-9.]*\).*/\1/p' <<< "$ibl")
lim=200; grep -q '^GAME device="llvmpipe' "$T/bake.log" && lim=2000  # lavapipe bakes on the CPU
grep -q ' cache=miss ' <<< "$ibl" && awk -v m="${ms:-99999}" -v l=$lim 'BEGIN {exit !(m > 0 && m <= l)}' && [ -s "$A.ibl.ktx2" ] && [ -s "$A.lut.ktx2" ] \
	&& ok "first run bakes in $ms ms GPU, caches written" || bad "bake (<= $lim ms): '$ibl'"
run cached
grep -q ' cache=hit ' <<< "$ibl" && cmp -s "$T/bake.png" "$T/cached.png" && ok "second run loads the cache, same frame" || bad "cache: '$ibl'"
printf '\n' >> "$A"
run edited
grep -q ' cache=miss ' <<< "$ibl" && ok "edited .hdr re-bakes" || bad "edited: '$ibl'"
run off --no-ibl
grep -q '^IBL off' <<< "$ibl" && ok "--no-ibl: $ibl" || bad "--no-ibl: '$ibl'"

python3 -I "$G/tests/fixtures/make_sphere_glb.py" "$T/sphere.glb" || { echo "FAIL sphere fixture"; exit 1; }
run metal --model "$T/sphere.glb"
run metal-off --model "$T/sphere.glb" --no-ibl
m=$(flip_mean "$T/metal-off.png" "$T/metal.png")
awk -v m="${m:-0}" 'BEGIN {exit !(m >= 0.1)}' && ok "metal sphere reflection: mean FLIP $m >= 0.1 vs --no-ibl" || bad "metal FLIP '$m' want >= 0.1"
echo "cpp-ibl.test: $fails failed"
exit $((fails > 0))
