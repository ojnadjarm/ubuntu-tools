#!/usr/bin/env bash
# Blender -> glTF -> gltfpack LODs with KTX2 textures (normal maps UASTC) -> glTF-Validator + ktx validate -> KTX2 quality gate -> headless Godot import check -> optional per-LOD budget gate; writes OUT/report.txt.
set -euo pipefail
usage() { echo "usage: asset-pipeline.sh [--glb SRC.glb | --blend SRC.blend] [--lods \"1 0.5 0.1\"] [--budget budgets.json] [--uastc-orm | --uastc-all | --etc1s-all] [--min-psnr DB] [--min-psnr-color DB] [--min-psnr-orm DB] [--max-normal-angle 5] OUT_DIR | --validate FILE.glb|FILE.ktx2..."; exit "${1:-2}"; }

here=$(cd "$(dirname "$0")/.." && pwd)
lib=$(cd "$(dirname "$(readlink -f "$0")")/../../../lib" && pwd)
gp=${GLTFPACK:-$HOME/opt/gamedev/gltfpack-1.3/gltfpack}
gv=${GLTF_VALIDATOR:-gltf_validator}
kx=${KTX:-ktx}
cache=${ASSET_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/asset-pipeline}

# True when cache entry dir $1 matches its SUMS (then touched as used); a corrupt entry is removed.
cache_ok() {
	[ -f "$1/SUMS" ] && (cd "$1" && sha256sum -c --quiet --status SUMS) && touch "$1" && return
	rm -rf "$1"; return 1
}

# Best-effort: stores "name path" pairs as entry $1 (staged, then renamed into place), prunes oldest entries to ASSET_CACHE_MB and staging dirs over an hour old; never fails.
cache_put() {
	local k=$1 t ok=1; shift
	mkdir -p "$cache" 2>/dev/null && t=$(mktemp -d "$cache/.new.XXXX" 2>/dev/null) || return 0
	while [ $# -gt 0 ]; do cp "$2" "$t/$1" 2>/dev/null || ok=0; shift 2; done
	[ "$ok" = 1 ] && (cd "$t" && sha256sum -- * > SUMS) 2>/dev/null && rm -rf "${cache:?}/$k" && mv -T "$t" "$cache/$k" 2>/dev/null || :
	rm -rf "$t"
	find "$cache" -mindepth 1 -maxdepth 1 -name '.new.*' -mmin +60 -exec rm -rf {} + 2>/dev/null || :
	{ ls -dt "$cache"/*/ | tr '\n' '\0' | xargs -0r du -sk | awk -v m="$(( ${ASSET_CACHE_MB:-512} * 1024 ))" '{ s += $1 } s > m { sub(/^[0-9]+\t/, ""); print }' | xargs -d '\n' -r rm -rf; } 2>/dev/null || :
}

# Runs gltfpack on $src into $1 with args $3..; with the cache on, keyed on sha256(src) + args + gltfpack binary, hit label $2.
pack() {
	local o=$1 label=$2 k e rc=0; shift 2
	if [ "$cache" = 0 ]; then "$gp" -i "$src" -o "$o" "$@" 2>&1; return; fi
	k=$(printf '%s\n' "$src_sha" "$gp_sha" "$@" | sha256sum | cut -c1-64); e=$cache/$k
	if cache_ok "$e" && cp "$e/glb" "$o" 2>/dev/null && cp "$e/log" "$proj/gp.log" 2>/dev/null; then cat "$proj/gp.log"; echo "ASSET cache hit $label ${k:0:8}" >&2; return; fi
	"$gp" -i "$src" -o "$o" "$@" > "$proj/gp.log" 2>&1 || rc=$?
	cat "$proj/gp.log"
	[ "$rc" -ne 0 ] || cache_put "$k" glb "$o" log "$proj/gp.log"
	return "$rc"
}

# Godot import + inspect.gd over $proj, printing its ASSET lines; cached on the glbs, inspect.gd and Godot version unless an import failed.
godot_check() {
	local k="" e
	if [ "$cache" != 0 ]; then
		k=$({ godot --version; basename -a "$proj"/*.glb; cat "$proj"/*.glb "$proj/inspect.gd"; } | sha256sum | cut -c1-64); e=$cache/$k
		if cache_ok "$e" && cp "$e/import.log" "$out/import.log" 2>/dev/null && cp "$e/lines" "$proj/godot.txt" 2>/dev/null; then cat "$proj/godot.txt"; echo "ASSET cache hit godot ${k:0:8}" >&2; return; fi
	fi
	godot --headless --path "$proj" --import > "$out/import.log" 2>&1 || true
	godot --headless --path "$proj" --script res://inspect.gd 2>&1 | grep "^ASSET" > "$proj/godot.txt"
	cat "$proj/godot.txt"
	[ -z "$k" ] || grep -q "import FAIL" "$proj/godot.txt" || cache_put "$k" import.log "$out/import.log" lines "$proj/godot.txt"
}

# Prints "ASSET valid FILE <tool> warnings=N" or "ASSET INVALID FILE: <first error>" for a .ktx2 file (path, label).
ktx_check() {
	local r
	r=$({ "$kx" validate -f mini-json "$1" || true; } | jq -r --arg f "$2" 'if .valid then "ASSET valid \($f) ktx warnings=\([.messages[] | select(.type == "warning")] | length)"
		else "ASSET INVALID \($f): \(first(.messages[] | select(.type != "warning")) | .message)" end')
	echo "${r:-ASSET INVALID $2: ktx validate gave no report}"
}

# Validates a glb with glTF-Validator, then every KTX2 image embedded in it, or a .ktx2 file with ktx validate.
validate() {
	local f=$1 line x img
	{ command -v "$gv" && command -v "$kx"; } >/dev/null || { echo "ASSET need $gv and $kx (DEPS.tsv hint, ~/opt/gamedev)" >&2; exit 1; }
	case $f in *.ktx2) ktx_check "$f" "$f"; return ;; esac
	line=$({ "$gv" -o "$f" 2>/dev/null || true; } | jq -r --arg f "$f" '.issues | if .numErrors == 0 then "ASSET valid \($f) gltf warnings=\(.numWarnings)"
		else "ASSET INVALID \($f): \(first(.messages[] | select(.severity == 0)) | "\(.code) \(.message)")" end')
	line=${line:-ASSET INVALID $f: gltf_validator gave no report}
	echo "$line"
	case $line in "ASSET INVALID"*) return ;; esac
	x=$(mktemp -d "${TMPDIR:-/tmp}/asset-validate.XXXX")
	python3 -Ic 'import os, sys; sys.path.insert(0, sys.argv[1]); import glb
g, b = glb.load(sys.argv[2])
for i, m in enumerate(g.get("images", [])):
	if m.get("mimeType") == "image/ktx2":
		open(f"{sys.argv[3]}/image{i}.ktx2", "wb").write(glb.image_bytes(g, b, i, os.path.dirname(sys.argv[2])))' "$lib" "$f" "$x"
	for img in "$x"/*.ktx2; do [ -e "$img" ] && ktx_check "$img" "$f#$(basename "$img" .ktx2)"; done
	rm -rf "$x"
}

src="" blend="" lods="1 0.5 0.1" out="" budget="" tex=(-tc -tu normal) psnr=() max_angle=5
while [ $# -gt 0 ]; do
	case $1 in
		--glb) src=$2; shift 2 ;;
		--blend) blend=$2; shift 2 ;;
		--lods) lods=$2; shift 2 ;;
		--budget) budget=$(realpath "$2"); shift 2 ;;
		--uastc-orm) tex+=(-tu attrib); shift ;;
		--uastc-all) tex=(-tc -tu); shift ;;
		--etc1s-all) tex=(-tc); shift ;;
		--min-psnr|--min-psnr-color|--min-psnr-orm) psnr+=("$1" "$2"); shift 2 ;;
		--max-normal-angle) max_angle=$2; shift 2 ;;
		--validate) shift; [ $# -gt 0 ] || usage >&2; r=$(for f in "$@"; do validate "$f"; done); echo "$r"; ! grep -q "^ASSET INVALID" <<< "$r"; exit ;;
		-h|--help) usage 0 ;;
		*) out=$1; shift ;;
	esac
done
[ -n "$out" ] || usage >&2
mkdir -p "$out"; out=$(cd "$out" && pwd)
[ -x "$gp" ] || { echo "ASSET need gltfpack with BasisU (apt build lacks it): $gp" >&2; exit 1; }

if [ -z "$src" ]; then
	src=$out/src.glb
	if [ -n "$blend" ]; then
		blender -b "$blend" --python-expr "import bpy; bpy.ops.export_scene.gltf(filepath='$src', export_format='GLB')" > "$out/blender.log" 2>&1
	else
		blender -b --factory-startup --python "$here/fixture-assets/make_demo.py" -- "$src" > "$out/blender.log" 2>&1
	fi
	echo "ASSET blender -> $src ($(du -h "$src" | cut -f1))"
fi

proj=$(mktemp -d "${TMPDIR:-/tmp}/asset-pipeline.XXXX")
trap 'rm -rf "$proj" "$proj.etc1s.glb"' EXIT
printf 'config_version=5\n[application]\nconfig/name="asset-pipeline"\n' > "$proj/project.godot"
cp "$here/fixture-assets/inspect.gd" "$proj/"
[ "$cache" = 0 ] || { src_sha=$(sha256sum < "$src"); gp_sha=$(sha256sum < "$gp"); }
i=0
for si in $lods; do
	pack "$out/model_lod$i.glb" "lod$i" -si "$si" "${tex[@]}" -noq -v | awk -v p="ASSET lod$i si=$si" '/^output:/ && !n++ {sub(/^output: /, ""); print p, $0}'
	cp "$out/model_lod$i.glb" "$proj/"
	i=$((i + 1))
done
godot_check | tee "$out/report.txt"
ls -l "$out"/*.glb | awk '{print "ASSET size", $5, $9}' | tee -a "$out/report.txt"
for f in "$out"/*.glb; do validate "$f"; done | tee -a "$out/report.txt"
etc1s=""
if [ "${tex[*]}" != -tc ]; then
	etc1s=$proj.etc1s.glb
	pack "$etc1s" etc1s -si "${lods%% *}" -tc -noq > /dev/null
	echo "ASSET QUALITY lod0 cost bytes=$(stat -c %s "$out/model_lod0.glb") etc1s_bytes=$(stat -c %s "$etc1s")" | tee -a "$out/report.txt"
fi
for ((l = 0; l < i; l++)); do
	python3 -I "$here/scripts/asset_quality.py" "$src" "$out/model_lod$l.glb" "lod$l" ${etc1s:+--etc1s "$etc1s"} --ktx "$kx" "${psnr[@]}" --max-normal-angle "$max_angle"
done | tee -a "$out/report.txt"
if [ -n "$budget" ]; then
	gate=$(jq -r 'to_entries[] | .key as $l | .value | to_entries[] | "B \($l) \(.key) \(.value)"' "$budget" | awk '
		$1 == "B" { max[$2 " " $3] = $4; next }
		match($0, /model_lod[0-9]+\.glb/) {
			lod = substr($0, RSTART + 6, RLENGTH - 10)
			if ($2 == "size") val[lod " bytes"] = $3
			if ($3 == "OK") {
				split($5, t, "="); val[lod " tris"] += t[2]
				if (split(substr($6, 9), d, "x") == 2) { px = d[1] > d[2] ? d[1] : d[2]; if (px > val[lod " texture_px"]) val[lod " texture_px"] = px }
			}
		}
		END { for (k in val) if ((k in max) && val[k] + 0 > max[k] + 0) print "ASSET OVER", k, val[k], ">", max[k] }
	' - "$out/report.txt" | sort)
	echo "${gate:-ASSET budget OK $budget}" | tee -a "$out/report.txt"
fi
! grep -qE "import FAIL|ASSET OVER|ASSET INVALID|ASSET QUALITY FAIL" "$out/report.txt" && [ "$(grep -c "import OK" "$out/report.txt")" -eq "$i" ]
