#!/usr/bin/env bash
# T1515-P2: org.json + lib/org.py (seats, parent, may_assign) and lib/sessions.py (live registry, protected rows = 3 keys)
# on a fixture registry in the 2.1.321 format, a fixture org file and a fixture protected config; nothing real is read.
set -uo pipefail
AG=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
WORK=$(mktemp -d); PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null; rm -rf "$WORK"' EXIT
. "$AG/bin/tests/lib/assert.sh"
unset PROTECTED_PROJECTS WORK_REPO_ROOTS PC_NOT_OURS HARNESS_ENV_LOADED ORG_FILE CLAUDE_SESSIONS_DIR
H="$WORK/home"; mkdir -p "$H/agents/po-fx" "$H/agents/job" "$H/acme/sub" "$WORK/reg"
ln -s "$H/acme/sub" "$H/link-to-acme"
export HARNESS_CONFIG="$WORK/config.env"
printf 'PROTECTED_PROJECTS="acme"\nPROTECTED_ACME_PATHS="%s/acme"\n' "$H" >"$HARNESS_CONFIG"

for _ in 1 2 3 4 5 6; do tail -f /dev/null & PIDS+=($!); done
bash -c 'exit 0' & dead=$!; wait "$dead"

python3 - "$AG" "$H" "$WORK" "$dead" "${PIDS[@]}" <<'PY'
import json, os, sys
ag, home, work, dead, *live = sys.argv[1:]
live = [int(p) for p in live]
tpl = json.load(open(f"{ag}/bin/tests/fixtures/sessions/registry-2.1.321.json"))
start = lambda pid: open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[19]
def put(pid, cwd, status="busy", ps=None, **kw):
    d = dict(tpl, pid=pid, cwd=cwd, procStart=ps or start(pid), status=status, statusUpdatedAt=1794261588030, **kw)
    json.dump({k: v for k, v in d.items() if v is not None}, open(f"{work}/reg/{pid}.json", "w"))
put(live[0], home, "busy", name="Orchestrator session", entrypoint="cli")
put(live[1], f"{home}/agents/po-fx", "idle", name="agent-po-fx")
put(live[2], f"{home}/agents/job", "busy", name="agent-fx-job")
put(live[3], f"{home}/acme/sub", "busy", name="secret client work")
put(live[4], f"{home}/link-to-acme", "idle", name="via a symlink")
put(live[5], f"{home}/agents/job", "busy", ps="1", name="pid reused")
put(int(dead), home, "busy", ps="1", name="ended")
put(live[1] + 900000, home, ps="1", name=None)
open(f"{work}/reg/broken.json", "w").write("{not json")
open(f"{work}/reg/{live[0]}.key", "w").write("not a session")
PY

cat >"$WORK/org.json" <<'EOF'
{"seats": [
  {"id": "owner", "name": "You", "role": "owner", "parent": null, "wake": null, "match": null},
  {"id": "ceo", "name": "Orchestrator", "role": "ceo", "parent": "owner", "wake": "channel", "match": "~"},
  {"id": "fx", "name": "Fx owner", "role": "po", "parent": "ceo", "wake": "po-inbox", "match": "~/agents/po-fx"},
  {"id": "gx", "name": "Gx owner", "role": "po", "parent": "ceo", "wake": "po-inbox", "match": "~/agents/po-gx"},
  {"id": "acme", "name": "Acme seat", "role": "po", "parent": "ceo", "wake": "pull", "match": null}
]}
EOF

HOME="$H" ORG_FILE="$WORK/org.json" CLAUDE_SESSIONS_DIR="$WORK/reg" python3 - "$AG" "$WORK" <<'PY'
import json, os, sys
ag, work = sys.argv[1:]
sys.path.insert(0, f"{ag}/lib")
import org, sessions
bad = 0
def check(name, cond, got=""):
    global bad
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {got}"))
    bad |= not cond

check("selftest: org file is the fixture", org.path() == f"{work}/org.json", org.path())
check("selftest: registry is the fixture", sessions.registry_dir() == f"{work}/reg", sessions.registry_dir())
ids = [s["id"] for s in org.seats()]
check("org: 5 seats in file order", ids == ["owner", "ceo", "fx", "gx", "acme"], ids)
check("org: parent of a po is the ceo", org.parent("fx") == "ceo")
check("org: owner has no parent", org.parent("owner") is None)
check("org: unknown seat has no parent", org.parent("nobody") is None)
for a, b, want in [("owner", "fx", True), ("owner", "ceo", True), ("ceo", "fx", True), ("fx", "gx", False),
                   ("fx", "ceo", False), ("ceo", "owner", False), ("ceo", "ceo", False), ("nobody", "fx", False)]:
    check(f"org: may_assign({a}, {b}) is {want}", org.may_assign(a, b) is want)

def invalid(name, seats, word):
    p = f"{work}/bad.json"; json.dump({"seats": seats}, open(p, "w"))
    try:
        org.seats(p); check(f"org invalid: {name}", False, "accepted")
    except ValueError as e:
        check(f"org invalid: {name}", word in str(e), str(e))
O = {"id": "owner", "name": "You", "role": "owner", "parent": None, "wake": None, "match": None}
C = {"id": "ceo", "name": "C", "role": "ceo", "parent": "owner", "wake": "channel", "match": "~"}
invalid("duplicate id", [O, C, dict(C)], "duplicate")
invalid("unknown parent", [O, dict(C, parent="ghost")], "parent")
invalid("bad role", [O, dict(C, role="king")], "role")
invalid("bad wake", [O, dict(C, wake="shout")], "wake")
invalid("two owners", [O, dict(O, id="o2")], "owner")
invalid("parent cycle", [O, dict(C, parent="po"), dict(C, id="po", role="po", parent="ceo", match="~/x")], "cycle")
invalid("missing key", [O, {k: v for k, v in C.items() if k != "match"}], "match")
invalid("machine path in match", [O, dict(C, match="/" + "home/someone/x")], "match")

rows = sessions.live()
by = {r.get("name"): r for r in rows}
check("live: 5 sessions (dead pid, reused pid, missing pid file, broken json dropped)", len(rows) == 5, [r.get("name") for r in rows])
o = by.get("Orchestrator session", {})
check("live: orchestrator by exact folder", o.get("seat") == "ceo" and o.get("parent") == "owner", o)
check("live: busy is working", o.get("state") == "working", o)
check("live: since is seconds", o.get("since") == 1794261588, o)
check("live: terminal session started_by owner", o.get("started_by") == "owner", o)
check("live: session keys", set(o) == {"pid", "seat", "parent", "name", "cwd", "state", "since", "started_by"}, sorted(o))
p = by.get("agent-po-fx", {})
check("live: po seat, idle, started by agent-run", (p.get("seat"), p.get("parent"), p.get("state"), p.get("started_by")) == ("fx", "ceo", "idle", "po-fx"), p)
j = by.get("agent-fx-job", {})
check("live: seatless job: no seat, parent = deepest seat folder", j.get("seat") is None and j.get("parent") == "ceo", j)
prot = [r for r in rows if "name" not in r]
check("live: 2 protected rows (one via symlink)", len(prot) == 2, rows)
check("live: protected row has exactly 3 keys", all(set(r) == {"seat", "state", "since"} for r in prot), prot)
check("live: protected rows carry the pull seat named after the project (on/off only)", [r["seat"] for r in prot] == ["acme", "acme"], prot)
bare = json.dumps([{k: v for k, v in r.items() if k != "seat"} for r in rows])
check("live: no protected text anywhere", "secret client" not in bare and "acme" not in bare and "symlink" not in bare, rows)
off = sessions.live(seats=[s for s in org.seats() if s["id"] != "acme"])
check("live: no pull seat: protected rows have no seat", [r["seat"] for r in off if "name" not in r] == [None, None], off)

import protectedlib
def boom(kind): raise RuntimeError("matcher down")
protectedlib.eres = boom
rows = sessions.live()
check("live: matcher error strips every row (fail closed)", len(rows) == 5 and all(set(r) == {"seat", "state", "since"} for r in rows), rows)
check("live: missing registry dir gives []", sessions.live(f"{work}/nope") == [])
check("locate: matcher down fails closed, no resolve", sessions.locate("/x/../y", None) == ("", "/y"))
sys.exit(bad)
PY
rc=$?; [ $rc = 0 ] || bad=1

# T1515-P20: on/off of a pull seat opens, lists and stats nothing in its protected folder (registry + /proc only);
# the only syscalls naming the folder are the shared matcher's `readlink -m` of its own config entry.
mkdir -p "$WORK/reg2"; tail -f /dev/null & PIDS+=($!)
python3 - "$AG" "$H" "$WORK" "${PIDS[-1]}" "${PIDS[0]}" <<'PY'
import json, sys
ag, home, work, *pids = sys.argv[1:]
tpl = json.load(open(f"{ag}/bin/tests/fixtures/sessions/registry-2.1.321.json"))
for pid, cwd in zip(map(int, pids), (f"{home}/acme/sub", home)):
    st = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[19]
    json.dump(dict(tpl, pid=pid, cwd=cwd, procStart=st, status="busy", name="n"), open(f"{work}/reg2/{pid}.json", "w"))
PY
out=$(HOME="$H" ORG_FILE="$WORK/org.json" CLAUDE_SESSIONS_DIR="$WORK/reg2" strace -f -y -qq -o "$WORK/trace" \
  -e trace=%file,getdents64,fchdir python3 -c "import sys; sys.path.insert(0, '$AG/lib'); import sessions; print([r['seat'] for r in sessions.live()])")
is "pull seat: on from the registry (acme on, ceo on)" "$out" "['ceo', 'acme']"
is "pull seat: no open, list or stat of the protected folder, no container runtime" \
  "$(python3 "$AG/bin/tests/lib/no_touch.py" "$WORK/trace" "$H/acme")" ""
ev "selftest: the trace saw the registry" 'grep -q "$WORK/reg2" "$WORK/trace"'
strace -f -y -qq -o "$WORK/trace-bad" -e trace=%file,getdents64,fchdir python3 -c "import os; os.listdir('$H/acme')"
ev "selftest: no_touch flags a listing of the protected folder" \
  '[ -n "$(python3 "$AG/bin/tests/lib/no_touch.py" "$WORK/trace-bad" "$H/acme")" ]'

# The tracked org.json validates and carries no machine values.
python3 -c "import sys; sys.path.insert(0, '$AG/lib'); import org; s = org.seats('$AG/org.json'); assert {x['role'] for x in s} >= {'owner', 'ceo', 'po'}" \
  && ok "tracked org.json validates (owner, ceo, po)" || nok "tracked org.json" "invalid"
python3 -c "import sys; sys.path.insert(0, '$AG/lib'); import org; v = [s for s in org.seats('$AG/org.json') if s['id'] == 'vass']; assert v and v[0]['wake'] == 'pull' and v[0]['match'] is None and v[0]['parent'] == 'orchestrator'" 2>/dev/null \
  && ok "tracked org.json: vass seat is pull, no folder" || nok "tracked org.json" "no vass pull seat"
grep -q "$HOME" "$AG/org.json" && nok "tracked org.json" "contains \$HOME" || ok "tracked org.json has no home path"
exit $bad
