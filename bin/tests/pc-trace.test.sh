#!/usr/bin/env bash
# live-sudo: the bpftrace live checks use the real sudo -n
# PT04: pc trace — every verb against the recorded fixture (no root, no window, no sound),
# then the live checks from the ticket when sudo -n is available.
set -uo pipefail
PC="${PC_TRACE_BIN:-$HOME/agents/bin/pc-trace}"
. "$HOME/agents/bin/tests/lib/budget.sh"
FIX="$HOME/agents/bin/tests/fixtures/trace"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
yes() { [ "$2" = true ] && ok "$1" || nok "$1" "jq said $2"; }
t()   { PC_FIXTURE="$FIX" "$PC" "$@"; }

# The live checks run only where sudo -n and the kernel are actually available. The 11 s hung
# probe starts first, so its fixed deadline overlaps every other window instead of following them.
LIVE=0
[ "${PC_TRACE_LIVE:-1}" = 1 ] && timeout 5 sudo -n true 2>/dev/null && command -v bpftrace >/dev/null && LIVE=1
if [ $LIVE = 1 ]; then
  # A program that never exits is still reaped, and leaves nothing behind. It runs in its own
  # session, so the leak check sees only this probe, never another agent's trace.
  # shellcheck disable=SC2016
  { t0=$EPOCHSECONDS
    setsid -w bash -c 'echo $$ >"$1"; shift; exec "$@"' _ "$WORK/sid" \
      env PC_TRACE_HANG=1 "$PC" raw 'interval:s:60{}' --seconds 1 >/dev/null 2>&1
    echo $((EPOCHSECONDS - t0)) >"$WORK/hang_el"; } &
  hang=$!
fi

# 1. usage and option handling — no probe is attached for any of these.
t -h | head -1 | grep -q '^usage: pc trace' && ok 'the -h usage' || nok 'the -h usage' 'no usage line'
t wakeups --nope >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
t nosuchverb >/dev/null 2>&1;     is 'unknown verb exits 2'   "$?" 2
t wakeups --by wrong >/dev/null 2>&1; is '--by rejects a bad grouping' "$?" 2
t wakeups --seconds 0 >/dev/null 2>&1; is '--seconds 0 exits 2' "$?" 2
t syscalls >/dev/null 2>&1; is 'syscalls without a pid exits 2' "$?" 2
head -2 "$PC" | tail -1 | grep -q '^# pc trace .* — ' \
  && ok 'line 2 is the pc help signature' || nok 'line 2 is the pc help signature' 'no signature'

# 2. wakeups — one capture per option set feeds every assertion that reads it.
jc=$(t wakeups --seconds 1 --json)
jp=$(t wakeups --seconds 2 -n 500 --by pid --json)
yes 'wakeups --json is a ranked array of {comm, per_s}' \
  "$(jq -e 'length>0 and (.[0]|(has("comm") and has("per_s")))' <<<"$jc" 2>/dev/null)"
yes 'wakeups is sorted by count, descending' "$(jq '[.[].count] | . == (sort | reverse)' <<<"$jc")"
is 'wakeups honours -n' "$(t wakeups --seconds 1 -n 3 --json | jq length)" 3
is 'per_s divides the count by the window' \
  "$(jq '.[0].count / 2 * 100 | floor / 100' <<<"$jp")" "$(jq '.[0].per_s' <<<"$jp")"
is '--by comm collapses the pids' "$(jq '.[0].pid' <<<"$jc")" null
yes '--by pid keeps them'  "$(jq '.[0].pid | type == "number"' <<<"$jp")"
yes '--by unit groups by cgroup' \
  "$(t wakeups --seconds 1 --by unit --json | jq '[.[].unit] | any(startswith("system.slice/fixture-"))')"
declare -A cap=([wakeups]="$jp")
cap[opens]=$(t opens --seconds 1 -n 500 --by pid --json)
cap[sleep]=$(t sleep --seconds 1 -n 500 --by pid --json)
for v in wakeups opens sleep; do
  jq -e . <<<"${cap[$v]}" >/dev/null 2>&1 \
    && ok "$v --json is valid JSON" || nok "$v --json is valid JSON" 'jq -e . failed'
  is "$v keeps a comm with a comma and its pid" \
    "$(jq -c '[.[] | select(.comm == "mp4,m4") | .pid]' <<<"${cap[$v]}" 2>/dev/null)" '[977]'
done
t wakeups --seconds 1 -n 2 | tail -1 | grep -qE '^window 1s · [0-9]+ events shown · [0-9]+ probes attached in [0-9]+ ms' \
  && ok 'the text footer carries window, events and attach cost' || nok 'the text footer' 'no footer line'

# 3. the other bpftrace verbs.
jd=$(t disk --seconds 1 --json)
yes 'disk sums bytes per comm and rwbs' \
  "$(jq <<<"$jd" -e '.[0] | (has("comm") and has("rw") and has("bytes") and has("ops")) and .bytes >= 1048576')"
yes 'disk is sorted by bytes' "$(jq <<<"$jd" '[.[].bytes] | . == (sort | reverse)')"
yes 'syscalls names the numbers and totals the latency' \
  "$(t syscalls 1234 --seconds 1 --json | jq -e 'length>0 and (.[0]|(has("syscall") and has("count") and has("total_ms") and has("avg_us"))) and (.[0].syscall|test("^[a-z]"))')"
yes 'opens keeps comm, pid and filename' \
  "$(jq <<<"${cap[opens]}" -e '.[0] | (has("comm") and has("pid") and has("file")) and (.file|startswith("/"))')"
yes 'execs lists the binaries that were exec'"'"'d' \
  "$(t execs --seconds 1 --json | jq -e '.[0] | (has("comm") and has("file") and has("count"))')"
yes 'sleep reports the call and its smallest timeout' \
  "$(jq <<<"${cap[sleep]}" -e 'length>0 and (.[0]|(has("comm") and has("pid") and has("call") and has("count") and has("min_ms"))) and any(.[]; .call=="epoll_pwait")')"

# 4. the tool-backed verbs.
yes 'offcpu ranks folded stacks by microseconds' \
  "$(t offcpu 1234 --seconds 2 --json | jq -e '.[0] | (has("us") and has("ms") and has("stack")) and (.stack|contains(";"))')"
t offcpu 1234 --seconds 2 | tail -1 | grep -q 'stripped' \
  && ok 'offcpu says so when the frames are [unknown]' || nok 'offcpu stripped note' 'no note'
yes 'cpu ranks perf symbols' \
  "$(t cpu 1234 --seconds 2 --json | jq -e '.[0] | (has("percent") and has("comm") and has("dso") and has("symbol"))')"
yes 'sched ranks run-queue latency' \
  "$(t sched --seconds 2 --json | jq -e '.[0] | (has("task") and has("count") and has("runtime_ms") and has("avg_delay_ms") and has("max_delay_ms"))')"

# 5. live: the ticket's success check, every window at once, each driven by one shared loop.
if [ $LIVE = 1 ]; then
  # This box's docker and netdata churn fills the default top 15, so a 1 s sample often ranked
  # none of these comms and the row failed at random. The window is 3 s wide over the whole
  # ranked list (-n 60), where the kernel's own workers always land, and is taken again once
  # before the row is called a failure.
  wakeups_hit() {
    "$PC" wakeups --seconds 3 -n 60 --json \
      | jq -e 'any(.[]; .comm | test("^(swapper/|gnome-shell|bash|kworker)"))' 2>/dev/null
  }
  wakeups_hit >"$WORK/wake" & wp=$!
  "$PC" syscalls $$ --seconds 3 --json >"$WORK/sys.json" 2>/dev/null & sp=$!
  "$PC" execs --seconds 3 -n 200 --json >"$WORK/execs.json" 2>/dev/null & ep=$!
  "$PC" disk --seconds 4 -n 100 --json >"$WORK/disk.json" 2>/dev/null & dp=$!
  # Each action repeats until its trace exits, so a slow attach under load still sees it.
  # $HOME, not /tmp: /tmp is tmpfs here and never reaches the block layer (KB/quirks).
  while kill -0 $sp 2>/dev/null || kill -0 $ep 2>/dev/null || kill -0 $dp 2>/dev/null; do
    kill -0 $sp 2>/dev/null && for i in $(seq 1 40); do [ -e /etc/hostname ]; done
    kill -0 $ep 2>/dev/null && /bin/true
    kill -0 $dp 2>/dev/null && dd if=/dev/zero of="$HOME/.pc-trace-test.bin" bs=1M count=4 oflag=direct status=none
    sleep 0.2
  done
  wait $sp $ep $dp; rm -f "$HOME/.pc-trace-test.bin"
  wait $wp; hit=$(<"$WORK/wake"); [ "$hit" = true ] || hit=$(wakeups_hit)
  yes 'live: wakeups sees the idle task or the shell' "$hit"
  yes 'live: syscalls counts this shell'"'"'s 40 stat calls' \
    "$(jq -e 'any(.[]; .syscall == "newfstatat" and .count >= 20)' "$WORK/sys.json" 2>/dev/null)"
  yes 'live: execs sees a spawned /bin/true' \
    "$(jq -e 'any(.[]; .file == "/bin/true")' "$WORK/execs.json" 2>/dev/null)"
  yes 'live: disk sees the 4 MB direct write' \
    "$(jq -e '[.[] | select(.comm == "dd") | .bytes] | add >= 4194304' "$WORK/disk.json" 2>/dev/null)"

  wait $hang; el=$(<"$WORK/hang_el"); sid=$(<"$WORK/sid")
  # The 11 s hard deadline is fixed; only the 1 s of start-up around it scales with load.
  lim=$(awk -v b="$(budget 1)" 'BEGIN{print 11 + b}')
  awk -v e="$el" -v l="$lim" 'BEGIN{exit !(e <= l)}' \
    && ok "a hung probe is reaped in ${el}s (≤ $lim)" || nok 'a hung probe is reaped' "${el}s > $lim"
  # TERM at the deadline, KILL two seconds later: give the probe that grace before looking.
  for _ in $(seq 1 40); do pgrep -s "$sid" -x bpftrace >/dev/null || break; sleep 0.1; done
  pgrep -s "$sid" -x bpftrace >/dev/null; is 'no bpftrace is left behind' "$?" 1
else
  echo 'skip live checks (no sudo -n or no bpftrace)'
fi

[ $bad = 0 ] && echo 'PASS pc-trace' || echo 'FAIL pc-trace'
exit $bad
