#!/usr/bin/env bash
# T1634-V5: a brief's `Secrets:` line becomes leases. Fixtures only: a repo fleet-vaultd on a temp state and registry,
# a fake cgroup tree (--cgroup-root) standing for agents.slice, a stub raise command; no value is sealed or read.
# Covers the line parser, leases kept across a broker restart, `secret leases`, a grant asked from inside an agent
# (refused, logged, raised), agent-exec --secrets-from (leases in, revoked after), the liaison job's grant file,
# brief-lint's warnings, and that no lease id reaches a log or an argument list.
set -uo pipefail
A=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
W=$(mktemp -d); PIDS=()
trap 'for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$W"' EXIT
. "$A/bin/tests/lib/assert.sh"
. "$A/bin/tests/lib/vault-seam.sh"
me=$(id -un); uid=$(id -u)
export FLEET_VAULT_SOCKET="$W/run/admin.sock" FLEET_VAULT_REGISTRY="$W/registry.toml" SECRET_RAISE_CMD="$W/raise"
export HARNESS_CONFIG=/dev/null
unset $(env | sed -n 's/^\(FLEET_LEASE_[A-Z0-9_]*\)=.*/\1/p')
CG="$W/cg"; SLICE="$CG/user.slice/user-$uid.slice/user@$uid.service/agents.slice"
mkdir -p "$W/run" "$W/state" "$W/creds" "$SLICE/run-fx.scope" "$CG/user.slice/user-$uid.slice/user@$uid.service/app.slice"
: >"$SLICE/run-fx.scope/cgroup.procs"
S="$A/bin/secret"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/raise.log"\n' "$W" >"$W/raise"; chmod +x "$W/raise"
inside() { echo "$1" >"$SLICE/run-fx.scope/cgroup.procs"; }

# 0. Selftest: every path the broker, the client and the raise use is a fixture.
for p in "$FLEET_VAULT_SOCKET" "$FLEET_VAULT_REGISTRY" "$W/state" "$CG" "$SECRET_RAISE_CMD"; do
  case "$p" in "$W"/*) ;; *) echo "FAIL selftest: $p is outside the fixture"; exit 1 ;; esac
done
ok "selftest: socket, registry, state, cgroup tree and raise command are fixtures ($W)"

# 1. Units: the line parser, the caller lookup, leases across a restart, the policy's inside-an-agent refusal.
unit=$(python3 -I - "$A/lib" "$W" "$uid" <<'EOF'
import os, sys; sys.path.insert(0, sys.argv[1]); w, uid = sys.argv[2], int(sys.argv[3])
from vault import briefline; from vault.caller import Callers; from vault.leases import Leases
from vault.grants import Grants
from vault.audit import Audit
r = []
names, asked, bad = briefline.parse("x\nSecrets: ntfy, spotify-client\n- Secrets: none\nSecrets: Bad X\n"
                                    'AI image grant: "hazme  una\timagen con IA"\nsee the Secrets: line\n')
r.append(names == ["ntfy", "spotify-client", "openrouter"] and asked == "hazme una imagen con IA" and bad == ["Bad X"])
r.append(briefline.parse("prose about a Secrets: line\n") == ([], "", []))
r.append(briefline.env_name("spotify-client") == "FLEET_LEASE_SPOTIFY_CLIENT")
c = Callers(f"{w}/cg")
slice_ = f"{w}/cg/user.slice/user-{uid}.slice/user@{uid}.service/agents.slice/run-fx.scope/cgroup.procs"
open(slice_, "w").write("41\n4242\n")
r.append(c.agent_unit(4242, uid) == "run-fx.scope" and c.agent_unit(424, uid) is None and c.agent_unit(4242, uid + 1) is None)
open(slice_, "w").write("")
t = [100.0]; path = f"{w}/leases-unit.json"
L = Leases(clock=lambda: t[0], path=path); a = L.mint("x", "T1", 50, cap=1.0); L.charge(a.id, 0.25); b = L.mint("x", "T2", 5)
r.append(oct(os.stat(path).st_mode & 0o777) == "0o600")
t[0] = 110.0; L2 = Leases(clock=lambda: t[0], path=path)
r.append(L2.check(a.id, "x").spent == 0.25)
try: L2.check(b.id, "x"); r.append(False)
except Exception: r.append(True)
r.append(L2.revoke(a.id) and not Leases(clock=lambda: t[0], path=path).revoke(a.id))
open(slice_, "w").write("777\n")
g = Grants(Leases(), Audit(f"{w}/unit-audit.jsonl"), c).grant(None, {"name": "x", "ticket": "T1"}, uid, 777)
r.append(g["ok"] is False and g["raise"] is True and "inside an agent (run-fx.scope)" in g["error"])
open(slice_, "w").write("")
print(" ".join("1" if x else "0" for x in r))
EOF
)
is "units: parse (names, quote, bad), prose ignored, env name, caller lookup by pid and uid, leases 600, kept across a restart (spent kept, expired dropped, revoke saved), inside an agent refused with raise" \
   "$unit" "1 1 1 1 1 1 1 1 1"

# 2. A fixture broker: the shipped registry plus a free and a critical fixture row; fake cgroup root.
cp "$A/vault/registry.toml" "$W/registry.toml"
printf '\n[secret.selftest-free]\nclass = "free"\nused_in = "fixture"\nmodes = ["proxy"]\nhosts = ["example.org"]\npaths = ["/"]\n' >>"$W/registry.toml"
printf '\n[secret.selftest-card]\nclass = "critical"\nused_in = "fixture card"\nmodes = ["proxy"]\nhosts = ["example.org"]\npaths = ["/"]\n' >>"$W/registry.toml"
start_broker() {
  python3 -I "$A/vault/fleet-vaultd" --registry "$W/registry.toml" --state "$W/state" --socket "$FLEET_VAULT_SOCKET" \
    --seal-socket "$W/no-seal.sock" --cred-dir "$W/creds" --clients "$me" --cgroup-root "$CG" >>"$W/d.out" 2>&1 &
  PIDS+=($!); BROKER=$!
  wait-for --label vault-grant-broker --every 0.1 --until "test -S '$FLEET_VAULT_SOCKET' && test -s '$W/state/port'" >/dev/null
}
start_broker
log() { python3 -I -c 'import json,sys; [print(json.dumps(json.loads(l), sort_keys=True)) for l in open(sys.argv[1])]' "$W/state/uses.jsonl"; }

# 3. `secret leases`: one lease per granted name, as FLEET_LEASE_<NAME>=<id>; critical and unknown names refused.
printf '# T9 brief\nSecrets: selftest-free, selftest-card, nope\nAI image grant: "hazme una imagen con IA de un mago"\n' >"$W/brief.md"
out=$("$S" leases --from "$W/brief.md" --ticket T9 --ttl 600 2>"$W/leases.err"); rc=$?
is "leases: exit 3 when any name is refused" "$rc" 3
is "leases: free and the image grant leased, in line order" "$(cut -d= -f1 <<<"$out" | tr '\n' ' ')" \
   "FLEET_LEASE_SELFTEST_FREE FLEET_LEASE_OPENROUTER "
ev "leases: critical and unknown names named on stderr, no lease" \
   'grep -q "no lease on selftest-card: .*critical" "$W/leases.err" && grep -q "no lease on nope: nope is not in the vault" "$W/leases.err"'
L1=$(sed -n 's/^FLEET_LEASE_SELFTEST_FREE=//p' <<<"$out")
is "leases: ids are long random tokens" "$(( ${#L1} >= 32 ))" 1
ev "leases: the image lease carries the brief's quote as the asked words" \
   'log | grep "\"secret\": \"openrouter\"" | grep -q "\"asked\": \"hazme una imagen con IA de un mago\""'
printf 'nothing to grant here\n' >"$W/none.md"
is "leases: a brief with no Secrets line asks nothing and exits 0" "$("$S" leases --from "$W/none.md" --ticket T9; echo "rc=$?")" "rc=0"

# 4. A grant asked from inside an agent (its pid in agents.slice): refused, logged with the unit, raised once.
python3 -I - "$A/lib" "$FLEET_VAULT_SOCKET" "$SLICE/run-fx.scope/cgroup.procs" >"$W/inside.out" <<'EOF'
import os, sys; sys.path.insert(0, sys.argv[1]); from vault import wire
open(sys.argv[3], "w").write(f"{os.getpid()}\n")
r = wire.call(sys.argv[2], {"op": "grant", "name": "selftest-free", "ticket": "T9"})
print(r.get("ok"), r.get("raise"), "lease" in r)
EOF
is "inside an agent: the broker refuses, flags raise, gives no lease" "$(cat "$W/inside.out")" "False True False"
: >"$SLICE/run-fx.scope/cgroup.procs"
bash -c 'echo $$ >"$1"; exec env AGENT_NAME=fx-worker "$2" grant selftest-free --ticket T9' _ "$SLICE/run-fx.scope/cgroup.procs" "$S" \
  >"$W/cli.out" 2>"$W/cli.err"; rc=$?
: >"$SLICE/run-fx.scope/cgroup.procs"
is "inside an agent: \`secret grant\` exits 1 and prints no lease" "$rc $(wc -c <"$W/cli.out")" "1 0"
ev "inside an agent: the refusal says why" 'grep -q "asked from inside an agent (run-fx.scope)" "$W/cli.err"'
is "inside an agent: raised once to the owner, with the agent and ticket" "$(grep -c . "$W/raise.log")" 1
ev "raise: one line naming the agent, the secret and the ticket" 'grep -qx "vault: fx-worker asked a lease on selftest-free (T9) from inside an agent; refused. Grants come from a brief.s Secrets: line." "$W/raise.log"'
is "inside an agent: 2 refusals logged with the unit as target" \
   "$(log | grep '"target": "run-fx.scope"' | grep -c '"result": "refused"')" 2
is "outside an agent the same grant is given" "$("$S" grant selftest-free --ticket T9 2>/dev/null | wc -c | awk '{print ($1 > 32)}')" 1
is "no lease id in the broker's log or stdout of the broker" "$(grep -c -F "$L1" "$W/state/uses.jsonl" "$W/d.out" | awk -F: '{s+=$2} END {print s}')" 0

# 5. Leases survive a broker restart; revoke from stdin.
kill "$BROKER"; wait "$BROKER" 2>/dev/null; rm -f "$FLEET_VAULT_SOCKET" "$W/state/port"
start_broker
is "restart: the lease minted before still lets a revoke find it" "$(printf '%s\n' "$L1" | "$S" revoke - 2>&1)" "secret: lease revoked"
is "restart: a revoked lease is gone" "$(printf '%s\n' "$L1" | "$S" revoke - 2>&1)" "secret: no such lease"
ev "state: leases.json is mode 600" '[ "$(stat -c %a "$W/state/leases.json")" = 600 ]'

# 6. agent-exec --secrets-from: leases asked before the agent, exported to it by name, revoked when it ends.
printf 'Secrets: selftest-free\n' >"$W/agent-brief.md"; printf 'do it' >"$W/p.md"; mkdir -p "$W/cwd"
seen="$W/agent.seen"
HARNESS_AGENT=generic HARNESS_AGENT_CMD="sh -c 'echo \${FLEET_LEASE_SELFTEST_FREE:+has-lease} >\"$seen\"; \
  printf %s \"\$FLEET_LEASE_SELFTEST_FREE\" >\"$W/agent.lease\"'" \
  "$A/bin/agent-exec" --prompt-file "$W/p.md" --cwd "$W/cwd" --name fx-agent --ticket T77 --timeout 60 \
  --secrets-from "$W/agent-brief.md" --raw-out "$W/raw" --meta-out "$W/meta.json" >/dev/null 2>"$W/ae.err"; rc=$?
is "agent-exec: exit 0" "$rc" 0
is "agent-exec: the agent sees FLEET_LEASE_SELFTEST_FREE" "$(cat "$seen" 2>/dev/null)" has-lease
ev "agent-exec: lease asked for ticket T77" \
   'log | grep "\"event\": \"grant\"" | grep "\"ticket\": \"T77\"" | grep -q "\"result\": \"ok\""'
is "agent-exec: the lease is revoked when the agent ends" "$(printf '%s\n' "$(cat "$W/agent.lease")" | "$S" revoke - 2>&1)" "secret: no such lease"
printf 'AI image grant: "hazme una imagen con IA del faro"\n' >"$W/image-brief.md"
HARNESS_AGENT=generic HARNESS_AGENT_CMD="sh -c 'echo \${FLEET_LEASE_OPENROUTER:+has-lease} >\"$W/image.seen\"'" \
  "$A/bin/agent-exec" --prompt-file "$W/p.md" --cwd "$W/cwd" --name fx-img --ticket T79 --timeout 60 \
  --secrets-from "$W/image-brief.md" --raw-out "$W/raw4" --meta-out "$W/meta4.json" >/dev/null 2>&1
is "agent-exec: a brief with only \`AI image grant:\` gives the agent FLEET_LEASE_OPENROUTER" "$(cat "$W/image.seen" 2>/dev/null)" has-lease
ev "agent-exec: that grant is logged for T79 with the quote as the asked words" \
   'log | grep "\"ticket\": \"T79\"" | grep "\"secret\": \"openrouter\"" | grep "\"result\": \"ok\"" | grep -q "\"asked\": \"hazme una imagen con IA del faro\""'
n=$(log | grep -c '"event": "grant"')
HARNESS_AGENT=generic HARNESS_AGENT_CMD='true' "$A/bin/agent-exec" --prompt-file "$W/p.md" --cwd "$W/cwd" --name fx \
  --secrets-from "$W/none.md" --raw-out "$W/raw2" --meta-out "$W/meta2.json" >/dev/null 2>&1
is "agent-exec: a brief without the line asks the vault nothing" "$(log | grep -c '"event": "grant"')" "$n"
"$A/bin/agent-exec" --prompt-file "$W/p.md" --secrets-from "$W/missing.md" >/dev/null 2>&1
is "agent-exec: an unreadable --secrets-from is a usage error" "$?" 2
# The agent's own tool call asking a lease: refused and raised (its pid is in the fixture agents.slice).
HARNESS_AGENT=generic HARNESS_AGENT_CMD="sh -c 'echo \$\$ >\"$SLICE/run-fx.scope/cgroup.procs\"; exec \"$S\" grant selftest-free --ticket T78'" \
  "$A/bin/agent-exec" --prompt-file "$W/p.md" --cwd "$W/cwd" --name fx-self --raw-out "$W/raw3" --meta-out "$W/meta3.json" >/dev/null 2>&1
: >"$SLICE/run-fx.scope/cgroup.procs"
ev "agent-exec: the agent's own \`secret grant\` is refused and raised" \
   'log | grep "\"ticket\": \"T78\"" | grep -q "\"result\": \"refused\"" && grep -q "asked a lease on selftest-free (T78)" "$W/raise.log"'
ev "agent-exec: the lease id is in no output of agent-exec (stdout, stderr, raw)" '! grep -qF "$(cat "$W/agent.lease")" "$W/ae.err" "$W/raw"'

# 7. The liaison job's grant file: only a message that asks for an AI image writes the grant line.
gf=$(python3 -I - "$A/discord-liaison" "$W" <<'EOF'
import os, sys; sys.path[:0] = [sys.argv[1], os.path.join(os.path.dirname(sys.argv[1]), "discord-bot")]; w = sys.argv[2]
from liaison.cli import App
class J: dir = f"{w}/jobs"
os.makedirs(f"{w}/jobs/j1", exist_ok=True)
app = App.__new__(App); app.jobs = J()
p = app.grant_file({"id": "j1"}, ["hazme una imagen\n con IA de un dragón"]); a = open(p).read()
p = app.grant_file({"id": "j1"}, []); b = open(p).read()
print(repr(a), repr(b))
EOF
)
is "liaison: grant file = the asking message's words; rewritten empty when none asks" "$gf" \
   "'AI image grant: \"hazme una imagen con IA de un dragón\"\\n' ''"
ev "liaison: the default worker command hands the grant file and the job id to agent-exec" \
   'grep -q -- "--secrets-from {secrets} --ticket {id}" "$A/discord-liaison/liaison/cli.py"'

# 8. brief-lint knows the line: names the vault would refuse are warned about; a clean line is quiet.
printf 'CHECK: true\nFILE-CLAIMS\nReport: max 6 lines\ntest changes\nSecrets: selftest-free, selftest-card, nope, Bad X, openrouter\n' >"$W/lint.md"
lint=$(FLEET_VAULT_SOCKET="$W/none.sock" "$A/bin/brief-lint" "$W/lint.md" 2>&1)
ev "brief-lint: critical, unknown, malformed and ruled-without-words are warned" \
   'grep -q "selftest-card is class critical" <<<"$lint" && grep -q "nope is not in the vault" <<<"$lint" && grep -q "\"Bad X\" on the Secrets: line is not a vault name" <<<"$lint" && grep -q "openrouter is class ruled" <<<"$lint"'
is "brief-lint: a free name raises no warning" "$(grep -c 'selftest-free' <<<"$lint")" 0

exit $bad
