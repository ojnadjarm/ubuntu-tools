#!/usr/bin/env bash
# asset-pipeline.sh ASSET_CACHE: stub gltfpack and godot count their calls; a rerun re-encodes nothing, a changed src or --lods does, 0 disables it, a corrupt entry is re-made.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
pipe=$here/scripts/asset-pipeline.sh
fx=$here/tests/fixtures/assets
export OPENBLAS_NUM_THREADS=1
t=$(mktemp -d "${TMPDIR:-/tmp}/asset-cache-test.XXXX")
trap 'rm -rf "$t"' EXIT
fail=0
mkdir "$t/bin"
cat > "$t/bin/gltfpack" <<EOF
#!/usr/bin/env bash
echo x >> "$t/gp.calls"
while [ \$# -gt 0 ]; do case \$1 in -i) i=\$2; shift 2 ;; -o) o=\$2; shift 2 ;; *) shift ;; esac; done
cp "\$i" "\$o"; echo "output: stub \$(stat -c %s "\$o") bytes"
EOF
cat > "$t/bin/godot" <<EOF
#!/usr/bin/env bash
[ "\$1" = --version ] && { echo 4.7.2.stub; exit; }
echo x >> "$t/godot.calls"
case \$* in *--script*) for f in "\$3"/*.glb; do echo "ASSET import OK \${f##*/} tris=2 texture=128x128"; done ;; esac
EOF
printf '#!/bin/sh\necho %s\n' "'{\"issues\": {\"numErrors\": 0, \"numWarnings\": 0}}'" > "$t/bin/gltf_validator"
printf '#!/bin/sh\necho %s\n' "'{\"valid\": true, \"messages\": []}'" > "$t/bin/ktx"
chmod +x "$t/bin"/*
export PATH=$t/bin:$PATH GLTFPACK=$t/bin/gltfpack XDG_CACHE_HOME=$t/xdg
export ASSET_CACHE=$t/cache
cp "$fx/normal-mapped-128.glb" "$t/src.glb"

n=0
run() { # args...: a pipeline run into $t/oN; sets o, rc, gp and gd (gltfpack and godot calls of this run)
	n=$((n + 1)); o=$t/o$n; rm -f "$t/gp.calls" "$t/godot.calls"
	"$pipe" --glb "$t/src.glb" "$@" "$o" > "$o.log" 2>&1; rc=$?
	gp=$(cat "$t/gp.calls" 2>/dev/null | wc -l); gd=$(cat "$t/godot.calls" 2>/dev/null | wc -l)
}
is() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2' want '$3'"; fail=1; fi; }
same() { sed "s#$o/#OUT/#g" "$o/report.txt" > "$t/now"; sed "s#$1/#OUT/#g" "$1/report.txt" | cmp -s - "$t/now" && echo same || echo differs; }

run --lods 1; first=$o; rc1=$rc
is "first run encodes lod0 + etc1s, imports twice" "$gp $gd" "2 2"
is "first run has a report" "$(grep -c '^ASSET import OK model_lod0.glb' "$o/report.txt")" 1
run --lods 1
is "rerun: 0 gltfpack, 0 godot calls" "$gp $gd" "0 0"
is "rerun prints the hit line" "$(grep -cE '^ASSET cache hit lod0 [0-9a-f]{8}$' "$o.log")" 1
is "rerun: report and rc identical" "$(same "$first") $rc" "same $rc1"
is "rerun: import.log served" "$(test -f "$o/import.log" && echo yes)" yes
run --lods "1 0.5"
is "--lods adds lod1 only" "$gp $gd" "1 2"
cp "$fx/normal-mapped.glb" "$t/src.glb"
run --lods 1
is "changed src: new calls" "$gp" 2
cp "$fx/normal-mapped-128.glb" "$t/src.glb"
before=$(ls "$t/cache" | wc -l)
ASSET_CACHE=0 run --lods 1
is "ASSET_CACHE=0: no cache use" "$gp $gd $(grep -c 'cache hit' "$o.log")" "2 2 0"
is "ASSET_CACHE=0: nothing stored" "$(ls "$t/cache" | wc -l) $(test -e "$t/xdg" && echo xdg)" "$before "
is "ASSET_CACHE=0: same report" "$(same "$first") $rc" "same $rc1"
for f in "$t/cache"/*/glb "$t/cache"/*/lines; do echo corrupt >> "$f"; done
run --lods 1
is "corrupt entries re-made, not served" "$gp $gd $(grep -c 'cache hit' "$o.log")" "2 2 0"
is "corrupt: report identical" "$(same "$first") $rc" "same $rc1"
run --lods 1
is "re-made entries hit" "$gp $gd" "0 0"
ASSET_CACHE_MB=0 ASSET_CACHE=$t/small run --lods 1
is "ASSET_CACHE_MB=0 prunes every entry" "$(ls "$t/small" | wc -l)" 0
mkdir -p "$t/cache/.new.old" "$t/cache/.new.live"; touch -d '2 hours ago' "$t/cache/.new.old"
run --lods "1 0.25"
is "stale staging dirs pruned, fresh kept" "$(ls -d "$t/cache"/.new.* | xargs -n1 basename | tr '\n' ' ')" ".new.live "
mkdir "$t/ro"; chmod 555 "$t/ro"
ASSET_CACHE=$t/ro/cache run --lods 1
is "unwritable cache: run still passes" "$(same "$first") $rc $gp $gd" "same $rc1 2 2"
chmod 755 "$t/ro"
unset ASSET_CACHE
run --lods 1
is "default dir is \$XDG_CACHE_HOME/asset-pipeline" "$(ls "$t/xdg/asset-pipeline" | wc -l)" 3
exit $fail
