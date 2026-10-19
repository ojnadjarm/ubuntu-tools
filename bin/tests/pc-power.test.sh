#!/usr/bin/env bash
# PT03: pc power against tests/fixtures/power (watt arithmetic incl. the energy_uj wrap, RC6 %,
# battery health, the profile table) plus one EPP round trip in bwrap over a fake cpu tree.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/power"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
# between <name> <value> <lo> <hi>
between() { awk -v v="$2" -v l="$3" -v h="$4" 'BEGIN{exit !(v>=l && v<=h)}' \
  && ok "$1" || nok "$1" "$2 not in [$3,$4]"; }
# fx <args…> — pc power against the recorded tree; sys2 is the second RAPL/rc6 sample.
fx() { PC_FIXTURE="$FIX" PC_SYS2="$FIX/sys2" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/l.jsonl" \
  "$BIN/pc-power" "$@"; }

J=$(fx --json)
[ -n "$J" ] && ok 'fixture run produces JSON' || nok 'fixture run produces JSON' empty

# 1. watts: 3.0 J / 0.3 s = 10 W package, 1.5 J core (the counter wrapped), 0.3 J uncore, 4.5 J psys.
between 'package watts'          "$(jq .rapl.package_w <<<"$J")" 9.5 10.2
between 'core watts across the energy_uj wrap' "$(jq .rapl.core_w <<<"$J")" 4.7 5.1
between 'uncore watts'           "$(jq .rapl.uncore_w <<<"$J")" 0.9 1.05
between 'psys watts'             "$(jq .rapl.psys_w   <<<"$J")" 14.2 15.3
is 'core is exactly half of package' \
  "$(jq '(.rapl.core_w / .rapl.package_w * 100 | round)' <<<"$J")" 50
is 'PL1 comes from constraint_0' "$(jq .rapl.pl1_w <<<"$J")" 95

# 2. RC6: 285 ms of residency in a 300 ms window.
between 'rc6 percent' "$(jq .gpu.rc6_pct <<<"$J")" 85 100
is 'gpu throttle reasons are a list' "$(jq -r '.gpu.throttle|type' <<<"$J")" array
is 'gpu runtime status' "$(jq -r .gpu.runtime_status <<<"$J")" active

# 3. battery: 50 585 000 / 70 032 000 = 72 %.
is 'battery health'  "$(jq .battery.health_pct  <<<"$J")" 72
is 'battery limit'   "$(jq .battery.charge_limit <<<"$J")" 80
is 'battery status'  "$(jq -r .battery.status   <<<"$J")" 'Not charging'
is 'AC is detected'  "$(jq .battery.ac          <<<"$J")" true

# 4. the profile table (ppd comes from the fixture's recorded powerprofilesctl).
is 'ppd from the fixture binary' "$(jq -r .profiles.ppd <<<"$J")" balanced
is 'platform profile'   "$(jq -r .profiles.platform <<<"$J")" performance
is 'platform choices'   "$(jq -r '.profiles.platform_choices|join(",")' <<<"$J")" 'quiet,balanced,performance'
is 'pstate'             "$(jq -r .profiles.pstate <<<"$J")" active
is 'turbo is a boolean' "$(jq -r '.profiles.turbo|type' <<<"$J")" boolean
is 'epp list'           "$(jq -r '.profiles.epps|length' <<<"$J")" 5

# 5. sub-verbs print only their own section.
is 'rapl verb'     "$(fx rapl --json | jq 'has("package_w")')" true
is 'battery verb'  "$(fx battery --json | jq .health_pct)" 72
is 'text status has four lines' "$(fx | wc -l)" 4

# 6. every mutating verb is a dry run without --apply, and writes no ledger line.
for v in 'profile performance' 'platform quiet' 'epp power' 'governor performance' 'turbo off' 'charge-limit 60'; do
  out=$(fx $v)
  case "$out" in would:*) ok "dry run: pc power $v";; *) nok "dry run: pc power $v" "$out";; esac
done
[ -e "$WORK/l.jsonl" ] && nok 'dry runs write no ledger entry' 'ledger exists' \
                       || ok 'dry runs write no ledger entry'

# 7. guard and argument validation.
out=$(fx fan 2>&1); rc=$?
is 'pc power fan exits 3' "$rc" 3
case "$out" in *FLEET*) ok 'pc power fan prints the FLEET line';; *) nok 'pc power fan prints the FLEET line' "$out";; esac
fx charge-limit 30 >/dev/null 2>&1; is 'charge-limit rejects 30' "$?" 2
fx epp nope        >/dev/null 2>&1; is 'epp rejects an unknown preference' "$?" 2
fx nosuchverb      >/dev/null 2>&1; is 'unknown verb exits 2' "$?" 2
fx --nosuchflag    >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
fx -h >/dev/null 2>&1; is '-h exits 0' "$?" 0
grep -q '^  pc power ' <<<"$("$BIN/pc" help)" && ok 'pc help lists pc power' || nok 'pc help lists pc power' 'missing'

# 8. sandboxed EPP round trip, undone inside this test: bwrap binds a fake cpu tree over
# /sys/devices/system/cpu and a pass-through sudo shim (no_new_privs: the real sudo cannot rise).
real_epp() { cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null; }
REAL_EPP=$(real_epp)
FCPU="$WORK/cpu"; mkdir -p "$WORK/shim"
for c in 0 1; do
  mkdir -p "$FCPU/cpu$c/cpufreq"; echo performance >"$FCPU/cpu$c/cpufreq/energy_performance_preference"
  echo 'default performance balance_performance balance_power power' >"$FCPU/cpu$c/cpufreq/energy_performance_available_preferences"
done
: >"$FCPU/.pt03-fake"
printf '#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n' >"$WORK/shim/sudo"; chmod +x "$WORK/shim/sudo"
sb() { bwrap --dev-bind / / --bind "$FCPU" /sys/devices/system/cpu --new-session --die-with-parent \
         --setenv PATH "$WORK/shim:/usr/sbin:/usr/bin:/bin" --setenv XDG_RUNTIME_DIR "$WORK" \
         --setenv PC_LEDGER "$WORK/live.jsonl" "$@"; }
epp_now() { cat "$FCPU/cpu0/cpufreq/energy_performance_preference"; }
if ! command -v bwrap >/dev/null || ! sb true 2>/dev/null; then
  ok 'sandboxed EPP round trip skipped (bwrap unavailable)'
elif ! sb test -e /sys/devices/system/cpu/.pt03-fake || [ -e /sys/devices/system/cpu/.pt03-fake ]; then
  nok 'sandboxed EPP round trip' 'refused: the cpu tree in the sandbox resolves to the real /sys'
else
  out=$(sb "$BIN/pc-power" epp balance_performance --apply)
  is 'sandboxed apply changes EPP' "$(epp_now)" balance_performance
  is 'every cpu got the new EPP' "$(cat "$FCPU/cpu1/cpufreq/energy_performance_preference")" balance_performance
  id=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^rollback: pc undo //p')
  [ -n "$id" ] && ok 'apply prints the rollback line' || nok 'apply prints the rollback line' "$out"
  is 'apply ledgers two lines' "$(wc -l <"$WORK/live.jsonl")" 2
  is 'the ledger entry is verified' "$(jq -r 'select(.verified!=null).verified' "$WORK/live.jsonl")" true
  sb "$BIN/pc-undo" --last --apply >/dev/null
  is 'pc undo restores EPP' "$(epp_now)" performance
fi
[ "$REAL_EPP" = performance ] && is 'pc status still reads the power profile' \
  "$("$BIN/pc-status" --json --fresh | jq -r .sections.power.profile.value)" performance
is 'the real EPP is untouched' "$(real_epp)" "$REAL_EPP"

[ $bad = 0 ] && echo 'PASS pc-power' || echo 'FAIL pc-power'
exit $bad
