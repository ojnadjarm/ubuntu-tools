#!/usr/bin/env bash
# T472: power-profile-auto on a fake /sys/class/power_supply (bwrap bind) and a stub powerprofilesctl on PATH;
# the live profile is never read or set (selftest proves the stub and the fake sysfs are what the script sees).
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
PPA="$BIN/power-profile-auto"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
STUB="$WORK/stub" PS="$WORK/ps" LOG="$WORK/calls.log"
mkdir -p "$STUB" "$PS"; : >"$LOG"
. "$HOME/agents/bin/tests/lib/assert.sh"
if ! bwrap --dev-bind / / --bind "$PS" /sys/class/power_supply true 2>/dev/null; then
  echo 'FAIL selftest: bwrap cannot bind a fake /sys/class/power_supply'; exit 1
fi
# sb CMD... — run with the stub first on PATH and the fake power_supply dir over the real one.
sb() { bwrap --dev-bind / / --bind "$PS" /sys/class/power_supply --setenv PATH "$STUB:$PATH" \
         --setenv PP_LOG "$LOG" --setenv PP_CURRENT "${PP_CURRENT:-balanced}" --setenv PP_FAIL "${PP_FAIL:-}" -- "$@"; }
# ac STATE — the fake AC0 adapter reports online=STATE; no argument removes it.
ac()  { rm -rf "${PS:?}"/*; [ $# -eq 0 ] || { mkdir -p "$PS/AC0" "$PS/BAT0"; echo "$1" >"$PS/AC0/online"; echo 77 >"$PS/BAT0/capacity"; }; }

cat >"$STUB/powerprofilesctl" <<'EOF'
#!/bin/sh
echo "powerprofilesctl $*" >>"$PP_LOG"
case "$1" in
  get) echo "$PP_CURRENT";;
  set) [ -z "$PP_FAIL" ] || { echo "powerprofilesctl: stub failure" >&2; exit 1; };;
esac
EOF
chmod +x "$STUB/powerprofilesctl"

# 0. selftest: inside the sandbox the stub resolves first and AC0 is the fake one.
ac 0
is 'selftest: powerprofilesctl resolves to the stub' "$(sb sh -c 'command -v powerprofilesctl')" "$STUB/powerprofilesctl"
is 'selftest: power_supply is the fake dir' "$(sb cat /sys/class/power_supply/BAT0/capacity)" 77

# 1. --help prints the description and touches nothing.
out=$(sb "$PPA" --help); is '--help exits 0' "$?" 0
is '--help prints the header' "$out" 'Set the power profile from the AC state: performance on AC, balanced on battery (T21).'
is '--help calls no powerprofilesctl' "$(grep -c . "$LOG")" 0

# 2. happy paths.
ac 1; : >"$LOG"
is 'on AC from balanced sets performance' "$(PP_CURRENT=balanced sb "$PPA")" 'power-profile-auto: online=1 profile=performance (was balanced)'
is 'the set call reached the stub' "$(tail -1 "$LOG")" 'powerprofilesctl set performance'
ac 0; : >"$LOG"
is 'on battery from performance sets balanced' "$(PP_CURRENT=performance sb "$PPA")" 'power-profile-auto: online=0 profile=balanced (was performance)'
is 'the battery set call reached the stub' "$(tail -1 "$LOG")" 'powerprofilesctl set balanced'
: >"$LOG"; PP_CURRENT=balanced sb "$PPA" >/dev/null
is 'an already-right profile is not set again' "$(grep -c set "$LOG")" 0
ac; : >"$LOG"
is 'no AC adapter falls back to performance' "$(PP_CURRENT=balanced sb "$PPA")" 'power-profile-auto: online=? profile=performance (was balanced)'

# 3. failure path: a failing set exits non-zero and prints no success line.
ac 1
out=$(PP_CURRENT=balanced PP_FAIL=1 sb "$PPA" 2>&1); rc=$?
[ $rc -ne 0 ] && ok 'a failing powerprofilesctl set exits non-zero' || nok 'a failing powerprofilesctl set exits non-zero' "rc=$rc"
case "$out" in *'profile=performance'*) nok 'a failed set prints no success line' "$out";; *) ok 'a failed set prints no success line';; esac

[ $bad -eq 0 ] && echo PASS || echo FAIL
exit $bad
