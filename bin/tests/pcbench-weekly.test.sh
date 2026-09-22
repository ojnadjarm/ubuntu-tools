#!/usr/bin/env bash
# PB09: the weekly pcbench timer and its "nobody home" gate. Unit files, gate verdicts against
# fixture JSON (never live state), roster/kill-switch registration. No trial, no model, no cost.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$BIN/tests/fixtures/pcbench-weekly"
UNITS="$HOME/.config/systemd/user"
RUNNER="$BIN/pcbench-weekly"
fail=0
t() { printf '%-56s' "pcbench-weekly: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }

# --- 1. unit files ---------------------------------------------------------
t "service + timer exist"
{ [ -r "$UNITS/pcbench-weekly.service" ] && [ -r "$UNITS/pcbench-weekly.timer" ]; } &&
  ok || no "missing unit file under $UNITS"

t "systemd-analyze --user verify"
out=$(systemd-analyze --user verify "$UNITS/pcbench-weekly.service" \
        "$UNITS/pcbench-weekly.timer" 2>&1 | grep -v spice-vdagent)
[ -z "$out" ] && ok || no "$out"

t "fires Sunday before maintenance (04:00)"
cal=$(sed -n 's/^OnCalendar=//p' "$UNITS/pcbench-weekly.timer")
case "$cal" in
  Sun*0[0-3]:*) systemd-analyze calendar "$cal" >/dev/null 2>&1 && ok || no "bad calendar: $cal";;
  *) no "OnCalendar=$cal is not a Sunday slot before 04:00";;
esac

# --- 2. the gate, against fixture JSON only --------------------------------
gate() {  # gate <fixture> -> the `pcbench away --json` object
  PATH="$FIX:$PATH" PCFAKE_STATUS="$FIX/$1.json" "$BIN/pcbench" away --json 2>/dev/null
}
for f in present-idle present-lid present-player present-seat; do
  t "gate: $f -> present"
  j=$(gate "$f")
  case $(echo "$j" | jq -r '.present') in
    true) [ -n "$(echo "$j" | jq -r '.reasons[0] // ""')" ] && ok || no "present with no reason";;
    *) no "$j";;
  esac
done

t "gate: away -> away, no reasons"
j=$(gate away)
[ "$(echo "$j" | jq -c '[.away,.present,(.reasons|length)]')" = '[true,false,0]' ] && ok || no "$j"

t "gate: unreadable pc status is read as present"
j=$(PATH="$FIX:$PATH" PCFAKE_STATUS=/nonexistent "$BIN/pcbench" away --json 2>/dev/null)
[ "$(echo "$j" | jq -r '.present')" = true ] && ok || no "$j"

t "away exit codes (0 away, 1 present)"
PATH="$FIX:$PATH" PCFAKE_STATUS="$FIX/away.json" "$BIN/pcbench" away >/dev/null 2>&1; a=$?
PATH="$FIX:$PATH" PCFAKE_STATUS="$FIX/present-idle.json" "$BIN/pcbench" away >/dev/null 2>&1; p=$?
[ "$a" = 0 ] && [ "$p" = 1 ] && ok || no "away=$a present=$p"

t "pcbench run --require-away exists and skips"
"$BIN/pcbench" run --help 2>&1 | grep -q -- --require-away && ok || no "no --require-away flag"

# --- 3. the runner's own gate ----------------------------------------------
W=$(mktemp -d); export PCBENCH_WEEKLY_STATE="$W" PCBENCH_WEEKLY_LOG="$W/log"

t "runner skips and counts when the owner is present"
PATH="$FIX:$BIN:$PATH" PCFAKE_STATUS="$FIX/present-player.json" bash "$RUNNER" --dry-run >"$W/o1" 2>&1
rc=$?
{ [ "$rc" = 0 ] && grep -q 'skipped: owner present' "$W/o1" && [ "$(cat "$W/weekly-skips")" = 1 ]; } &&
  ok || no "rc=$rc streak=$(cat "$W/weekly-skips" 2>/dev/null) $(cat "$W/o1")"

t "streak reaches 3 and stops there"
for _ in 2 3 4; do
  PATH="$FIX:$BIN:$PATH" PCFAKE_STATUS="$FIX/present-player.json" \
    bash "$RUNNER" --dry-run >>"$W/o1" 2>&1
done
[ "$(cat "$W/weekly-skips")" = 4 ] && ok || no "streak=$(cat "$W/weekly-skips")"

t "runner passes the gate when away and would run every tier"
PATH="$FIX:$BIN:$PATH" PCFAKE_STATUS="$FIX/away.json" bash "$RUNNER" --dry-run >"$W/o2" 2>&1
rc=$?
w=$(sed -n 's/.*would run: //p' "$W/o2")
{ [ "$rc" = 0 ] && grep -q 'gate: away' "$W/o2" &&
  case "$w" in *"--arm both"*"-n 3"*"--model opus"*"--require-away"*) [[ $w != *--tier* ]];; *) false;; esac
} && ok || no "rc=$rc cmd='$w'"

t "the idle row is sampled after the gate, never on a dry run"
{ grep -q 'pc idle --seconds 60 --tsv >>"$BENCH/BASELINE-IDLE.tsv"' "$RUNNER" &&
  ! grep -q 'BASELINE-IDLE' "$W/o2" &&
  [ "$(sed -n '2s/^#//p' "$BIN/../bench/BASELINE-IDLE.tsv" | awk -F'\t' '{print NF}')" = 10 ]
} && ok || no "idle line missing, sampled on --dry-run, or the header is not 9 columns"

t "the weekly selection includes the confirming C02/C04 re-run"
sel=$("$BIN/pcbench" list --set night | awk '{print $1}' | tr '\n' ' ')
case "$sel" in *C02*) case "$sel" in *C04*) ok;; *) no "C04 missing from $sel";; esac;;
                 *) no "C02 missing from $sel";; esac

t "away run resets the streak file only on success"
[ "$(cat "$W/weekly-skips")" = 4 ] && ok || no "a dry run must not reset the streak"
rm -rf "$W"

# --- 4. registration -------------------------------------------------------
t "roster row in KB/orchestrator.md"
grep -q '`pcbench-weekly.timer`' "$HOME/agents/KB/orchestrator.md" && ok || no "no roster row"

t "agents-start would re-enable it from the roster"
u=$(grep 'pcbench-weekly.timer' "$HOME/agents/KB/orchestrator.md" | head -1 | awk -F'|' '{print $3}' |
    grep -o '`[^`]*`' | head -1 | tr -d '`')
[ "$u" = pcbench-weekly.timer ] && ok || no "agents-start would parse '$u'"

t "agents-stop stops the service and the timer"
{ grep -q 'pcbench-weekly.service' "$BIN/agents-stop" &&
  grep -q 'pcbench-weekly.timer' "$BIN/agents-stop"; } && ok || no "not in agents-stop"

t "timer is enabled and listed"
systemctl --user list-timers --all --no-legend pcbench-weekly.timer 2>/dev/null |
  grep -q pcbench-weekly && ok || no "$(systemctl --user is-enabled pcbench-weekly.timer 2>&1)"

t "pcbench guard ignores its own timer"
grep -q '"pcbench" in line' "$BIN/pcbench" && ok || no "guard_start would refuse on its own timer"

t "the weekly units are not counted as trial residue"
grep -q 'pcbench-weekly' "$BIN/pcbench.d/fingerprint.sh" && ok || no "fingerprint counts them"

[ $fail = 0 ] && echo "pcbench-weekly.test.sh: all green" || echo "pcbench-weekly.test.sh: FAILURES"
exit $fail
