#!/usr/bin/env bash
# cpp-ci golden stage on a throwaway copy of the template (real build, Iris Xe under headless weston, ꟻLIP): same build passes, colour swap fails.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
CI=$G/scripts/cpp-ci
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
# ccache hits across runs despite the mktemp path; 2 compile jobs and a one-thread ꟻLIP cost about half the CPU s of all cores.
export CCACHE_BASEDIR=$T CCACHE_NOHASHDIR=1 CMAKE_BUILD_PARALLEL_LEVEL=2 OMP_NUM_THREADS=1
P=$T/game
"$G/scripts/new-cpp-game" "$P" > /dev/null || { echo "FAIL new-cpp-game"; exit 1; }
fails=0
golden() {  # name expected-rc expected-status jq-check, cpp-ci args...
	local name=$1 want_rc=$2 want=$3 q=$4; shift 4
	"$CI" --stages "configure build golden" "$@" "$P" > "$T/out.log" 2>&1
	local rc=$? got; got=$(jq -r '.stages.golden.status' "$P/ci/summary.json" 2>/dev/null)
	if [ "$rc" = "$want_rc" ] && [ "$got" = "$want" ] && jq -e "$q" "$P/ci/summary.json" > /dev/null; then echo "ok   $name"
	else echo "FAIL $name: rc=$rc want $want_rc; status '$got' want '$want'"; cat "$T/out.log"; fails=$((fails + 1)); fi
}
first='.stages.golden | .flip_mean <= 0.02 and .heatmap == null and .flip_version != ""'
golden "template golden passes" 0 pass "$first"
cmake -S "$P" -B "$P/build/ci-release" -DVCPKG_MANIFEST_INSTALL=OFF > /dev/null  # deps are in; later configures skip vcpkg
golden "same build twice passes" 0 pass "$first"
sed -i -f "$G/tests/fixtures/cpp-colour-swap.sed" "$P/shaders/mesh.frag"
golden "colour-swapped shader fails" 1 fail '.stages.golden | .flip_mean > 0.02 and .heatmap != null'
[ -s "$P/ci/golden-heatmap.png" ] && echo "ok   heat map saved" || { echo "FAIL heat map"; fails=$((fails + 1)); }
small=(--game-args "--size 320x180")  # the test's own golden: a small frame keeps ꟻLIP cheap
golden "--update-golden rewrites golden" 0 pass '.stages.golden.updated == true' --update-golden "${small[@]}"
golden "new golden passes" 0 pass "$first" "${small[@]}"
[ ! -e "$P/ci/golden-heatmap.png" ] && echo "ok   heat map removed on pass" || { echo "FAIL heat map left"; fails=$((fails + 1)); }
rm "$P/golden/frame.png"
golden "no golden skips" 0 skip '.stages.golden.reason != null'
echo "cpp-golden.test: $fails failed"
exit $((fails > 0))
