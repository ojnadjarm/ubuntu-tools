#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # is() evals its single-quoted checks
# asset-pipeline.sh quality gate: per-class floors (ETC1S colour 31 dB, UASTC colour 38 dB, normal angle 5); the demo passes, a crushed colour and an ETC1S normal map fail.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
pipe=$here/scripts/asset-pipeline.sh
gp=${GLTFPACK:-$HOME/opt/gamedev/gltfpack-1.3/gltfpack}
fx=$here/tests/fixtures/assets/normal-mapped-128.glb
export OPENBLAS_NUM_THREADS=1  # asset_quality.py: numpy on one thread, a tenth of the CPU
t=$(mktemp -d "${TMPDIR:-/tmp}/asset-quality-test.XXXX")
trap 'rm -rf "$t"' EXIT
fail=0
is() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

# Three pipeline builds one after another (in parallel they cost ~1.5x the CPU s), then the asserts; --uastc-all is encoded once (strict) for both its cases.
# The demo gets the pipeline's default encode and gate without a pipeline run (each run starts the Godot editor: 5-15 CPU s).
run() { local n=$1; shift; "$pipe" "$@" "$t/$n" > "$t/$n.log" 2>&1; echo $? > "$t/$n.rc"; }
run uastc --glb "$fx" --lods "1"
run etc1s --glb "$fx" --lods "1" --etc1s-all
run strict --glb "$fx" --lods "1" --uastc-all --min-psnr 99
{ blender -b --factory-startup --python "$here/fixture-assets/make_demo.py" -- "$t/demo.glb" > "$t/blender.log" 2>&1; echo $? > "$t/blender.rc"
	[ "$(cat "$t/blender.rc")" = 0 ] && "$gp" -i "$t/demo.glb" -o "$t/demo_lod0.glb" -si 1 -tc -tu normal -noq > /dev/null 2>&1; }

rc=$(cat "$t/uastc.rc")
r=$t/uastc/report.txt
is "UASTC normal map: rc 0" '[ "$rc" = 0 ]'
is "normal line: codec uastc, angle_p95 within 5" 'grep -qE "^ASSET QUALITY lod0 normal image=[0-9]+ psnr=[0-9.]+ angle_p95=([0-4]\.[0-9]+|5\.00) codec=uastc bytes=[0-9]+ etc1s_bytes=[0-9]+ max_angle=5$" "$r"'
is "base colour stays ETC1S, held to 31 dB" 'grep -qE "^ASSET QUALITY lod0 color image=[0-9]+ psnr=[0-9.]+ codec=etc1s .* min_psnr=31$" "$r" && ! grep -q "QUALITY FAIL" "$r"'
is "byte cost line UASTC vs ETC1S" 'grep -qE "^ASSET QUALITY lod0 cost bytes=[0-9]+ etc1s_bytes=[0-9]+$" "$r"'

rc=$(cat "$t/etc1s.rc")
r=$t/etc1s/report.txt
is "ETC1S normal map: rc 1" '[ "$rc" = 1 ]'
is "ETC1S normal map: angle gate FAIL line" 'grep -qE "^ASSET QUALITY FAIL lod0 normal image=[0-9]+ angle_p95=[0-9.]+ > 5$" "$r"'
is "ETC1S normal map: no cost line" '! grep -q "ASSET QUALITY lod0 cost" "$r"'

rc=$(cat "$t/strict.rc")
is "--uastc-all: colour in UASTC" 'grep -qE "^ASSET QUALITY lod0 color .* codec=uastc " "$t/strict/report.txt"'
q=$(python3 -I "$here/scripts/asset_quality.py" "$fx" "$t/strict/model_lod0.glb" lod0)
is "UASTC colour held to 38 dB" 'grep -qE "^ASSET QUALITY lod0 color .* codec=uastc .* min_psnr=38$" <<< "$q"'
is "--min-psnr 99: rc 1 with a psnr FAIL line" '[ "$rc" = 1 ] && grep -qE "^ASSET QUALITY FAIL lod0 color image=[0-9]+ psnr=[0-9.]+ < 99$" "$t/strict/report.txt"'

[ "$(cat "$t/blender.rc")" = 0 ] || { echo "FAIL demo glb"; exit 1; }
q=$(python3 -I "$here/scripts/asset_quality.py" "$t/demo.glb" "$t/demo_lod0.glb" lod0)
is "demo texture passes the default floors" 'grep -qE "^ASSET QUALITY lod0 color .* codec=etc1s .* min_psnr=31$" <<< "$q" && ! grep -q "QUALITY FAIL" <<< "$q"'
"$gp" -i "$t/demo.glb" -o "$t/crushed.glb" -tc -tq color 1 -noq > /dev/null 2>&1
q=$(python3 -I "$here/scripts/asset_quality.py" "$t/demo.glb" "$t/crushed.glb" lod0)
is "crushed ETC1S colour (-tq 1) fails 31 dB" 'grep -qE "^ASSET QUALITY FAIL lod0 color image=[0-9]+ psnr=[0-9.]+ < 31$" <<< "$q"'
q=$(python3 -I "$here/scripts/asset_quality.py" "$t/demo.glb" "$t/demo_lod0.glb" lod0 --min-psnr 20 --min-psnr-color 40)
is "--min-psnr-color overrides --min-psnr" 'grep -qE "^ASSET QUALITY FAIL lod0 color image=[0-9]+ psnr=[0-9.]+ < 40$" <<< "$q"'
exit $fail
