#!/usr/bin/env bash
# Fixtures for ~/agents/bin/sentinel-waits, run inside a bwrap PID namespace: real agents are invisible, so unkillable.
set -uo pipefail
SW="$HOME/agents/bin/sentinel-waits"
WF="$HOME/agents/bin/wait-for"
if [ -z "${IN_SANDBOX:-}" ]; then
  # owner() with /proc stubbed: a workflow agent's transcript sits under subagents/workflows/wf_*/.
  python3 - "$SW" <<'PY' || exit 1
import importlib.machinery, os, sys, tempfile
d = tempfile.mkdtemp(); os.environ["CLAUDE_PROJECTS_DIR"] = d
m = importlib.machinery.SourceFileLoader("sw", sys.argv[1]).load_module()
tx = os.path.join(d, "-proj", "S1", "subagents", "workflows", "wf_x", "agent-wfdone000000.jsonl")
os.makedirs(os.path.dirname(tx))
open(tx, "w").write('{"type":"assistant","message":{"content":[{"type":"tool_use","name":"SubagentHandback"}]}}\n{"id":"twf"}\n')
os.utime(tx, (0, 0))
m.tool_shell = lambda procs, pid: 2
m.environ = lambda pid, key: "S1"
os.readlink = lambda p: "/tmp/claude/-proj/S1/tasks/twf.output"
got = m.owner({1: {"comm": "claude"}, 2: {"ppid": 1}}, 3)
print(("PASS" if got == (True, "agent wfdone") else "FAIL") + f" workflow agent transcript is the owner (got {got})")
sys.exit(got != (True, "agent wfdone"))
PY
  # owner() (T988): a remembered task is not grepped again, and a transcript older than the shell is never grepped.
  python3 - "$SW" <<'PY' || exit 1
import importlib.machinery, os, sys, tempfile
d = tempfile.mkdtemp(); os.environ["CLAUDE_PROJECTS_DIR"] = d
m = importlib.machinery.SourceFileLoader("sw7", sys.argv[1]).load_module()
sub = os.path.join(d, "-proj", "S1", "subagents"); os.makedirs(sub)
old, new = os.path.join(sub, "agent-old000000000.jsonl"), os.path.join(sub, "agent-new000000000.jsonl")
for f in (old, new):
    open(f, "w").write('{"id":"tmem"}\n')
os.utime(old, (0, 0))
m.tool_shell = lambda procs, pid: 2
m.environ = lambda pid, key: "S1"
os.readlink = lambda p: "/tmp/claude/-proj/S1/tasks/tmem.output"
procs = {1: {"comm": "claude"}, 2: {"ppid": 1, "start": "0", "age": 5}}
argv, real = [], m.subprocess.run
m.subprocess.run = lambda a, **k: argv.extend(a) or real(a, **k)
first = m.owner(procs, 3)
m.subprocess.run = lambda *a, **k: (_ for _ in ()).throw(AssertionError("grep ran"))
m.OWNERS = dict(m.OWNERS_NOW)
second = m.owner(procs, 3)
good = first == second == (False, "agent new000") and m.OWNERS_NOW == {"tmem": new} and old not in argv and new in argv
print(("PASS" if good else "FAIL") + f" memo: old transcript skipped, second call not grepped (got {first} {second})")
sys.exit(not good)
PY
  # owner() with /proc stubbed: a loop forked inside a live tool shell (same snapshot cmdline) belongs to that session.
  python3 - "$SW" <<'PY' || exit 1
import importlib.machinery, sys
m = importlib.machinery.SourceFileLoader("sw5", sys.argv[1]).load_module()
m.environ = lambda pid, key: ""
ts = "bash -c source /h/.claude/shell-snapshots/snapshot-bash-1.sh && eval 'until x; do sleep 1; done | cat'"
procs = {1: {"comm": "claude", "ppid": 0, "cmd": "claude"}, 2: {"comm": "bash", "ppid": 1, "cmd": ts},
         3: {"comm": "bash", "ppid": 2, "cmd": ts}, 4: {"comm": "sleep", "ppid": 3, "cmd": "sleep 1"}}
got = m.owner(procs, 3)
print(("PASS" if got == (False, "session 1") else "FAIL") + f" forked subshell of a live tool shell is not 'session gone' (got {got})")
sys.exit(got != (False, "session 1"))
PY
  # transcript_ended(): a workflow agent whose last line is the StructuredOutput tool_result has handed back.
  python3 - "$SW" <<'PY' || exit 1
import importlib.machinery, os, sys, tempfile, time
m = importlib.machinery.SourceFileLoader("sw4", sys.argv[1]).load_module()
tx = os.path.join(tempfile.mkdtemp(), "agent-so.jsonl")
open(tx, "w").write('{"type":"assistant","message":{"content":[{"type":"tool_use","name":"StructuredOutput"}]}}\n'
  '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t1","type":"tool_result","content":"Structured output provided successfully"}]},"toolEndsTurn":true}\n')
os.utime(tx, (time.time() - 300, time.time() - 300))
got = m.transcript_ended(tx)
print(("PASS" if got else "FAIL") + f" StructuredOutput tool_result as last line counts as handed back (got {got})")
sys.exit(not got)
PY
  # owner() with /proc stubbed: a subagent whose turn ended (end_turn) while its background wait-for runs is waiting on it, not
  # ended (T408: two T407 waits killed at 02:34 and 02:49); an unregistered loop keeps the end_turn rule; 3 h idle still ends.
  python3 - "$SW" <<'PY' || exit 1
import importlib.machinery, os, sys, tempfile, time
d = tempfile.mkdtemp(); os.environ["CLAUDE_PROJECTS_DIR"] = d
m = importlib.machinery.SourceFileLoader("sw6", sys.argv[1]).load_module()
tx = os.path.join(d, "-proj", "S1", "subagents", "agent-await0000000.jsonl")
os.makedirs(os.path.dirname(tx))
open(tx, "w").write('{"type":"user","message":{"content":[{"type":"tool_result","content":"Command running in background with ID: tw1."}]}}\n'
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Waiting."}],"stop_reason":"end_turn"}}\n')
m.tool_shell = lambda procs, pid: 2
m.environ = lambda pid, key: "S1"
os.readlink = lambda p: "/tmp/claude/-proj/S1/tasks/tw1.output"
procs = {1: {"comm": "claude"}, 2: {"ppid": 1}}
bad = 0
for idle, waiting, want in ((180, True, False), (180, False, True), (2400, True, False), (11000, True, True)):
    os.utime(tx, (time.time() - idle, time.time() - idle))
    got = m.owner(procs, 3, waiting=waiting)
    good = got == (want, "agent await0")
    bad += not good
    print(("PASS" if good else "FAIL") + f" end_turn, idle {idle} s, {'registered wait' if waiting else 'unregistered loop'}: ended={want} (got {got})")
sys.exit(bad)
PY
  # transcript_ended(): the SubagentHandback tool *schema* in api-request-shape/attachment records is not a handback (T438:
  # T429's wait killed at 750 s, 08:22:49); the real assistant tool_use still is.
  python3 - "$SW" <<'PY' || exit 1
import importlib.machinery, os, sys, tempfile, time
m = importlib.machinery.SourceFileLoader("sw7", sys.argv[1]).load_module()
tx = os.path.join(tempfile.mkdtemp(), "agent-schema.jsonl")
schema = ('{"type":"api-request-shape","shape":{"tools":[{"name":"SubagentHandback","input_schema":{}}]}}\n'
  '{"type":"attachment","attachment":{"type":"deferred_tools_record","entries":[{"name":"SubagentHandback"}]}}\n'
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Waiting."}],"stop_reason":"end_turn"}}\n')
real = '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t9","name":"SubagentHandback","input":{}}]}}\n'
bad = 0
for body, want, what in ((schema, False, "tool schema only"), (schema + real, True, "real SubagentHandback tool_use")):
    open(tx, "w").write(body)
    os.utime(tx, (time.time() - 750, time.time() - 750))
    got = m.transcript_ended(tx, waiting=True)
    bad += got != want
    print(("PASS" if got == want else "FAIL") + f" registered wait, idle 750 s, {what}: ended={want} (got {got})")
sys.exit(bad)
PY
  # reap() with kill stubbed: a multi-line loop logs as one line, stamped like `date -Is`.
  python3 - "$SW" <<'PY' || exit 1
import importlib.machinery, os, re, sys, tempfile
m = importlib.machinery.SourceFileLoader("sw2", sys.argv[1]).load_module()
m.DRY, m.ST = False, tempfile.mkdtemp()
m.os.kill = lambda p, s: None
m._state = lambda p: "Z"
m.audit = lambda pid, why: None
m.reap({9: {"comm": "bash", "ppid": 1, "cmd": "until x;\n  do\n\tsleep 1\ndone"}}, 9, "why")
lines = open(os.path.join(m.ST, "sentinel.log")).read().splitlines()
good = len(lines) == 1 and re.match(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d stuck-wait killed pid 9 \(why\): until x; do sleep 1 done$", lines[0])
print(("PASS" if good else "FAIL") + f" stuck-wait log is one line with a date -Is stamp (got {lines})")
sys.exit(not good)
PY
  # audit() into a temp HARNESS_HOME: the kill row is filed under agent "sentinel".
  python3 - "$SW" <<'PY' || exit 1
import importlib.machinery, json, os, sys, tempfile
os.environ["HARNESS_HOME"] = tempfile.mkdtemp()
m = importlib.machinery.SourceFileLoader("sw3", sys.argv[1]).load_module()
m.audit(9, "why")
rows = [json.loads(l) for l in open(os.path.join(os.environ["HARNESS_HOME"], "log", "actions.jsonl"))]
good = len(rows) == 1 and rows[0]["agent"] == "sentinel"
print(("PASS" if good else "FAIL") + f" audit row is filed under agent sentinel (got {[r['agent'] for r in rows]})")
sys.exit(not good)
PY
  exec bwrap --dev-bind / / --unshare-pid --proc /proc --die-with-parent \
    env IN_SANDBOX=1 OUTSIDE_CLAUDE="$(pgrep -x claude | tr '\n' ' ')" bash "$0"
fi

. "$HOME/agents/bin/tests/lib/assert.sh"
isalive() { [ -n "$1" ] && [ -e "/proc/$1" ] && [ "$(awk '{print $3}' "/proc/$1/stat")" != Z ] && echo alive || echo dead; }

# Selftest: no process from outside the sandbox is visible, so none can be signalled.
seen=0
for p in $OUTSIDE_CLAUDE; do [ -e "/proc/$p" ] && grep -q '^claude$' "/proc/$p/comm" 2>/dev/null && seen=1; done
eq "selftest: host claude processes invisible" 0 "$seen"
eq "selftest: no claude in the sandbox yet" 0 "$(grep -lx claude /proc/[0-9]*/comm 2>/dev/null | wc -l)"

WORK=$(mktemp -d)
export WAIT_FOR_DIR="$WORK/waits" CLAUDE_PROJECTS_DIR="$WORK/projects" SENTINEL_STATE_DIR="$WORK/state" \
  HARNESS_HOME="$WORK/h" WAITS_MIN_AGE=2 WAITS_STALL=60 WAITS_TX_SLACK=3600  # transcripts are backdated before the shells start
S=11111111-2222-3333-4444-555555555555
TASKS="$WORK/tmp/-proj/$S/tasks"; SUB="$CLAUDE_PROJECTS_DIR/-proj/$S/subagents"
mkdir -p "$TASKS" "$SUB" "$WORK/bin" "$WORK/.claude/shell-snapshots"
cp /bin/bash "$WORK/bin/claude"
SNAP="$WORK/.claude/shell-snapshots/snapshot-bash-1.sh"; : >"$SNAP"

# Owners: agent "adone" handed back 10 min ago; agent "alive" wrote its transcript just now.
tx() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"%s"}]}}\n{"id":"%s"}\n' "$2" "$3" >>"$SUB/agent-$1.jsonl"; }
tx adone0000000 SubagentHandback tdead; tx adone0000000 SubagentHandback treg1; touch -d '-10 min' "$SUB/agent-adone0000000.jsonl"
tx alive0000000 Bash tlive; tx alive0000000 Bash tseen; tx alive0000000 Bash treg2
# Workflow agent "wfdone": transcript under subagents/workflows/wf_x/, handed back 10 min ago.
WFTX="$SUB/workflows/wf_x/agent-wfdone000000.jsonl"; mkdir -p "${WFTX%/*}"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"SubagentHandback"}]}}\n{"id":"twf"}\n' >"$WFTX"
touch -d '-10 min' "$WFTX"

# toolshell <task> <script>: what Claude Code's Bash tool starts in the background (run by a fake `claude`).
toolshell() { echo "CLAUDE_CODE_SESSION_ID=$S bash -c \"source $SNAP 2>/dev/null || true && eval '$2'\" >$TASKS/$1.output 2>&1 &"; }

STALE="$WORK/r-dia.log"; : >"$STALE"; touch -d '-1 hour' "$STALE"
HELD="$WORK/held.log"; : >"$HELD"
bash -c 'exec 3>>"$1"; sleep 300' _ "$HELD" & writer=$!
sleep 0.2; touch -d '-1 hour' "$HELD"
sleep 300 & livejob=$!
sleep 300 & deadjob=$!; kill "$deadjob"; wait "$deadjob" 2>/dev/null

cat >"$WORK/session1.sh" <<EOF
$(toolshell tdead "until grep -q DONE $STALE; do sleep 1; done")
echo \$! >$WORK/pid.dead
$(toolshell tlive "until grep -q DONE $HELD; do sleep 1; done")
echo \$! >$WORK/pid.live
$(toolshell tseen "until grep -q DONE $STALE; do sleep 1; done; echo seen")
echo \$! >$WORK/pid.seen
$(toolshell twf "until grep -q DONE $HELD; do sleep 1; done")
echo \$! >$WORK/pid.wf
$(toolshell treg1 "$WF --label reg1 --pid $livejob --every 1")
$(toolshell treg2 "$WF --label reg2 --pid $livejob --every 1")
sleep 300
EOF
cat >"$WORK/session2.sh" <<EOF
$(toolshell torph "until [ -e $WORK/never ]; do ps -p $deadjob >/dev/null; sleep 1; done")
echo \$! >$WORK/pid.orph
$(toolshell tbusy "until [ -e $WORK/never ]; do for i in \\\$(seq 300000); do :; done; sleep 0.05; done")
echo \$! >$WORK/pid.busy
EOF
"$WORK/bin/claude" "$WORK/session1.sh" & sess1=$!
"$WORK/bin/claude" "$WORK/session2.sh"   # exits at once: its shells are orphaned, like a finished headless run
sleep 3
reg1=$(jq -r 'select(.label=="reg1").pid' "$WAIT_FOR_DIR"/*.json); reg2=$(jq -r 'select(.label=="reg2").pid' "$WAIT_FOR_DIR"/*.json)

"$SW" --dry-run >"$WORK/dry.txt"
eq "dry run: kills nothing" alive "$(isalive "$(cat "$WORK/pid.dead")")"
eq "dry run: lists 4 would-kills" 4 "$(grep -c 'would kill' "$WORK/dry.txt")"

"$SW"
LOG="$SENTINEL_STATE_DIR/sentinel.log"
eq "dead job + finished agent: loop killed"        dead  "$(isalive "$(cat "$WORK/pid.dead")")"
eq "  logged with its reason" 1 "$(grep -c "killed pid $(cat "$WORK/pid.dead") (polls r-dia.log unchanged 60 min, no writer; owner ended; owner agent adone0" "$LOG")"
eq "orphaned session, dead pid: loop killed"       dead  "$(isalive "$(cat "$WORK/pid.orph")")"
eq "  logged with its reason" 1 "$(grep -c "killed pid $(cat "$WORK/pid.orph") (waits on dead pid $deadjob; owner ended; owner session gone" "$LOG")"
eq "workflow agent finished: loop killed"         dead  "$(isalive "$(cat "$WORK/pid.wf")")"
eq "  logged with its owner" 1 "$(grep -c "killed pid $(cat "$WORK/pid.wf") .*owner agent wfdone" "$LOG")"
eq "live job holding its file: loop kept"          alive "$(isalive "$(cat "$WORK/pid.live")")"
eq "stuck loop of a running agent: kept"           alive "$(isalive "$(cat "$WORK/pid.seen")")"
eq "  logged once as seen" 1 "$(grep -c "seen pid $(cat "$WORK/pid.seen") .*owner agent alive0 still running" "$LOG")"
eq "busy long job, owner gone: kept"               alive "$(isalive "$(cat "$WORK/pid.busy")")"
eq "registered wait, finished agent: killed"       dead  "$(isalive "$reg1")"
eq "  registry entry removed" 0 "$(grep -l '"reg1"' "$WAIT_FOR_DIR"/*.json 2>/dev/null | wc -l)"
eq "registered wait, running agent: kept"          alive "$(isalive "$reg2")"
eq "each kill in the audit log" 4 "$(grep -c '"op": "sentinel kill ' "$HARNESS_HOME/log/actions.jsonl")"

"$SW"
eq "second tick: no new lines" 5 "$(grep -c stuck-wait "$LOG")"

# T1372: a registered wait older than 6 h is flagged once as stale and left running.
regf=$(grep -l '"reg2"' "$WAIT_FOR_DIR"/*.json)
jq '.start -= 25200' "$regf" >"$WORK/r.json" && cat "$WORK/r.json" >"$regf"
"$SW"; "$SW"
eq "registered wait over 6 h: flagged stale once" 1 "$(grep -c "stale-wait pid $reg2 (reg2, 7 h" "$LOG")"
eq "  and kept" alive "$(isalive "$reg2")"

kill "$(cat "$WORK/pid.busy")" "$(cat "$WORK/pid.live")" "$(cat "$WORK/pid.seen")" "$reg2" "$sess1" "$writer" "$livejob" 2>/dev/null
rm -rf "$WORK"
[ "$bad" = 0 ] && echo "all sentinel-waits fixtures pass"
exit $bad
