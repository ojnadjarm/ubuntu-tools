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

# 2b. T347-10: the pending reboot itself never blocks the reboot; any other pc status FAIL does.
# maintenance-run puts $HOME/agents/bin first on PATH, so the pc stub lives in a fake HOME.
GH="$WORK/gate-home"; mkdir -p "$GH/agents/bin" "$GH/agents/maintenance/state"
cp "$BIN/fleetlib.sh" "$BIN/env.sh" "$GH/agents/bin/"
pcstub() { printf '#!/bin/sh\necho "pc $*" >>"%s"\nprintf "%%b\\n" "%s"\nexit %s\n' "$CALLS" "$1" "$2" >"$GH/agents/bin/pc"; chmod +x "$GH/agents/bin/pc"; }
gate_mr() { printf 'HARNESS_HOST=fixture\nMAINT_AUTO_REBOOT=1\n' >"$WORK/config.env"
  HOME="$GH" HARNESS_CONFIG="$WORK/config.env" bash "$BIN/maintenance-run" --assume-reboot --dry-run --dry-run-ignore-window 2>&1; }
pcstub 'FAIL host.reboot_required: 11 d (linux-image)' 1
out=$(gate_mr)
{ grep -q 'REBOOT REFUSED' <<<"$out" && ! grep -q 'pc-status-check' <<<"$out"; } \
  && ok 'a pending reboot alone passes the health gate' || nok 'a pending reboot alone passes the health gate' "$(grep REBOOT <<<"$out")"
pcstub 'FAIL host.reboot_required: 11 d (linux-image)\nFAIL services.docker: inactive' 1
has 'another FAIL still refuses the reboot' "$(gate_mr)" 'pc-status-check'
pcstub '' 1
has 'a pc status that prints nothing still refuses' "$(gate_mr)" 'pc-status-check'

# 2c. T443: the refusal names the failed checks (at most 3) in the REFUSED line and the push (<= 200 chars).
pcstub 'FAIL host.reboot_required: 11 d (linux-image)\nFAIL host.failed_units: 1: pcbench-fail-fixture.service' 1
out=$(gate_mr)
has 'refusal names the failed fixture unit' "$(grep 'REBOOT REFUSED' <<<"$out")" 'pc-status-check(host.failed_units: 1: pcbench-fail-fixture.service)'
has 'refusal names the failed unit in the push' "$(grep 'would run: notify-owner' <<<"$out")" 'pcbench-fail-fixture.service'
grep -q 'REBOOT REFUSED.*reboot_required' <<<"$out" && nok 'refusal names skip the pending reboot' "$out" || ok 'refusal names skip the pending reboot'
long=$(printf 'x%.0s' $(seq 80))
pcstub "FAIL a.one: $long\nFAIL b.two: $long\nFAIL c.three: $long\nFAIL d.four: $long" 1
out=$(gate_mr)
grep -q 'd\.four' <<<"$out" && nok 'refusal names at most 3 checks' "$out" || ok 'refusal names at most 3 checks'
push=$(sed -n 's/^would run: notify-owner -t maintenance "\(.*\)"$/\1/p' <<<"$out")
[ -n "$push" ] && [ "${#push}" -le 200 ] && ok 'refusal push with names stays <= 200 chars' || nok 'refusal push with names stays <= 200 chars' "${#push}: $push"

# 3. Unset: fails safe to 0, a missing switch never reboots (T116).
printf 'HARNESS_HOST=fixture\n' >"$WORK/config.env"
out=$(HARNESS_CONFIG="$WORK/config.env" bash "$BIN/maintenance-run" --assume-reboot --dry-run 2>&1)
has 'unset defaults to auto-reboot off' "$out" 'REBOOT REFUSED: auto-reboot-disabled-by-owner'

# 4. Real run under a fake HOME: the upgrade count is this run's "Setting up" lines, printed once.
FH="$WORK/home"; mkdir -p "$FH/agents/bin" "$FH/agents/maintenance/state"
cp "$BIN/fleetlib.sh" "$BIN/env.sh" "$FH/agents/bin/"
printf 'Setting up old-run (1)\nSetting up old-run (2)\n' >"$FH/agents/maintenance/state/last-apt.log"
printf '#!/bin/sh\necho "sudo $*" >>"%s"\ncase "$*" in *full-upgrade*) printf "Unpacking a\\nSetting up a (1)\\nSetting up b (2)\\nSetting up c (3)\\n" ;; esac\nexit 0\n' \
  "$CALLS" >"$WORK/stub/sudo"
printf 'HARNESS_HOST=fixture\nMAINT_AUTO_REBOOT=0\n' >"$WORK/config.env"
out=$(HOME="$FH" MAINT_AUTO_REBOOT=0 HARNESS_CONFIG="$WORK/config.env" bash "$BIN/maintenance-run" 2>&1)
is 'real run counts this run only, once' "$(grep '^upgraded\|package operations' <<<"$out")" 'upgraded: 3 package operations'
grep -q 'shutdown' "$CALLS" && nok 'real run with switch=0 never calls shutdown' "$(cat "$CALLS")" || ok 'real run with switch=0 never calls shutdown'

# 4b. A failing apt step (held dpkg lock) is reported, pushed and exits 1.
printf '#!/bin/sh\necho "sudo $*" >>"%s"\ncase "$*" in *apt-get*) echo "E: Could not get lock /var/lib/dpkg/lock-frontend"; exit 100 ;; esac\nexit 0\n' \
  "$CALLS" >"$WORK/stub/sudo"
: >"$CALLS"
out=$(HOME="$FH" MAINT_AUTO_REBOOT=0 HARNESS_CONFIG="$WORK/config.env" bash "$BIN/maintenance-run" 2>&1); rc=$?
is 'apt failure exits 1' "$rc" 1
has 'apt failure in the summary' "$out" 'apt FAILED (rc 100)'
has 'apt failure pushed' "$(cat "$CALLS")" 'notify-owner -t maintenance apt FAILED (rc 100)'

# 5-6. The unit's chain (T116): env -i with agent@.service's environment, a parent that sources
# fleetlib.sh like agent-run, then maintenance-run as a child, not dry, with a reboot pending.
# bwrap binds a fixture /run/reboot-required and the stub over the real systemctl (= shutdown) and sudo.
UH="$WORK/unit-home"; mkdir -p "$UH/agents/bin" "$UH/agents/maintenance/state" "$UH/.config/pc-harness"
cp "$BIN/fleetlib.sh" "$BIN/env.sh" "$UH/agents/bin/"
echo 'linux-image-fixture' >"$WORK/reboot-required"
printf '#!/bin/sh\necho "sudo $*" >>"%s"\nexit 0\n' "$CALLS" >"$WORK/stub/sudo"
printf '#!/bin/sh\necho "real-path $0 $*" >>"%s"\nexit 0\n' "$CALLS" >"$WORK/stub/real"; chmod +x "$WORK/stub/real"
unit_mr() { # <config.env body> -> output; rc in $?
  printf '%s' "$1" >"$UH/.config/pc-harness/config.env"; shift
  env -i HOME="$UH" USER="$USER" PATH="$UH/.local/bin:$UH/agents/bin:/usr/local/bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="/run/user/$(id -u)" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" \
    bwrap --dev-bind / / --tmpfs /run --ro-bind "$WORK/reboot-required" /run/reboot-required \
      --bind "$WORK/stub" "$WORK/stub" \
      --ro-bind "$WORK/stub/real" "$(readlink -f /usr/sbin/shutdown)" \
      --ro-bind "$WORK/stub/real" "$(readlink -f /usr/bin/sudo)" \
      bash -c ". \"\$HOME/agents/bin/fleetlib.sh\"; fleet_path; export PATH=\"$WORK/stub:\$PATH\"; \"\$@\"" _ "$@" 2>&1
}
: >"$CALLS"
unit_mr '' /usr/sbin/shutdown -r +5 >/dev/null; unit_mr '' /usr/bin/sudo shutdown -r +5 >/dev/null
is 'selftest: real shutdown and sudo paths are the stub in the sandbox' "$(grep -c '^real-path' "$CALLS")" 2
: >"$CALLS"
out=$(unit_mr $'HARNESS_HOST=fixture\nMAINT_AUTO_REBOOT=0\n' bash "$BIN/maintenance-run"); rc=$?
is 'unit chain switch=0 exits 3' "$rc" 3
has 'unit chain switch=0 refused by the switch' "$out" 'REBOOT REFUSED: auto-reboot-disabled-by-owner'
has 'unit chain switch=0 pushes' "$(cat "$CALLS")" 'notify-owner -t maintenance reboot required on fixture'
grep -q 'shutdown\|^real-path' "$CALLS" && nok 'unit chain switch=0 never calls shutdown' "$(cat "$CALLS")" || ok 'unit chain switch=0 never calls shutdown'
printf 'unit chain switch=0 calls:\n%s\n' "$(sed 's/^/  /' "$CALLS")"
: >"$CALLS"
out=$(unit_mr $'HARNESS_HOST=fixture\n' bash "$BIN/maintenance-run"); rc=$?
is 'unit chain switch removed exits 3' "$rc" 3
has 'unit chain switch removed refused by the switch' "$out" 'REBOOT REFUSED: auto-reboot-disabled-by-owner'
grep -q 'shutdown\|^real-path' "$CALLS" && nok 'unit chain switch removed never calls shutdown' "$(cat "$CALLS")" || ok 'unit chain switch removed never calls shutdown'

exit $bad
