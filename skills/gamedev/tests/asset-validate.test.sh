#!/usr/bin/env bash
# asset-pipeline.sh validation: glTF-Validator + ktx validate pass a good glb, fail a broken accessor and a truncated KTX2, gate the pipeline rc.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
pipe=$here/scripts/asset-pipeline.sh
fx=$here/tests/fixtures/assets
t=$(mktemp -d "${TMPDIR:-/tmp}/asset-validate-test.XXXX")
trap 'rm -rf "$t"' EXIT
fail=0
is() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$3', got '$2'"; fail=1; fi; }

out=$("$pipe" --validate "$fx/good.glb"); is "good glb rc 0" "$?" 0
is "good glb line" "$out" "ASSET valid $fx/good.glb gltf warnings=0"
out=$("$pipe" --validate "$fx/broken-accessor.glb"); is "broken accessor rc 1" "$?" 1
is "broken accessor first error" "$out" "ASSET INVALID $fx/broken-accessor.glb: ACCESSOR_TOO_LONG Accessor (offset: 0, length: 360) does not fit referenced bufferView [0] length 36."
out=$("$pipe" --validate "$fx/good.glb" "$fx/truncated.ktx2"); is "truncated ktx2 rc 1" "$?" 1
is "truncated ktx2 first error" "$(tail -1 <<< "$out")" "ASSET INVALID $fx/truncated.ktx2: Unexpected end of file."
GLTF_VALIDATOR=$t/missing "$pipe" --validate "$fx/good.glb" > /dev/null 2>&1; is "missing validator rc 1" "$?" 1

blender -b --factory-startup --python "$here/fixture-assets/make_demo.py" -- "$t/demo.glb" > "$t/blender.log" 2>&1 || { echo "FAIL fixture glb"; exit 1; }
"$pipe" --glb "$t/demo.glb" --lods "1" --min-psnr 30 "$t/ok" > "$t/ok.log" 2>&1; is "pipeline on demo rc 0" "$?" 0
is "report counts glTF warnings for the LOD" "$(grep -c "^ASSET valid $t/ok/model_lod0.glb gltf warnings=[0-9]*$" "$t/ok/report.txt")" 1
n=$(grep -ao '"image/ktx2"' "$t/ok/model_lod0.glb" | wc -l)
is "report checks every embedded KTX2 image ($n)" "$(grep -c "^ASSET valid $t/ok/model_lod0.glb#image[0-9]* ktx warnings=[0-9]*$" "$t/ok/report.txt")" "$((n > 0 ? n : -1))"

printf '#!/bin/sh\necho %s\n' "'{\"issues\":{\"numErrors\":1,\"numWarnings\":2,\"messages\":[{\"code\":\"STUB\",\"message\":\"bad\",\"severity\":0}]}}'" > "$t/gv-stub"
chmod +x "$t/gv-stub"
GLTF_VALIDATOR=$t/gv-stub "$pipe" --glb "$t/demo.glb" --lods "1" "$t/bad" > "$t/bad.log" 2>&1; is "pipeline with an invalid output rc 1" "$?" 1
is "report names it" "$(grep -c "^ASSET INVALID $t/bad/model_lod0.glb: STUB bad$" "$t/bad/report.txt")" 1
exit $fail
