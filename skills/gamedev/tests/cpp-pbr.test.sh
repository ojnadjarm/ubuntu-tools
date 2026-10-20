#!/usr/bin/env bash
# cpp-vulkan PBR on a throwaway copy of the template (real build, Iris Xe under headless weston): KTX2 maps transcode with full mips, a missing base colour or no model falls back, 0 validation errors.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
GP=${GLTFPACK:-$HOME/opt/gamedev/gltfpack-1.3/gltfpack}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
P=$T/game
"$G/scripts/new-cpp-game" "$P" > /dev/null || { echo "FAIL new-cpp-game"; exit 1; }
"$G/scripts/cpp-ci" --stages "configure build" "$P" > "$T/ci.log" 2>&1 || { echo "FAIL build"; cat "$T/ci.log" "$P"/ci/logs/*.log | tail -40; exit 1; }
for v in "" --no-base-color; do
	python3 "$G/tests/fixtures/make_pbr_glb.py" "$T/src$v.glb" $v && "$GP" -i "$T/src$v.glb" -o "$T/pbr$v.glb" -tc -tu normal -tu attrib -noq > /dev/null 2>&1 \
		|| { echo "FAIL fixture$v"; exit 1; }
done
fails=0
pbr() {  # name material-regex game-args...
	local name=$1 want=$2; shift 2
	"$G/scripts/cpp-vk-run.sh" --frames 30 "$P/build/ci-release/game" "$@" > "$T/run.log" 2>&1
	local rc=$? m; m=$(grep -m1 '^MATERIAL ' "$T/run.log")
	if [ $rc = 0 ] && grep -qE "$want" <<< "$m" && grep -q '^DONE .*validation_errors=0 ' "$T/run.log"; then echo "ok   $name: $m"
	else echo "FAIL $name: rc=$rc '$m' want /$want/"; tail -20 "$T/run.log"; fails=$((fails + 1)); fi
}
full='(bc7|etc2|rgba8):9'
pbr "KTX2 maps transcode with 9 mips" "base_color=$full normal=$full orm=$full" --model "$T/pbr.glb"
pbr "missing base colour falls back" "base_color=fallback:1 normal=$full orm=$full" --model "$T/pbr--no-base-color.glb"
pbr "no model: cube, all fallback" "base_color=fallback:1 normal=fallback:1 orm=fallback:1" --model "$T/none.glb"
echo "cpp-pbr.test: $fails failed"
exit $((fails > 0))
