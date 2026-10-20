#!/usr/bin/env bash
# Settle the GPU, run a Godot scene N times offscreen sampling gt0 clock/throttle and other GPU clients (exit 3, no rows, if > --max-gpu %), append one CSV row per run; exit 1 if the median p50 frame time > (1+tol) x the last 10 PASS rows' median, or median p99 > (1+p99-tol) x theirs.
set -euo pipefail
usage() { echo "usage: godot-perfgate.sh [--runs N] [--max-load L (default 0.5 × nproc)] [--max-gpu PCT (default 15)] [--seconds S] [--csv FILE] [--tol PCT] [--p99-tol PCT] [--pin-gpu MHZ] [PROJECT_DIR]"; exit 0; }

here=$(cd "$(dirname "$0")/.." && pwd)
runs=5 seconds=6 csv="" tol=10 p99tol=25 maxload="" maxgpu=15 pin="" proj=""
settle_cap=${PERFGATE_SETTLE_CAP:-10} noise_pct=20 keep=10
gt=${PERFGATE_GT-$(for d in /sys/class/drm/card*/gt/gt0; do echo "$d"; break; done)}
[ -d "$gt" ] || gt=""
while [ $# -gt 0 ]; do
	case $1 in
		--runs) runs=$2; shift 2 ;;
		--seconds) seconds=$2; shift 2 ;;
		--csv) csv=$2; shift 2 ;;
		--tol) tol=$2; shift 2 ;;
		--p99-tol) p99tol=$2; shift 2 ;;
		--max-load) maxload=$2; shift 2 ;;
		--max-gpu) maxgpu=$2; shift 2 ;;
		--pin-gpu) pin=$2; shift 2 ;;
		-h|--help) usage ;;
		*) proj=$1; shift ;;
	esac
done
work=$(mktemp -d "${TMPDIR:-/tmp}/godot-perfgate.XXXX")
orig="" warmpid="" sampler="" gsampler=""
gpu_write() { echo "$2" | sudo tee "$gt/rps_$1_freq_mhz" >/dev/null; }
gpu_set() {  # MIN MAX, written in the order that keeps min <= max
	if [ "$1" -gt "$(cat "$gt/rps_max_freq_mhz")" ]; then gpu_write max "$2"; gpu_write min "$1"
	else gpu_write min "$1"; gpu_write max "$2"; fi
}
cleanup() {
	[ -z "$sampler" ] || kill "$sampler" 2>/dev/null || true
	[ -z "$gsampler" ] || kill "$gsampler" 2>/dev/null || true
	[ -z "$warmpid" ] || pkill -TERM -s "$warmpid" 2>/dev/null || true
	if [ -n "$orig" ]; then gpu_set "${orig% *}" "${orig#* }" && echo "perfgate: gpu clock restored to min/max $orig MHz" >&2; fi
	rm -rf "$work"
}
trap cleanup EXIT
# shellcheck source=/dev/null
. "$(command -v quiet-gate)"
# shellcheck source=ci-lib.sh
. "$here/scripts/ci-lib.sh"
if [ -z "$proj" ]; then
	mkdir "$work/fixture"; cp -r "$here/fixture/." "$work/fixture/"
	proj=$work/fixture
fi
proj=$(cd "$proj" && pwd)
csv=${csv:-$proj/perf.csv}
cols="p50_ms,p95_ms,p99_ms,low1_fps" cols2="gpu_mhz_p50,throttle_pct,verdict"
[ -s "$csv" ] || echo "date,project,seconds,avg_fps,frame_ms,min_fps,load1,adapter,$cols,$cols2" > "$csv"
sed -i -e "1{/p99_ms/!s/\$/,$cols/}" -e "1{/verdict/!s/\$/,$cols2/}" "$csv"
baseline=$(awk -F, '$15 == "PASS" {print ($9 != "" ? $9 : $5)}' "$csv" | tail -n "$keep" | median)
base99=$(awk -F, '$15 == "PASS" && $11 != "" {print $11}' "$csv" | tail -n "$keep" | median)
field() { sed -n "s/^SMOKE done .* $1=\([0-9.]*\).*/\1/p" <<< "$out"; }

if ! busy=$(quiet-gate --max-per-cpu 0.5 --max-load1 "$maxload" --gpu "$maxgpu"); then
	echo "PERFGATE SKIP ${busy#quiet-gate: busy, }: numbers would be noise"; exit 3
fi
if [ -n "$pin" ]; then
	[ -n "$gt" ] || { echo "PERFGATE --pin-gpu needs gt0 sysfs (none found)"; exit 2; }
	orig="$(cat "$gt/rps_min_freq_mhz") $(cat "$gt/rps_max_freq_mhz")"
	gpu_set "$pin" "$pin" || { orig=""; echo "PERFGATE --pin-gpu $pin: sudo write to $gt failed"; exit 2; }
fi

# Warm-up: export, then run until two consecutive 1 s fps windows (t >= 2, past pipeline compile) agree within 3 % (cap settle_cap s); never written.
: > "$work/warm"
setsid "$here/scripts/godot-smoke.sh" --seconds "$settle_cap" "$proj" > "$work/warm" 2>&1 &
warmpid=$! settled=""
while kill -0 "$warmpid" 2>/dev/null; do
	settled=$(awk -F'[ =]' '/^SMOKE fps=/ && $5 >= 2 {f = $3; if (p > 0 && f > 0 && (p > f ? p - f : f - p) <= 0.03 * (p > f ? p : f)) {print $5; exit} p = f}' "$work/warm")
	if [ -n "$settled" ]; then pkill -TERM -s "$warmpid" 2>/dev/null || true; break; fi
	sleep 0.2
done
rc=0; wait "$warmpid" || rc=$?
warmpid=""
if [ -z "$settled" ] && [ "$rc" != 0 ]; then echo "PERFGATE warm-up failed"; tail -5 "$work/warm"; exit 1; fi
echo "perfgate: warm-up ${settled:+settled at t=$settled s}${settled:-ended unsettled (cap ${settle_cap} s)}" >&2

# NOISE counts only hard throttle reasons; PL1/PL2 is the package power budget shared with CPU load, set on most loaded runs.
hard=()
for n in thermal prochot ratl vr_thermalert vr_tdc pl4; do [ ! -f "$gt/throttle_reason_$n" ] || hard+=("$gt/throttle_reason_$n"); done
sample_gt() { while :; do echo "$(cat "$gt/rps_act_freq_mhz") $(cat "${hard[@]}" /dev/null | tr -d '\n')"; sleep 0.1; done; }
rows=() avgs=() mets=() p99s=() gpus=() noise=0 label=p50_ms
flush() { [ ${#rows[@]} -eq 0 ] || printf '%s\n' "${rows[@]}" | sed "s/,\$/,$1/" | tee -a "$csv"; }
for r in $(seq "$runs"); do
	for attempt in 1 2; do
		load=$(cut -d' ' -f1 /proc/loadavg)
		if [ -n "$gt" ]; then sample_gt > "$work/gt" & sampler=$!; fi
		qg_gpu_pct $$ > "$work/gpu" & gsampler=$!
		for try in 1 2; do
			out=$("$here/scripts/godot-smoke.sh" --no-export --seconds "$seconds" "$proj")
			avg=$(sed -n 's/^SMOKE done .*avg_fps=\([0-9.]*\).*/\1/p' <<< "$out")
			[ -n "$avg" ] && break
			cp "$proj/run.log" "$proj/run-hung-$r.log"; echo "PERFGATE run $r try $try gave no avg_fps (log run-hung-$r.log) $(grep -m1 '^SMOKE timeout' <<< "$out"), retrying" >&2
		done
		wait "$gsampler" || true; gsampler=""
		if awk -v p="$(cat "$work/gpu")" -v m="$maxgpu" 'BEGIN {exit !(p > m)}'; then
			echo "PERFGATE SKIP gpu busy at $(cat "$work/gpu")% > $maxgpu% mid-run (another GPU client), rows discarded"; exit 3
		fi
		gpu="" thr=""
		if [ -n "$sampler" ]; then
			kill "$sampler"; wait "$sampler" 2>/dev/null || true; sampler=""
			gpu=$(awk '$1 > 0 {print $1}' "$work/gt" | median)
			thr=$(awk '{n++; t += ($2 ~ /1/)} END {if (n) printf "%.0f", 100 * t / n}' "$work/gt")
		fi
		[ -n "$avg" ] || { echo "PERFGATE run $r produced no avg_fps"; tail -5 "$proj/run.log"; flush ABORT >/dev/null; exit 1; }
		minfps=$(awk '/^SMOKE fps=/ {split($2, f, "="); split($3, t, "="); if (t[2] >= 2 && (m == "" || f[2] < m)) m = f[2]} END {print m + 0}' <<< "$out")
		adapter=$(sed -n 's/^SMOKE renderer=.* adapter=//p' <<< "$out" | tr -d ,)
		frame=$(awk -v a="$avg" 'BEGIN {printf "%.2f", 1000 / a}')
		p50=$(field p50_ms) p99=$(field p99_ms)
		row="$(date -Is),$(basename "$proj"),$seconds,$avg,$frame,$minfps,$load,$adapter,$p50,$(field p95_ms),$p99,$(field low1_fps),$gpu,$thr,"
		if [ "$attempt" = 1 ] && [ -n "$thr" ] && [ "$thr" -gt "$noise_pct" ]; then
			rows+=("${row}NOISE"); noise=$((noise + 1))
			echo "perfgate: run $r throttle_pct=$thr > $noise_pct, marked NOISE, re-running once" >&2
			continue
		fi
		break
	done
	rows+=("$row") avgs+=("$avg")
	if [ -n "$p50" ]; then mets+=("$p50"); else mets+=("$frame"); label=frame_ms; fi
	[ -n "$p99" ] && p99s+=("$p99")
	[ -n "$gpu" ] && gpus+=("$gpu")
done
median=$(printf '%s\n' "${avgs[@]}" | median)
medmet=$(printf '%s\n' "${mets[@]}" | median)
med99=$( [ ${#p99s[@]} -gt 0 ] && printf '%s\n' "${p99s[@]}" | median || true)
medgpu=$( [ ${#gpus[@]} -gt 0 ] && printf '%s\n' "${gpus[@]}" | median || true)
spread="spread_fps=$(printf '%s\n' "${avgs[@]}" | sort -n | sed -n '1p;$p' | paste -sd-) median_p99_ms=${med99:-na} median_$label=$medmet gpu_mhz_p50=${medgpu:-na} noise_reruns=$noise"
if [ -z "$baseline" ]; then
	flush PASS; echo "PERFGATE baseline set median_fps=$median csv=$csv $spread"; exit 0
fi
ceil=$(awk -v b="$baseline" -v t="$tol" 'BEGIN {printf "%.2f", b * (1 + t / 100)}')
if awk -v m="$medmet" -v c="$ceil" 'BEGIN {exit !(m > c)}'; then
	flush FAIL; echo "PERFGATE FAIL median_fps=$median $label=$medmet > ceil=$ceil ($label baseline $baseline of last $keep PASS rows, tol $tol%) $spread"; exit 1
fi
if [ -n "$base99" ] && [ -n "$med99" ]; then
	ceil99=$(awk -v b="$base99" -v t="$p99tol" 'BEGIN {printf "%.2f", b * (1 + t / 100)}')
	if awk -v m="$med99" -v c="$ceil99" 'BEGIN {exit !(m > c)}'; then
		flush FAIL; echo "PERFGATE FAIL median_fps=$median p99_ms=$med99 > ceil=$ceil99 (p99 baseline $base99, tol $p99tol%) $spread"; exit 1
	fi
fi
flush PASS; echo "PERFGATE PASS median_fps=$median $label=$medmet <= ceil=$ceil ($label baseline $baseline of last $keep PASS rows, tol $tol%) $spread"
