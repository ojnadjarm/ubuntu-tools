#!/usr/bin/env bash
# Download a CC0 asset from Poly Haven, ambientCG or Kenney into OUT/<source>/<id>/ and log its licence in OUT/LICENSES.csv.
set -euo pipefail
usage() { echo "usage: cc0-fetch.sh polyhaven|ambientcg|kenney ID OUT_DIR [--res 1k | --glb]   (kenney ID = page slug, e.g. prototype-textures; --glb unzips a 3D kit's GLB models + Textures/ into OUT/kenney/ID/glb, e.g. mini-dungeon)"; exit "${1:-2}"; }
case ${1:-} in -h|--help) usage 0 ;; esac
[ $# -ge 3 ] || usage >&2
src=$1 id=$2 out=$3 res=1k glb=0
[ "${4:-}" = --res ] && res=$5
[ "${4:-}" = --glb ] && glb=1
dir=$out/$src/$id
mkdir -p "$dir"
log=$out/LICENSES.csv
[ -s "$log" ] || echo "date,source,id,name,author,licence,url,sha256,file" > "$log"
ua="fleet-cc0-fetch/1.0"

get() {  # url name author licence [relpath] -> file in $dir + one licence row
	local f=$dir/${5:-$(basename "${1%%\?*}")}
	mkdir -p "$(dirname "$f")"
	[[ $1 == *"?file="* ]] && f=$dir/${1##*=}
	if [ -s "$f" ] && grep -qF ",${f#"$out"/}" "$log"; then echo "CC0 have ${f#"$out"/}"; return; fi
	curl -sfL -A "$ua" -o "$f" "$1"
	echo "$(date -Is),$src,$id,\"$2\",\"$3\",$4,$1,$(sha256sum "$f" | cut -c1-64),${f#"$out"/}" >> "$log"
	echo "CC0 got ${f#"$out"/} ($(du -h "$f" | cut -f1))"
}

case $src in
	polyhaven)
		info=$(curl -sf -A "$ua" "https://api.polyhaven.com/info/$id")
		name=$(jq -r .name <<< "$info"); author=$(jq -r '.authors | keys | join(" & ")' <<< "$info")
		files=$(curl -sf -A "$ua" "https://api.polyhaven.com/files/$id")
		case $(jq -r .type <<< "$info") in
			0) urls=$(jq -r --arg r "$res" '.hdri[$r].hdr.url' <<< "$files") ;;
			1) urls=$(jq -r --arg r "$res" 'to_entries[] | select(.key | test("^(Diffuse|nor_gl|Rough|AO|Displacement)$")) | .value[$r].jpg.url // empty' <<< "$files") ;;
			2) urls=$(jq -r --arg r "$res" '.gltf[$r].gltf.url' <<< "$files")
				jq -r --arg r "$res" '.gltf[$r].gltf.include // {} | to_entries[] | "\(.key) \(.value.url)"' <<< "$files" |
					while read -r rel u; do get "$u" "$name" "$author" CC0-1.0 "$rel"; done ;;
		esac
		for u in $urls; do get "$u" "$name" "$author" CC0-1.0; done ;;
	ambientcg)
		meta=$(curl -sf -A "$ua" "https://ambientcg.com/api/v2/full_json?id=$id&include=downloadData")
		u=$(jq -r --arg a "${res^^}-JPG" '.foundAssets[0].downloadFolders.default.downloadFiletypeCategories.zip.downloads[] | select(.attribute == $a) | .downloadLink' <<< "$meta")
		[ -n "$u" ] || { echo "CC0 ambientcg: no ${res^^}-JPG zip for $id" >&2; exit 1; }
		get "$u" "$id" "ambientCG" CC0-1.0 ;;
	kenney)
		u=$(curl -sfL -A "$ua" "https://kenney.nl/assets/$id" | grep -oE "https://kenney.nl/media/pages/assets/$id/[^\"]+\.zip" | head -1)
		[ -n "$u" ] || { echo "CC0 kenney: no zip on page $id" >&2; exit 1; }
		get "$u" "$id" "Kenney" CC0-1.0
		unzip -p "$dir/$(basename "$u")" '*icense*' 2>/dev/null | grep -qi "CC0\|creative commons zero\|public domain" || echo "CC0 WARN kenney: licence file not CC0, check $u"
		if [ $glb = 1 ]; then
			unzip -oqj "$dir/$(basename "$u")" 'Models/GLB format/*.glb' -d "$dir/glb"
			unzip -oqj "$dir/$(basename "$u")" 'Models/GLB format/Textures/*' -d "$dir/glb/Textures"
			echo "CC0 glb $(find "$dir/glb" -name '*.glb' | wc -l) models in ${dir#"$out"/}/glb"
		fi ;;
	*) usage >&2 ;;
esac
