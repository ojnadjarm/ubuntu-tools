#!/usr/bin/env bash
# T899: gpu_timed against a stub cpp-vk-run, stub quiet-gate/sudo and a fixture gt sysfs: busy, low clock, lavapipe -> skip row; full clock -> ran row + metric; failing command -> ran row, no value; pin set and restored (also on failure); refused sudo -> unpinned; INT to the group -> sampler and command killed, pin restored; T949: INT or TERM (rc 130/143) -> an `interrupted` skip row, never `ran`.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
. "$HOME/agents/bin/tests/lib/assert.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/gt"
export GT_SYSFS=$W/gt GAMEDEV_PERF_DIR=$W/perf PATH=$W/bin:$PATH
cat > "$W/bin/quiet-gate" <<'EOF'
#!/bin/sh
[ -n "${STUB_BUSY:-}" ] && { echo "quiet-gate: busy, $STUB_BUSY"; exit 3; }
exit 0
EOF
cat > "$W/bin/cpp-vk-run.sh" <<'EOF'
#!/bin/sh
echo "GAME device=\"${STUB_DEVICE:-Intel(R) Iris(R) Xe Graphics}\""
echo "min=$(cat "$GT_SYSFS/gt_min_freq_mhz")" >> "$GT_SYSFS/seen"
sleep 0.5
[ -n "${STUB_FAIL:-}" ] && { echo "fatal: stub"; exit 1; }
echo "DONE frames=600 validation_errors=0 post_ms_p50=0.512 gpu_ms_p50=1.1"
EOF
cat > "$W/bin/sudo" <<'EOF'
#!/bin/sh
echo "$*" >> "$GT_SYSFS/sudo.log"
[ -n "${STUB_SUDO_DENY:-}" ] && exit 1
[ "$1" = -n ] && shift
exec "$@"
EOF
chmod +x "$W/bin/"*
# shellcheck source=SCRIPTDIR/../scripts/gpu-gate.sh
. "$G/scripts/gpu-gate.sh"
gt() { echo "$1" > "$W/gt/gt_act_freq_mhz"; echo 1300 > "$W/gt/gt_max_freq_mhz"; echo 1300 > "$W/gt/gt_RP0_freq_mhz"; echo 100 > "$W/gt/gt_min_freq_mhz"; rm -f "$W/gt/seen" "$W/gt/sudo.log"; }
row() { tail -1 "$W/perf/skips.tsv" | cut -f2-4; }  # last skips.tsv row: test, metric, why
timed() { gpu_timed cpp-x post_ms_p50 -- cpp-vk-run.sh --frames 600 game > "$W/out" 2>&1; rc=$?; out=$(cat "$W/out"); }

gt 1300; STUB_BUSY="gpu 99% > 15%" timed
is "busy: rc 3" "$rc" 3
is "busy: skip row" "$(row)" "$(printf 'cpp-x\tpost_ms_p50\tbusy: quiet-gate: busy, gpu 99%% > 15%%')"
[ ! -e "$W/gt/seen" ] && ok "busy: command not run" || nok "busy: command not run" "it ran"
grep -q '^skip post_ms_p50: machine busy' <<< "$out" && ok "busy: skip line" || nok "busy: skip line" "$out"

gt 600; timed
is "low clock: rc 3" "$rc" 3
is "low clock: skip row" "$(row)" "$(printf 'cpp-x\tpost_ms_p50\tgpu-clock 600 of 1300 MHz')"
grep -q 'skip post_ms_p50=0.512: GPU clock 600 of 1300 MHz' <<< "$out" && ok "low clock: skip line" || nok "low clock: skip line" "$out"

gt 1300; timed
is "full clock: rc 0" "$rc" 0
is "full clock: ran row" "$(row)" "$(printf 'cpp-x\tpost_ms_p50\tran')"
gpu_timed cpp-x post_ms_p50 -- cpp-vk-run.sh > /dev/null 2>&1
is "full clock: metric returned" "$gpu_value" 0.512
is "full clock: median clock" "$gpu_mhz" 1300
GPU_LOG=$W/kept.log gpu_timed cpp-x post_ms_p50 -- cpp-vk-run.sh > /dev/null 2>&1
grep -q '^DONE ' "$W/kept.log" && ok "GPU_LOG keeps the output" || nok "GPU_LOG keeps the output" "no DONE"

gt 1300; STUB_DEVICE="llvmpipe (LLVM 20.1, 256 bits)" timed
is "lavapipe: rc 3" "$rc" 3
is "lavapipe: skip row" "$(row)" "$(printf 'cpp-x\tpost_ms_p50\tlavapipe')"

n=$(wc -l < "$W/perf/skips.tsv")
gt 1300; STUB_FAIL=1 timed
is "failing command: rc 0 (the test fails on the empty value)" "$rc" 0
is "failing command: ran row" "$(row)" "$(printf 'cpp-x\tpost_ms_p50\tran')"
is "one row per call" "$(wc -l < "$W/perf/skips.tsv")" $((n + 1))
grep -q 'fatal: stub' <<< "$out" && ok "failing command: log tail shown" || nok "failing command: log tail shown" "$out"

gt 1300; GAMEDEV_GPU_PIN=1 timed
is "pin: min raised to RP0 for the run" "$(cat "$W/gt/seen")" "min=1300"
is "pin: min restored" "$(cat "$W/gt/gt_min_freq_mhz")" 100
grep -q '^gpu pin 100 -> 1300 MHz, restored$' <<< "$out" && ok "pin: restored line" || nok "pin: restored line" "$out"
grep -q -- '-n tee' "$W/gt/sudo.log" && ok "pin: sudo -n tee" || nok "pin: sudo -n tee" "$(cat "$W/gt/sudo.log")"

gt 1300; GAMEDEV_GPU_PIN=1 STUB_FAIL=1 timed
is "pin + failing command: min restored" "$(cat "$W/gt/gt_min_freq_mhz")" 100
grep -q 'restored' <<< "$out" && ok "pin + failing command: restored line" || nok "pin + failing command: restored line" "$out"

gt 1300; GAMEDEV_GPU_PIN=1 STUB_SUDO_DENY=1 timed
is "refused sudo: rc 0" "$rc" 0
is "refused sudo: unpinned run" "$(cat "$W/gt/seen")" "min=100"
grep -q 'gpu pin: sudo -n refused, running unpinned' <<< "$out" && ok "refused sudo: unpinned line" || nok "refused sudo: unpinned line" "$out"
gt 1300; gpu_timed cpp-x post_ms_p50 -- sh -c 'kill -TERM $$' > "$W/out" 2>&1; rc=$?
is "TERM: rc 143" "$rc" 143
is "TERM: interrupted skip row, not ran" "$(row)" "$(printf 'cpp-x\tpost_ms_p50\tinterrupted')"
grep -q '^skip post_ms_p50: interrupted (rc 143)' "$W/out" && ok "TERM: skip line" || nok "TERM: skip line" "$(cat "$W/out")"
gt 1300; rm -f "$W/pg"  # Ctrl-C: INT to the process group (env un-ignores the INT that & ignores)
setsid env --default-signal=INT G="$G" W="$W" GAMEDEV_GPU_PIN=1 bash -c 'echo $$ > "$W/pg"; . "$G/scripts/gpu-gate.sh"; gpu_timed cpp-x m -- sleep 5' > "$W/out" 2>&1 &
sleep 0.8; kill -INT -- "-$(cat "$W/pg")"; sleep 0.6
is "INT: no sampler or command left" "$(pgrep -g "$(cat "$W/pg")" -a)" ""
is "INT + pin: min restored" "$(cat "$W/gt/gt_min_freq_mhz")" 100
is "INT: interrupted skip row, not ran" "$(row)" "$(printf 'cpp-x\tm\tinterrupted')"
pkill -g "$(cat "$W/pg")"; wait
echo "gpu-gate.test: $([ "${bad:-1}" = 0 ] && echo pass || echo FAIL)"
exit "${bad:-1}"
