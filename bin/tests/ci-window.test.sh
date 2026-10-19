#!/usr/bin/env bash
# Fixtures for ~/agents/bin/ci-window: a fake clock and a fake /proc/loadavg file; no real load is read or made.
set -uo pipefail
B="$HOME/agents/bin"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export CI_LOADAVG="$WORK/loadavg" WAIT_FOR_DIR="$WORK/waits" CI_QUIET_EVERY=1
bad=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want $2, got $3)"; bad=$((bad+1)); fi; }

for t in 00:49:0 00:50:1 01:20:1 01:49:1 01:50:0 13:00:0; do
  CI_WINDOW_NOW="${t%:*}" "$B/ci-window" >/dev/null; ok "window at ${t%:*}" "${t##*:}" $?
done

echo "1.20 1.00 1.00 1/100 1" >"$CI_LOADAVG"
out="$("$B/ci-window" --quiet)"; ok "quiet: rc 0" 0 $?
ok "quiet: load recorded" yes "$(case "$out" in *"load 1.20 < 4 after 0 s"*) echo yes;; *) echo no;; esac)"

echo "14.02 9 9 1/100 1" >"$CI_LOADAVG"
out="$(CI_QUIET_CAP=2 "$B/ci-window" --quiet)"; ok "busy past the cap: rc 1" 1 $?
ok "busy: load and cap recorded" yes "$(case "$out" in *"load 14.02, still ≥ 4"*"cap 2 s"*) echo yes;; *) echo no;; esac)"

( sleep 1; echo "3.10 9 9 1/100 1" >"$CI_LOADAVG" ) &
out="$(CI_QUIET_CAP=20 "$B/ci-window" --quiet)"; ok "load drops: rc 0" 0 $?
ok "load drops: quiet load recorded" yes "$(case "$out" in *"load 3.10 < 4"*) echo yes;; *) echo no;; esac)"
"$B/ci-window" --bogus 2>/dev/null; ok "bad flag: rc 2" 2 $?

# Shared budget (T408): CI_DEADLINE (set by ci-autofix) shortens every wait so the run after it still fits (CI_RUN_NEED s).
echo "14.02 9 9 1/100 1" >"$CI_LOADAVG"
out="$(CI_DEADLINE=$(( $(date +%s) + 3 )) CI_RUN_NEED=1 "$B/ci-window" --quiet)"; ok "budget: busy past the shared cap: rc 1" 1 $?
ok "budget: the wait was cut to the budget" yes "$(case "$out" in *"still ≥ 4 after "[0-3]" s (cap 2 s, shared budget"*) echo yes;; *) echo "no: $out";; esac)"
out="$(CI_DEADLINE=$(( $(date +%s) + 100 )) CI_RUN_NEED=2700 "$B/ci-window" --quiet)"; ok "budget spent: rc 1 at once" 1 $?
ok "budget spent: says so" yes "$(case "$out" in "ci-window: no wait budget left ("*" s to the deadline, a run needs 2700 s); going on") echo yes;; *) echo "no: $out";; esac)"

exit $(( bad > 0 ))
