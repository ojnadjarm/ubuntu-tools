#!/usr/bin/env bash
# PT03: pc thermal against tests/fixtures/thermal — zones and trip points, the hwmon roll-up
# from the recorded `sensors -j`, the read-only fan, the throttle section. Nothing is written.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/thermal"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
fx() { PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-thermal" "$@"; }

J=$(fx --json)
is 'all four sections' "$(jq -r 'keys|join(",")' <<<"$J")" 'fan,hwmon,throttle,zones'

# 1. zones: every thermal_zone with a readable temp, in °C, with its trip points.
is 'zone count'         "$(jq '.zones|length' <<<"$J")" 13
is 'zones carry a type' "$(jq '[.zones[]|select(.type=="x86_pkg_temp")]|length' <<<"$J")" 1
is 'temps are numbers'  "$(jq -r '[.zones[].c|type]|unique|join(",")' <<<"$J")" number
is 'millidegrees become °C' \
  "$(jq '[.zones[]|select(.c>100)]|length' <<<"$J")" 0
is 'trip points are parsed' \
  "$(jq -r '[.zones[]|select(.type=="acpitz")|.trips[0].type]|join("")' <<<"$J")" critical
is 'trip temps are numbers' \
  "$(jq -r '[.zones[]|select(.type=="acpitz")|.trips[0].c|type]|join("")' <<<"$J")" number

# 2. hwmon: one row per chip from the recorded sensors -j, hottest sensor per chip.
is 'hwmon chip count' "$(jq '.hwmon|length' <<<"$J")" 6
is 'coretemp is the package max' \
  "$(jq -r '[.hwmon[]|select(.chip|startswith("coretemp"))|.c]|join("")' <<<"$J")" \
  "$(jq -r '[."coretemp-isa-0000"|..|objects|to_entries[]|select(.key|test("^temp[0-9]+_input$"))|.value]|max|(.*10|round)/10' "$FIX/bin/sensors.json")"
is 'the fan chip reports rpm' \
  "$(jq -r '[.hwmon[]|select(.chip|startswith("asus"))|.fan_rpm]|join("")' <<<"$J")" 2300

# 3. fan: read-only, pwm1_enable reported as a value and never written.
is 'fan rpm'          "$(jq .fan.rpm <<<"$J")" 2300
is 'fan label'        "$(jq -r .fan.label <<<"$J")" cpu_fan
is 'pwm1_enable read' "$(jq .fan.pwm1_enable <<<"$J")" 2
is 'pwm1 is not writable' "$(jq .fan.pwm1_writable <<<"$J")" false
fx fan | grep -q rpm && ok 'text fan line carries rpm' || nok 'text fan line carries rpm' "$(fx fan)"
grep -q 'pwm1_enable' <<<"$(fx fan)" && ok 'text fan line names pwm1_enable' || nok 'text fan line names pwm1_enable' 'missing'

# 4. throttle: the i915 reasons plus the package temperature against PL1.
is 'known i915 reasons' "$(jq '.throttle.gpu_reasons_known|length' <<<"$J")" 8
is 'active reasons are a subset' \
  "$(jq '[.throttle.gpu_reasons[]|IN(.; $ARGS.positional[])]|all' --args $(jq -r '.throttle.gpu_reasons_known[]' <<<"$J") <<<"$J")" true
is 'PL1 in watts'  "$(jq .throttle.pl1_w <<<"$J")" 95
is 'pkg temp'      "$(jq -r '.throttle.pkg_c|type' <<<"$J")" number
is 'throttled flag' "$(jq -r '.throttle.throttled|type' <<<"$J")" boolean

# 4b. per-CPU throttle counters, deltas since the last record, --record into a scratch thermal.tsv.
S="$WORK/fx"; cp -a "$FIX" "$S"; mkdir -p "$S/proc"; echo '0.91 0.80 0.70 1/100 1' >"$S/proc/loadavg"
cnt() { mkdir -p "$S/sys/devices/system/cpu/cpu$1/thermal_throttle"
        echo "$2" >"$S/sys/devices/system/cpu/cpu$1/thermal_throttle/package_throttle_count"
        echo "$3" >"$S/sys/devices/system/cpu/cpu$1/thermal_throttle/core_throttle_count"; }
cg() { mkdir -p "$S/sys/fs/cgroup/$1"; printf 'usage_usec %s\nuser_usec 0\n' "$2" >"$S/sys/fs/cgroup/$1/cpu.stat"; }
LOG="$WORK/thermal.tsv"
tx() { PC_FIXTURE="$S" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/l.jsonl" PC_THERMAL_LOG="$LOG" "$BIN/pc-thermal" "$@"; }
fx throttle | grep -q '^package_throttle n/a$' && ok 'missing counters read n/a' || nok 'missing counters read n/a' "$(fx throttle)"
is 'missing counters are null in json' "$(fx throttle --json | jq -c '[.package_throttle,.core_throttle]')" '[null,null]'
cnt 0 100 10; cnt 1 200 20
cg system.slice/a.service 1000000; cg user.slice/user@$UID.service/app.slice/b.service 5000000; cg user.slice/user@$UID.service 6000000
is 'counters sum over CPUs' "$(tx throttle --json | jq -c '[.package_throttle,.core_throttle]')" '[300,30]'
tx throttle | grep -q '^package_throttle 300 (no record yet)$' && ok 'no record yet' || nok 'no record yet' "$(tx throttle)"
tx throttle --record >/dev/null
is 'record writes header + one row' "$(wc -l <"$LOG")" 2
is 'record header' "$(head -1 "$LOG")" "$(printf 'ts\tpkg\tcore\tmax_temp\tload1\ttop_unit_by_cpu\treasons')"
is 'record row: counts, load1, first top n/a' "$(tail -1 "$LOG" | cut -f2,3,5,6)" "$(printf '300\t30\t0.91\tn/a')"
is 'record max_temp is a number' "$(tail -1 "$LOG" | cut -f4 | grep -cE '^[0-9]+\.[0-9]$')" 1
ts0=$(tail -1 "$LOG" | cut -f1)
sed -i "2s/^$ts0/$((ts0 - 7200))/" "$LOG"
cnt 0 1100 10; cg system.slice/a.service 1500000; cg user.slice/user@$UID.service/app.slice/b.service 9000000; cg user.slice/user@$UID.service 16000000
tx throttle | grep -q '^package_throttle 1300 (+500/h since record ' && ok 'per-hour delta since the last record' \
  || nok 'per-hour delta since the last record' "$(tx throttle)"
is 'json per-hour delta' "$(tx throttle --json | jq -c '[.package_throttle_per_h,.core_throttle_per_h]')" '[500,0]'
tx throttle --record >/dev/null
is 'top unit is the leaf with the largest cpu delta' "$(tail -1 "$LOG" | cut -f6)" 'b.service:4s'
D=0123456789ab$(printf 'f%.0s' {1..52}); cg system.slice/docker-$D.scope 90000000
printf '0123456789ab\tvass-web-1\t2026-10-21T10:00:00\n' >"$WORK/names.tsv"
PC_MEM_NAMES="$WORK/names.tsv" tx throttle --record >/dev/null
is 'docker scope named from docker-names.tsv' "$(tail -1 "$LOG" | cut -f6)" 'docker:vass-web-1:90s'
cnt 0 5 1; cnt 1 5 1
tx throttle | grep -q '^package_throttle 10 (+10 since boot' && ok 'counter reset counts from boot' || nok 'counter reset counts from boot' "$(tx throttle)"
is '--seconds window delta' "$(tx throttle --seconds 1 --json | jq -c '[.package_throttle_window,.window_s]')" '[0,1]'
[ -e "$WORK/l.jsonl" ] && nok 'record writes no ledger entry' 'ledger exists' || ok 'record writes no ledger entry'

# 4c. --reasons: perf-limit (0x64F) and package therm status (0x1B1) bits named from a recorded MSR table.
fx throttle --reasons | grep -q '^reasons n/a' && ok 'no MSR table reads n/a' || nok 'no MSR table reads n/a' "$(fx throttle --reasons)"
printf '%s\n' '# sample cpu 0x64f 0x1b1 0x1a2' '0 0 0x1d030800 0x881b0c0a 0x08640000' '0 1 0x00000000 0x881b0c0a 0x08640000' \
  '1 0 0x1d030c00 0x881b0c08 0x08640000' '1 1 0x00000800 0x881b0c08 0x08640000' >"$S/msr.tsv"
is 'reasons line names every set bit' "$(tx throttle --reasons)" \
  'reasons core.prochot 0/4 log 1/2, core.thermal 0/4 log 1/2, core.other_edp 0/4 log 1/2, core.pl1 1/4 log 1/2, core.pl2 3/4 log 1/2, core.max_turbo 0/4 log 1/2, pkg.prochot 0/2 log 1/1, pkg.power_limit 2/2 log 1/1 (2 cpus x 2 samples; tjmax 100 C, tcc offset 8 C, pkg 27 C below)'
R=$(tx throttle --reasons --json)
is 'json active reasons' "$(jq -c .active <<<"$R")" '["core.pl1","core.pl2","pkg.power_limit"]'
is 'json tjmax, offset, below' "$(jq -c '[.tjmax_c,.tcc_offset_c,.pkg_below_tjmax_c]' <<<"$R")" '[100,8,27]'
is 'json lists all 17 known bits' "$(jq '.reasons|length' <<<"$R")" 17
tx throttle --record >/dev/null
is 'record reasons column' "$(tail -1 "$LOG" | cut -f7)" 'core.pl1,core.pl2,pkg.power_limit'
printf '%s\n' '0 0 0x0 0x0 0x08640000' >"$S/msr.tsv"
tx throttle --reasons | grep -q '^reasons none (1 cpus x 1 samples' && ok 'clear bits read none' || nok 'clear bits read none' "$(tx throttle --reasons)"
sed -i '1s/\treasons$//' "$LOG"; tx throttle --record >/dev/null
is 'old header gains the reasons column' "$(head -1 "$LOG" | cut -f7)" reasons
tx throttle --reasons --window x >/dev/null 2>&1; is 'bad --window exits 2' "$?" 2

# 5. verbs, watch, and the CLI contract.
is 'zones verb alone'  "$(fx zones --json | jq -r 'type')" array
is 'watch prints one line per second' "$(fx watch --seconds 2 | wc -l)" 2
is 'watch --json is one object per line' "$(fx watch --seconds 2 --json | jq -sc '[.[].t]|join(",")')" '"0,1"'
fx nosuchverb >/dev/null 2>&1; is 'unknown verb exits 2' "$?" 2
fx --nosuchflag >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
fx -h >/dev/null 2>&1; is '-h exits 0' "$?" 0
grep -q '^  pc thermal ' <<<"$("$BIN/pc" help)" && ok 'pc help lists pc thermal' || nok 'pc help lists pc thermal' 'missing'
[ -e "$WORK/l.jsonl" ] && nok 'pc thermal writes no ledger entry' 'ledger exists' \
                       || ok 'pc thermal writes no ledger entry'

[ $bad = 0 ] && echo 'PASS pc-thermal' || echo 'FAIL pc-thermal'
exit $bad
