#!/usr/bin/env bash
# PT02: pc-io against tests/fixtures/io (disks, smart) and tests/fixtures/top (procs, reused
# from pc-top's fixture) — Δ arithmetic, JSON schema, and a live wall-clock budget.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/io"
TOPFIX="$BIN/tests/fixtures/top"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

# 1. disks: Δ over a 1 s window (100 sectors*512=51200B read/write delta -> 10.24 MB/s each).
run_disks() { PC_PROC="$FIX/proc" PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" "$BIN/pc-io" disks --seconds 1 "$@"; }
is 'read MB/s from the diskstats Δ' "$(run_disks --json | jq -r '.nvme0n1.read_mb_s')" 10.24
is 'write MB/s from the diskstats Δ' "$(run_disks --json | jq -r '.nvme0n1.write_mb_s')" 10.24
is 'read IOPS from the diskstats Δ' "$(run_disks --json | jq -r '.nvme0n1.read_iops')" 100.0
is 'await_ms = Δ(rd_ms+wr_ms)/Δios' "$(run_disks --json | jq -r '.nvme0n1.await_ms')" 0.25

# 2. smart: the fixture smartctl (tests/fixtures/io/bin/smartctl) under PC_FIXTURE.
run_smart() { PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK/smart-$RANDOM" "$BIN/pc-io" smart "$@"; }
is 'smart text reports PASSED from the fixture' \
  "$(run_smart | head -1)" "SMART overall-health self-assessment test result: PASSED"
is 'smart --json carries the fixture temperature' "$(run_smart --json | jq -r '.health.temperature')" 35

# 3. procs: reuse pc-top's own fixture (4 fake pids, pid 300 is the IO-heavy one).
is 'procs ranks the IO-heavy pid first' \
  "$(PC_PROC="$TOPFIX/proc" PC_FIXTURE="$TOPFIX" "$BIN/pc-io" procs --seconds 1 --json | jq -r '.[0].pid')" 300

# 4. JSON schema for the default (disks + procs) combined view.
is 'default --json has both disks and procs' \
  "$(PC_PROC="$FIX/proc" PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" "$BIN/pc-io" --seconds 1 --json \
     | jq -e 'has("disks") and has("procs")')" true

# 5. live wall budget for the default combined command (samplers run in parallel, not serial —
# serial would cost ~2x the window). Measured 0.41-0.46 s on a quiet box; the bound below leaves
# headroom for a busy `tests/run.sh` (many suites run concurrently on this machine) without
# masking a regression back to the ~0.9 s+ a serial pair would cost.
t0=$(date +%s.%N)
"$BIN/pc-io" --seconds 0.3 --json >/dev/null
t1=$(date +%s.%N)
wall=$(python3 -c "print($t1-$t0)")
python3 -c "import sys; sys.exit(0 if $wall <= 0.8 else 1)" && ok "live default run stays <= 0.8 s wall ($wall s)" \
  || nok 'live default run stays <= 0.8 s wall' "$wall s"

[ $bad = 0 ] && echo 'PASS pc-io' || echo 'FAIL pc-io'
exit $bad
