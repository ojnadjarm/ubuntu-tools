#!/usr/bin/env bash
# T1634-V6: op mode. notify-owner and po-picks reach ntfy through the broker (the topic stays inside it); a critical lease
# waits for the owner's tap (a nonce only his push carries) or the orchestrator's `secret approve`; a self-grant refused
# inside an agent is pushed by the broker itself. Fixtures only: bwrap --unshare-net, a fake ntfy on 127.0.0.1, a repo
# fleet-vaultd on a temp state, registry and creds dir, a fake cgroup tree for agents.slice, a stub raise command.
set -uo pipefail
SELF=$(readlink -f "$0"); A=$(cd "$(dirname "$SELF")/../.." && pwd)
if [ -z "${VAULT_OP_SANDBOXED:-}" ]; then
  exec bwrap --dev-bind / / --unshare-net --setenv VAULT_OP_SANDBOXED 1 -- bash "$SELF"
fi
W=$(mktemp -d); PIDS=()
trap 'for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$W"' EXIT
. "$A/bin/tests/lib/assert.sh"
. "$A/bin/tests/lib/vault-seam.sh"
me=$(id -un); uid=$(id -u)
TOPIC=fxtopic-$RANDOM$RANDOM
export FLEET_VAULT_SOCKET="$W/run/admin.sock" FLEET_VAULT_REGISTRY="$W/registry.toml" SECRET_RAISE_CMD="$W/raise"
export HARNESS_CONFIG=/dev/null NTFY_ENV_FILE="$W/no-ntfy.env" NTFY_LOG_FILE="$W/notify.log" NTFY_KEYS_FILE="$W/keys.tsv"
CG="$W/cg"; SLICE="$CG/user.slice/user-$uid.slice/user@$uid.service/agents.slice"
mkdir -p "$W/run" "$W/state" "$W/creds" "$SLICE/run-fx.scope"; : >"$SLICE/run-fx.scope/cgroup.procs"
S="$A/bin/secret"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/raise.log"\n' "$W" >"$W/raise"; chmod +x "$W/raise"; : >"$W/raise.log"

# 0. Selftest: no route out; every path is a fixture.
if curl -sS -m 3 -o /dev/null https://ntfy.sh 2>/dev/null; then echo 'FAIL selftest: sandbox reaches the network'; exit 1; fi
ok 'selftest: the sandbox has no route to ntfy.sh'
for p in "$FLEET_VAULT_SOCKET" "$FLEET_VAULT_REGISTRY" "$W/state" "$CG" "$SECRET_RAISE_CMD" "$NTFY_LOG_FILE"; do
  case "$p" in "$W"/*) ;; *) echo "FAIL selftest: $p is outside the fixture"; exit 1 ;; esac
done
ok "selftest: socket, registry, state, creds, cgroup tree, raise and logs are fixtures"

# A fake ntfy: POST / (JSON publish) is recorded; POST /<topic> is a tap; GET /<topic>/json?poll=1&since= serves taps.
python3 -I - "$W/port" "$W/got.jsonl" "$W/taps.jsonl" <<'PY' &
import json, sys, time, http.server, urllib.parse
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        if self.path == '/':
            open(sys.argv[2], 'a').write(json.dumps(json.loads(body)) + '\n')
        else:
            n = sum(1 for _ in open(sys.argv[3]))
            open(sys.argv[3], 'a').write(json.dumps({'id': f'm{n}', 'time': int(time.time()), 'event': 'message',
                                                     'topic': self.path.strip('/'), 'message': body}) + '\n')
        self.send_response(200); self.end_headers(); self.wfile.write(b'{}')
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); topic = u.path.split('/')[1]
        since = urllib.parse.parse_qs(u.query).get('since', [''])[0]
        rows = [json.loads(l) for l in open(sys.argv[3]) if json.loads(l)['topic'] == topic]
        ids = [r['id'] for r in rows]
        if since in ids: rows = rows[ids.index(since) + 1:]
        elif since.isdigit(): rows = [r for r in rows if r['time'] >= int(since)]
        self.send_response(200); self.end_headers()
        self.wfile.write(''.join(json.dumps(r) + '\n' for r in rows).encode())
    def log_message(self, *a): pass
s = http.server.HTTPServer(('127.0.0.1', 0), H)
open(sys.argv[1], 'w').write(str(s.server_port))
s.serve_forever()
PY
PIDS+=($!)
: >"$W/got.jsonl"; : >"$W/taps.jsonl"
wait-for --label vault-op-ntfy --every 0.1 --until "test -s '$W/port'" >/dev/null
UP="http://127.0.0.1:$(cat "$W/port")"
tap() { curl -fsS -m 5 -X POST --data-binary "$2" "$UP/$1" >/dev/null; }
pushes() { grep -c . "$W/got.jsonl"; }
last() { tail -1 "$W/got.jsonl" | jq -r "$1"; }

# 1. Units: the op's publish shape and refusals, poll without the topic, one approval ask per (secret, ticket).
unit=$(python3 -I - "$A/lib" "$UP" "$TOPIC" <<'EOF'
import sys; sys.path.insert(0, sys.argv[1]); up, topic = sys.argv[2], sys.argv[3].encode()
from vault.op import Ntfy, OpError
from vault.registry import Entry
from vault.push import Push
from vault.approvals import Approvals
from vault.seal import MemorySealer
class Log:
    def log(self, e): pass
def refused(f):
    try: f()
    except OpError: return True
    return False
e = Entry("ntfy", "free", "x", ("op",), hosts=("ntfy.sh",))
n, r = Ntfy(up), []
r.append(n.publish(e, topic, "hi", "t", "high", "a,b", [("Yes", "p:1:A")]) == 200)
r.append(all(refused(f) for f in [lambda: n.publish(e, topic, "x", prio="loud"),
                                  lambda: n.publish(e, topic, "x", buttons=[("a", "b")] * 4),
                                  lambda: n.publish(e, topic, "x", buttons=[("a,b", "c")]),
                                  lambda: n.publish(e, b"bad topic!", "x"),
                                  lambda: n.poll(e, topic, "1;rm")]))
seal = MemorySealer(); seal.put("ntfy", topic)
ap = Approvals(Push(lambda: {"ntfy": e}, seal, n), Log(), every=5)
p, sent = ap.ask("card", "T1", "fx", "buy it")
r.append(sent is True and ap.ask("card", "T1", "fx")[1] is None)
print(" ".join("1" if x else "0" for x in r))
print(p.ref, p.nonce)
EOF
)
is "units: publish ok; bad priority, 4 buttons, a comma, a bad topic, a bad since refused; one ask per (secret, ticket)" \
   "$(head -1 <<<"$unit")" "1 1 1"
first=$(head -1 "$W/got.jsonl")
ev "units: JSON publish to the topic, priority 4, tags, one button posting to <topic>-picks" \
   'jq -e --arg t "$TOPIC" --arg u "$UP/$TOPIC-picks" ".topic == \$t and .priority == 4 and .tags == [\"a\",\"b\"] and .actions[0].url == \$u and .actions[0].body == \"p:1:A\"" <<<"$first" >/dev/null'
read -r uref unonce < <(sed -n 2p <<<"$unit")
apush=$(sed -n 2p "$W/got.jsonl")
ev "units: the approval push carries Approve and Deny, both to <topic>-vault, with the nonce" \
   'jq -e --arg u "$UP/$TOPIC-vault" --arg b "vault:$uref:$unonce:yes" "[.actions[].url] == [\$u, \$u] and .actions[0].body == \$b and .actions[0].label == \"Approve\"" <<<"$apush" >/dev/null'

# 2. A fixture broker: the shipped registry plus a free proxy and a critical proxy row; the ntfy creds is a fake topic.
cp "$A/vault/registry.toml" "$W/registry.toml"
printf '\n[secret.selftest-free]\nclass = "free"\nused_in = "fixture"\nmodes = ["proxy"]\nhosts = ["example.org"]\npaths = ["/"]\n' >>"$W/registry.toml"
printf '\n[secret.selftest-card]\nclass = "critical"\nused_in = "fixture card"\nmodes = ["proxy"]\nhosts = ["example.org"]\npaths = ["/"]\n' >>"$W/registry.toml"
printf '%s' "$TOPIC" >"$W/creds/fleet.ntfy"
python3 -I "$A/vault/fleet-vaultd" --registry "$W/registry.toml" --state "$W/state" --socket "$FLEET_VAULT_SOCKET" \
  --seal-socket "$W/no-seal.sock" --cred-dir "$W/creds" --clients "$me" --cgroup-root "$CG" --upstream "$UP" \
  >>"$W/d.out" 2>&1 &
PIDS+=($!)
wait-for --label vault-op-broker --every 0.1 --until "test -S '$FLEET_VAULT_SOCKET' && test -s '$W/state/port'" >/dev/null
ev "registry: the shipped ntfy row is class free, op mode, pinned to ntfy.sh" \
   'python3 -I - "$A/lib" "$A/vault/registry.toml" <<<"import sys; sys.path.insert(0, sys.argv[1]); from vault import registry; e = registry.load(sys.argv[2])[\"ntfy\"]; sys.exit(not (e.modes == (\"op\",) and e.hosts == (\"ntfy.sh\",) and e.cls == \"free\"))"'
log() { python3 -I -c 'import json,sys; [print(json.dumps(json.loads(l), sort_keys=True)) for l in open(sys.argv[1])]' "$W/state/uses.jsonl"; }

# 3. notify-owner with no env file: the broker sends; buttons go to the reply topic; one log row, ok.
n=$(pushes)
AGENT_NAME=fx-notify "$A/bin/notify-owner" -p high -t fxtitle -g warning -a "Yes=po:ab12:A;No=po:ab12:B" "fixture push" \
  >"$W/no.out" 2>&1; rc=$?
is "notify-owner via the vault: exit 0, one push" "$rc $(( $(pushes) - n ))" "0 1"
ev "notify-owner via the vault: text, title, priority, tags and 2 buttons to <topic>-picks" \
   'jq -e --arg u "$UP/$TOPIC-picks" ".message == \"fixture push\" and .title == \"fxtitle\" and .priority == 4 and .tags == [\"warning\"] and ([.actions[].url] | unique) == [\$u] and .actions[1].body == \"po:ab12:B\"" <<<"$(tail -1 "$W/got.jsonl")" >/dev/null'
is "notify-owner via the vault: one ok row in notify.log" "$(cut -f2,4 "$NTFY_LOG_FILE")" $'ok\tfixture push'
ev "broker log: one ntfy use, ok, by the caller" 'log | grep "\"secret\": \"ntfy\"" | grep "\"agent\": \"fx-notify\"" | grep -q "\"result\": \"ok\""'
printf 'x' | "$S" notify -p loud >/dev/null 2>"$W/bad.err"; rc=$?
ev "secret notify: a bad priority is refused by the broker (exit 1, why on stderr)" '[ $rc = 1 ] && grep -q "priority must be" "$W/bad.err"'
FLEET_VAULT_SOCKET="$W/none.sock" "$A/bin/notify-owner" "broker down" 2>/dev/null; rc=$?
is "notify-owner, broker down: exit 1 and a fail row" "$rc $(tail -1 "$NTFY_LOG_FILE" | cut -f2)" "1 fail"

# 4. po-picks with no env file reads the reply topic through the broker; the topic never reaches the client.
tap "$TOPIC-picks" "not-a-pick"; tap "$TOPIC-vault" "vault:000000:xxxxxxxxxxxxxxxxxxxx:yes"
out=$("$S" picks --since 10m)
is "secret picks: the reply topic's taps only, without the topic field" "$(jq -c '[.message, has("topic")]' <<<"$out")" '["not-a-pick",false]'
mkdir -p "$W/hh/log" "$W/hh/state"
HARNESS_HOME="$W/hh" PO_PAPERS="$W/pp" "$A/bin/po-picks" --once; rc=$?
is "po-picks --once via the vault: exit 0, the tap read and dropped as not a pick" \
   "$rc $(grep -c 'not a pick' "$W/hh/log/po-picks.log")" "0 1"
is "po-picks: the last id is kept for the next poll" "$(cat "$W/hh/state/po-picks.since")" "m0"

# 5. A critical lease waits for one approval: a forged tap does nothing, the owner's tap (with the nonce) approves.
n=$(pushes); "$S" grant fleet-backup-pass --ticket T4 >/dev/null 2>"$W/g4.err"
ev "critical with no lease mode (unit only): refused at once, no approval push" \
   'grep -q "no lease mode" "$W/g4.err" && [ "$(pushes)" = "$n" ]'
refof() { grep -o 'ref [0-9a-f]\{6\}' "$1" | head -1 | cut -d' ' -f2; }
"$S" grant selftest-card --ticket T5 >"$W/g5.out" 2>"$W/g5.err"; rc=$?
ref=$(refof "$W/g5.err")
ev "critical: no lease, exit 1, a ref named" '[ $rc = 1 ] && [ ! -s "$W/g5.out" ] && [ -n "$ref" ]'
body=$(tail -1 "$W/got.jsonl" | jq -r '.actions[0].body')
ev "critical: the approval push names the secret and ticket and carries the nonce" \
   'tail -1 "$W/got.jsonl" | jq -e ".message | test(\"selftest-card for T5\")" >/dev/null && [[ $body == vault:$ref:*:yes ]]'
tap "$TOPIC-vault" "vault:$ref:forgedforgedforgedforged:yes"
is "critical: a forged tap leaves it pending" "$("$S" pending | awk -v r="$ref" '$1 == r {print $3}')" pending
tap "$TOPIC-vault" "$body"
timeout 20 wait-for --label vault-op-tap --every 1 --until "'$S' pending | grep -q '^$ref .* approved '" >/dev/null
is "critical: the owner's tap approves it" "$("$S" pending | awk -v r="$ref" '$1 == r {print $3, $7, $8}')" "approved owner tap"
L5=$("$S" grant selftest-card --ticket T5 2>/dev/null)
is "critical: the next grant gets the lease" "$(( ${#L5} >= 32 ))" 1
"$S" grant selftest-card --ticket T5 >/dev/null 2>&1
is "critical: one approval, one lease (the next ask waits again)" "$("$S" pending | awk '$5 == "T5" {print $3}')" pending

# 6. The orchestrator's path: `secret approve` outside an agent works; inside one it is refused and pushed by the broker.
"$S" grant selftest-card --ticket T6 >/dev/null 2>"$W/g6.err"; ref6=$(refof "$W/g6.err")
n=$(pushes)
bash -c 'echo $$ >"$1"; exec env AGENT_NAME=fx-self "$2" approve "$3"' _ "$SLICE/run-fx.scope/cgroup.procs" "$S" "$ref6" \
  >/dev/null 2>"$W/in.err"; rc=$?; : >"$SLICE/run-fx.scope/cgroup.procs"
ev "approve from inside an agent: exit 1, refused, the broker pushed it" \
   '[ $rc = 1 ] && grep -q "never comes from inside an agent" "$W/in.err" && [ $(( $(pushes) - n )) = 1 ] && tail -1 "$W/got.jsonl" | jq -e ".message | test(\"fx-self asked approve\")" >/dev/null'
is "approve from inside an agent: still pending" "$("$S" pending | awk -v r="$ref6" '$1 == r {print $3}')" pending
is "approve outside an agent: approved" "$("$S" approve "$ref6")" "secret: approved selftest-card for T6 (ref $ref6)"
ev "approve outside an agent: the next grant gets the lease" '[ "$("$S" grant selftest-card --ticket T6 2>/dev/null | wc -c)" -gt 32 ]'
"$S" grant selftest-card --ticket T7 >/dev/null 2>"$W/g7.err"; ref7=$(refof "$W/g7.err")
"$S" deny "$ref7" >/dev/null
"$S" grant selftest-card --ticket T7 >/dev/null 2>"$W/g7b.err"; rc=$?
ev "deny: the grant is refused, saying who denied it" '[ $rc = 1 ] && grep -q "denied by uid" "$W/g7b.err"'

# 7. --wait: a launcher's grant waits for the approval and then prints the lease.
"$S" grant selftest-card --ticket T8 --wait 30 >"$W/g8.out" 2>"$W/g8.err" & wp=$!
timeout 15 wait-for --label vault-op-wait --every 0.2 --until "grep -q 'waits for approval' '$W/g8.err'" >/dev/null
"$S" approve "$(refof "$W/g8.err")" >/dev/null
wait "$wp"; rc=$?
ev "--wait: exit 0 with a lease once approved" '[ $rc = 0 ] && [ "$(wc -c <"$W/g8.out")" -gt 32 ]'

# 8. A raw self-grant from inside an agent: the broker pushes the owner itself; the client raises nothing more.
n=$(pushes)
python3 -I - "$A/lib" "$FLEET_VAULT_SOCKET" "$SLICE/run-fx.scope/cgroup.procs" >"$W/raw.out" <<'EOF'
import os, sys; sys.path.insert(0, sys.argv[1]); from vault import wire
open(sys.argv[3], "w").write(f"{os.getpid()}\n")
r = wire.call(sys.argv[2], {"op": "grant", "name": "selftest-free", "ticket": "T9", "agent": "fx-raw"})
print(r.get("ok"), r.get("raise"), r.get("raised"), "lease" in r)
EOF
: >"$SLICE/run-fx.scope/cgroup.procs"
is "raw self-grant: refused, raised by the broker (raise false, raised true), no lease" "$(cat "$W/raw.out")" "False False True False"
ev "raw self-grant: one high push naming the agent and the secret" \
   '[ $(( $(pushes) - n )) = 1 ] && tail -1 "$W/got.jsonl" | jq -e ".priority == 4 and (.message | test(\"fx-raw asked grant on selftest-free\"))" >/dev/null'
is "raw self-grant: the client-side raise was not needed" "$(grep -c . "$W/raise.log")" 0

# 9. Nothing secret leaves the broker: no topic in any client output, the broker log or stdout; no nonce in the log.
ev "the topic is in no client output, no broker log line and no broker stdout" \
   '! grep -qF "$TOPIC" "$W"/*.out "$W"/*.err "$W/state/uses.jsonl" "$W/d.out" "$NTFY_LOG_FILE" "$W/hh/log/po-picks.log"'
ev "no approval nonce in the broker log" '! grep -qF "${body#vault:$ref:}" "$W/state/uses.jsonl"'

exit $bad
