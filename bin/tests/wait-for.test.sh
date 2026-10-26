#!/usr/bin/env bash
# Fixtures for ~/agents/bin/wait-for: every exit path plus registry lifecycle. Own child processes only.
set -uo pipefail
WF="$HOME/agents/bin/wait-for"
WORK=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$WORK"' EXIT
export WAIT_FOR_DIR="$WORK/waits"
. "$HOME/agents/bin/tests/lib/assert.sh"

sleep 1 & job=$!
"$WF" --pid "$job" --every 0.2 >/dev/null; eq "pid: exits 0 when the job ends" 0 $?

F="$WORK/job.log"; : >"$F"
( sleep 0.6; echo DONE >>"$F"; sleep 5 ) & job=$!
"$WF" --file "$F" --match '^DONE' --job "$job" --every 0.2 >/dev/null; eq "file: exits 0 on match" 0 $?
kill "$job" 2>/dev/null

: >"$F"; sleep 0.5 & job=$!
out=$("$WF" --label dia --file "$F" --match '^\{|Traceback' --job "$job" --every 0.2); rc=$?
eq "file: exits 3 when the job dies without a match" 3 "$rc"
eq "file: says why" "wait-for: dia: job $job died before the condition held (exit 3)" "$out"

touch -d '-1 hour' "$F"
WAIT_FOR_STALL=60 "$WF" --file "$F" --match DONE --every 0.2 >/dev/null; eq "file: stale file with no writer exits 3" 3 $?

bash -c 'exec 5>>"$1"; sleep 30' _ "$F" & writer=$!
sleep 0.3; touch -d '-1 hour' "$F"
WAIT_FOR_STALL=60 timeout 1.5 "$WF" --file "$F" --match DONE --every 0.2 >/dev/null
eq "file: stale file with a live writer keeps waiting" 124 $?
kill "$writer"

( sleep 0.5; : >"$WORK/flag" ) &
out=$("$WF" --label fl --until "test -e '$WORK/flag'" --every 0.2); eq "until: exits 0 when the condition holds" 0 $?
eq "until: a late flip says done after N s" yes "$(case "$out" in "wait-for: fl: done after "[0-9]*" s") echo yes;; *) echo "no: $out";; esac)"
out=$("$WF" --label now --until true --every 0.2); eq "until: true at the first poll exits 0" 0 $?
eq "  and says it held at start, so nothing was waited on" "wait-for: now: done at once, the condition already held at start" "$out"
( sleep 0.6; : >"$WORK/flag2" ) &
out=$("$WF" --label nz --until "ls '$WORK/flag2' >/dev/null 2>&1 || exit 7" --every 0.2); eq "until: a condition exiting non-zero keeps waiting" 0 $?
eq "  until it holds" yes "$(case "$out" in "wait-for: nz: done after "[0-9]*" s") echo yes;; *) echo "no: $out";; esac)"

sleep 30 & job=$!
"$WF" --label long --pid "$job" --every 5 >"$WORK/term.out" & wf=$!
sleep 0.5
eq "list: shows the running wait" long "$("$WF" --list | cut -f3)"
eq "list --json: records the job" "$job" "$("$WF" --list --json | jq -r '.[0].target')"
kill "$wf"; wait "$wf"; eq "TERM: exits 143 at once" 143 $?
eq "TERM: says it was killed, not done" yes "$(case "$(cat "$WORK/term.out")" in "wait-for: long: killed by SIGTERM after "[0-9]*" s, condition not met (exit 143)") echo yes;; *) echo "no: $(cat "$WORK/term.out")";; esac)"
eq "TERM: registry entry removed" 0 "$(find "$WAIT_FOR_DIR" -name '*.json' | wc -l)"
kill "$job"

"$WF" --file x >/dev/null 2>&1; eq "usage: --file needs --match" 2 $?

# T1372 self-match: an unbracketed `pgrep -f X` matches the waiter's own argv, so `! pgrep -f X` never holds.
name="t1406zz$$"
out=$(timeout 3 "$WF" --label pg --until "! pgrep -f $name" --every 0.2 2>&1); rc=$?
eq "until: unbracketed pgrep -f is refused, not run (exit 2)" 2 "$rc"
eq "  with a one-line bracket hint" yes "$(case "$out" in *"[n]pm"*) [ "$(wc -l <<<"$out")" = 1 ] && echo yes || echo "no: $out";; *) echo "no: $out";; esac)"
timeout 3 "$WF" --until "pgrep -of $name >/dev/null && false" --every 0.2 >/dev/null 2>&1; eq "until: combined -of flags refused too" 2 $?
timeout 3 "$WF" --until "! pkill -f $name" --every 0.2 >/dev/null 2>&1; eq "until: unbracketed pkill -f refused" 2 $?
timeout 3 "$WF" --until "! pgrep -f '[${name:0:1}]${name:1}'" --every 0.2 >/dev/null 2>&1; eq "until: bracketed pattern runs and holds at once" 0 $?
timeout 3 "$WF" --until "! pgrep -A -f $name" --every 0.2 >/dev/null 2>&1; eq "until: pgrep -A (ignore ancestors) runs" 0 $?
timeout 3 "$WF" --until "! pgrep -x $name" --every 0.2 >/dev/null 2>&1; eq "until: pgrep without -f runs" 0 $?

[ "$bad" = 0 ] && echo "all wait-for fixtures pass"
exit $bad
