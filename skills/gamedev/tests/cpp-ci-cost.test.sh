#!/usr/bin/env bash
# T995 cpp-ci build cost: vcpkg_s, .ninja_log compile/link/top TU, ccache deltas, per-stage cpu_s and the cpp-report "build cost" row, on fixtures and stub cmake/ccache (no compiler).
# T1001: the static shaders stage (GROW fails, no baseline skips, no glslang is error) and gamedev-perf refusing a 0 ms budget.
set -uo pipefail
G=$(cd "$(dirname "$0")/.." && pwd)
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ $T == "${TMPDIR:-/tmp}"/* || $T == /tmp/* ]] && ok "selftest: sandbox in a temp dir" || bad "sandbox $T not a temp dir"
# shellcheck source=../scripts/cpp-ci
. "$G/scripts/cpp-ci"

printf '%s\n' '-- Running vcpkg install (at 120 ms)' 'All requested packages are installed.' '-- Running vcpkg install - done (at 3570 ms)' '-- Configuring done' > "$T/configure.log"
[ "$(vcpkg_s "$T/configure.log")" = 3.45 ] && ok "vcpkg_s: 3.45 s between the stamped lines" || bad "vcpkg_s: '$(vcpkg_s "$T/configure.log")'"
printf '%s\n' '-- Running vcpkg install (at 5 ms)' 'error: building zstd failed' > "$T/half.log"
[ -z "$(vcpkg_s "$T/half.log")" ] && ok "vcpkg_s: empty without a done line" || bad "vcpkg_s half: '$(vcpkg_s "$T/half.log")'"
out=$(printf '%s\n' 'x' '-- Running vcpkg install' 'y' | vcpkg_stamp)
[[ $out == $'x\n-- Running vcpkg install (at '*$' ms)\ny' ]] && ok "vcpkg_stamp: stamps the vcpkg line only" || bad "vcpkg_stamp: $out"

printf '# ninja log v7\n10\t2010\t1\tCMakeFiles/game.dir/src/old.cpp.o\taa\n' > "$T/before"
{ cat "$T/before"
  printf '%s\t%s\t1\t%s\t%s\n' 5 394 shaders/mesh.frag.spv s1 5 394 /abs/build/shaders/mesh.frag.spv s1 \
	0 4000 CMakeFiles/game.dir/src/renderer.cpp.o h1 0 1500 CMakeFiles/game.dir/src/audio.cpp.o h2 \
	0 9000 CMakeFiles/game.dir/src/miniaudio.cpp.o h3 100 600 CMakeFiles/game.dir/src/vma.cpp.o h4 \
	9000 9800 game h5 9000 9100 libcore.a h6; } > "$T/after"
j=$(ninja_cost "$T/before" "$T/after")
jq -e '.compile_s == 15 and .link_s == 0.9 and .other_s == 0.39' <<< "$j" > /dev/null \
	&& ok "ninja_cost: compile 15 s, link 0.9 s (game + .a), other 0.39 s (spv once, old entry ignored)" || bad "ninja_cost sums: $j"
jq -e '[.top_tu[] | "\(.tu)=\(.s)"] == ["src/miniaudio.cpp=9", "src/renderer.cpp=4", "src/audio.cpp=1.5"]' <<< "$j" > /dev/null \
	&& ok "ninja_cost: top_tu = 3 slowest objects" || bad "top_tu: $j"
jq -e '.compile_s == 0 and .top_tu == []' <<< "$(ninja_cost "$T/after" "$T/after")" > /dev/null && ok "ninja_cost: no-op build is 0, not the last run" || bad "no-op build"
jq -e '.compile_s == 2 and .top_tu[0].s == 2' <<< "$(ninja_cost /dev/null "$T/before")" > /dev/null && ok "ninja_cost: first build (no BEFORE) counts all" || bad "first build"
jq -e '.compile_s == null and .top_tu == null' <<< "$(ninja_cost "$T/before" "$T/none")" > /dev/null && ok "ninja_cost: no .ninja_log gives nulls" || bad "no log"

mkdir -p "$T/bin"
printf '#!/bin/sh\n[ "$1" = --print-stats ] || exit 1\nprintf "cache_miss\\t%%s\\ndirect_cache_hit\\t40\\npreprocessed_cache_hit\\t2\\nfiles_in_cache\\t9\\n" "${STUB_MISS:-5}"\n' > "$T/bin/ccache"
chmod +x "$T/bin/ccache"
[ "$(PATH=$T/bin:$PATH ccache_counts)" = "42 5" ] && ok "ccache_counts: hits = direct + preprocessed" || bad "ccache_counts: '$(PATH=$T/bin:$PATH ccache_counts)'"
jq -e '.ccache_hits == 12 and .ccache_misses == 3' <<< "$(ccache_delta "30 2" "42 5")" > /dev/null && ok "ccache_delta: 12 hits, 3 misses" || bad "ccache_delta"
jq -e '.ccache_hits == null and .ccache_misses == null' <<< "$(ccache_delta "" "")" > /dev/null && ok "ccache_delta: nulls without ccache" || bad "ccache_delta empty"

# end to end on stub cmake: summary.json carries the fields, cpp-report draws the row
P=$T/proj; mkdir -p "$P"; echo '{}' > "$P/CMakePresets.json"
cat > "$T/bin/cmake" <<'SH'
#!/bin/sh
case $1 in
	--preset) mkdir -p "$4"; echo '-- Running vcpkg install'; echo '-- Running vcpkg install - done'; echo '-- Generating done' ;;
	--build) printf '#!/bin/sh\n' > "$2/game"; chmod +x "$2/game"; i=0; while [ $i -lt 200000 ]; do i=$((i + 1)); done
		printf '# ninja log v7\n0\t2500\t1\tCMakeFiles/game.dir/src/a.cpp.o\th1\n2500\t2700\t1\tgame\th2\n' > "$2/.ninja_log" ;;
esac
SH
printf '#!/bin/sh\nexit 0\n' > "$T/bin/mold"; chmod +x "$T/bin/cmake" "$T/bin/mold"
PATH=$T/bin:$PATH CREATIVE_CI_LOG=$T/ci.jsonl STUB_MISS=6 "$G/scripts/cpp-ci" --stages "configure build" "$P" > "$T/ci.out" 2>&1; rc=$?
S=$P/ci/summary.json
[ $rc = 0 ] && jq -e '.stages.configure.vcpkg_s >= 0 and (.stages | map(.cpu_s | type == "number") | all) and .stages.build.cpu_s > 0' "$S" > /dev/null \
	&& ok "cpp-ci: every stage has cpu_s, configure vcpkg_s (build cpu_s $(jq .stages.build.cpu_s "$S") s)" || bad "cpp-ci rc=$rc: $(cat "$T/ci.out")"
jq -e '.stages.build | .compile_s == 2.5 and .link_s == 0.2 and .top_tu[0].tu == "src/a.cpp" and .ccache_hits == 0 and .ccache_misses == 0' "$S" > /dev/null \
	&& ok "cpp-ci build: compile 2.5 s, link 0.2 s, top TU, ccache delta" || bad "build cost: $(jq -c .stages.build "$S")"
grep -q '(at [0-9]* ms)' "$P/ci/logs/configure.log" && [ ! -e "$P/ci/logs/ninja_log.before" ] && ok "configure.log stamped, ninja_log.before removed" || bad "log files"

"$G/scripts/cpp-report" "$P" > /dev/null 2>&1; H=$P/ci/cpp-report.html
grep -o '<tr><td>build cost</td>.\{0,400\}' "$H" | grep -q 'compile 2.5.*link 0.2.*ccache 0 hit / 0 miss.*src/a.cpp 2.5' \
	&& ok "cpp-report: build cost row" || bad "report row: $(grep -o '<tr><td>build cost</td>.\{0,400\}' "$H")"
jq 'del(.stages[].cpu_s)' "$S" > "$T/s" && mv "$T/s" "$S"
"$G/scripts/cpp-report" "$P" > /dev/null 2>&1 && grep -q 'build cost</td><td></td><td></td><td><span class=na>n/a (no cpu_s' "$H" && ok "cpp-report: older summary reads n/a (why)" || bad "report n/a"

# T1001 shaders stage: real shader-stats on a one-sample fragment shader, no cmake
Q=$T/sh; mkdir -p "$Q/shaders"; echo '{}' > "$Q/CMakePresets.json"
frag() { printf '%s\n' '#version 450' 'layout(location = 0) in vec2 uv;' 'layout(location = 0) out vec4 o;' \
	'layout(set = 0, binding = 0) uniform sampler2D tex;' 'void main() {' '    o = texture(tex, uv);' "$1" '}' > "$Q/shaders/f.frag"; }
frag ''; "$G/scripts/shader-stats" --write-baseline "$Q/shaders/stats-baseline.tsv" "$Q/shaders/f.frag" > /dev/null
frag '    o += texture(tex, uv * 0.5);'
CREATIVE_CI_LOG=$T/ci.jsonl "$G/scripts/cpp-ci" --stages shaders "$Q" > "$T/sh.out" 2>&1; rc=$?
[ $rc = 1 ] && grep -qx 'CPPCI shaders GROW f.frag tex +100 % (1 -> 2)' "$T/sh.out" \
	&& jq -e '.stages.shaders | .status == "fail" and .shaders[0].counts.tex == 2 and .shaders[0].delta.tex == 1 and (.grow | map(.metric) | index("tex")) and .seconds <= 3' "$Q/ci/summary.json" > /dev/null \
	&& ok "shaders: extra sample -> GROW line, stage fail, rc 1, per-shader rows, <= 3 s" || bad "shaders grow rc=$rc: $(cat "$T/sh.out")"
"$G/scripts/cpp-report" "$Q" > /dev/null 2>&1; H=$Q/ci/cpp-report.html
grep -q '<h2>Shaders (SPIR-V ops vs baseline)</h2>' "$H" && grep -q '<td>f.frag</td>' "$H" && grep -q 'GROW f.frag tex +100 % (1 -&gt; 2)' "$H" \
	&& ok "cpp-report: shaders table and the GROW detail" || bad "report shaders: $(grep -o '<tr><td>shaders</td>.\{0,300\}' "$H")"
frag ''; CREATIVE_CI_LOG=$T/ci.jsonl "$G/scripts/cpp-ci" --stages shaders "$Q" > "$T/sh.out" 2>&1; rc=$?
[ $rc = 0 ] && jq -e '.stages.shaders | .status == "pass" and .grow == [] and .errors == []' "$Q/ci/summary.json" > /dev/null && ok "shaders: back at baseline -> pass" || bad "shaders pass rc=$rc"
mkdir -p "$T/farm"; for f in /usr/bin/* /bin/*; do case ${f##*/} in glslang*|spirv-*) ;; *) ln -sf "$f" "$T/farm/" ;; esac; done
np=$T/farm; IFS=: read -ra parts <<< "$PATH"; for d in "${parts[@]}"; do case $d in /usr/bin|/bin) ;; *) np+=":$d" ;; esac; done
PATH=$np CREATIVE_CI_LOG=$T/ci.jsonl "$G/scripts/cpp-ci" --stages shaders "$Q" > "$T/sh.out" 2>&1; rc=$?
[ $rc = 0 ] && grep -qx 'CPPCI shaders ERROR f.frag: glslang: No such file or directory' "$T/sh.out" \
	&& jq -e '.stages.shaders | .status == "error" and .rc == 2 and .shaders == [] and .grow == []' "$Q/ci/summary.json" > /dev/null \
	&& ok "shaders: no glslang on PATH -> error (rc 2 path), not GROW, run not failed" || bad "no glslang rc=$rc: $(cat "$T/sh.out")"
rm "$Q/shaders/stats-baseline.tsv"; CREATIVE_CI_LOG=$T/ci.jsonl "$G/scripts/cpp-ci" --stages shaders "$Q" > "$T/sh.out" 2>&1; rc=$?
[ $rc = 0 ] && jq -e '.stages.shaders | .status == "skip" and .reason == "no baseline"' "$Q/ci/summary.json" > /dev/null && ok "shaders: no baseline -> skip: no baseline" || bad "no baseline rc=$rc"

# T1001 a 0 ms budget is refused when gamedev-perf loads perf-budgets.json
printf '{"post": {"col": "post_ms_p50", "ms": 0.6}, "shadow": {"col": "gpu_ms_p50_shadow", "ms": 0}}\n' > "$T/b0.json"
printf 'date,post_ms_p50,gpu_ms_p50_shadow\n1,0.5,0.05\n' > "$T/b0.csv"
for m in "--budget $T/b0.csv" "--trend" "--compare -2 -1"; do
	# shellcheck disable=SC2086
	out=$(GAMEDEV_PERF_DIR=$T GAMEDEV_PERF_BUDGETS=$T/b0.json "$HOME/agents/bin/gamedev-perf" $m 2>&1); rc=$?
	[ $rc = 2 ] && [ "$out" = "gamedev-perf: budget shadow.ms=0 must be > 0 ($T/b0.json)" ] && ok "gamedev-perf ${m%% *}: 0 ms budget -> rc 2 naming shadow" || bad "0 budget ${m%% *} rc=$rc: $out"
done

echo "cpp-ci-cost: $fails failed"
[ "$fails" -eq 0 ]
