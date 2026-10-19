#!/usr/bin/env bash
# T48-L1: improve-meter against tests/fixtures/improve-meter — stub transcripts, run metas, corpus,
# corrector, pc and pcbench. Nothing real is read except the dashboard's word_diff; nothing real is written.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$BIN/tests/fixtures/improve-meter"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

cp -r "$FIX/agents" "$WORK/agents"
ORCH="$WORK/projects/$(printf %s "$HOME" | tr / -)"
mkdir -p "$ORCH"; cp "$FIX"/orch/*.jsonl "$ORCH/"
find "$WORK" -type f -exec touch -d '2026-09-22 11:30 UTC' {} +
touch -d '2026-09-10 08:00 UTC' "$WORK/agents/old/logs/"*.meta.json "$ORCH/stale.jsonl"
NOW=$(date -d '2026-09-22 12:00 UTC' +%s)

im() {
  IMPROVE_NOW="$NOW" IMPROVE_AGENTS="$WORK/agents" IMPROVE_PROJECTS="$WORK/projects" \
  IMPROVE_CORPUS="$FIX/corpus" IMPROVE_CORRECTOR="${CORRECTOR:-$FIX/eye/correct.js}" \
  IMPROVE_METRICS="$WORK/improve/metrics.tsv" IMPROVE_PC="$FIX/stubs/pc" IMPROVE_PCBENCH="$FIX/stubs/pcbench" \
  "$BIN/improve-meter" "$@"
}
col() { awk -F'\t' -v c="$1" 'NR==1{for(i=1;i<=NF;i++) if($i==c) k=i} NR==2{print $k}' <<<"$2"; }

# 1. every column filled with --idle on, each from its own source.
t0=$(date +%s.%N); R=$(im --idle on); rc=$?; t1=$(date +%s.%N)
is 'exit 0'                 "$rc" 0
is 'header'                 "$(head -1 <<<"$R")" "$(printf 'date\torch_ctx_k\theadless_cc_k\tdoctor_s\tpcbench_pass\tcorpus_wer_pct\tidle_psys_w')"
is 'date from IMPROVE_NOW'  "$(col date "$R")" 2026-09-22
is 'orch ctx: 3 turns in window (one split over 2 lines, F18), sidechain, old turn and stale file skipped' "$(col orch_ctx_k "$R")" 200.0
is 'headless cc: 2 runs in window, old, broken and all-zero skipped' "$(col headless_cc_k "$R")" 25.0
is 'pcbench new-arm pass'   "$(col pcbench_pass "$R")" 0.75
is 'corpus WER after corrector, pooled 1/8' "$(col corpus_wer_pct "$R")" 12.5
is 'idle psys W'            "$(col idle_psys_w "$R")" 4.20
d=$(col doctor_s "$R"); awk -v d="$d" 'BEGIN{exit !(d>=0.3 && d<2)}' && ok "doctor wall $d s" || nok 'doctor wall' "$d"
filled=$(sed -n 2p <<<"$R" | tr '\t' '\n' | grep -vc '^-$'); is '7/7 fields filled' "$filled" 7
awk -v a="$t0" -v b="$t1" 'BEGIN{exit !(b-a<5)}' && ok 'fixture wall < 5 s' || nok 'fixture wall' "$(echo "$t1 - $t0" | bc)"

# 2. idle gate: auto samples only when pcbench says away; off never samples.
is 'auto, present -> no idle' "$(col idle_psys_w "$(FIX_AWAY=false im)")" -
is 'auto, away -> idle'       "$(col idle_psys_w "$(FIX_AWAY=true im)")" 4.20
is 'off -> no idle'           "$(col idle_psys_w "$(FIX_AWAY=true im --idle off)")" -

# 3. a missing corrector or source is '-', never a crash.
is 'no corrector -> -' "$(col corpus_wer_pct "$(CORRECTOR="$WORK/none.js" im --idle off)")" -
E=$(IMPROVE_NOW="$NOW" IMPROVE_AGENTS="$WORK/nope" IMPROVE_PROJECTS="$WORK/nope" IMPROVE_CORPUS="$WORK/nope" \
    IMPROVE_PC="$WORK/nope" IMPROVE_PCBENCH="$WORK/nope" "$BIN/improve-meter"); is 'all missing exit 0' "$?" 0
is 'all missing -> 6 dashes' "$(sed -n 2p <<<"$E" | tr '\t' '\n' | grep -c '^-$')" 6

# 4. --append: header once, one row per date, same date replaced.
im --idle off --append >/dev/null; im --idle on --append >/dev/null
is 'metrics: header + 1 row' "$(wc -l <"$WORK/improve/metrics.tsv")" 2
is 'same date replaced'      "$(awk -F'\t' 'NR==2{print $7}' "$WORK/improve/metrics.tsv")" 4.20
IMPROVE_NOW=$((NOW + 86400)) IMPROVE_AGENTS="$WORK/agents" IMPROVE_PROJECTS="$WORK/projects" IMPROVE_CORPUS="$FIX/corpus" \
  IMPROVE_METRICS="$WORK/improve/metrics.tsv" IMPROVE_PC="$FIX/stubs/pc" IMPROVE_PCBENCH="$FIX/stubs/pcbench" \
  "$BIN/improve-meter" --idle off --append >/dev/null
is 'next day appended' "$(cut -f1 "$WORK/improve/metrics.tsv" | tr '\n' ' ')" 'date 2026-09-22 2026-09-23 '
[ -e "$WORK/improve/metrics.tsv.tmp" ] && nok 'no tmp left' present || ok 'no tmp left'

# 5. flags.
im --help >/dev/null; is '--help exit 0' "$?" 0
im --nope >/dev/null 2>&1; is 'unknown flag exit 2' "$?" 2
im --idle maybe >/dev/null 2>&1; is 'bad idle mode exit 2' "$?" 2

# 6. read-only without --append: the fixture tree is untouched.
before=$(find "$FIX" -type f -newermt '-2 second' | wc -l)
im --idle on >/dev/null
is 'fixture untouched' "$(find "$FIX" -type f -newermt '-2 second' | wc -l)" "$before"

# 7. registration (CR-004): daily 06:45 timer, oneshot --append, roster row, kill switch. Files only.
U="$BIN/../units"
is 'service is a oneshot'      "$(grep -c '^Type=oneshot$' "$U/improve-meter.service" 2>/dev/null)" 1
is 'service runs --append'     "$(grep -c '^ExecStart=%h/agents/bin/improve-meter --append$' "$U/improve-meter.service" 2>/dev/null)" 1
is 'service PATH has agents/bin' "$(grep -c '^Environment=PATH=%h/agents/bin:' "$U/improve-meter.service" 2>/dev/null)" 1
is 'timer daily 06:45'         "$(grep -c '^OnCalendar=\*-\*-\* 06:45$' "$U/improve-meter.timer" 2>/dev/null)" 1
is 'timer persistent'          "$(grep -c '^Persistent=true$' "$U/improve-meter.timer" 2>/dev/null)" 1
systemd-analyze calendar '*-*-* 06:45' >/dev/null 2>&1; is 'calendar spec valid' "$?" 0
u=$(grep 'improve-meter.timer' "$BIN/../KB/orchestrator.md" | head -1 | awk -F'|' '{print $3}' | grep -o '`[^`]*`' | head -1 | tr -d '`')
is 'agents-start parses the roster row' "$u" improve-meter.timer
{ grep -q 'improve-meter.service' "$BIN/agents-stop" && grep -q 'improve-meter.timer' "$BIN/agents-stop"; } &&
  ok 'agents-stop stops service and timer' || nok 'agents-stop stops service and timer' 'not listed'

[ "$bad" = 0 ] && printf 'PASS improve-meter\n' || printf 'FAIL improve-meter\n'
exit "$bad"
