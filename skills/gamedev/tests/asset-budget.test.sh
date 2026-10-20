#!/usr/bin/env bash
# asset-pipeline.sh --budget: a 128 px fixture glb passes a fitting budget and fails over-tris and over-texture budgets.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
pipe=$here/scripts/asset-pipeline.sh
fx=$here/tests/fixtures/assets/normal-mapped-128.glb
export OPENBLAS_NUM_THREADS=1  # asset_quality.py: numpy on one thread, a tenth of the CPU
t=$(mktemp -d "${TMPDIR:-/tmp}/asset-budget-test.XXXX")
trap 'rm -rf "$t"' EXIT
export ASSET_CACHE=${ASSET_CACHE:-$t/cache}  # one cache for the 3 cases: gltfpack and Godot run once
fail=0

run() { # name, budget json: one pipeline run (in parallel they cost ~1.5x the CPU s), output and rc kept for check
	echo "$2" > "$t/$1.json"
	"$pipe" --glb "$fx" --lods "1" --min-psnr 30 --budget "$t/$1.json" "$t/$1" > "$t/$1.out" 2>&1; echo $? > "$t/$1.rc"
}
check() { # name, expected rc, expected line
	out=$(cat "$t/$1.out"); rc=$(cat "$t/$1.rc")
	if [ "$rc" -eq "$2" ] && grep -qxF -- "$3" <<< "$out"; then echo "PASS $1"; else echo "FAIL $1 rc=$rc"; echo "$out" | tail -3; fail=1; fi
}
run pass '{"lod0": {"tris": 70000, "texture_px": 512, "bytes": 2000000}}'
run over-tris '{"lod0": {"tris": 1, "texture_px": 512, "bytes": 2000000}}'
run over-texture '{"lod0": {"tris": 70000, "texture_px": 64, "bytes": 2000000}}'
check pass 0 "ASSET budget OK $t/pass.json"
check over-tris 1 "ASSET OVER lod0 tris 2 > 1"
check over-texture 1 "ASSET OVER lod0 texture_px 128 > 64"
exit $fail
