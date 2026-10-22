#!/usr/bin/env bash
# PT03: pc power against tests/fixtures/power (watt arithmetic incl. the energy_uj wrap, RC6 %,
# battery health, the profile table) plus one EPP round trip in bwrap over a fake cpu tree.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/power"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
# between <name> <value> <lo> <hi>
between() { awk -v v="$2" -v l="$3" -v h="$4" 'BEGIN{exit !(v>=l && v<=h)}' \
  && ok "$1" || nok "$1" "$2 not in [$3,$4]"; }
# fx <args…> — pc power against the recorded tree; sys2 is the second RAPL/rc6 sample, 300 ms apart.
fx() { PC_FIXTURE="$FIX" PC_POWER_ELAPSED_US=300000 PC_SYS2="$FIX/sys2" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/l.jsonl" \
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
# A refusing sudo and a private cache (T1136): no root SMART read, the live pc-status cache stays.
mkdir -p "$WORK/nosudo" "$WORK/pcs"; printf '#!/bin/sh\nexit 1\n' >"$WORK/nosudo/sudo"; chmod +x "$WORK/nosudo/sudo"
[ "$REAL_EPP" = performance ] && is 'pc status still reads the power profile' \
  "$(PATH="$WORK/nosudo:$PATH" XDG_RUNTIME_DIR="$WORK/pcs" "$BIN/pc-status" --json --fresh | jq -r .sections.power.profile.value)" performance
is 'the real EPP is untouched' "$(real_epp)" "$REAL_EPP"

# 9. cstates: pmc_core and cpuidle deltas over a 1 s window, runtime-PM `on` devices.
CF="$WORK/cfix"
pkgc() { mkdir -p "$CF/$1/kernel/debug/pmc_core"; local n; for n in 2 3 6 7 8 9 10; do
  printf 'Package C%s : %s\n' "$n" "$2"; done | awk -v d="$3" '{split(d,a," "); $4=$4+a[NR]; print}' \
  >"$CF/$1/kernel/debug/pmc_core/package_cstate_show"; }
pkgc sys 1000000 '0 0 0 0 0 0 0'; pkgc sys2 1000000 '150000 357000 1000 0 3000 0 151000'
idle() { local s=$1 c=$2 t=$3 st=$4 nm=$5 d="$CF/$1/devices/system/cpu/cpu$2/cpuidle/state$4"
  mkdir -p "$d"; echo "$nm" >"$d/name"; echo "$t" >"$d/time"; }
for s in sys sys2; do for c in 0 1; do idle $s $c 1000 0 POLL; done; done
idle sys 0 5000000 1 C6; idle sys 1 5000000 1 C6; idle sys2 0 5600000 1 C6; idle sys2 1 5400000 1 C6
idle sys 0 100 2 C10; idle sys 1 100 2 C10; idle sys2 0 200100 2 C10; idle sys2 1 100 2 C10
for p in 0000:00:00.0:on 0000:00:02.0:auto 10000:e1:00.0:on; do
  mkdir -p "$CF/sys/bus/pci/devices/${p%:*}/power"; echo "${p##*:}" >"$CF/sys/bus/pci/devices/${p%:*}/power/control"; done
for u in 1-3:on:'Cruzer Blade' 1-4:auto:Mouse usb1:auto:'xHCI Host Controller'; do IFS=: read -r id c nm <<<"$u"
  mkdir -p "$CF/sys/bus/usb/devices/$id/power"; echo "$c" >"$CF/sys/bus/usb/devices/$id/power/control"
  echo "$nm" >"$CF/sys/bus/usb/devices/$id/product"; done
mkdir -p "$CF/bin"; printf '#!/bin/sh\nprintf "%%s\\n" "0000:00:00.0 Host bridge: Intel Device 4621" "0000:00:02.0 VGA compatible controller: Intel" "10000:e1:00.0 Non-Volatile memory controller: Intel SSD 670p"\n' >"$CF/bin/lspci"
chmod +x "$CF/bin/lspci"
C=$(PC_FIXTURE="$CF" PC_SYS2="$CF/sys2" PC_POWER_ELAPSED_US=1000000 XDG_RUNTIME_DIR="$WORK" "$BIN/pc-power" cstates --window 0.1)
pk=$(grep '^pkg ' <<<"$C")
is 'cstates pkg line' "$(tr -s ' ' <<<"${pk%%(*}")" 'pkg pc2 15.0% pc3 35.7% pc6 0.1% pc7 0.0% pc8 0.3% pc9 0.0% pc10 15.1% '
case "$pk" in *'(1.00 s window)'*) ok 'cstates names the window';; *) nok 'cstates names the window' "$pk";; esac
is 'cstates core line averages every cpu' "$(grep '^core ' <<<"$C" | tr -s ' ')" 'core POLL 0.0% C6 50.0% C10 10.0% (2 cpus)'
is 'cstates lists only runtime-PM on devices' "$(grep '^rpm-on ' <<<"$C" | tr -s ' ')" \
  "$(printf '%s\n' 'rpm-on pci 0000:00:00.0 Host bridge: Intel Device 4621' \
    'rpm-on pci 10000:e1:00.0 Non-Volatile memory controller: Intel SSD 670p' 'rpm-on usb 1-3 Cruzer Blade')"
rm "$CF/sys2/kernel/debug/pmc_core/package_cstate_show"
pk=$(PC_FIXTURE="$CF" PC_SYS2="$CF/sys2" PC_POWER_ELAPSED_US=1000000 XDG_RUNTIME_DIR="$WORK" "$BIN/pc-power" cstates --window 0.1 | grep '^pkg ')
case "$pk" in *unavailable*) ok 'cstates says when pmc_core is unreadable';; *) nok 'cstates says when pmc_core is unreadable' "$pk";; esac

# 10. pl and runtime-pm (T1148) on a fake sysfs, writes through a pass-through sudo shim; the
# real powercap and USB values are read before and after and must not move.
real_pl() { cat /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw 2>/dev/null; }
real_rpm() { cat /sys/bus/usb/devices/1-3/power/control 2>/dev/null; }
REAL_PL=$(real_pl); REAL_RPM=$(real_rpm)
PF="$WORK/plfix"; PS="$PF/sys"
zone() { local d="$PS/class/powercap/$1" i=0 c; mkdir -p "$d"; echo package-0 >"$d/name"; shift
  for c in "$@"; do IFS=/ read -r n l t <<<"$c"; echo "$n" >"$d/constraint_${i}_name"
    echo "$l" >"$d/constraint_${i}_power_limit_uw"; echo "$t" >"$d/constraint_${i}_time_window_us"; i=$((i + 1)); done; }
zone intel-rapl-mmio:0 long_term/15000000/27983872 short_term/25000000/2440
zone intel-rapl:0 long_term/95000000/27983872 short_term/95000000/2440
mkdir -p "$PS/class/thermal/thermal_zone0" "$PS/class/thermal/thermal_zone1"
echo acpitz >"$PS/class/thermal/thermal_zone0/type"; echo 90000 >"$PS/class/thermal/thermal_zone0/temp"
echo x86_pkg_temp >"$PS/class/thermal/thermal_zone1/type"; echo 52000 >"$PS/class/thermal/thermal_zone1/temp"
for p in 0000:00:00.0:on:0x060000 0000:02:00.0:on:0x028000 0000:00:14.0:auto:0x0c0330; do IFS=: read -r a b c m k <<<"$p"
  mkdir -p "$PS/bus/pci/devices/$a:$b:$c/power"; echo "$m" >"$PS/bus/pci/devices/$a:$b:$c/power/control"
  echo "$k" >"$PS/bus/pci/devices/$a:$b:$c/class"; done
for u in 1-3:on:'Cruzer Blade' 1-4:auto:Mouse; do IFS=: read -r id c nm <<<"$u"
  mkdir -p "$PS/bus/usb/devices/$id/power"; echo "$c" >"$PS/bus/usb/devices/$id/power/control"
  echo "$nm" >"$PS/bus/usb/devices/$id/product"; done
mkdir -p "$PF/bin"; printf '#!/bin/sh\nprintf "%%s\\n" "0000:00:00.0 Host bridge: Intel" "0000:02:00.0 Network controller: MEDIATEK MT7921"\n' >"$PF/bin/lspci"; chmod +x "$PF/bin/lspci"
pf() { PATH="$WORK/shim:$PATH" PC_FIXTURE="$PF" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/pl.jsonl" "$BIN/pc-power" "$@"; }
pu() { PATH="$WORK/shim:$PATH" PC_FIXTURE="$PF" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/pl.jsonl" "$BIN/pc-undo" "$@"; }
plv() { echo "$(<"$PS/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw")/$(<"$PS/class/powercap/intel-rapl-mmio:0/constraint_1_power_limit_uw")"; }
rpm() { cat "$PS/bus/usb/devices/1-3/power/control"; }

P=$(pf pl)
is 'pl mmio line' "$(grep '^pl  *mmio' <<<"$P" | tr -s ' ')" 'pl mmio long_term 15.00 W (27.98 s) short_term 25.00 W (2 ms)'
is 'pl msr line' "$(grep '^pl  *msr' <<<"$P" | tr -s ' ')" 'pl msr long_term 95.00 W (27.98 s) short_term 95.00 W (2 ms)'
is 'pl effective line takes the lower zone and x86_pkg_temp' "$(grep '^pl  *effective' <<<"$P" | tr -s ' ')" 'pl effective PL1 15 W PL2 25 W pkg 52 C'
is 'pl dry run' "$(pf pl 35)" 'would: rapl-mmio PL1/PL2 W 15/25 → 35/25'
is 'pl dry run with a short limit' "$(pf pl 30 40)" 'would: rapl-mmio PL1/PL2 W 15/25 → 30/40'
pf pl 36 >/dev/null 2>&1; is 'pl refuses long > 35 W' "$?" 2
pf pl 30 46 >/dev/null 2>&1; is 'pl refuses short > 45 W' "$?" 2
pf pl x >/dev/null 2>&1; is 'pl refuses a non-number' "$?" 2
is 'pl reads a leading zero as decimal' "$(pf pl 010 2>&1)" 'would: rapl-mmio PL1/PL2 W 15/25 → 10/25'
pf pl 08 >/dev/null 2>&1; is 'pl takes 08 as 8 W' "$?" 0
pf pl 0 >/dev/null 2>&1; is 'pl refuses long < 5 W' "$?" 2
pf pl 10 4 >/dev/null 2>&1; is 'pl refuses short < 5 W' "$?" 2
echo 85000 >"$PS/class/thermal/thermal_zone1/temp"
out=$(pf pl 30 2>&1); rc=$?
is 'pl refuses at 85 C' "$rc" 3
case "$out" in *85*) ok 'pl names the temperature';; *) nok 'pl names the temperature' "$out";; esac
is 'pl may lower at 85 C' "$(pf pl 10 2>&1)" 'would: rapl-mmio PL1/PL2 W 15/25 → 10/25'
echo 52000 >"$PS/class/thermal/thermal_zone1/temp"
[ -e "$WORK/pl.jsonl" ] && nok 'pl dry runs write no ledger entry' 'ledger exists' || ok 'pl dry runs write no ledger entry'
out=$(pf pl 30 40 --apply)
is 'pl apply writes both mmio limits' "$(plv)" 30000000/40000000
case "$(tail -1 <<<"$out")" in 'rollback: pc undo '*) ok 'pl apply prints the rollback line';; *) nok 'pl apply prints the rollback line' "$out";; esac
is 'pl apply is verified' "$(jq -r 'select(.verified!=null).verified' "$WORK/pl.jsonl" | tail -1)" true
is 'pl apply leaves the msr zone' "$(<"$PS/class/powercap/intel-rapl:0/constraint_0_power_limit_uw")" 95000000
pu --last --apply >/dev/null
is 'pc undo restores PL1/PL2' "$(plv)" 15000000/25000000

R=$(pf runtime-pm)
is 'runtime-pm lists only on devices' "$(tr -s ' ' <<<"$R")" \
  "$(printf '%s\n' 'rpm-on pci 0000:00:00.0 Host bridge: Intel' 'rpm-on pci 0000:02:00.0 Network controller: MEDIATEK MT7921' 'rpm-on usb 1-3 Cruzer Blade')"
is 'runtime-pm dry run' "$(pf runtime-pm 1-3 auto)" 'would: runtime-pm usb 1-3 on → auto'
is 'runtime-pm already' "$(pf runtime-pm 1-4 auto)" 'already: runtime-pm usb 1-4 auto'
out=$(pf runtime-pm 1-3 auto --apply)
is 'runtime-pm apply writes auto' "$(rpm)" auto
case "$(tail -1 <<<"$out")" in 'rollback: pc undo '*) ok 'runtime-pm apply prints the rollback line';; *) nok 'runtime-pm apply prints the rollback line' "$out";; esac
is 'runtime-pm apply is verified' "$(jq -r 'select(.verified!=null).verified' "$WORK/pl.jsonl" | tail -1)" true
pu --last --apply >/dev/null
is 'pc undo restores runtime PM' "$(rpm)" on
is 'runtime-pm takes a short pci id' "$(pf runtime-pm 00:00.0 auto)" 'would: runtime-pm pci 0000:00:00.0 on → auto'
out=$(pf runtime-pm 02:00.0 auto 2>&1); rc=$?
is 'runtime-pm refuses the network controller' "$rc" 3
case "$out" in *owner-ok*) ok 'the refusal names --owner-ok';; *) nok 'the refusal names --owner-ok' "$out";; esac
is 'runtime-pm --owner-ok passes the network guard' "$(pf runtime-pm 02:00.0 auto --owner-ok)" 'would: runtime-pm pci 0000:02:00.0 on → auto'
pf runtime-pm 9-9 auto >/dev/null 2>&1; is 'runtime-pm unknown device exits 2' "$?" 2
pf runtime-pm 1-3 off >/dev/null 2>&1; is 'runtime-pm rejects a mode other than auto|on' "$?" 2
is 'the real mmio PL1 is untouched' "$(real_pl)" "$REAL_PL"
is 'the real usb 1-3 runtime PM is untouched' "$(real_rpm)" "$REAL_RPM"

[ $bad = 0 ] && echo 'PASS pc-power' || echo 'FAIL pc-power'
exit $bad
