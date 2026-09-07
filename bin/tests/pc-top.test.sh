#!/usr/bin/env bash
# PT02: pc_top.py against tests/fixtures/top — ranking, wake/s arithmetic, unit names, JSON
# schema, and a live wall-clock budget. No machine state is read or written by the fixture part.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/top"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

run() { PC_PROC="$FIX/proc" PC_SYS="$FIX/sys" PC_FIXTURE=1 python3 "$BIN/pc_top.py" --seconds 1 "$@"; }

# 1. ranking: highest CPU% first by default.
is 'default sort ranks pid 100 first (highest cpu%)' "$(run --json | jq -r '.[0].pid')" 100
is 'sort=wake ranks pid 200 first' "$(run --sort wake --json | jq -r '.[0].pid')" 200
is 'sort=io ranks pid 300 first' "$(run --sort io --json | jq -r '.[0].pid')" 300

# 2. wake/s arithmetic: pid 200 goes 0->500 ctxt switches over a 1 s window.
is 'wake/s is the ctxt-switch delta over the window' "$(run --sort wake --json | jq -r '.[0].wake')" 500.0

# 3. cpu% arithmetic: pid 100 goes 1200->1215 ticks (CLK_TCK from sysconf) over 1 s.
hz=$(python3 -c 'import os; print(os.sysconf("SC_CLK_TCK"))')
want=$(python3 -c "print(round(15/$hz*100,2))")
is 'cpu% matches Δticks/CLK_TCK/window*100' "$(run --json | jq -r '.[0].cpu')" "$want"

# 4. unit names: dark-eye.service / session.scope / no unit ("-").
is 'unit from the last cgroup path element (.service)' "$(run --unit dark-eye --json | jq -r 'map(.unit)|unique|.[0]')" dark-eye.service
is 'a pid with no service/scope cgroup gets "-"' "$(run --json | jq -r 'map(select(.pid==400))[0].unit')" -

# 5. --unit filters by substring.
is '--unit dark-eye keeps only the body pids' "$(run --unit dark-eye --json | jq -r '[.[].pid]|sort|join(",")')" "100,300"

# 6. JSON schema.
is 'every row has pid,cpu,wake,rss,unit' "$(run --json | jq -e 'all(.[]; has("pid","cpu","wake","rss","unit"))')" true

# 7. live wall budget: a real 0.3 s window stays close to 0.6 s wall (measured 0.37-0.44 s on a
# quiet box; the bound below leaves headroom for a busy `tests/run.sh`, many suites concurrently).
t0=$(date +%s.%N)
PC_PROC=/proc PC_SYS=/sys python3 "$BIN/pc_top.py" --seconds 0.3 --json >/dev/null
t1=$(date +%s.%N)
wall=$(python3 -c "print($t1-$t0)")
python3 -c "import sys; sys.exit(0 if $wall <= 0.8 else 1)" && ok "live run stays <= 0.8 s wall ($wall s)" \
  || nok 'live run stays <= 0.8 s wall' "$wall s"

[ $bad = 0 ] && echo 'PASS pc-top' || echo 'FAIL pc-top'
exit $bad
