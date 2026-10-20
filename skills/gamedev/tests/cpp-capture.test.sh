#!/usr/bin/env bash
# cpp-ci perf capture: a failed GPU gate re-runs the replay under a stub renderdoccmd with RD_FRAME and writes OUT/perf/frame.rdc + .stages.perf.capture.
set -u
CI=$(cd "$(dirname "$0")/.." && pwd)/scripts/cpp-ci
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
mkdir -p "$T/bin" "$T/proj"
echo '{}' > "$T/proj/CMakePresets.json"
cat > "$T/bin/cmake" <<'SH'
#!/bin/sh
case $1 in
	--preset) mkdir -p "$4" ;;
	--build) printf '#!/bin/sh\n' > "$2/game"; chmod +x "$2/game" ;;
esac
SH
cat > "$T/bin/runner" <<'SH'
#!/bin/sh
echo "$*" >> "$STUB_DIR/runner.args"
while [ $# -gt 0 ]; do case $1 in --frames|--timeout) shift 2 ;; --no-validate|--x11) shift ;; *) break ;; esac; done
case $1 in */rdc-run) exec "$@" --frames 90 --no-validate ;; esac
echo "DONE frames=600 seconds=1 avg_fps=500 validation_errors=0 validation_warnings=0 gpu_ms_p50=${STUB_G50:-1.0} gpu_ms_p99=2.0 cpu_ms_p50=0.4"
SH
cat > "$T/bin/renderdoccmd" <<'SH'
#!/bin/sh
echo "RD_FRAME=$RD_FRAME LD_PRELOAD=$LD_PRELOAD $*" >> "$STUB_DIR/rd.args"
while [ $# -gt 0 ]; do [ "$1" = -c ] && tpl=$2; shift; done
[ -n "${STUB_NO_RDC:-}" ] || echo rdc > "${tpl}_frame$RD_FRAME.rdc"
SH
touch "$T/rd-trigger.so"; mkdir -p "$T/gpu-idle/a" "$T/gpu-idle/b"
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" CPPCI_RUNNER="$T/bin/runner" CPPCI_RDSHIM="$T/rd-trigger.so" STUB_DIR=$T QUIET_FDINFO=$T/gpu-idle
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
run() {  # expected-rc cpp-ci args...
	local want=$1; shift
	rm -f "$T/rd.args" "$T/runner.args"
	"$CI" --stages "configure build perf" --perf-max-load 999 --out "$T/ci" "$@" "$T/proj" > "$T/out.log" 2>&1
	[ $? = "$want" ] || { bad "rc want $want"; cat "$T/out.log"; }
}
for i in 1 2 3; do STUB_G50=1.0 run 0; done
[ ! -e "$T/rd.args" ] && jq -e '.stages.perf.capture == null' "$T/ci/summary.json" > /dev/null && ok "pass rows: no capture, capture null" || bad "pass rows captured"
STUB_G50=2.0 run 1 --capture-frame 42
grep -q "^RD_FRAME=42 LD_PRELOAD=$T/rd-trigger.so capture -w -c $T/ci/perf/frame $T/proj/build/ci-release/game --frames 90 --no-validate$" "$T/rd.args" \
	&& ok "renderdoccmd capture with RD_FRAME=42 and the shim" || { bad "renderdoccmd call"; cat "$T/rd.args"; }
grep -q -- '--frames 72 --no-validate --x11 --timeout 300 .*/ci/perf/rdc-run$' "$T/runner.args" && ok "replay re-run 72 frames" || { bad "runner call"; cat "$T/runner.args"; }
jq -e --arg p "$T/ci/perf/frame.rdc" '.stages.perf | .status == "fail" and .capture == $p' "$T/ci/summary.json" > /dev/null \
	&& [ -s "$T/ci/perf/frame.rdc" ] && [ ! -e "$T/ci/perf/rdc-run" ] && ls "$T/ci/perf" | grep -qx frame.rdc && ok "perf/frame.rdc + capture path in summary.json" || bad "capture path"
grep -q "^CPPCI perf capture $T/ci/perf/frame.rdc$" "$T/out.log" && ok "capture line printed" || bad "capture line"
STUB_NO_RDC=1 STUB_G50=2.0 run 1
jq -e '.stages.perf | .status == "fail" and .capture == null' "$T/ci/summary.json" > /dev/null && [ ! -e "$T/ci/perf/frame.rdc" ] && ok "no rdc written: capture null" || bad "no rdc"
echo "$([ $fails = 0 ] && echo PASS || echo FAIL) cpp-capture fails=$fails"
[ $fails = 0 ]
