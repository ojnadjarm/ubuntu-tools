#!/usr/bin/env bash
# Compile GLSL to SPIR-V (glslang), validate (spirv-val), reflect (spirv-cross); exit 1 if any shader fails.
set -uo pipefail
usage="usage: shader-check.sh [--out DIR] SHADER.{vert,frag,comp,...}..."
[ $# -gt 0 ] || { echo "$usage" >&2; exit 2; }
case $1 in -h|--help) echo "$usage"; exit 0 ;; esac
out=""
[ "$1" = --out ] && { out=$2; shift 2; mkdir -p "$out"; }
work=$(mktemp -d "${TMPDIR:-/tmp}/shader-check.XXXX")
trap 'rm -rf "$work"' EXIT
fails=0
for f in "$@"; do
	name=$(basename "$f")
	spv=$work/$name.spv
	if ! log=$(glslang -V --target-env vulkan1.3 "$f" -o "$spv" 2>&1); then
		echo "SHADER FAIL compile $name: $(grep -m1 ERROR <<< "$log")"; fails=$((fails + 1)); continue
	fi
	if ! log=$(spirv-val --target-env vulkan1.3 "$spv" 2>&1); then
		echo "SHADER FAIL validate $name: $log"; fails=$((fails + 1)); continue
	fi
	refl=$(spirv-cross "$spv" --reflect)
	res=$(jq -r '[(.ubos // [] | map("ubo:" + .name)), (.textures // [] | map("tex:" + .name)), (.push_constants // [] | map("push:" + .name)), (.inputs // [] | map("in:" + .name))] | add | join(" ")' <<< "$refl")
	echo "SHADER OK $name $(stat -c %s "$spv") B spirv; $res"
	if [ -n "$out" ]; then
		cp "$spv" "$out/"; echo "$refl" > "$out/$name.reflect.json"
	fi
done
echo "SHADER summary files=$# fails=$fails"
[ "$fails" -eq 0 ]
