#!/usr/bin/env bash
# PT03: pc thermal against tests/fixtures/thermal — zones and trip points, the hwmon roll-up
# from the recorded `sensors -j`, the read-only fan, the throttle section. Nothing is written.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/thermal"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
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
