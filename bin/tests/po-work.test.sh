#!/usr/bin/env bash
# T1626 detached PO workers: po-work start/run/reap/list with po-run and po-ask --from worker, po-new --refresh.
# Fixture-only (FLEET §5.6): bwrap --unshare-net, HARNESS_HOME in a temp dir, fake systemd-run (a detached setsid child
# that runs ExecStopPost after), fake agent-exec (a worker that runs up to 60 s, ends early on $WORK/release), fake
# agent-run (a manager that starts work with po-work and writes outbox replies). No real unit, Discord or LLM.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${PO_SANDBOXED:-}" ]; then
  REAL_HOME=$(readlink -f "${HARNESS_HOME:-$HOME/agents}")
  exec bwrap --dev-bind / / --ro-bind "$REAL_HOME" "$REAL_HOME" --unshare-net --setenv PO_SANDBOXED 1 \
    --setenv REAL_HOME "$REAL_HOME" -- bash "$SELF"
fi
. "$BIN/tests/lib/assert.sh"

WORK=$(mktemp -d)
trap 'touch "$WORK/release"; pkill -f "$WORK/stubs" 2>/dev/null; sleep 0.2; rm -rf "$WORK"' EXIT
export HARNESS_ENV_LOADED=1 HARNESS_HOME="$WORK/agents" AGENT_WORK="$WORK/agent-work" HARNESS_CONFIG=/dev/null PO_PAPERS="$WORK/agent-work/po"
mkdir -p "$HARNESS_HOME" "$AGENT_WORK/decisions" "$AGENT_WORK/briefs" "$WORK/stubs"
cp -r "$BIN/../po-template" "$HARNESS_HOME/po-template"
: >"$HARNESS_HOME/AGENT-PREAMBLE.md"

# Fake systemd-run: run the command detached (own session), then its ExecStopPost 0.5 s later (systemd kills the
# whole unit cgroup first; the pause lets stray children such as the stub's `sleep` end), like a transient unit.
cat >"$WORK/stubs/systemd-run" <<'STUB'
#!/usr/bin/env bash
post=''
while [ $# -gt 0 ]; do
  case "$1" in --property=ExecStopPost=*) post=${1#--property=ExecStopPost=} ;; --unit=*) echo "${1#--unit=}" >>"$WORK/units.log" ;;
    --*) ;; *) break ;; esac; shift
done
[ -e "$WORK/launch.fail" ] && exit 1
setsid bash -c '"$@"; sleep 0.5; '"$post" _ "$@" </dev/null >>"$WORK/unit.out" 2>&1 &
STUB
# Fake agent-exec: a worker of up to 60 s; $WORK/release ends it early, $WORK/crash makes it exit 1.
cat >"$WORK/stubs/agent-exec" <<'STUB'
#!/usr/bin/env bash
echo "$$ $*" >>"$WORK/exec.log"
for _ in $(seq 600); do [ -e "$WORK/release" ] && break; sleep 0.1; done
[ -e "$WORK/crash" ] && { echo "boom" >&2; exit 1; }
echo "1. did the work for $(grep -o 'ticket T[0-9]*' "$2")"
STUB
# Fake manager run: per request, `work: <key>` starts a worker (reply = plan, already running or queued); a worker
# report becomes one result reply; anything else gets an answer. Replies go to outbox/discord like the real brief.
cat >"$WORK/stubs/agent-run" <<'STUB'
#!/usr/bin/env bash
d="$HARNESS_HOME/$1"; p=${1#po-}; o="$d/outbox/discord"; mkdir -p "$o" "$PO_PAPERS/$p/done"
for f in "$d"/current/*.md; do
  [ -e "$f" ] || continue
  th=$(sed -n 's/^thread: //p' "$f"); key=$(sed -n 's/^work: //p' "$f")
  if grep -qx 'from: worker' "$f"; then text="result: $(grep -m1 '^po-work: worker' "$f")"
  elif [ -n "$key" ]; then
    n=$(( $(cat "$WORK/ticket" 2>/dev/null || echo 100) + 1 )); echo "$n" >"$WORK/ticket"
    echo "goal $key" >"$AGENT_WORK/briefs/T$n-$p-$key.md"
    msg=$(po-work "$p" start "T$n" --brief "$AGENT_WORK/briefs/T$n-$p-$key.md" --channel discord --thread "$th" --asked-by fx); rc=$?
    case $rc in 0) text="plan: T$n $key" ;; 3) text="already running: $msg" ;; 4) text="queued: $msg" ;; *) text="start failed $rc" ;; esac
  else text="answer: $(tail -1 "$f")"; fi
  r="$(date -u +%Y%m%dT%H%M%S%N)-$th"; printf 'thread: %s\n%s\n' "$th" "$text" >"$o/.$r.tmp"; mv "$o/.$r.tmp" "$o/$r.md"
  echo "$(date +%s.%N) $text" >>"$WORK/replies.log"
  echo "outcome: answered" >>"$f"; mv "$f" "$PO_PAPERS/$p/done/"
done
: >"$d/REPORT.md"
STUB
printf '#!/bin/sh\nexit 0\n' >"$WORK/stubs/plan-usage"
chmod +x "$WORK"/stubs/*
export PATH="$WORK/stubs:$BIN:$PATH" WORK

# selftest
if curl -sS -m 3 -o /dev/null https://ntfy.sh 2>/dev/null; then echo 'FAIL selftest: sandbox reaches the network'; exit 1; fi
ok 'selftest: no route to ntfy.sh'
for c in systemd-run agent-exec agent-run plan-usage; do is "selftest: $c is the fake" "$(command -v $c)" "$WORK/stubs/$c"; done
case "$HARNESS_HOME" in "$WORK"/*) ok 'selftest: HARNESS_HOME is the fixture';; *) nok 'selftest: HARNESS_HOME' "$HARNESS_HOME";; esac

po-new rt "Router" >/dev/null && po-new mg "Mg Game" --parent rt >/dev/null || nok 'fixture: po-new' 'failed'
M="$HARNESS_HOME/po-mg"
touch "$AGENT_WORK/decisions/mg.md"
ask() { po-ask mg --from liaison --channel discord --thread "$1" --copy "$2" >/dev/null; }
replies() { grep -c "$1" "$WORK/replies.log" 2>/dev/null; }
status() { jq -r .status "$M/state/work/$1.json"; }

# (a) a request that starts a 60-s worker: the manager answers and frees its lock in < 5 s, the worker keeps running
ask 11 $'please build the map\nwork: map'
t0=$(date +%s.%N); po-run mg >/dev/null 2>&1; rc=$?; t1=$(date +%s.%N)
secs=$(echo "$t1 - $t0" | bc)
is '(a) po-run exit 0' "$rc" 0
ev "(a) manager run ended in < 5 s while the worker runs ($secs s)" '[ "$(echo "$secs < 5" | bc)" = 1 ]'
is '(a) plan reply written' "$(replies 'plan: T101 map')" 1
ev '(a) lock free after the run' 'flock -n "$M/.po-run.lock" true'
timeout 10 wait-for --every 0.05 --until "[ \"\$(jq -r .status '$M/state/work/T101.json')\" = running ]" >/dev/null 2>&1
is '(a) worker T101 running, detached' "$(status T101)" running
case "$(po-work mg list)" in "T101  running  map  started "*"asked by fx  thread 11  opus") ok '(a) po-work list shows the open work';;
  *) nok '(a) po-work list' "$(po-work mg list)";; esac
case "$(po-status mg)" in *"workers 1"*) ok '(a) po-status counts the worker';; *) nok '(a) po-status' "$(po-status mg)";; esac

# (b) a second request during the worker is answered before the worker ends
ask 12 "how is it going?"
po-run mg >/dev/null 2>&1
is '(b) second request answered' "$(replies 'answer: how is it going?')" 1
is '(b) the worker is still running' "$(status T101)" running

# (e) the same work asked twice never starts twice: through the manager, and two racing starts
ask 13 $'map again please\nwork: map'
po-run mg >/dev/null 2>&1
is '(e) a second ask for running work starts nothing' "$(replies 'already running: po-work: already running: T101 (map)')" 1
is '(e) one unit launched so far' "$(wc -l <"$WORK/units.log")" 1
echo b >"$AGENT_WORK/briefs/T201-mg-art.md"; echo b >"$AGENT_WORK/briefs/T202-mg-art.md"
po-work mg start T201 --brief "$AGENT_WORK/briefs/T201-mg-art.md" >"$WORK/s1" 2>&1 & S1=$!
po-work mg start T202 --brief "$AGENT_WORK/briefs/T202-mg-art.md" >"$WORK/s2" 2>&1; r2=$?; wait "$S1"; r1=$?
is '(e) two racing starts of key art: one 0, one 3' "$(printf '%s\n' "$r1" "$r2" | sort | paste -sd' ')" '0 3'

# (f, step 7) no cap: 3 workers run at once and a 4th request is answered in < 5 s
ask 14 $'and the sound\nwork: sound'; po-run mg >/dev/null 2>&1
timeout 10 wait-for --every 0.05 --until "[ \$(po-work mg list | grep -c ' running ') = 3 ]" >/dev/null 2>&1
is '(f) 3 detached workers running at once (T101 map, art, T104 sound)' "$(po-work mg list | grep -c ' running ')" 3
ask 17 "anything new?"
t0=$(date +%s.%N); po-run mg >/dev/null 2>&1; secs=$(echo "$(date +%s.%N) - $t0" | bc)
is '(f) the 4th request is answered' "$(replies 'answer: anything new?')" 1
ev "(f) answered in < 5 s with 3 workers running ($secs s)" '[ "$(echo "$secs < 5" | bc)" = 1 ]'

# (c) the worker's result reaches the inbox once and is relayed once
: >"$WORK/stop-unused"; touch "$WORK/release"
timeout 15 wait-for --every 0.1 --until "[ \$(grep -ls '^po-work: worker' '$M'/inbox/*.md | wc -l) -ge 3 ]" >/dev/null 2>&1
f=$(grep -l '^po-work: worker T101' "$M"/inbox/*.md 2>/dev/null)
is '(c) one from: worker request for T101' "$(printf '%s' "$f" | grep -c .)" 1
ev '(c) it names the thread, the outcome and the report' 'grep -qx "from: worker" $f && grep -qx "thread: 11" $f && grep -q "^po-work: worker T101 (map) done after" $f && grep -qx "1. did the work for ticket T101" $f'
po-run mg >/dev/null 2>&1; po-work mg reap; po-run mg >/dev/null 2>&1
is '(c) T101 result relayed once' "$(replies 'result: po-work: worker T101 (map) done')" 1
is '(c) reap and later runs file nothing again' "$(grep -l '^po-work: worker T101' "$M"/inbox/*.md "$PO_PAPERS"/mg/done/*.md 2>/dev/null | wc -l)" 1
is '(c) no open work left' "$(po-work mg list | wc -l)" 0
rm -f "$WORK/release"

# (d) a crashed worker is reported, and a runner killed hard is reaped as lost; neither is lost silently
touch "$WORK/crash"; echo c >"$AGENT_WORK/briefs/T301-mg-crash.md"
po-work mg start T301 --brief "$AGENT_WORK/briefs/T301-mg-crash.md" --thread 15 >/dev/null; touch "$WORK/release"
timeout 15 wait-for --every 0.1 --until "grep -qs '^po-work: worker T301' '$M'/inbox/*.md" >/dev/null 2>&1
ev '(d) a crashed worker files "failed (exit 1)"' 'grep -qs "^po-work: worker T301 (crash) failed (exit 1)" "$M"/inbox/*.md'
rm -f "$WORK/crash" "$WORK/release"
echo k >"$AGENT_WORK/briefs/T302-mg-killed.md"
po-work mg start T302 --brief "$AGENT_WORK/briefs/T302-mg-killed.md" --thread 16 >/dev/null
timeout 10 wait-for --every 0.05 --until "grep -q T302 '$WORK/exec.log'" >/dev/null 2>&1   # the worker itself runs
pkill -9 -f "^bash [^ ]*po-work mg run T302|[s]tubs/agent-exec"
timeout 15 wait-for --every 0.1 --until "grep -qs '^po-work: worker T302' '$M'/inbox/*.md" >/dev/null 2>&1
ev '(d) a killed runner is reaped as lost by ExecStopPost' 'grep -qs "^po-work: worker T302 (killed) lost" "$M"/inbox/*.md'
po-work mg reap
is '(d) each failure filed once' "$(grep -ls '^po-work: worker T30[12]' "$M"/inbox/*.md | wc -l)" 2
touch "$WORK/launch.fail"; echo l >"$AGENT_WORK/briefs/T303-mg-launch.md"
po-work mg start T303 --brief "$AGENT_WORK/briefs/T303-mg-launch.md" >/dev/null 2>&1; is '(d) a failed launch exits 1' "$?" 1
rm -f "$WORK/launch.fail"
is '(d) a failed launch is not left open' "$(status T303)" failed
po-work mg start T9 --brief /nope >/dev/null 2>&1; is 'start: missing brief exits 2' "$?" 2
po-work mg start 9 --brief "$AGENT_WORK/briefs/T303-mg-launch.md" >/dev/null 2>&1; is 'start: bad ticket exits 2' "$?" 2
po-ask mg --from worker "x" >/dev/null; is 'po-ask: --from worker accepted' "$?" 0

# (g, step 8) delegate, never work: the generated prompts carry the rule; a "build X" request gives a brief and a
# detached worker, and the manager run ends while the work runs (the fake manager stands in for the LLM)
for b in "$M/BRIEF.md" "$HARNESS_HOME/po-rt/BRIEF.md"; do
  ev "(g) $(basename "$(dirname "$b")") prompt carries the delegate rule" 'grep -q "^## Delegate, never work" "$b" && grep -q "You never do the work yourself: no code" "$b" && grep -q "a task of a few lines and under a minute or" "$b"'
done
n=$(wc -l <"$WORK/units.log")
ask 18 $'build X please\nwork: build-x'
t0=$(date +%s.%N); po-run mg >/dev/null 2>&1; secs=$(echo "$(date +%s.%N) - $t0" | bc)
ev '(g) "build X": a brief was written' 'ls "$AGENT_WORK"/briefs/T*-mg-build-x.md >/dev/null 2>&1'
is '(g) "build X": one detached worker unit launched' "$(( $(wc -l <"$WORK/units.log") - n ))" 1
ev "(g) \"build X\": the manager run ended in < 5 s, the worker still running ($secs s)" '[ "$(echo "$secs < 5" | bc)" = 1 ] && po-work mg list | grep -q " running  build-x "'
touch "$WORK/release"; timeout 15 wait-for --every 0.1 --until "! po-work mg list | grep -q build-x" >/dev/null 2>&1; rm -f "$WORK/release"

# po-new --refresh: a manager brief made from an older template gets the current head, keeps name and project block
sed -i 's/^## Project$/## Project\nproject block kept/' "$M/BRIEF.md"; sed -i '/{{PROJECT}}/d' "$M/BRIEF.md"
sed -i 's/po-work/OLD-WORDS/g' "$M/BRIEF.md"
out=$(po-new mg --refresh); is 'refresh: exit 0' "$?" 0
ev 'refresh: head from the template, name, parent and project block kept' 'grep -q "po-work mg start" "$M/BRIEF.md" && ! grep -q OLD-WORDS "$M/BRIEF.md" && grep -q "the manager of Mg Game only" "$M/BRIEF.md" && grep -q "goes to po-rt" "$M/BRIEF.md" && grep -qx "project block kept" "$M/BRIEF.md" && ! grep -q "{{" "$M/BRIEF.md"'
is 'refresh: one "## Project" heading' "$(grep -cx '## Project' "$M/BRIEF.md")" 1
ev 'refresh: a PO without PARENT gets the PO template' 'po-new rt --refresh >/dev/null && grep -q "the product owner of Router only" "$HARNESS_HOME/po-rt/BRIEF.md" && grep -q "po-work rt start" "$HARNESS_HOME/po-rt/BRIEF.md"'
printf 'You are po-rt, the Discord router.\n' >"$HARNESS_HOME/po-rt/BRIEF.md"
po-new rt --refresh >/dev/null 2>&1; is 'refresh: a hand-written brief (router) exits 2' "$?" 2
is 'refresh: the hand-written brief is untouched' "$(cat "$HARNESS_HOME/po-rt/BRIEF.md")" 'You are po-rt, the Discord router.'

# (T1632) the image key reaches a worker only when its brief carries the requester's grant
mkdir -p "$WORK/argstub"; printf '#!/bin/sh\necho "$*" >>"$WORK/args.log"\n' >"$WORK/argstub/systemd-run"; chmod +x "$WORK/argstub/systemd-run"
echo 'draw him' >"$AGENT_WORK/briefs/T401-mg-nogrant.md"
printf 'AI image grant: "hazme una imagen con IA"\n' >"$AGENT_WORK/briefs/T402-mg-grant.md"
PATH="$WORK/argstub:$PATH" po-work mg start T401 --brief "$AGENT_WORK/briefs/T401-mg-nogrant.md" >/dev/null 2>&1
PATH="$WORK/argstub:$PATH" po-work mg start T402 --brief "$AGENT_WORK/briefs/T402-mg-grant.md" >/dev/null 2>&1
ev '(T1632) a brief without a grant: the worker unit gets no key' 'grep "po-work-mg-T401" "$WORK/args.log" | grep -q -- "--setenv=OPENROUTER_KEY_FILE=/dev/null"'
ev '(T1632) a brief with a grant: the key file is left as is' 'grep -q "po-work-mg-T402" "$WORK/args.log" && ! grep "po-work-mg-T402" "$WORK/args.log" | grep -q OPENROUTER_KEY_FILE'

# (T1634) a granted brief gets a vault lease on the image key, passed to the unit by name (never in its arguments)
mkdir -p "$HARNESS_HOME/bin"; printf '#!/bin/sh\necho "$*" >>"%s/grant.log"\necho LEASE-FX\n' "$WORK" >"$HARNESS_HOME/bin/secret"
chmod +x "$HARNESS_HOME/bin/secret"
printf 'AI image grant: "hazme una imagen con IA"\n' >"$AGENT_WORK/briefs/T403-mg-lease.md"
PATH="$WORK/argstub:$PATH" po-work mg start T403 --brief "$AGENT_WORK/briefs/T403-mg-lease.md" >/dev/null 2>&1
echo 'draw him again' >"$AGENT_WORK/briefs/T404-mg-nolease.md"
PATH="$WORK/argstub:$PATH" po-work mg start T404 --brief "$AGENT_WORK/briefs/T404-mg-nolease.md" >/dev/null 2>&1
ev '(T1634) a grant: the vault is asked for a lease on openrouter with the ticket and the quote' \
   'grep -q -- "^grant openrouter --ticket T403 --ttl [0-9]* --asked hazme una imagen con IA$" "$WORK/grant.log"'
ev '(T1634) a grant: the unit inherits FLEET_LEASE_OPENROUTER; the lease is not in its arguments' \
   'grep "po-work-mg-T403" "$WORK/args.log" | grep -q -- "--setenv=FLEET_LEASE_OPENROUTER " && ! grep -q LEASE-FX "$WORK/args.log"'
ev '(T1634) no grant: no lease asked' '[ "$(grep -c . "$WORK/grant.log")" = 1 ] && grep "po-work-mg-T404" "$WORK/args.log" | grep -qv FLEET_LEASE'

touch "$REAL_HOME/.po-test-probe" 2>/dev/null; is 'selftest: the real agents tree is read-only in the sandbox' "$?" 1
exit $bad
