# shellcheck shell=bash
# GPU timing gate for the cpp timing tests (sourced): `gpu_timed TEST METRIC -- CMD...` decides busy / run / lavapipe / low clock and logs one skips.tsv row.
# rc 0: measured, $gpu_value = METRIC from CMD's output (empty when CMD failed), $gpu_mhz = median clock; rc 3: skipped, one `skip` line printed; rc 130/143: interrupted, an `interrupted` skip row.
# GT_SYSFS: a dir with gt_act/max/min/RP0_freq_mhz (default the first /sys/class/drm/card*/); GPU_LOG: keep CMD's output there; GAMEDEV_GPU_PIN=1: gt_min to RP0 for the run.
declare -F ci_timing_skip > /dev/null || . "$(dirname "${BASH_SOURCE[0]}")/ci-lib.sh"

_gg_sysfs() {  # the gt sysfs dir, or nothing
	if [ -n "${GT_SYSFS:-}" ]; then echo "$GT_SYSFS"; return; fi
	local f; f=$(ls -d /sys/class/drm/card*/gt_act_freq_mhz 2>/dev/null | head -1)
	[ -n "$f" ] && echo "${f%/gt_act_freq_mhz}"
}

_gg_unpin() {  # GT OLD RP0: gt_min back to OLD
	echo "$2" | sudo -n tee "$1/gt_min_freq_mhz" > /dev/null 2>&1 && echo "gpu pin $2 -> $3 MHz, restored" || echo "gpu pin: restore of gt_min $2 MHz failed"
}

_gg_run() {  # GT SAMPLES LOG CMD... (in a subshell): CMD to LOG with a 0.2 s clock sampler, gt_min pinned to RP0 when GAMEDEV_GPU_PIN=1; rc = CMD's
	local gt=$1 samples=$2 log=$3 old rp0 rc; shift 3
	_gg_jobs="" _gg_pin=""
	trap 'exit 130' INT TERM
	trap '[ -n "$_gg_jobs" ] && kill $_gg_jobs 2>/dev/null; [ -n "$_gg_pin" ] && eval "_gg_unpin $_gg_pin"' EXIT
	if [ "${GAMEDEV_GPU_PIN:-0}" = 1 ] && [ -n "$gt" ]; then
		old=$(cat "$gt/gt_min_freq_mhz") rp0=$(cat "$gt/gt_RP0_freq_mhz")
		if echo "$rp0" | sudo -n tee "$gt/gt_min_freq_mhz" > /dev/null 2>&1; then
			_gg_pin=$(printf '%q %q %q' "$gt" "$old" "$rp0")
		else echo "gpu pin: sudo -n refused, running unpinned"; fi
	fi
	"$@" > "$log" 2>&1 &
	_gg_jobs=$!
	[ -n "$gt" ] && { while :; do cat "$gt/gt_act_freq_mhz" >> "$samples"; sleep 0.2; done & _gg_jobs+=" $!"; }
	wait "${_gg_jobs%% *}"; rc=$?
	return $rc
}

gpu_timed() {  # TEST METRIC -- CMD...: see the header
	local test=$1 metric=$2 gt busy tmp log rc max
	shift 2; [ "${1:-}" = -- ] && shift
	gpu_value="" gpu_mhz=0
	if ! busy=$(quiet-gate --max-per-cpu 0.5 --gpu 2>&1); then
		busy=$(head -1 <<< "$busy")
		echo "skip $metric: machine busy ($busy)"
		ci_timing_skip "$test" "$metric" "busy: $busy"; return 3
	fi
	gt=$(_gg_sysfs) tmp=$(mktemp -d)
	log=${GPU_LOG:-$tmp/cmd.log}
	( _gg_run "$gt" "$tmp/mhz" "$log" "$@" ); rc=$?
	if [ $rc = 130 ] || [ $rc = 143 ]; then
		echo "skip $metric: interrupted (rc $rc)"
		ci_timing_skip "$test" "$metric" interrupted; rm -rf "$tmp"; return $rc
	fi
	gpu_value=$(grep -oE "(^| )$metric=[0-9.-]+" "$log" | tail -1 | cut -d= -f2)
	gpu_mhz=$(awk '$1 > 0' "$tmp/mhz" 2>/dev/null | median | cut -d. -f1)
	gpu_mhz=${gpu_mhz:-0} max=$([ -n "$gt" ] && cat "$gt/gt_max_freq_mhz" || echo 0)
	if [ $rc != 0 ] || [ -z "$gpu_value" ]; then
		echo "gpu_timed $test: rc=$rc $metric='$gpu_value'"; tail -15 "$log"
		ci_timing_ran "$test" "$metric"; rm -rf "$tmp"; return 0
	fi
	grep -q '^GAME device="llvmpipe' "$log" && rc=lavapipe
	rm -rf "$tmp"
	if [ $rc = lavapipe ]; then
		echo "skip $metric=$gpu_value: lavapipe (CPU Vulkan)"
		ci_timing_skip "$test" "$metric" lavapipe; return 3
	fi
	if [ "$max" -gt 0 ] && [ "$gpu_mhz" -lt $((max * 9 / 10)) ]; then
		echo "skip $metric=$gpu_value: GPU clock $gpu_mhz of $max MHz"
		ci_timing_skip "$test" "$metric" "gpu-clock $gpu_mhz of $max MHz"; return 3
	fi
	ci_timing_ran "$test" "$metric"
}
