#!/usr/bin/env bash
# cpp-ci stage pass/fail/skip on a stub cmake and a stub runner (no compiler, GPU or weston).
set -u
CI=$(cd "$(dirname "$0")/.." && pwd)/scripts/cpp-ci
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
mkdir -p "$T/bin" "$T/proj"
echo '{}' > "$T/proj/CMakePresets.json"
touch "$T/proj/.clang-tidy"
cat > "$T/bin/cmake" <<'SH'
#!/bin/sh
echo "$*" >> "${STUB_ARGS:-/dev/null}"
echo "base=${CCACHE_BASEDIR:-} nohashdir=${CCACHE_NOHASHDIR:-}" >> "${STUB_ENV:-/dev/null}"
case $1 in
	--preset)
		[ "${STUB_CFG_FAIL:-}" = "$2" ] && { echo "CMake Error"; exit 1; }
		mkdir -p "$4" ;;
	--build)
		[ -n "${STUB_BUILD_FAIL:-}" ] && { echo "error: boom"; exit 1; }
		printf '#!/bin/sh\n' > "$2/game"; chmod +x "$2/game"
		[ -n "${CCACHE_STATSLOG:-}" ] && printf '# a.cpp\ndirect_cache_hit\n# b.cpp\npreprocessed_cache_hit\n# c.cpp\ndirect_cache_hit\n# d.cpp\ncache_miss\n' >> "$CCACHE_STATSLOG" ;;
esac
SH
cat > "$T/bin/runner" <<'SH'
#!/bin/sh
case "$*" in
	*ci-sanitize*) [ -n "${STUB_SAN_REPORT:-}" ] && { echo "==1==ERROR: AddressSanitizer: heap-use-after-free"; exit 1; } ;;
	*ci-release*--no-validate*|*--no-validate*ci-release*)
		[ -n "${STUB_GPU_HEAVY:-}" ] && g=9.5 || g=${STUB_G50:-0.120}
		echo "DONE frames=600 seconds=1 avg_fps=500.5 validation_errors=0 validation_warnings=0 gpu_ms_p50=$g gpu_ms_p99=${STUB_G99:-12.25} cpu_ms_p50=0.410"; exit 0 ;;
	*--no-validate*) ;;
	*) [ -n "${STUB_VALERR:-}" ] && { echo "DONE frames=120 seconds=1 avg_fps=50.0 validation_errors=3 validation_warnings=0"; exit 2; } ;;
esac
echo "DONE frames=120 seconds=1 avg_fps=500.5 validation_errors=0 validation_warnings=0"
SH
cat > "$T/bin/tracy-capture" <<'SH'
#!/bin/sh
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
[ -n "${STUB_NO_TRACE:-}" ] && exit 1
echo trace > "$out"; printf 'Connecting...\r\nFrames: 302\nZones: 1,500\n'
SH
cat > "$T/bin/tracy-csvexport" <<'SH'
#!/bin/sh
echo name,src_file,src_line,total_ns,total_perc,counts,mean_ns,min_ns,max_ns,std_ns
for z in record:6000 submit:78000 acquire:2400 present:8500 wait_fence:26000 extra:100; do
	echo "${z%:*},r.cpp,1,1,1,300,${z#*:},1,1,1"
done
SH
cat > "$T/bin/tidy" <<'SH'
#!/bin/sh
case $1 in */ci-release) ;; *) echo "bad build dir $1"; exit 2 ;; esac
echo "TIDY findings=${STUB_TIDY_FINDINGS:-0} files=7 seconds=1"; [ -z "${STUB_TIDY_FINDINGS:-}" ]
SH
chmod +x "$T/bin/cmake" "$T/bin/runner" "$T/bin/tracy-capture" "$T/bin/tracy-csvexport" "$T/bin/tidy"
mkdir -p "$T/gpu-idle/a" "$T/gpu-idle/b"
for snap in a:0 b:400000000; do  # another client renders 40 % of 1 s
	d=$T/gpu-busy/${snap%:*}/4242; mkdir -p "$d/fdinfo"
	printf 'Name:\tblender\nPPid:\t1\nUid:\t%s\n' "$(id -u)" > "$d/status"
	printf 'drm-client-id:\t9\ndrm-engine-render:\t%s ns\n' "${snap#*:}" > "$d/fdinfo/3"
done
export PATH="$T/bin:$PATH" CPPCI_RUNNER="$T/bin/runner" CPPCI_TIDY="$T/bin/tidy" QUIET_FDINFO=$T/gpu-idle
fails=0
check() {  # name expected-rc expected "shaders configure build sanitize run perf profile tidy golden" statuses, cpp-ci args...
	local name=$1 want_rc=$2 want=$3; shift 3
	rm -rf "$T/proj/ci" "$T/proj/build"
	"$CI" "$@" "$T/proj" > "$T/out.log" 2>&1
	local rc=$? got
	got=$(jq -r '[.stages[] | .status] | join(" ")' "$T/proj/ci/summary.json" 2>/dev/null)
	if [ "$rc" = "$want_rc" ] && [ "$got" = "$want" ]; then echo "ok   $name"
	else echo "FAIL $name: rc=$rc want $want_rc; got '$got' want '$want'"; cat "$T/out.log"; fails=$((fails + 1)); fi
}
check "all pass" 0 "skip pass pass pass pass pass pass pass skip" --perf-max-load 999
[ "$(wc -l < "$T/proj/ci/perf.csv")" = 2 ] && grep -qE ',500.5,.*,0.120,12.25,0.410,cpu,pass(,[^,]*){8}$' "$T/proj/ci/perf.csv" && echo "ok   perf row" || { echo "FAIL perf row"; fails=$((fails + 1)); }
jq -e '.stages.perf | .gpu_ms_p50 == 0.12 and .gpu_ms_p99 == 12.25 and .cpu_ms_p50 == 0.41 and .bound == "cpu"' "$T/proj/ci/summary.json" > /dev/null \
	&& echo "ok   perf gpu/cpu fields, bound=cpu" || { echo "FAIL perf gpu fields"; fails=$((fails + 1)); }
jq -e '.stages.profile | .zones == 6 and .frames_captured == 302 and .trace == null and ([.top_mean_ns[].name] | join(" ")) == "submit wait_fence present record acquire"' "$T/proj/ci/summary.json" > /dev/null \
	&& [ ! -e "$T/proj/ci/profile.tracy" ] && echo "ok   profile top 5, trace deleted" || { echo "FAIL profile top 5"; fails=$((fails + 1)); }
fast() {  # name expected-preset-lines-with-ccache+mold expected-ccache_hit_pct, cpp-ci args...
	local name=$1 want_n=$2 want_pct=$3; shift 3
	rm -rf "$T/proj/ci" "$T/proj/build" "$T/args" "$T/env"
	STUB_ARGS=$T/args STUB_ENV=$T/env "$CI" --perf-max-load 0 "$@" "$T/proj" > "$T/out.log" 2>&1
	local n pct; n=$(grep -c '^--preset.*COMPILER_LAUNCHER=ccache.*CMAKE_LINKER_TYPE=MOLD' "$T/args"); pct=$(jq -c .ccache_hit_pct "$T/proj/ci/summary.json")
	if [ "$n" = "$want_n" ] && [ "$pct" = "$want_pct" ]; then echo "ok   $name"
	else echo "FAIL $name: ccache+mold presets $n want $want_n; ccache_hit_pct $pct want $want_pct"; fails=$((fails + 1)); fi
}
fast "ccache + mold on configure, sanitize, profile; hit 75 %" 3 75.0 --stages "configure build sanitize profile"
pm="-fdebug-prefix-map=$T/proj=."
[ "$(grep -c -- "-DCMAKE_CXX_FLAGS=$pm\$" "$T/args")" = 2 ] && grep -q -- "-DCMAKE_CXX_FLAGS=-fsanitize=address,undefined -fno-omit-frame-pointer $pm -DCMAKE_EXE" "$T/args" \
	&& [ "$(sort -u "$T/env")" = "base=$T/proj nohashdir=1" ] && echo "ok   base_dir, nohashdir, debug-prefix-map (sanitize keeps its flags)" || { echo "FAIL base_dir env or prefix map"; cat "$T/args" "$T/env"; fails=$((fails + 1)); }
CPPCI_MOLD=no-such-mold fast "no mold: plain presets, hit null" 0 null --stages "configure build sanitize profile"
! grep -q 'prefix-map' "$T/args" && [ "$(sort -u "$T/env")" = "base= nohashdir=" ] && echo "ok   no mold: no base_dir, no prefix map" || { echo "FAIL no-mold env"; fails=$((fails + 1)); }
fast "package preset through ccache + mold" 2 75.0 --stages "configure build package"
grep -q '^--preset release -B [^ ]*ci-package -DGAME_PORTABLE=ON -DCMAKE_COMPILE_WARNING_AS_ERROR=ON -DCMAKE_C_COMPILER_LAUNCHER=ccache .*-DCMAKE_LINKER_TYPE=MOLD' "$T/args" && echo "ok   package keeps GAME_PORTABLE, adds fast" || { echo "FAIL package args"; fails=$((fails + 1)); }
check "perf skip on load, --keep" 0 "skip pass pass pass pass skip pass pass skip" --perf-max-load 0 --keep
[ -f "$T/proj/ci/profile.tracy" ] && echo "ok   --keep keeps trace" || { echo "FAIL --keep"; fails=$((fails + 1)); }
QUIET_FDINFO=$T/gpu-busy check "perf skip on a busy GPU" 0 "skip pass pass pass pass skip pass pass skip" --perf-max-load 999
jq -e '.stages.perf | .reason == "gpu" and .gpu_busy_pct == 40' "$T/proj/ci/summary.json" > /dev/null && echo "ok   reason gpu, 40 %" || { echo "FAIL gpu skip fields"; fails=$((fails + 1)); }
grep -q '^\. "\$S/ci-lib.sh"' "$CI" && ! grep -q '^record()' "$CI" && echo "ok   record() from ci-lib.sh" || { echo "FAIL ci-lib"; fails=$((fails + 1)); }
STUB_NO_TRACE=1 check "no trace fails profile" 1 "skip pass pass pass pass skip fail pass skip" --perf-max-load 0
STUB_GPU_HEAVY=1 check "gpu-heavy frame" 0 "skip pass pass pass pass pass pass pass skip" --perf-max-load 999
jq -e '.stages.perf.bound == "gpu" and .stages.perf.gpu_ms_p50 == 9.5' "$T/proj/ci/summary.json" > /dev/null && echo "ok   bound=gpu" || { echo "FAIL bound=gpu"; fails=$((fails + 1)); }
STUB_SAN_REPORT=1 check "sanitizer report fails sanitize" 1 "skip pass pass fail pass skip pass pass skip" --perf-max-load 0
jq -e '.stages.sanitize.reports == 1' "$T/proj/ci/summary.json" > /dev/null && echo "ok   reports=1" || { echo "FAIL reports"; fails=$((fails + 1)); }
STUB_VALERR=1 check "validation error fails run" 1 "skip pass pass pass fail pass pass pass skip" --perf-max-load 999
jq -e '.stages.run.validation_errors == 3' "$T/proj/ci/summary.json" > /dev/null && echo "ok   validation_errors=3" || { echo "FAIL validation_errors"; fails=$((fails + 1)); }
STUB_TIDY_FINDINGS=3 check "tidy findings fail tidy" 1 "skip pass pass pass pass skip pass fail skip" --perf-max-load 0
jq -e '.stages.tidy.findings == 3 and .stages.tidy.rc == 1' "$T/proj/ci/summary.json" > /dev/null && echo "ok   findings=3" || { echo "FAIL tidy findings"; fails=$((fails + 1)); }
rm "$T/proj/.clang-tidy"
check "no .clang-tidy skips tidy" 0 "skip pass pass pass pass skip pass skip skip" --perf-max-load 0
touch "$T/proj/.clang-tidy"
STUB_CFG_FAIL=release check "configure fail skips dependents" 1 "skip fail skip pass skip skip skip skip skip" --perf-max-load 999
STUB_BUILD_FAIL=1 check "build fail" 1 "skip pass fail fail skip skip skip pass skip" --perf-max-load 999
gate() {  # name expected-rc expected-verdict, cpp-ci args...; runs into the shared $T/gate out dir
	local name=$1 want_rc=$2 want=$3; shift 3
	"$CI" --out "$T/gate" --perf-max-load 999 "$@" "$T/proj" > "$T/out.log" 2>&1
	local rc=$? got; got=$(jq -r '.stages.perf | "\(.status) \(.verdict)"' "$T/gate/summary.json")
	if [ "$rc" = "$want_rc" ] && [ "$got" = "$want" ]; then echo "ok   $name"
	else echo "FAIL $name: rc=$rc want $want_rc; got '$got' want '$want'"; fails=$((fails + 1)); fi
}
rm -rf "$T/proj/build"
for i in 1 2 3; do STUB_G50=1.0 STUB_G99=2.0 gate "steady row $i records" 0 "pass record"; done
for i in 4 5; do STUB_G50=1.0 STUB_G99=2.0 gate "steady row $i gated" 0 "pass pass"; done
gate "high load row stays skip" 0 "skip null" --perf-max-load 0
tail -1 "$T/gate/perf.csv" | grep -q ',,,,,skip,,,,,,,,$' && echo "ok   skip row recorded" || { echo "FAIL skip row"; fails=$((fails + 1)); }
for i in $(seq 10); do echo "2026-01-01T00:00:00,proj,600,,99,2.0,4.0,0.4,gpu,skip" >> "$T/gate/perf.csv"; done
STUB_G50=2.0 STUB_G99=2.0 gate "2x gpu_ms_p50 fails (skip rows ignored)" 1 "fail fail"
jq -e '.stages.perf | .baseline_gpu_ms_p50 == 1 and .delta_pct == 100' "$T/gate/summary.json" > /dev/null \
	&& tail -1 "$T/gate/perf.csv" | grep -qE ',fail(,[^,]*){8}$' && echo "ok   baseline 1.0, delta 100, fail row" || { echo "FAIL baseline fields"; fails=$((fails + 1)); }
STUB_G50=1.05 STUB_G99=2.0 gate "+5% gpu_ms_p50 passes (fail row ignored)" 0 "pass pass"
STUB_G50=1.0 STUB_G99=3.0 gate "+50% gpu_ms_p99 fails" 1 "fail fail"
STUB_G50=1.1 STUB_G99=2.0 gate "+10% fails at --gpu-tol 5" 1 "fail fail" --gpu-tol 5
"$CI" --help > /dev/null && echo "ok   --help" || { echo "FAIL --help"; fails=$((fails + 1)); }
"$CI" "$T/nope" > /dev/null 2>&1; [ $? = 2 ] && echo "ok   bad project rc 2" || { echo "FAIL bad project"; fails=$((fails + 1)); }
echo "cpp-ci.test: $fails failed"
exit $((fails > 0))
