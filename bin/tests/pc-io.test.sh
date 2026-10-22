#!/usr/bin/env bash
# PT02: pc-io against tests/fixtures/io (disks, smart) and tests/fixtures/top (procs, reused
# from pc-top's fixture) — Δ arithmetic, JSON schema, and a live wall-clock budget.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/io"
TOPFIX="$BIN/tests/fixtures/top"
. "$BIN/tests/lib/budget.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

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
b=$(budget 0.8)
python3 -c "import sys; sys.exit(0 if $wall <= $b else 1)" && ok "live default run stays <= $b s wall budget ($wall s)" \
  || nok "live default run stays <= $b s wall budget" "$wall s"

# 6. units: a fixture cgroup tree (two io.stat ticks per unit) + diskstats + a stub docker on PATH.
UF="$WORK/units"; CG="$UF/sys/fs/cgroup"; ID=$(printf 'ab%.0s' {1..32}); U=$(id -u)
iost() { mkdir -p "$1"; printf '259:0 rbytes=%s wbytes=%s rios=1 wios=1 dbytes=0 dios=0\n7:0 rbytes=9000000 wbytes=9000000 rios=1 wios=1 dbytes=0 dios=0\n' "$2" "$3" >"$1/io.stat.$4"; }
unit() { iost "$CG/$1" "$2" "$3" 0; iost "$CG/$1" "$4" "$5" 1; }
unit system.slice/netdata.service 0 1000000 0 3000000
unit "system.slice/docker-$ID.scope" 0 0 2000000 6000000
unit system.slice/idle.service 5 5 5 5
unit init.scope 0 0 1000000 0
# Real layout (T1067): io.stat on user.slice only; user-UID.slice and below have none (io not delegated).
unit user.slice 0 0 0 4000000
UT="user.slice/user-$U.slice/user@$U.service/app.slice/sub.slice/tool.service"; mkdir -p "$CG/$UT"
mkdir -p "$UF/proc" "$UF/bin"
for t in 0 1; do s=$((t * 40000)); printf '259 0 nvme0n1 1 0 %s 0 1 0 %s 0 0 0 0\n259 1 nvme0n1p1 1 0 %s 0 1 0 %s 0 0 0 0\n259 2 nvme0n10 1 0 5 0 1 0 5 0 0 0 0\n7 0 loop0 1 0 99999 0 1 0 99999 0 0 0 0\n' \
  "$s" "$s" "$s" "$s" >"$UF/proc/diskstats.$t"; done
printf '#!/bin/sh\nprintf "%s\\tmoodle53-db-1\\n"\n' "$ID" >"$UF/bin/docker"; chmod +x "$UF/bin/docker"
run_units() { PATH="$UF/bin:$PATH" PC_FIXTURE="$UF" "$BIN/pc-io" units --seconds 1 "$@"; }
uj=$(run_units --json)
is 'units: netdata write MB/s from the io.stat Δ (loop rows ignored)' "$(jq -r '.units[] | select(.unit=="netdata.service") | .write_mb_s' <<<"$uj")" 2.0
is 'units: docker scope shown by container name' "$(jq -r '.units[0].unit' <<<"$uj")" moodle53-db-1
is 'units: docker read MB/s' "$(jq -r '.units[0].read_mb_s' <<<"$uj")" 2.0
is 'units: undelegated user.slice is one aggregate row' "$(jq -r '.units[] | select(.unit=="user.slice") | "\(.write_mb_s) \(.aggregate)"' <<<"$uj")" '4.0 true'
is 'units: undelegated slices listed' "$(jq -c .undelegated <<<"$uj")" '["user.slice"]'
is 'units: init.scope walked' "$(jq -r '.units[] | select(.unit=="init.scope") | .read_mb_s' <<<"$uj")" 1.0
D="$WORK/deleg"; cp -r "$UF" "$D"; p=$D/sys/fs/cgroup/user.slice
for s_ in "user-$U.slice" "user@$U.service" app.slice sub.slice; do p=$p/$s_; iost "$p" 0 0 0; iost "$p" 0 0 1; done
iost "$D/sys/fs/cgroup/$UT" 0 0 0; iost "$D/sys/fs/cgroup/$UT" 0 1000000 1
dj=$(PATH="$UF/bin:$PATH" PC_FIXTURE="$D" "$BIN/pc-io" units --seconds 1 --json)
is 'units: delegated io walks to user@UID units, user: prefix' "$(jq -r '.units[] | select(.unit=="user:tool.service") | .write_mb_s' <<<"$dj")" 1.0
is 'units: delegated io leaves no aggregate' "$(jq -c '[.undelegated, [.units[] | select(.aggregate)]]' <<<"$dj")" '[[],[]]'
is 'units: zero-Δ unit dropped' "$(jq -r '[.units[].unit] | index("idle.service")' <<<"$uj")" null
is 'units: diskstats total skips partitions and loop, keeps nvme0n10' "$(jq -r '[.disks[], .total_write_mb_s] | join(" ")' <<<"$uj")" 'nvme0n1 nvme0n10 20.48'
is 'units: share of the disk total' "$(jq -r '.units[0].share_pct' <<<"$uj")" 19.5
is 'units: -n caps the rows' "$(run_units -n 2 --json | jq '.units | length')" 2
ut=$(run_units)
ev 'units: text row names the unit' 'grep -qE "^netdata\.service +0\.0 +2\.0 +4\.9%$" <<<"$ut"'
ev 'units: text footer names the undelegated slice' 'grep -qx "io not delegated below user.slice: one aggregate row each" <<<"$ut"'
PC_FIXTURE="$WORK/none" "$BIN/pc-io" units --seconds 1 --json >"$WORK/crash.out" 2>&1; rc=$?
is 'units: a sampler crash exits 1, not 0' "$rc" 1

# 7. procs: an unreadable <pid>/io (root-owned on a live box) prints ? and a footer, not 0K.
if [ "$(id -u)" != 0 ]; then
  cp -r "$TOPFIX" "$WORK/top"; chmod 000 "$WORK/top/proc/100/io".* "$WORK/top/proc/400/io".*
  sed -i 's/^400 (idleapp) S 1 /400 (idleapp) S 2 /' "$WORK/top/proc/400/stat".*
  pt=$(PC_FIXTURE="$WORK/top" "$BIN/pc-io" procs --seconds 1)
  ev 'procs: unreadable io row is not ranked' '! grep -qE "^ +(100|400) " <<<"$pt"'
  ev 'procs: footer counts unreadable pids, not kernel threads' 'grep -qx "1 processes of root/other users hide their IO (not ranked): pc io units" <<<"$pt"'
  chmod 000 "$WORK/top/proc/300/io".* "$WORK/top/proc/200/io".*
  ev 'procs: all ranked rows unreadable says so' 'PC_FIXTURE="$WORK/top" "$BIN/pc-io" procs --seconds 1 | grep -qx "no readable process did IO in the window"'
  chmod 644 "$WORK/top/proc/300/io".* "$WORK/top/proc/200/io".*
  ev 'procs: wide view keeps cpu/rss/pss' 'head -1 <<<"$pt" | grep -q "cpu%.*rss.*pss.*io_r/s"'
  is 'procs --json flags io_ok false' "$(PC_FIXTURE="$WORK/top" "$BIN/pc-io" procs --seconds 1 --json | jq -r '.[] | select(.pid==100) | .io_ok')" false
  chmod 644 "$WORK/top/proc/100/io".*
fi

# 8. smart --record/--trend (T1071): a fixture smartctl with the NVMe counters, a log in $WORK.
SF="$WORK/smartfx"; mkdir -p "$SF/bin"
printf '#!/bin/sh\n[ -n "$SMART_EMPTY" ] && { echo "{}"; exit 0; }\necho %s\n' \
  "'{\"smart_status\":{\"passed\":true},\"nvme_smart_health_information_log\":{\"temperature\":35,\"percentage_used\":6,\"data_units_written\":39392420,\"data_units_read\":45397677,\"unsafe_shutdowns\":93,\"media_errors\":0}}'" \
  >"$SF/bin/smartctl"; chmod +x "$SF/bin/smartctl"
LOG="$WORK/smart.tsv"
rec() { PC_FIXTURE="$SF" PC_SMART_LOG="$LOG" XDG_RUNTIME_DIR="$WORK/smart-$RANDOM" "$BIN/pc-io" smart --record "$@"; }
PC_SMART_DATE=2026-10-20 rec >/dev/null
is 'record: header + row, TB from 512000-byte data units' "$(sed -n 2p "$LOG")" "$(printf '2026-10-20\t20.169\t23.244\t6\t93\t0\t35')"
is 'record: same day again is a no-op' "$(PC_SMART_DATE=2026-10-20 rec)" "nothing: 2026-10-20 already in $LOG"
PC_SMART_DATE=2026-10-21 rec >/dev/null
is 'record: a new day appends one row' "$(wc -l <"$LOG")" 3
SMART_EMPTY=1 PC_SMART_DATE=2026-10-22 rec >/dev/null 2>&1; rc=$?
is 'record: no SMART data exits 1, no row' "$rc $(wc -l <"$LOG")" '1 3'
TL="$WORK/trend.tsv"
printf 'date\twritten_tb\tread_tb\tpercent_used\tunsafe_shutdowns\tmedia_errors\ttemp_c\n2026-09-21\t10.000\t1\t5\t90\t0\t35\n2026-10-14\t11.000\t1\t6\t92\t0\t35\n2026-10-21\t11.700\t1\t6\t93\t0\t35\n' >"$TL"
tr_=$(PC_SMART_LOG="$TL" "$BIN/pc-io" smart --trend)
ev 'trend: 7 d rate from the row 7 d back' 'grep -qx "written 7 d: 100.0 GB/day (over 7 d)" <<<"$tr_"'
ev 'trend: 30 d rate from the row 30 d back' 'grep -qx "written 30 d: 56.7 GB/day (over 30 d)" <<<"$tr_"'
ev 'trend: unsafe-shutdown delta' 'grep -qx "unsafe_shutdowns: +3 over 30 d" <<<"$tr_"'
ev 'trend: one row is not a trend' 'PC_SMART_LOG="$LOG" PC_SMART_DATE=x "$BIN/pc-io" smart --trend | grep -q "^smart trend: 2 rows" && head -2 "$TL" >"$WORK/one.tsv" && PC_SMART_LOG="$WORK/one.tsv" "$BIN/pc-io" smart --trend | grep -q "^trend: need 2 rows"'

# 9. sample/history (T1133): hourly io.stat wbytes deltas per cgroup, gone/reset counters, root remainder.
IF="$WORK/iohist"; ICG="$IF/sys/fs/cgroup"; T0=1761040800; G=1000000000
mkdir -p "$IF/proc" "$IF/bin"; printf '259 0 nvme0n1 1 0 0 0 1 0 0 0 0 0 0 0\n' >"$IF/proc/diskstats"
printf '%s\tmoodle53-db-1\t2026-10-21\n' "${ID:0:12}" >"$IF/names.tsv"
printf '#!/bin/sh\nexit 0\n' >"$IF/bin/docker"; chmod +x "$IF/bin/docker"
w_() { mkdir -p "$ICG/$1"; printf '259:0 rbytes=0 wbytes=%s rios=0 wios=0 dbytes=0 dios=0\n' "$2" >"$ICG/$1/io.stat"; }
smp() { PATH="$IF/bin:$PATH" PC_FIXTURE="$IF" PC_IO_STATE="$IF/state.tsv" PC_IO_LOG="$IF/io-history.tsv" \
  PC_IO_NAMES="$IF/names.tsv" PC_IO_NOW=$1 "$BIN/pc-io" sample; }
w_ . $((20 * G)); w_ system.slice $((12 * G)); w_ system.slice/netdata.service $((2 * G))
w_ "system.slice/docker-$ID.scope" $((4 * G)); w_ system.slice/old.service $((5 * G))
w_ system.slice/restart.service $((1 * G)); w_ user.slice $((3 * G))
ev 'sample: first run is a baseline, no rows' 'smp $T0 | grep -q "^baseline" && ! test -s "$IF/io-history.tsv"'
rm -r "$ICG/system.slice/old.service"
w_ . $((305 * G / 10)); w_ system.slice $((185 * G / 10)); w_ system.slice/netdata.service $((3 * G))
w_ "system.slice/docker-$ID.scope" $((75 * G / 10)); w_ system.slice/restart.service $((G / 2))
w_ system.slice/small.service 1000000; w_ user.slice $((6 * G))
smp $((T0 + 3600)) >/dev/null
row() { awk -F'\t' -v u="$1" '$3 == u { print $5 }' "$IF/io-history.tsv"; }
is 'sample: delta of a surviving cgroup' "$(row netdata.service)" $G
is 'sample: docker scope named from docker-names.tsv' "$(row moodle53-db-1)" $((35 * G / 10))
is 'sample: counter reset counts the new counter, never negative' "$(row restart.service)" $((G / 2))
is 'sample: gone child writes stay with its parent' "$(row 'system.slice (gone)')" 1499000000
is 'sample: root remainder (kernel, fs)' "$(row 'root (kernel/fs)')" $G
is 'sample: < 50 MB/h rows fold into (small)' "$(row '(small)') $(row small.service)" '1000000 '
is 'sample: undelegated user.slice is one row' "$(row user.slice)" $((3 * G))
is 'sample: rows carry the interval seconds' "$(awk -F'\t' 'NR == 2 { print $2 }' "$IF/io-history.tsv")" 3600
ev 'sample: no negative delta anywhere' '! awk -F"\t" "NR > 1 && \$5 < 0" "$IF/io-history.tsv" | grep -q .'
n_=$(wc -l <"$IF/io-history.tsv"); smp $((T0 + 3600)) >/dev/null
is 'sample: same timestamp again adds nothing' "$(wc -l <"$IF/io-history.tsv")" "$n_"
his() { TZ=UTC PC_IO_LOG="$IF/io-history.tsv" PC_IO_NOW=$((T0 + 3600)) "$BIN/pc-io" history "$@"; }
h_=$(his --since 6h)
ev 'history: hourly row MM-DD HH:00  unit  GB/h' 'grep -qx "10-21 10:00  moodle53-db-1  3.500" <<<"$h_"'
ev 'history: hour rows ranked by GB/h' 'grep -E "^10-21 10:00 " <<<"$h_" | head -1 | grep -q moodle53-db-1'
ev 'history: daily top names the top writer' 'sed -n "/^daily top 10/,\$p" <<<"$h_" | sed -n 2p | grep -qx "10-21  moodle53-db-1  3.500"'
ev 'history: daily total and unattributed share' 'grep -qx "10-21  total 10.500 GB  unattributed 23.8%" <<<"$h_"'
ev 'history: --since excludes older rows' 'TZ=UTC PC_IO_LOG="$IF/io-history.tsv" PC_IO_NOW=$((T0 + 90000)) "$BIN/pc-io" history --since 6h | grep -q "^nothing:"'
ev 'history: no log says nothing' 'PC_IO_LOG="$WORK/none.tsv" "$BIN/pc-io" history | grep -q "^nothing: no io samples"'

[ $bad = 0 ] && echo 'PASS pc-io' || echo 'FAIL pc-io'
exit $bad
