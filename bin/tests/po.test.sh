#!/usr/bin/env bash
# T1412 product-owner agents: po-new, po-ask, po-run (queue, one run at a time), po-status, po-push (cap, pick buttons),
# po-picks (tap -> inbox, once), deploy-lock (second deployer waits and reads the new version).
# Fixture-only (FLEET §5.6): bwrap --unshare-net, a fake ntfy on 127.0.0.1, HARNESS_HOME in a temp dir, a fake agent-run
# (no LLM); the selftest proves no route out and that the real PO folders are untouched.
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${PO_SANDBOXED:-}" ]; then
  exec bwrap --dev-bind / / --unshare-net --setenv PO_SANDBOXED 1 -- bash "$SELF"
fi
. "$BIN/tests/lib/assert.sh"
REAL_HOME="${HARNESS_HOME:-$HOME/agents}"
real_count() { find "$REAL_HOME"/po-*/inbox "$REAL_HOME"/po-*/done -type f 2>/dev/null | wc -l; }
real_before=$(real_count)

WORK=$(mktemp -d); trap 'kill "${SRV:-0}" 2>/dev/null; rm -rf "$WORK"' EXIT
export HARNESS_ENV_LOADED=1 HARNESS_HOME="$WORK/agents" HARNESS_CONFIG=/dev/null
mkdir -p "$HARNESS_HOME" "$WORK/stubs"
cp -r "$BIN/../po-template" "$HARNESS_HOME/po-template"

# Fake agent-run: logs start/end, flags overlap, files current/ like a PO (unless $WORK/leave), may drop a new request.
cat >"$WORK/stubs/agent-run" <<'STUB'
#!/usr/bin/env bash
d="$HARNESS_HOME/$1"
mkdir "$WORK/running" 2>/dev/null || echo overlap >>"$WORK/runs.log"
echo "start $(ls "$d/current" | wc -l)" >>"$WORK/runs.log"; echo "$PO_BUDGET" >>"$WORK/budget.log"
[ -e "$WORK/drop" ] && { rm -f "$WORK/drop"; po-ask fx "arrived mid-run" >/dev/null; }
[ -e "$WORK/hold" ] && while [ -e "$WORK/hold" ]; do sleep 0.05; done
if [ ! -e "$WORK/leave" ]; then
  for f in "$d"/current/*.md; do [ -e "$f" ] || continue; echo "outcome: answered" >>"$f"; mv "$f" "$d/done/"; done
fi
echo "ESCALATE: fx decision" >"$d/REPORT.md"
rmdir "$WORK/running"; echo end >>"$WORK/runs.log"
STUB
printf '#!/bin/sh\nexit $(cat "$WORK/plan.rc" 2>/dev/null || echo 0)\n' >"$WORK/stubs/plan-usage"
chmod +x "$WORK/stubs/agent-run" "$WORK/stubs/plan-usage"
export PATH="$WORK/stubs:$BIN:$PATH" WORK

python3 - "$WORK/port" "$WORK/got.jsonl" "$WORK/stream.jsonl" <<'PY' &
import json, sys, http.server, urllib.parse
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        with open(sys.argv[2], 'a') as f:
            f.write(json.dumps({'path': self.path, 'actions': self.headers.get('Actions'), 'body': body}) + '\n')
        self.send_response(200); self.end_headers(); self.wfile.write(b'{}')
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); since = urllib.parse.parse_qs(u.query).get('since', [''])[0]
        lines = open(sys.argv[3]).read().splitlines()
        ids = [json.loads(l).get('id') for l in lines]
        if since in ids: lines = lines[ids.index(since) + 1:]
        self.send_response(200); self.end_headers()
        self.wfile.write(('\n'.join(lines) + '\n' if lines else '').encode())
        with open(sys.argv[2], 'a') as f:
            f.write(json.dumps({'get': self.path}) + '\n')
    def log_message(self, *a): pass
s = http.server.HTTPServer(('127.0.0.1', 0), H)
open(sys.argv[1], 'w').write(str(s.server_port))
s.serve_forever()
PY
SRV=$!
: >"$WORK/stream.jsonl"; : >"$WORK/got.jsonl"
for _ in $(seq 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
printf 'NTFY_URL=http://127.0.0.1:%s\nNTFY_TOPIC=fixture\n' "$(cat "$WORK/port")" >"$WORK/ntfy.env"
export NTFY_ENV_FILE="$WORK/ntfy.env" NTFY_LOG_FILE="$WORK/notify.log" NTFY_KEYS_FILE="$WORK/keys.tsv"

# selftest
if curl -sS -m 3 -o /dev/null https://ntfy.sh 2>/dev/null; then echo 'FAIL selftest: sandbox reaches the network'; exit 1; fi
ok 'selftest: no route to ntfy.sh'
is 'selftest: agent-run is the fake' "$(command -v agent-run)" "$WORK/stubs/agent-run"
is 'selftest: plan-usage is the fake' "$(command -v plan-usage)" "$WORK/stubs/plan-usage"
case "$HARNESS_HOME" in "$WORK"/*) ok 'selftest: HARNESS_HOME is the fixture';; *) nok 'selftest: HARNESS_HOME' "$HARNESS_HOME";; esac

# po-new
out=$(po-new fx "Fixture Game"); is 'po-new: exit 0' "$?" 0
P="$HARNESS_HOME/po-fx"
ev 'po-new: folder contract' '[ -s "$P/BRIEF.md" ] && [ -d "$P/inbox" ] && [ -d "$P/outbox/discord" ] && [ -s "$P/state/BACKLOG.md" ] && [ -s "$P/agent.env" ]'
ev 'po-new: placeholders filled' 'grep -q "po-fx, the product owner of Fixture Game" "$P/BRIEF.md" && ! grep -q "{{" "$P/BRIEF.md" "$P"/state/*.md'
case "$out" in *"po@fx.path"*) ok 'po-new: prints the unit command';; *) nok 'po-new: prints the unit command' "$out";; esac
po-new fx >/dev/null 2>&1; is 'po-new: existing PO refused' "$?" 3
po-new template >/dev/null 2>&1; is 'po-new: template name refused' "$?" 2

# po-ask (review focus 1 and 3)
po-ask nope "x" >/dev/null 2>&1; is 'po-ask: unknown PO exits 2' "$?" 2
ev 'po-ask: unknown PO wrote nothing' '[ ! -e "$HARNESS_HOME/po-nope" ]'
a=$(po-ask fx --from owner --channel discord --thread 123 --copy "first, verbatim") b=$(po-ask fx "second")
ev 'po-ask: two requests in one second are two files' '[ "$a" != "$b" ] && [ -s "$a" ] && [ -s "$b" ]'
is 'po-ask: inbox holds 2' "$(ls "$P/inbox" | wc -l)" 2
ev 'po-ask: front matter + verbatim text' 'grep -qx "from: owner" "$a" && grep -qx "thread: 123" "$a" && grep -qx "quote: copy" "$a" && grep -qx "first, verbatim" "$a"'
echo "from stdin" | po-ask fx - >/dev/null; is 'po-ask: stdin text' "$(grep -lx 'from stdin' "$P"/inbox/*.md | wc -l)" 1
po-ask fx --from boss "x" >/dev/null 2>&1; is 'po-ask: bad --from exits 2' "$?" 2
ev 'po-ask: no temp file left in the inbox' '[ -z "$(ls -A "$P/.inbox-tmp")" ]'

# po-run (review focus 2): a request during a run is queued for one more run, never a parallel one
touch "$WORK/drop" "$WORK/hold"
po-run fx >"$WORK/run1.out" 2>&1 & R=$!
timeout 10 wait-for --every 0.05 --until "grep -q start '$WORK/runs.log'" >/dev/null 2>&1
out=$(po-run fx); is 'po-run: second call exits 0' "$?" 0
case "$out" in *"already running"*) ok 'po-run: second call says already running';; *) nok 'po-run: second call' "$out";; esac
rm -f "$WORK/hold"; wait "$R"; is 'po-run: exit 0' "$?" 0
is 'po-run: two runs, first with 3 requests, second with the mid-run one' "$(paste -sd' ' "$WORK/runs.log")" 'start 3 end start 1 end'
is 'po-run: inbox empty' "$(ls "$P/inbox" | wc -l)" 0
is 'po-run: 4 requests in done/' "$(ls "$P/done" | wc -l)" 4
touch "$WORK/leave"; po-ask fx "unfiled" >/dev/null; po-run fx >/dev/null 2>&1; rm -f "$WORK/leave"
ev 'po-run: a request the run left gets an outcome line' 'grep -l unfiled "$P"/done/*.md | xargs grep -q "^outcome: left in current/"'
is 'po-run: current/ empty after' "$(ls "$P/current" | wc -l)" 0
# review focus 4: week >= 95 % -> the run gets PO_BUDGET=stop (the brief then spawns no worker)
is 'po-run: PO_BUDGET=ok under 95 %' "$(sort -u "$WORK/budget.log")" ok
echo 1 >"$WORK/plan.rc"; po-ask fx "work at 96 %" >/dev/null; po-run fx >/dev/null 2>&1; rm -f "$WORK/plan.rc"
is 'po-run: PO_BUDGET=stop at >= 95 %' "$(tail -1 "$WORK/budget.log")" stop

# po-status
printf '| F1 | fx | t | open |\n| F2 | fx | t | done |\n| F3 | fx | t | doing |\n' >>"$P/state/BACKLOG.md"
out=$(po-status)
case "$out" in *"po-fx  last never  inbox 0  running 0  open 2  pushes today 0"*) ok 'po-status: counts';; *) nok 'po-status: counts' "$out";; esac
case "$out" in *"  ESCALATE: fx decision"*) ok 'po-status: ESCALATE lines';; *) nok 'po-status: ESCALATE lines' "$out";; esac
po-status nope >/dev/null 2>&1; is 'po-status: unknown PO exits 2' "$?" 2

# po-push: prefix, buttons to the reply topic, daily cap
out=$(po-push fx --pick 'A=Dimensioned;B=Plain' "pick a look https://x/y"); is 'po-push: exit 0' "$?" 0
pid=$(sed -n 's/.*pick \([0-9a-f]*\)$/\1/p' <<<"$out")
got=$(grep '"body"' "$WORK/got.jsonl" | tail -1)
is 'po-push: [fx] prefix' "$(jq -r .body <<<"$got")" '[fx] pick a look https://x/y'
act=$(jq -r .actions <<<"$got")
case "$act" in "http, A Dimensioned, http://127.0.0.1:"*"/fixture-picks, method=POST, body=fx:$pid:A, clear=true; http, B Plain, "*"body=fx:$pid:B, clear=true")
  ok 'po-push: two buttons POST to the reply topic';; *) nok 'po-push: buttons' "$act";; esac
ev 'po-push: pick record' '[ "$(jq -r ".options.B" "$P/state/picks/$pid.json")" = Plain ] && [ "$(jq -r .answer "$P/state/picks/$pid.json")" = null ]'
po-push fx "two" >/dev/null && po-push fx "three" >/dev/null; is 'po-push: 3 sent' "$?" 0
po-push fx "four" >/dev/null 2>&1; is 'po-push: 4th refused (3/day)' "$?" 3
is 'po-push: fake ntfy got 3 pushes' "$(grep -c '"body"' "$WORK/got.jsonl")" 3

# po-picks: a valid tap files one request; forged, unknown and repeated taps are dropped
{ printf '{"id":"m1","event":"open"}\n{"id":"m2","event":"message","message":"fx:%s:B"}\n' "$pid"
  printf '{"id":"m3","event":"message","message":"fx:%s:Z"}\n{"id":"m4","event":"message","message":"rm -rf /"}\n' "$pid"
  printf '{"id":"m5","event":"message","message":"fx:%s:A"}\n{"id":"m6","event":"message","message":"nope:%s:A"}\n' "$pid" "$pid"
} >"$WORK/stream.jsonl"
po-picks --once; is 'po-picks: exit 0' "$?" 0
f=$(ls "$P"/inbox/*-pick-*.md 2>/dev/null)
is 'po-picks: one request filed' "$(printf '%s' "$f" | grep -c .)" 1
ev 'po-picks: request names the pick' 'grep -q "Owner pick $pid: B = Plain (question: \[fx\] pick a look" $f && grep -qx "channel: ntfy" $f'
is 'po-picks: pick answered B' "$(jq -r .answer.key "$P/state/picks/$pid.json")" B
is 'po-picks: 4 dropped in the log' "$(grep -c dropped "$HARNESS_HOME/log/po-picks.log")" 4
po-picks --once
is 'po-picks: second poll resumes after the last id' "$(grep '"get"' "$WORK/got.jsonl" | tail -1 | jq -r .get | grep -o 'since=[a-z0-9]*')" since=m6
is 'po-picks: no duplicate request' "$(ls "$P"/inbox/*-pick-*.md | wc -l)" 1

# deploy-lock (review focus 5)
echo 1 >"$WORK/live"
deploy-lock fx-5.2 --version "cat $WORK/live" -- bash -c "sleep 1; echo 2 >$WORK/live" >"$WORK/d1.out" 2>&1 & D=$!
timeout 10 wait-for --every 0.05 --until "grep -q 'live before' '$WORK/d1.out'" >/dev/null 2>&1
out=$(deploy-lock fx-5.2 --version "cat $WORK/live" -- bash -c 'echo "saw $DEPLOY_LIVE_BEFORE"'); rc=$?; wait "$D"
is 'deploy-lock: second deploy exit 0' "$rc" 0
case "$out" in *"waiting"*"live before 2"*"saw 2"*"live after 2 (exit 0)"*) ok 'deploy-lock: second waits and reads the new version';;
  *) nok 'deploy-lock: second waits' "$out";; esac
deploy-lock fx -- false >/dev/null; is 'deploy-lock: passes the exit code' "$?" 1
DEPLOY_LOCK_WAIT=0 deploy-lock 'bad/env' -- true >/dev/null 2>&1; is 'deploy-lock: bad env exits 2' "$?" 2

# units
U="$BIN/../units"
ev 'units: path unit wakes po@%i.service on a non-empty inbox' 'grep -qx "DirectoryNotEmpty=%h/agents/po-%i/inbox" "$U/po@.path" && grep -qx "Unit=po@%i.service" "$U/po@.path"'
ev 'units: service runs po-run' 'grep -qx "ExecStart=%h/agents/bin/po-run %i" "$U/po@.service"'

is 'selftest: real PO folders untouched' "$(real_count)" "$real_before"
exit $bad
