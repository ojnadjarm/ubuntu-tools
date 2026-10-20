#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # ok() evals its single-quoted checks
# shader-check, cc0-fetch, new-cpp-game and godot-test.sh on stub binaries (no GPU, no network, no real godot/glslang/curl/cmake).
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
S=$here/scripts TOOLS=$here/tests/fixtures/tools STUBS=$here/tests/fixtures/stub-bin
T=$(mktemp -d "${TMPDIR:-/tmp}/gamedev-tools-test.XXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tmp"
export PATH="$TOOLS:$STUBS:$PATH" TMPDIR=$T/tmp STUB_CALLS=$T/calls.log STUB_ZIP=$T/kenney.zip GUT_DIR=$T/gut
pass=0 fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }

ok "selftest: every external binary resolves to a stub" \
	'for b in curl glslang cmake; do [ "$(command -v $b)" = "$TOOLS/$b" ] || exit 1; done; for b in godot spirv-val spirv-cross; do [ "$(command -v $b)" = "$STUBS/$b" ] || exit 1; done'
ok "selftest: stub curl refuses unknown hosts" '! curl -sf https://example.com/ >/dev/null'

# shader-check
"$S/shader-check.sh" "$here/fixture-shaders/tri.vert" "$here/fixture-shaders/tri.frag" >"$T/sc1" 2>&1; rc=$?
ok "shader-check: 2 good shaders rc 0" '[ $rc = 0 ] && [ "$(grep -c "^SHADER OK" "$T/sc1")" = 2 ] && grep -q "files=2 fails=0" "$T/sc1"'
"$S/shader-check.sh" --out "$T/spv" "$here"/fixture-shaders/* >"$T/sc2" 2>&1; rc=$?
ok "shader-check: broken shader rc 1 naming the file" '[ $rc = 1 ] && grep -q "^SHADER FAIL compile broken.frag: ERROR" "$T/sc2" && grep -q "files=3 fails=1" "$T/sc2"'
ok "shader-check: --out keeps spv + reflection of the good ones only" '[ -f "$T/spv/tri.vert.spv" ] && [ -f "$T/spv/tri.frag.reflect.json" ] && [ ! -e "$T/spv/broken.frag.spv" ]'

# cc0-fetch
printf 'Creative Commons Zero, CC0\n' >"$T/License.txt"
(cd "$T" && zip -q kenney.zip License.txt)
O=$T/assets
fetch_all() { "$S/cc0-fetch.sh" polyhaven rock_wall "$O" && "$S/cc0-fetch.sh" ambientcg Rock030 "$O" && "$S/cc0-fetch.sh" kenney prototype-textures "$O"; }
fetch_all >"$T/cc1" 2>&1; rc=$?
L=$O/LICENSES.csv
ok "cc0-fetch: 3 sources rc 0, no licence warning" '[ $rc = 0 ] && ! grep -q WARN "$T/cc1"'
ok "cc0-fetch: polyhaven texture maps only (Diffuse, nor_gl)" '[ -f "$O/polyhaven/rock_wall/rock_wall_diff_1k.jpg" ] && [ -f "$O/polyhaven/rock_wall/rock_wall_nor_gl_1k.jpg" ] && [ ! -e "$O/polyhaven/rock_wall/bump.jpg" ]'
ok "cc0-fetch: ambientcg 1K zip named from ?file=" '[ -f "$O/ambientcg/Rock030/Rock030_1K-JPG.zip" ]'
ok "cc0-fetch: kenney zip from the page link" 'cmp -s "$O/kenney/prototype-textures/kenney_prototype-textures.zip" "$T/kenney.zip"'
ok "cc0-fetch: header + 4 licence rows" '[ "$(head -1 "$L")" = "date,source,id,name,author,licence,url,sha256,file" ] && [ "$(wc -l <"$L")" = 5 ]'
ok "cc0-fetch: each row has source, CC0-1.0 and the file sha256" \
	'tail -n +2 "$L" | while IFS= read -r row; do f=${row##*,}; sum=$(sha256sum "$O/$f" | cut -c1-64); case $row in *",${f%%/*},"*",CC0-1.0,"*",$sum,$f") ;; *) exit 1 ;; esac; done'
ok "cc0-fetch: polyhaven row names the asset and author" 'grep -q "polyhaven,rock_wall,\"Rock Wall\",\"Rob Tuytel\",CC0-1.0," "$L"'
cp "$L" "$T/licences.before"; dl=$(grep -c "^curl -o" "$T/calls.log")
fetch_all >"$T/cc2" 2>&1; rc=$?
ok "cc0-fetch: repeat fetch is a no-op (rc 0, no download, same LICENSES.csv)" '[ $rc = 0 ] && [ "$(grep -c "^curl -o" "$T/calls.log")" = "$dl" ] && cmp -s "$L" "$T/licences.before"'
"$S/cc0-fetch.sh" nosuch x "$O" >/dev/null 2>&1; rc=$?
ok "cc0-fetch: unknown source rc 2" '[ $rc = 2 ]'

# new-cpp-game
tpl=$here/templates/cpp-vulkan
tsum() { (cd "$1" && find . -type f -exec sha256sum {} + | sort); }
before=$(tsum "$tpl")
"$S/new-cpp-game" "$T/my-game" >"$T/ng1" 2>&1; rc=$?
ok "new-cpp-game: rc 0, project name substituted" '[ $rc = 0 ] && grep -q "^project(my_game " "$T/my-game/CMakeLists.txt" && ! grep -q cpp_vulkan_game "$T/my-game/CMakeLists.txt" && grep -q "project my_game" "$T/ng1"'
ok "new-cpp-game: tree = template, only CMakeLists.txt differs" '[ "$(diff -rq "$tpl" "$T/my-game")" = "Files $tpl/CMakeLists.txt and $T/my-game/CMakeLists.txt differ" ]'
"$S/new-cpp-game" "$T/my-game" >"$T/ng2" 2>&1; rc=$?
ok "new-cpp-game: refuses an existing dir" '[ $rc = 1 ] && grep -q "exists" "$T/ng2" && grep -q "^project(my_game " "$T/my-game/CMakeLists.txt"'
ok "new-cpp-game: template untouched, cmake never called" '[ "$(tsum "$tpl")" = "$before" ] && ! grep -q "^cmake" "$T/calls.log"'
# The copy's presets on a stub project (no compiler, no vcpkg): real cmake configures and builds a target that prints its env.
P=$T/my-game realcmake=$(PATH=${PATH#"$TOOLS:$STUBS:"} command -v cmake)
mkdir -p "$T/vcpkg/scripts/buildsystems"; : >"$T/vcpkg/scripts/buildsystems/vcpkg.cmake"
printf 'cmake_minimum_required(VERSION 3.28)\nproject(envcheck LANGUAGES NONE)\nadd_custom_target(envcheck ALL COMMAND ${CMAKE_COMMAND} -E environment)\n' >"$P/CMakeLists.txt"
(cd "$P" && export VCPKG_ROOT=$T/vcpkg && "$realcmake" --preset dev && "$realcmake" --build --preset dev && "$realcmake" --preset release) >"$T/preset.log" 2>&1; rc=$?
ok "new-cpp-game preset: CCACHE_BASEDIR=copy dir and NOHASHDIR reach the build" '[ $rc = 0 ] && grep -qxF "CCACHE_BASEDIR=$P" "$T/preset.log" && grep -qxF "CCACHE_NOHASHDIR=1" "$T/preset.log"'
ok "new-cpp-game preset: dev and release map the copy dir, module scan off" \
	'(for b in dev release; do c=$P/build/$b/CMakeCache.txt; for v in "CMAKE_C_FLAGS:-fdebug-prefix-map=$P=." "CMAKE_CXX_FLAGS:-fdebug-prefix-map=$P=." CMAKE_CXX_SCAN_FOR_MODULES:OFF; do sed -n "s/^${v%%:*}:[A-Z]*=//p" "$c" | grep -qxF -e "${v#*:}" || exit 1; done; done)'

# godot-test.sh
mkdir -p "$GUT_DIR"; echo stub >"$GUT_DIR/gut_cmdln.gd"
"$S/godot-test.sh" --junit "$T/j1.xml" >"$T/gt1" 2>&1; rc=$?
ok "godot-test: sample fixture passes, JUnit at --junit" '[ $rc = 0 ] && grep -q "<testsuites" "$T/j1.xml" && grep -q "TEST junit=$T/j1.xml rc=0" "$T/gt1" && grep -q "All tests passed" "$T/gt1"'
ok "godot-test: sample fixture copy cleaned up" '[ -z "$(ls "$T/tmp")" ]'
P=$T/proj; cp -r "$here/fixture-test" "$P"
STUB_GUT_FAIL=1 "$S/godot-test.sh" "$P" >"$T/gt2" 2>&1; rc=$?
ok "godot-test: failing GUT rc 1, JUnit in project, FAILED line" '[ $rc = 1 ] && grep -q "failures=\"1\"" "$P/junit.xml" && grep -q "TEST junit=$P/junit.xml rc=1" "$T/gt2" && grep -q "FAILED" "$T/gt2"'
ok "godot-test: GUT vendored from GUT_DIR, import then headless GUT run" '[ -f "$P/addons/gut/gut_cmdln.gd" ] && grep -q "godot --headless --path $P --import" "$T/calls.log" && grep -q "gut_cmdln.gd -gdir=res://test" "$T/calls.log"'

echo "gamedev-tools: $pass passed, $fail failed"
[ "$fail" = 0 ]
