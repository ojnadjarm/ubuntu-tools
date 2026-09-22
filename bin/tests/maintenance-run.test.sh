#!/usr/bin/env bash
# maintenance-run: the MAINT_AUTO_REBOOT switch, under a fixture config with shutdown/sudo/notify stubbed.
set -uo pipefail
BIN="$HOME/agents/bin"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"; [ -f "$WORK.summary" ] && mv "$WORK.summary" "$HOME/agents/maintenance/state/last-summary.txt"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
has() { grep -q -- "$3" <<<"$2" && ok "$1" || nok "$1" "missing '$3' in: $2"; }

# Stubs: every binary that could reach the real machine logs its call and does nothing.
mkdir -p "$WORK/stub"; CALLS="$WORK/calls.log"; : >"$CALLS"
for n in shutdown sudo notify-owner pc systemctl docker; do
  printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 0\n' "$n" "$CALLS" >"$WORK/stub/$n"; chmod +x "$WORK/stub/$n"
done
export PATH="$WORK/stub:/usr/local/bin:/usr/bin:/bin"

# Selftest: shutdown is the stub, directly and through sudo, before any run.
is 'selftest: shutdown resolves to the stub' "$(command -v shutdown)" "$WORK/stub/shutdown"
is 'selftest: sudo resolves to the stub' "$(command -v sudo)" "$WORK/stub/sudo"
shutdown -r +5; sudo shutdown -r +5
is 'selftest: stub shutdown recorded, nothing rebooted' "$(grep -c shutdown "$CALLS")" 2
: >"$CALLS"

# The real summary file is restored on exit; the fixture config replaces the owner's.
cp "$HOME/agents/maintenance/state/last-summary.txt" "$WORK.summary" 2>/dev/null || true
run_mr() { # <switch value> <flags…>
  local v="$1"; shift
  printf 'HARNESS_HOST=fixture\nMAINT_AUTO_REBOOT=%s\n' "$v" >"$WORK/config.env"
  HARNESS_CONFIG="$WORK/config.env" bash "$BIN/maintenance-run" --assume-reboot --dry-run "$@" 2>&1
}

# 1. MAINT_AUTO_REBOOT=0: refused first, by the owner switch, exit 3, push text names the hand reboot.
out=$(run_mr 0 --dry-run-ignore-window); rc=$?
is 'switch=0 exits 3' "$rc" 3
has 'switch=0 reason' "$out" 'REBOOT REFUSED: auto-reboot-disabled-by-owner'
has 'switch=0 push says a reboot is pending' "$out" 'would run: notify-owner -t maintenance "reboot required on fixture'
has 'switch=0 push says he does it by hand' "$out" 'do it yourself when convenient'
grep -q 'time-window\|pc-status-check\|boot-check\|agents-active' <<<"$out" && nok 'switch=0 skips the other gates' "$out" || ok 'switch=0 skips the other gates'
grep -q 'shutdown' "$CALLS" && nok 'switch=0 never calls shutdown' "$(cat "$CALLS")" || ok 'switch=0 never calls shutdown'
grep -q 'notify-owner' "$CALLS" && nok 'switch=0 dry-run does not push' "$(cat "$CALLS")" || ok 'switch=0 dry-run does not push'

# 2. MAINT_AUTO_REBOOT=1: the existing gates decide (window, health, agents); the switch is silent.
out=$(run_mr 1); rc=$?
grep -q 'auto-reboot-disabled-by-owner' <<<"$out" && nok 'switch=1 never names the switch' "$out" || ok 'switch=1 never names the switch'
case "$rc" in
  3) has 'switch=1 refused by a real gate' "$out" 'REBOOT REFUSED: ' ;;
  4) has 'switch=1 allowed only prints the shutdown' "$out" 'would run: sudo shutdown -r +' ;;
  *) nok 'switch=1 exit is 3 or 4' "$rc" ;;
esac
grep -q 'shutdown' "$CALLS" && nok 'switch=1 dry-run never calls shutdown' "$(cat "$CALLS")" || ok 'switch=1 dry-run never calls shutdown'

# 3. Unset: defaults to 1 (behaviour before the switch existed).
printf 'HARNESS_HOST=fixture\n' >"$WORK/config.env"
out=$(HARNESS_CONFIG="$WORK/config.env" bash "$BIN/maintenance-run" --assume-reboot --dry-run 2>&1)
grep -q 'auto-reboot-disabled-by-owner' <<<"$out" && nok 'unset defaults to auto-reboot on' "$out" || ok 'unset defaults to auto-reboot on'

exit $bad
