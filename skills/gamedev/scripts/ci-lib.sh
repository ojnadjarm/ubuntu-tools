# shellcheck shell=bash
# Shared stage runner for game-ci and cpp-ci (sourced): summary.json schema, record, needs, quiet-machine gate.
# Each ci_finish appends one line to the creative CI ledger that `pc failures` reads.
# A caller defines stage_<name> (sets $st pass|fail|skip and $x stage JSON), optionally needs(), then: ci_init, ci_run, ci_finish.

ci_init() {  # PREFIX OUT: stdout prefix; creates OUT/logs and an empty OUT/summary.json; sets $out (absolute) and $summary
	CI_PREFIX=$1
	mkdir -p "$2/logs"; out=$(cd "$2" && pwd)
	summary=$out/summary.json
	echo '{"stages": {}}' > "$summary"
}
record() {  # stage status seconds json
	local tmp; tmp=$(mktemp)
	jq --arg s "$1" --arg st "$2" --argjson sec "$3" --argjson x "$4" '.stages[$s] = ({status: $st, seconds: $sec} + $x)' "$summary" > "$tmp" && mv "$tmp" "$summary"
	echo "$CI_PREFIX $1 $2 ${3}s $(jq -c . <<< "$4")"
}
needs() { :; }  # stage: the stages it depends on (skipped unless they passed); callers override
ci_gate() {  # WAIT_S quiet-gate-args...: rc 0 quiet, 3 busy with $ci_busy = the reason; WAIT_S > 0 prints one waiting line, then waits up to WAIT_S s
	local w=$1; shift
	ci_busy=$(quiet-gate "$@") && return 0
	ci_busy=${ci_busy#quiet-gate: busy, }
	[ "$w" -gt 0 ] || return 3
	echo "$CI_PREFIX waiting: busy, $ci_busy"
	quiet-gate "$@" --wait "$w" > /dev/null
}
ci_run() {  # STAGE...: runs each stage_<name> (or skips it on a failed need) and records it; sets $ci_fail
	local s d dep t0
	ci_fail=0 ci_start=$(date +%s)
	for s in "$@"; do
		t0=$(date +%s); st=fail x='{}' dep=""
		for d in $(needs "$s"); do
			jq -e --arg d "$d" '.stages[$d].status == "pass"' "$summary" > /dev/null || dep=$d
		done
		if [ -n "$dep" ]; then
			st=skip; x=$(jq -n --arg d "$dep" '{reason: ("needs " + $d)}')
		else
			"stage_$s"
		fi
		record "$s" "$st" $(( $(date +%s) - t0 )) "$x"
		[ "$st" = fail ] && ci_fail=1
	done
}
ci_finish() {  # PROJECT [EXTRA_JSON]: top-level keys project, date, EXTRA, load, seconds, ok; prints the done line; rc = $ci_fail
	local tmp ok e=${2:-'{}'}; tmp=$(mktemp); ok=$([ "$ci_fail" = 0 ] && echo true || echo false)
	jq --arg p "$1" --arg d "$(date -Is)" --argjson e "$e" --argjson sec $(( $(date +%s) - ci_start )) --argjson ok "$ok" \
		--arg l "$(cut -d' ' -f1-3 /proc/loadavg)" \
		'{project: $p, date: $d} + $e + {load: $l, seconds: $sec, ok: $ok} + .' "$summary" > "$tmp" && mv "$tmp" "$summary"
	chmod 644 "$summary"
	ci_log "$(tr '[:upper:]' '[:lower:]' <<< "${CI_PREFIX/CI/-ci}")" "$1" "$ok" "$(jq -c '[.stages | to_entries[] | select(.value.status == "fail") | .key]' "$summary")" "$summary"
	echo "$CI_PREFIX done ok=$ok summary=$summary"
	return "$ci_fail"
}
ci_log() {  # TOOL PROJECT OK FAILED_JSON SUMMARY: appends {ts, tool, project, ok, failed, summary = its copy in creative-ci/<date>/, never cut[, run = RUN_TESTS_ID]} (<= 400 B: failed names dropped first) to creative-ci.jsonl under flock; scratch projects go to creative-ci-scratch.jsonl unless CREATIVE_CI_LOG is set or the ledger is itself in scratch
	local f=${CREATIVE_CI_LOG:-${HARNESS_HOME:-$HOME/agents}/log/creative-ci.jsonl} s=$5 k=creative-ci days=30 p=$2
	[[ $p == /* ]] || p=$5
	if [ -z "${CREATIVE_CI_LOG:-}" ] && ! ci_scratch "$f" && ci_scratch "$p"; then f=${f%.jsonl}-scratch.jsonl k=creative-ci/scratch days=7; fi
	mkdir -p "$(dirname "$f")"
	[ -f "$s" ] && s=$(ci_keep "$(dirname "$f")/$k" "$1" "$(basename "$2")" "$s" "$days")
	jq -cn --arg ts "$(date -Is)" --arg t "$1" --arg p "$(basename "$2")" --argjson ok "$3" --argjson fl "$4" --arg s "$s" --arg r "${RUN_TESTS_ID:-}" \
		'{ts: $ts, tool: $t, project: $p[:40], ok: $ok, failed: [$fl[:5][] | .[:40]], summary: $s} + (if $r == "" then {} else {run: $r} end) | until((tojson | utf8bytelength) <= 400 or .failed == []; .failed |= .[:-1])' | flock "$f" tee -a "$f" > /dev/null
}
ci_scratch() {  # PATH: rc 0 when its realpath is under a scratch root (CI_SCRATCH_ROOTS, default $TMPDIR and /tmp) or a Claude scratchpad
	local r p; [ -n "$1" ] || return 1
	p=$(realpath -m "$1")
	[[ $p == */claude-*/scratchpad/* ]] && return 0
	for r in ${CI_SCRATCH_ROOTS:-${TMPDIR:-/tmp} /tmp}; do
		[[ $p == "$(realpath -m "$r")"/* ]] && return 0
	done
	return 1
}
ci_keep() {  # DIR TOOL PROJECT SUMMARY [DAYS]: copies SUMMARY (> 16 KB: stages only) to DIR/<date>/<time>-TOOL-PROJECT.json, prunes copies > DAYS (30) days; prints the copy
	local c; c=$1/$(date +%F)/$(date +%H%M%S)-$2-${3:0:40}.json
	find "$1" -name '*.json' -mtime +"${5:-30}" -delete 2>/dev/null; find "$1" -mindepth 1 -type d -empty -delete 2>/dev/null
	mkdir -p "${c%/*}"
	if [ "$(stat -c %s "$4")" -le 16384 ]; then cp "$4" "$c"; else jq '{stages}' "$4" > "$c"; fi
	echo "$c"
}
ci_timing_skip() {  # TEST METRIC WHY: appends ts, test, metric, why (busy..., gpu-clock..., ran), load1, GPU clock MHz as one TSV row to skips.tsv under flock
	local f=${GAMEDEV_PERF_DIR:-${HARNESS_HOME:-$HOME/agents}/state/gamedev-perf}/skips.tsv gt w=${3//[$'\t\n']/ }
	gt=$(ls -d /sys/class/drm/card*/gt_act_freq_mhz 2>/dev/null | head -1)
	mkdir -p "${f%/*}"
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -Is)" "$1" "$2" "$w" "$(cut -d' ' -f1 /proc/loadavg)" "$([ -n "$gt" ] && cat "$gt" || echo -)" | flock "$f" tee -a "$f" > /dev/null
}
ci_timing_ran() { ci_timing_skip "$1" "$2" ran; }  # TEST METRIC: the gate measured (pass or fail)
median() { sort -n | awk '{a[NR] = $1} END {if (NR) print (NR % 2 ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2)}'; }  # stdin numbers: their median
