#!/usr/bin/env bash
# plates.test.sh: fixtures/plates/plates.sh in a mktemp tree with a stub blender, no Blender run - valid plates, STALE (inputs or blender version), full run with and without Blender, SKIP reasons, mv-render-speed's nan diff (T898).
set -uo pipefail
SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/fixtures/plates/plates.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
unset MV_BLENDER_FULL MV_PLATES_INTO
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }

mkdir -p "$T/tests" "$T/templates/blender" "$T/scripts" "$T/base" "$T/bl" "$T/sun" "$T/ver" "$T/fx"
echo 'bpy.ops.render.render(animation=True)' >"$T/templates/blender/shot.py"
echo 'echo mv-render' >"$T/scripts/mv-render"
echo 'plates fake' >"$T/tests/fake.test.sh"
for c in cat sha256sum cut awk date mkdir dpkg-query; do ln -s "$(command -v "$c")" "$T/base/$c"; done
printf '#!/bin/sh\necho "Blender 0.0 stub"\n' >"$T/bl/blender"
printf '#!/bin/sh\n[ "$1" = +%%u ] && echo 7 || exec %s "$@"\n' "$(command -v date)" >"$T/sun/date"
printf '#!/bin/sh\necho 9.9-other\n' >"$T/ver/dpkg-query"
chmod +x "$T/bl/blender" "$T/sun/date" "$T/ver/dpkg-query"
NOBL=$T/base BL_PATH=$T/bl:$T/base
# run PATH [VAR=value...]: plates fake in a subshell of the sandbox tree; prints its line, then BL and P.
run() {
  local path=$1; shift
  (export PATH=$path HERE=$T/tests FX=$T/fx MV_PLATES=$T/plates "$@"; . "$SRC"; plates fake; echo "BL=$BL P=$P") 2>&1
}

out=$(run "$BL_PATH" MV_PLATES_INTO="$T/rec")
sha=$(awk '$1 == "sha" { print $2 }' "$T/rec/manifest" 2>/dev/null)
ok "$([[ ${#sha} == 16 && $(has "$out" "BL=1 P=$T/rec") == 1 ]] && echo 1 || echo 0)" "MV_PLATES_INTO: manifest sha $sha written, Blender path"
mkdir -p "$T/plates/fake"
cp "$T/rec/manifest" "$T/plates/fake/manifest"

out=$(run "$BL_PATH" MV_BLENDER_FULL=0)
ok "$(has "$out" "plates fake $sha")" "valid plates: 'plates fake $sha'"
ok "$(has "$out" "BL=0 P=$T/plates/fake")" "valid plates: BL=0, P is the recorded dir"

out=$(run "$T/ver:$BL_PATH" MV_BLENDER_FULL=0)
ok "$(has "$out" "STALE fixture")" "another blender package version: STALE"

sed -i "s/^sha .*/sha 0000000000000000/" "$T/plates/fake/manifest"
out=$(run "$BL_PATH" MV_BLENDER_FULL=0)
ok "$(has "$out" "STALE fixture")" "stale sha: STALE line"
ok "$(has "$out" "BL=1 P=$T/fx/plates")" "stale sha: BL=1, renders into FX/plates"
ok "$(grep -qx "sha $sha" "$T/fx/plates/manifest" 2>/dev/null && echo 1 || echo 0)" "stale sha: fresh manifest written"
out=$(run "$NOBL" MV_BLENDER_FULL=0)
ok "$(has "$out" "SKIP fake: STALE fixture (re-record: make.sh) and no blender")" "stale and no blender: SKIP names stale"
ok "$([[ $(has "$out" "BL=") == 0 ]] && echo 1 || echo 0)" "SKIP exits before the asserts"

cp "$T/rec/manifest" "$T/plates/fake/manifest"
out=$(run "$T/sun:$BL_PATH")
ok "$(has "$out" "full run (MV_BLENDER_FULL or Sunday)")" "Sunday with blender: full run, Blender path"
ok "$(has "$out" "BL=1")" "Sunday with blender: BL=1"
out=$(run "$T/sun:$NOBL")
ok "$(has "$out" "plates fake $sha (full run, no blender)")" "Sunday, no blender, valid plates: plates used"
ok "$(has "$out" "BL=0")" "Sunday, no blender: BL=0"
out=$(run "$NOBL" MV_BLENDER_FULL=1)
ok "$(has "$out" "BL=0 P=$T/plates/fake")" "MV_BLENDER_FULL=1, no blender, valid plates: plates used"

rm -rf "$T/plates/fake"
out=$(run "$NOBL" MV_BLENDER_FULL=0)
ok "$(has "$out" "SKIP fake: no plates and no blender")" "no plates, no blender: SKIP names no plates"
out=$(run "$BL_PATH" MV_BLENDER_FULL=0)
ok "$(has "$out" "fake: no plates: Blender path")" "no plates, blender: Blender path"

# mv-render-speed on sandbox plates (sha from plates itself, blender hidden): a nan or missing diff FAILs, a number passes.
TESTS=$(dirname "$(dirname "$(dirname "$SRC")")") RS=$T/rs/mv-render-speed
mkdir -p "$T/hide" && printf '#!/bin/sh\nexit 127\n' >"$T/hide/blender" && chmod +x "$T/hide/blender"
(export PATH=$T/bl:$PATH HERE=$TESTS FX=$T/fx MV_PLATES_INTO=$RS; . "$SRC"; plates mv-render-speed) >/dev/null 2>&1
for f in unset:16 auto:16 24:24 cycles:32; do echo "${f#*:}" >"$RS/spp-${f%%:*}"; done
speed() { PATH=$T/hide:$PATH MV_PLATES=$T/rs MV_BLENDER_FULL=0 bash "$TESTS/mv-render-speed.test.sh" 2>&1; echo "rc=$?"; }
echo nan >"$RS/diff"; out=$(speed)
ok "$([[ $(has "$out" "FAIL auto vs 32 spp") == 1 && $(has "$out" "rc=1") == 1 ]] && echo 1 || echo 0)" "mv-render-speed: diff nan FAILs"
rm "$RS/diff"; out=$(speed)
ok "$([[ $(has "$out" "FAIL auto vs 32 spp") == 1 && $(has "$out" "rc=1") == 1 ]] && echo 1 || echo 0)" "mv-render-speed: no diff plate FAILs"
echo 0.00100 >"$RS/diff"; out=$(speed)
ok "$([[ $(has "$out" "5/5 passed") == 1 && $(has "$out" "rc=0") == 1 ]] && echo 1 || echo 0)" "mv-render-speed: diff 0.00100 passes"

echo "plates.test: $((n - bad))/$n passed"
exit $((bad > 0))
