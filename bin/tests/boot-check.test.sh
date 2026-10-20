#!/usr/bin/env bash
# boot-check.sh and its reboot-gate refusal, under a fake HOME with docker/curl/tmux/systemctl stubbed.
set -uo pipefail
unset HARNESS_ENV_LOADED
BIN="$HOME/agents/bin"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
has() { grep -q -- "$3" <<<"$2" && ok "$1" || nok "$1" "missing '$3' in: $2"; }

# Stubs log every call; docker reports a container down when it is in $DOWN, curl fails for ports in $HTTP_DOWN.
S="$WORK/stub"; mkdir -p "$S"; CALLS="$WORK/calls.log"; : >"$CALLS"
stub() { printf '#!/bin/sh\necho "%s $*" >>"%s"\n%s\n' "$1" "$CALLS" "$2" >"$S/$1"; chmod +x "$S/$1"; }
stub docker 'for a; do n=$a; done; case " $DOWN " in *" $n "*) echo false ;; *) echo true ;; esac'
stub curl 'for a; do u=$a; done; for p in $HTTP_DOWN; do case "$u" in *:$p/*) exit 22 ;; esac; done'
stub loginctl 'echo Linger=yes'
for n in tmux systemctl tailscale gdbus shutdown sudo notify-owner; do stub "$n" 'exit 0'; done
export PATH="$S:/usr/local/bin:/usr/bin:/bin" DOWN="" HTTP_DOWN=""

# Fake HOME: the real boot-check and maintenance-run libraries, pc and pc-mode stubbed.
FH="$WORK/home"; mkdir -p "$FH/agents/bin" "$FH/agents/maintenance/state"
cp "$BIN/env.sh" "$BIN/fleetlib.sh" "$BIN/boot-check.sh" "$FH/agents/bin/"
printf '#!/bin/sh\necho agent\n' >"$FH/agents/bin/pc-mode"
printf '#!/bin/sh\necho "pc $*" >>"%s"\nexit 0\n' "$CALLS" >"$FH/agents/bin/pc"
chmod +x "$FH/agents/bin/pc-mode" "$FH/agents/bin/pc"
export HARNESS_CONFIG="$WORK/config.env"
printf 'HARNESS_HOST=fixture\nMAINT_AUTO_REBOOT=1\n' >"$HARNESS_CONFIG"

# Selftest: every machine-reaching binary is the stub before any run.
for n in docker curl tmux systemctl shutdown sudo; do
  is "selftest: $n resolves to the stub" "$(command -v "$n")" "$S/$n"
done
bc() { HOME="$FH" bash "$FH/agents/bin/boot-check.sh"; }

# 1. Default env list: the 5.2 rows, all OK, exit 0.
out=$(bc); rc=$?
is 'all-OK exits 0' "$rc" 0
grep -q '^FAIL' <<<"$out" && nok 'all-OK prints no FAIL' "$out" || ok 'all-OK prints no FAIL'
has 'default checks moodle52 app' "$out" '^OK   docker moodle52-app-1$'
has 'default checks moodle52 http' "$out" '^OK   moodle52 http$'
has 'default curls port 8052' "$(cat "$CALLS")" 'localhost:8052/login/index.php'
is 'default has 13 rows' "$(wc -l <<<"$out")" 13

# 2. BOOT_CHECK_ENVS adds 5.3; one container down is named and fails the run.
printf 'BOOT_CHECK_ENVS="moodle52=8052 moodle53=8053"\n' >>"$HARNESS_CONFIG"
: >"$CALLS"; out=$(DOWN=moodle53-app-1 bc); rc=$?
is 'one FAIL exits 1' "$rc" 1
is 'exactly one FAIL row' "$(grep -c '^FAIL' <<<"$out")" 1
has 'the FAIL names the container' "$out" '^FAIL docker moodle53-app-1$'
has 'env list checks moodle53 http' "$out" '^OK   moodle53 http$'
has 'env list curls port 8053' "$(cat "$CALLS")" 'localhost:8053/login/index.php'
is 'env list has 16 rows' "$(wc -l <<<"$out")" 16

# 3. The reboot gate names up to 3 boot-check FAILs in the REFUSED line.
mr() { HOME="$FH" bash "$BIN/maintenance-run" --assume-reboot --dry-run --dry-run-ignore-window 2>&1; }
out=$(DOWN="moodle52-db-1 moodle53-db-1" HTTP_DOWN="8052 8053" mr)
has 'refusal names the first 3 FAILs' "$(grep 'REBOOT REFUSED' <<<"$out")" \
  'boot-check(docker moodle52-db-1, moodle52 http, docker moodle53-db-1)'
grep -q 'REBOOT REFUSED.*moodle53 http' <<<"$out" && nok 'refusal names at most 3' "$out" || ok 'refusal names at most 3'
has 'push carries the names' "$(grep 'would run: notify-owner' <<<"$out")" 'boot-check(docker moodle52-db-1'
out=$(mr)
grep -q 'boot-check' <<<"$out" && nok 'all-OK boot-check does not refuse' "$out" || ok 'all-OK boot-check does not refuse'
grep -q 'shutdown' "$CALLS" && nok 'no shutdown reached' "$(cat "$CALLS")" || ok 'no shutdown reached'

exit $bad
