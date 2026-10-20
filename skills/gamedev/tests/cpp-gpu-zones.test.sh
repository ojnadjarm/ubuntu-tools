#!/usr/bin/env bash
# T658: per-pass GPU zones - template sources time shadow/scene/post; cpp-ci perf keeps gpu_ms_p50_<pass> and names the culprit pass on a fail (stub runner, no GPU).
set -u
SKILL=$(cd "$(dirname "$0")/.." && pwd)
CI=$SKILL/scripts/cpp-ci SRC=$SKILL/templates/cpp-vulkan/src
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CREATIVE_CI_LOG=$T/creative-ci.jsonl
mkdir -p "$T/bin" "$T/proj" "$T/idle/a" "$T/idle/b"
echo '{}' > "$T/proj/CMakePresets.json"
cat > "$T/bin/cmake" <<'SH'
#!/bin/sh
case $1 in --preset) mkdir -p "$4" ;; --build) printf '#!/bin/sh\n' > "$2/game"; chmod +x "$2/game" ;; esac
SH
cat > "$T/bin/runner" <<'SH'
#!/bin/sh
echo "DONE frames=600 seconds=1 avg_fps=500.0 validation_errors=0 validation_warnings=0 gpu_ms_p50=$G50 gpu_ms_p99=0.3000 cpu_ms_p50=0.4100 post_ms_p50=$PO gpu_ms_p50_shadow=$SH gpu_ms_p50_scene=$SC gpu_ms_p50_post=$PO gpu_ms_p50_skin=0.0100 vram_used_mb=40 vram_budget_mb=900 draws=5 culled=0"
SH
chmod +x "$T/bin/cmake" "$T/bin/runner"
export PATH="$T/bin:$PATH" CPPCI_RUNNER="$T/bin/runner" QUIET_FDINFO=$T/idle
pass=0 fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi; }
perf() {  # G50 SHADOW SCENE POST
	G50=$1 SH=$2 SC=$3 PO=$4 "$CI" --out "$T/ci" --stages "configure build perf" --perf-max-load 999 "$T/proj" > "$T/out.log" 2>&1
	echo $? > "$T/rc"
}
P() { jq -r ".stages.perf.$1" "$T/ci/summary.json"; }

ok "gpu_timer.cpp names the pass keys" 'grep -q "\"gpu_ms_p50_shadow\", \"gpu_ms_p50_scene\", \"gpu_ms_p50_post\"" "$SRC/gpu_timer.cpp"'
ok "renderer.cpp wraps shadow and scene in timer zones" '[ "$(grep -cE "timer_\.(begin|end)\(cmd, frame_, .*zone_of\(GpuPass::(Shadow|Scene)\)\)" "$SRC/renderer.cpp")" = 4 ]'
ok "main.cpp prints every pass key in DONE" 'grep -q "gpu_pass_key(static_cast<GpuPass>(p))" "$SRC/main.cpp" && grep -q "post_ms_p50=%.4f %svram_used_mb" "$SRC/main.cpp"'

for i in 1 2 3; do perf 0.1100 0.0200 0.0600 0.0300; done
ok "3 seed runs pass" '[ "$(cat "$T/rc")" = 0 ] && [ "$(P status)" = pass ]'
ok "summary.json carries gpu_ms_p50_<pass>" 'jq -e ".stages.perf | .gpu_ms_p50_shadow == 0.02 and .gpu_ms_p50_scene == 0.06 and .gpu_ms_p50_post == 0.03 and .culprit == null" "$T/ci/summary.json" >/dev/null'
ok "skinned draw in csv col 18 and summary.json" '[ "$(tail -1 "$T/ci/perf.csv" | cut -d, -f18)" = 0.0100 ] && jq -e ".stages.perf.gpu_ms_p50_skin == 0.01" "$T/ci/summary.json" >/dev/null'
ok "perf.csv cols 15-17 are post,shadow,scene" '[ "$(head -1 "$T/ci/perf.csv" | cut -d, -f15-17)" = post_ms_p50,gpu_ms_p50_shadow,gpu_ms_p50_scene ] && [ "$(tail -1 "$T/ci/perf.csv" | cut -d, -f15-17)" = 0.0300,0.0200,0.0600 ]'

perf 0.2100 0.0250 0.1600 0.0300
ok "regressed frame fails perf" '[ "$(cat "$T/rc")" = 1 ] && [ "$(P status)" = fail ] && [ "$(P verdict)" = fail ]'
ok "culprit line names the scene pass" 'grep -q "perf culprit pass=scene delta_ms=0.1 ms=0.1600 baseline_ms=0.0600" "$T/out.log"'
ok "summary.json culprit object" 'jq -e ".stages.perf.culprit | .pass == \"scene\" and .delta_ms == 0.1 and .baseline_ms == 0.06" "$T/ci/summary.json" >/dev/null'

perf 0.2100 0.1200 0.0600 0.0300
ok "a slower shadow pass is the culprit" 'grep -q "perf culprit pass=shadow delta_ms=0.1 " "$T/out.log"'

mkdir -p "$T/old"
{ echo "date,project,frames,avg_fps,load1,gpu_ms_p50,gpu_ms_p99,cpu_ms_p50,bound,status,vram_used_mb,vram_budget_mb,draws,culled,post_ms_p50"
	for i in 1 2 3; do echo "2026-10-01T00:00:00,proj,600,500.0,0.1,0.1100,0.3,0.41,cpu,pass,40,900,5,0,0.0300"; done; } > "$T/old/perf.csv"
cp -r "$T/old/." "$T/ci/" && rm -f "$T/ci/perf.old.csv"
perf 0.2100 0.0200 0.0600 0.1300
ok "15-column csv gains the columns in place" '[ ! -e "$T/ci/perf.old.csv" ] && [ "$(wc -l < "$T/ci/perf.csv")" = 5 ] && head -1 "$T/ci/perf.csv" | grep -q ",post_ms_p50,gpu_ms_p50_shadow,gpu_ms_p50_scene,gpu_ms_p50_skin$"'
ok "old rows still baseline the post pass" 'grep -q "perf culprit pass=post delta_ms=0.1 " "$T/out.log"'

echo "cpp-gpu-zones: $pass passed, $fail failed"
[ "$fail" = 0 ]
