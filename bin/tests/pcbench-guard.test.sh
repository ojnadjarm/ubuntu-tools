#!/usr/bin/env bash
# pcbench guard_start: a fleet timer due inside its clearance refuses the run; sub-10-min ticks do not.
# Fixture only: a throwaway HOME and a stub systemctl that answers list-timers in text (systemd 259, no "left") and JSON.
set -uo pipefail
PB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/pcbench"
fail=0
t() { printf '%-52s' "pcbench guard: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }

FH=$(mktemp -d); trap 'rm -rf "$FH"' EXIT
mkdir -p "$FH/stub" "$FH/home/agents"
cat > "$FH/stub/systemctl" <<'EOF'
#!/bin/sh
case "$*" in
  *list-timers*json*) cat "$FX/timers.json" ;;
  *list-timers*) cat "$FX/timers.txt" ;;
esac
EOF
chmod +x "$FH/stub/systemctl"

# timers <name> <due-in s> <period s> ...: writes both list-timers forms for the given timers.
timers() {
  local now; now=$(date +%s); : > "$FH/timers.txt"; local js=""
  while [ $# -ge 3 ]; do
    local nx=$(( now + $2 )) ls=$(( now + $2 - $3 )); [ "$3" = 0 ] && ls=0
    printf '%s %ss %s %s %s.service\n' "$(date -d @$nx '+%a %F %T %Z')" "$2" "-" "-" "$1" >> "$FH/timers.txt"
    js="$js${js:+,}{\"next\":${nx}000000,\"left\":${nx}000000,\"last\":$(( ls * 1000000 )),\"unit\":\"$1\",\"activates\":\"${1%.timer}.service\"}"
    shift 3
  done
  echo "[$js]" > "$FH/timers.json"
}
guard() {
  FX="$FH" HOME="$FH/home" PATH="$FH/stub:/usr/bin:/bin" python3 -I -c '
import importlib.machinery, sys
m = importlib.machinery.SourceFileLoader("pcbench", sys.argv[1]).load_module()
print(m.guard_start(None) or "clear")' "$PB" 2>&1
}
case_() { t "$1"; shift; local want=$1; shift; timers "$@"; local got; got=$(guard)
  case $got in $want) ok;; *) no "got '$got', want '$want'";; esac; }

case_ "daily timer due in 300 s refuses"     "fleet-ci-daily.timer fires in *s (need 600s clearance)" fleet-ci-daily.timer 300 86400
case_ "daily timer due in 900 s is clear"    clear fleet-ci-daily.timer 900 86400
case_ "1-min moodle cron is exempt"          clear moodle52-cron.timer 30 60
case_ "5-min tick exempt, daily refuses" "fleet-ci-daily.timer fires in *" liaison-check.timer 20 300 fleet-ci-daily.timer 500 86400
case_ "sentinel-check due in 30 s refuses"   "sentinel-check.timer fires in *s (need 60s clearance)" sentinel-check.timer 30 900
case_ "sentinel-check due in 120 s is clear" clear sentinel-check.timer 120 900
case_ "never-run timer due in 300 s refuses" "first.timer fires in *" first.timer 300 0
case_ "pcbench timer is ignored"             clear pcbench-weekly.timer 30 604800

t "inactive timer (next 0) is ignored"
echo '[{"next":0,"left":0,"last":0,"unit":"off.timer","activates":"off.service"}]' > "$FH/timers.json"; : > "$FH/timers.txt"
got=$(guard); [ "$got" = clear ] && ok || no "got '$got'"

[ $fail = 0 ] && echo "pcbench-guard.test.sh: all green" || echo "pcbench-guard.test.sh: FAILURES"
exit $fail
