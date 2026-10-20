#!/usr/bin/env bash
# cpp-ci perf parses vram_used_mb/vram_budget_mb into perf.csv and gates on --vram-mb; run fails on VMA live_allocations > 0 (stubs, then a real leak fixture on the GPU).
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
CI=$G/scripts/cpp-ci
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
echo "DONE frames=600 seconds=1 avg_fps=500.5 validation_errors=0 validation_warnings=0 gpu_ms_p50=0.120 gpu_ms_p99=0.200 cpu_ms_p50=0.410 vram_used_mb=${STUB_VRAM:-22} vram_budget_mb=26196 draws=3 culled=1"
[ -z "${STUB_LIVE:-}" ] || echo "VMA live_allocations=$STUB_LIVE live_bytes=64"
SH
printf '#!/bin/sh\nexit 1\n' > "$T/bin/tracy-capture"
printf '#!/bin/sh\n' > "$T/bin/tracy-csvexport"
chmod +x "$T/bin/"*
mkdir -p "$T/gpu-idle/a" "$T/gpu-idle/b"
export PATH="$T/bin:$PATH" CPPCI_RUNNER="$T/bin/runner" QUIET_FDINFO=$T/gpu-idle
fails=0
check() {  # name expected-perf-status expected-csv-row-substring, cpp-ci args...
	local name=$1 want=$2 tail=$3 got; shift 3
	rm -rf "$T/proj/ci"
	"$CI" --perf-max-load 999 "$@" "$T/proj" > "$T/out.log" 2>&1
	got=$(jq -r '.stages.perf.status' "$T/proj/ci/summary.json" 2>/dev/null)
	if [ "$got" = "$want" ] && tail -1 "$T/proj/ci/perf.csv" | grep -qF -- "$tail"; then echo "ok   $name"
	else echo "FAIL $name: perf=$got want $want; row $(tail -1 "$T/proj/ci/perf.csv" 2>/dev/null) want *$tail"; fails=$((fails + 1)); fi
}
check "vram columns recorded" pass ',cpu,pass,22,26196,3,1,'
head -1 "$T/proj/ci/perf.csv" | grep -q ',status,vram_used_mb,vram_budget_mb,draws,culled,' && echo "ok   perf.csv header" || { echo "FAIL header"; fails=$((fails + 1)); }
jq -e '.stages.perf | .vram_used_mb == 22 and .vram_budget_mb == 26196 and .draws == 3 and .culled == 1' "$T/proj/ci/summary.json" > /dev/null \
	&& echo "ok   summary vram fields" || { echo "FAIL summary vram fields"; fails=$((fails + 1)); }
check "under --vram-mb passes" pass ',pass,22,26196,3,1,' --vram-mb 64
check "over --vram-mb fails" fail ',fail,22,26196,3,1,' --vram-mb 16
STUB_VRAM=n/a check "n/a used is empty, no gate" pass ',pass,,26196,3,1,' --vram-mb 16
run() {  # name expected-run-status expected-live, extra env
	local name=$1 want=$2 live=$3; shift 3
	rm -rf "$T/proj/ci"
	env "$@" "$CI" --stages "configure build run" "$T/proj" > "$T/out.log" 2>&1
	if jq -e --arg w "$want" --argjson l "$live" '.stages.run | .status == $w and .vma_live_allocations == $l' "$T/proj/ci/summary.json" > /dev/null
	then echo "ok   $name"; else echo "FAIL $name: $(jq -c .stages.run "$T/proj/ci/summary.json" 2>/dev/null)"; fails=$((fails + 1)); fi
}
run "run passes with 0 live VMA allocations" pass 0 STUB_LIVE=0
run "run fails with 1 live VMA allocation" fail 1 STUB_LIVE=1
run "run without a VMA line records null" pass null STUB_LIVE=
src=$G/templates/cpp-vulkan/src
grep -q 'VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT' "$src/gpu_context.cpp" && grep -q 'vmaGetHeapBudgets' "$src/gpu_context.cpp" \
	&& grep -q 'vram_used_mb=%s vram_budget_mb=%llu' "$src/main.cpp" && ! grep -q 'vkAllocateMemory' "$src"/*.cpp \
	&& echo "ok   template reads budgets through VMA, no vkAllocateMemory" || { echo "FAIL template"; fails=$((fails + 1)); }
P=$T/game
"$G/scripts/new-cpp-game" "$P" > /dev/null || { echo "FAIL new-cpp-game"; exit 1; }
PATH=${PATH#"$T/bin:"} CPPCI_RUNNER= "$CI" --stages "configure build run" --frames 30 "$P" > "$T/out.log" 2>&1
jq -e '.stages.run | .status == "pass" and .vma_live_allocations == 0' "$P/ci/summary.json" > /dev/null \
	&& echo "ok   real template run: 0 live allocations" || { echo "FAIL real clean run: $(jq -c .stages.run "$P/ci/summary.json")"; fails=$((fails + 1)); }
grep -q '^        destroy_buffer(gpu_, m.block);$' "$P/src/renderer.cpp" && sed -i '/^        destroy_buffer(gpu_, m.block);$/d' "$P/src/renderer.cpp"
PATH=${PATH#"$T/bin:"} CPPCI_RUNNER= "$CI" --stages "configure build run" --frames 30 "$P" > "$T/out.log" 2>&1
# Default scene: the cube's, the ground's and the character's material blocks leak.
jq -e '.stages.run | .status == "fail" and .vma_live_allocations == 3' "$P/ci/summary.json" > /dev/null \
	&& echo "ok   leaked-buffer fixture: run red, 3 live allocations" || { echo "FAIL leak fixture: $(jq -c .stages.run "$P/ci/summary.json")"; fails=$((fails + 1)); }
echo "cpp-vram.test: $fails failed"
exit $((fails > 0))
