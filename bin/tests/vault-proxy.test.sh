#!/usr/bin/env bash
# T1634-V3: proxy mode and leases on fixtures: a repo fleet-vaultd on a temp state, a fake value, a fake upstream on
# loopback; concept-img through a lease; refusals (no lease, other secret, expired, path, method, rules, critical, caps);
# no redirect followed; the value never reaches the agent, a log or an output. Last: the image key's 5 routes on the
# live machine, read-only (the old file, the sealed store), never a value read.
set -uo pipefail
A=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
W=$(mktemp -d); PIDS=()
trap 'for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$W"' EXIT
. "$A/bin/tests/lib/assert.sh"
me=$(id -un)
VALUE="fixture-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"   # fake, random, never a real secret
export FLEET_VAULT_SOCKET="$W/run/admin.sock" FLEET_VAULT_REGISTRY="$W/registry.toml" NO_PROXY=127.0.0.1 no_proxy=127.0.0.1
export HARNESS_CONFIG=/dev/null CONCEPT_IMG_LEDGER="$W/ledger.tsv" CONCEPT_IMG_NOTIFY=true
unset OPENROUTER_KEY_FILE FLEET_LEASE_OPENROUTER CONCEPT_IMG_JOB_CAP CONCEPT_IMG_MONTH_CAP CONCEPT_IMG_API
mkdir -p "$W/run" "$W/state" "$W/store" "$W/creds"; chmod 700 "$W/store"
S="$A/bin/secret"; ASK='hazme una imagen con IA de un mago'

# 0. Selftest: every path the broker and the client use is a fixture.
for p in "$FLEET_VAULT_SOCKET" "$FLEET_VAULT_REGISTRY" "$W/store" "$W/state" "$W/creds"; do
  case "$p" in "$W"/*) ;; *) echo "FAIL selftest: $p is outside the fixture"; exit 1 ;; esac
done
ok "selftest: socket, registry, store, state and credentials are fixtures ($W)"

# 1. Units: leases, path filter, grant policy on the shipped registry.
unit=$(python3 -I - "$A/lib" "$A/vault/registry.toml" <<'EOF'
import sys; sys.path.insert(0, sys.argv[1])
from vault import registry; from vault.leases import Leases, LeaseError; from vault.proxy import allowed_path
from vault.grants import refusal
t = [0.0]; L = Leases(clock=lambda: t[0]); r = []
a = L.mint("openrouter", "T1", 10, cap=1.0)
r.append(L.check(a.id, "openrouter") is a)
for lid, sec in ((a.id, "ntfy"), ("nope", "openrouter")):
    try: L.check(lid, sec); r.append(False)
    except LeaseError: r.append(True)
L.charge(a.id, 1.0)
try: L.check(a.id, "openrouter"); r.append(False)
except LeaseError as e: r.append("cap" in str(e))
b = L.mint("openrouter", "T1", 10); t[0] = 11
try: L.check(b.id, "openrouter"); r.append(False)
except LeaseError as e: r.append("expired" in str(e))
for ttl in (0, 86401):
    try: L.mint("x", "T1", ttl); r.append(False)
    except LeaseError: r.append(True)
c = L.mint("x", "T1", 5); r.append(L.revoke(c.id) and not L.revoke(c.id))
r.append(len({L.mint("x", "T", 5).id for _ in range(50)}) == 50 and len(a.id) >= 32)
print(" ".join("1" if x else "0" for x in r))
P = ("/api/v1/",)
print(" ".join("1" if allowed_path(p, P) else "0" for p in
      ("/api/v1/key", "/api/v1/images", "/api/v2/key", "/api/v1/../v2/x", "/api/v1/%2e%2e/x", "/api/v1//x", "/x")))
e = registry.load(sys.argv[2])
print(refusal(e["openrouter"], {"asked": "hazme una imagen con IA"}), "|", bool(refusal(e["openrouter"], {})), "|",
      bool(refusal(e["openrouter"], {"asked": "dibuja una representación de ti"})), "|",
      e["openrouter"].cap_usd, e["openrouter"].month_cap_usd, e["openrouter"].cost)
EOF
)
is "leases: check, other secret, unknown, cap, expired, ttl 0 and >24h, revoke once, 50 unique ids" \
   "$(sed -n 1p <<<"$unit")" "1 1 1 1 1 1 1 1 1"
is "paths: /api/v1/ allowed; v2, dot segments (plain and %2e), empty segment, outside refused" \
   "$(sed -n 2p <<<"$unit")" "1 1 0 0 0 0 0"
is "policy: openrouter (ruled) needs the requester's words for an AI image; caps 2 and 10 USD; cost at usage.cost" \
   "$(sed -n 3p <<<"$unit")" "None | True | True | 2.0 10.0 usage.cost"

# 2. Fake upstream: records each call and whether the right credential came with it; echoes it on /echo.
printf '%s' "$VALUE" >"$W/creds/fleet.openrouter"; printf '%s' "$VALUE" >"$W/creds/fleet.selftest-card"
cat >"$W/up.py" <<'PY'
import base64, http.server, json, sys
w = sys.argv[1]; want = "Bearer " + open(f"{w}/creds/fleet.openrouter").read(); state = {"usage": 1.0}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, obj, extra=()):
        b = json.dumps(obj).encode(); self.send_response(code)
        for k, v in extra: self.send_header(k, v)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def note(self):
        open(f"{w}/up.log", "a").write(f"{self.command} {self.path} {self.headers.get('Authorization') == want}\n")
    def do_GET(self):
        self.note()
        if self.path == "/api/v1/echo": return self.reply(200, {"auth": self.headers.get("Authorization")})
        if self.path == "/api/v1/redirect": return self.reply(302, {}, [("Location", "http://127.0.0.1:9/evil")])
        self.reply(200, {"data": {"usage": state["usage"]}})
    def do_POST(self):
        self.note(); self.rfile.read(int(self.headers["Content-Length"])); state["usage"] += 0.12
        self.reply(200, {"data": [{"b64_json": base64.b64encode(b"\x89PNG\r\n\x1a\nmock").decode()}], "usage": {"cost": 0.12}})
s = http.server.HTTPServer(("127.0.0.1", 0), H); open(f"{w}/up.port", "w").write(str(s.server_port)); s.serve_forever()
PY
python3 -I "$W/up.py" "$W" & PIDS+=($!)
cat >"$W/fake-creds" <<'EOF'
#!/bin/sh
printf 'FAKESEAL %s\n' "${3#--name=}" >"$5"
EOF
chmod +x "$W/fake-creds"
for n in openrouter selftest-card; do printf 'FAKESEAL fleet.%s\n' "$n" >"$W/store/fleet.$n"; done
systemd-socket-activate -l "$W/seal.sock" --inetd -a \
  python3 -I "$A/vault/fleet-vault-seal" --store "$W/store" --creds-bin "$W/fake-creds" --peer "$me" 2>/dev/null &
PIDS+=($!)
cp "$A/vault/registry.toml" "$W/registry.toml"
printf '\n[secret.selftest-card]\nclass = "critical"\nused_in = "fixture card"\nmodes = ["proxy"]\nhosts = ["example.org"]\npaths = ["/"]\n' >>"$W/registry.toml"
wait-for --label vault-proxy-up --every 0.1 --until "test -s '$W/up.port' && test -S '$W/seal.sock'" >/dev/null
python3 -I "$A/vault/fleet-vaultd" --registry "$W/registry.toml" --state "$W/state" --socket "$FLEET_VAULT_SOCKET" \
  --seal-socket "$W/seal.sock" --cred-dir "$W/creds" --clients "$me" --upstream "http://127.0.0.1:$(cat "$W/up.port")" \
  --cgroup-root "$W/cg" >"$W/d.out" 2>&1 &
PIDS+=($!)
wait-for --label vault-proxy-broker --every 0.1 --until "test -S '$FLEET_VAULT_SOCKET' && test -s '$W/state/port'" >/dev/null
export FLEET_VAULT_URL="http://127.0.0.1:$(cat "$W/state/port")"
[[ $FLEET_VAULT_URL =~ ^http://127.0.0.1:[0-9]+$ ]] && ok "broker: listens on loopback only ($FLEET_VAULT_URL)" || nok broker "$FLEET_VAULT_URL"
code() { curl -s -o "$W/body" -w '%{http_code}' --noproxy '*' "$@"; }

# 3. Grants through `secret grant`.
L1=$("$S" grant openrouter --ticket T9001 --asked "$ASK" 2>"$W/g1"); r1=$?
"$S" grant openrouter --ticket T9001 >"$W/g2" 2>&1; r2=$?
"$S" grant openrouter --ticket T9001 --asked 'dibuja una representación de ti' >"$W/g3" 2>&1; r3=$?
"$S" grant selftest-card --ticket T9001 >"$W/g4" 2>&1; r4=$?
"$S" grant openrouter --asked "$ASK" >"$W/g5" 2>&1; r5=$?
LF=$("$S" grant discord-bot-token --ticket T9001 2>/dev/null); r6=$?
is "grant: ruled with words 0, without 1, non-AI words 1, critical 1, no ticket 2, free 0" "$r1 $r2 $r3 $r4 $r5 $r6" "0 1 1 1 2 0"
ev "grant: refusals say why (outside its rules / critical approval)" \
   'grep -q "outside its rules: ask the orchestrator or the owner" "$W/g2" && grep -q "approval" "$W/g4"'
ev "grant: the lease is one token, the cap 2.00 USD comes from the registry" \
   '[[ $L1 =~ ^[A-Za-z0-9_-]{32,}$ ]] && grep -q "cap 2.00 USD" "$W/g1"'

# 4. concept-img through the lease: the image arrives, the upstream got the credential, the agent never held it.
FLEET_LEASE_OPENROUTER="$L1" "$A/bin/concept-img" --asked "$ASK" --model m/x --prompt 'a wizard' --out "$W/a.png" \
  --log "$W/s.tsv" >"$W/c1" 2>&1
is "concept-img + lease: exit 0, PNG written" "$? $(head -c 4 "$W/a.png" 2>/dev/null | tail -c 3)" "0 PNG"
is "upstream: key, image, key calls each carried the credential" "$(cut -d' ' -f1,3 "$W/up.log" | tr '\n' ' ')" \
   "GET True POST True GET True "
n=$(wc -l <"$W/up.log")
"$A/bin/concept-img" --asked "$ASK" --model m/x --prompt 'p' --out "$W/b.png" --log "$W/s.tsv" >/dev/null 2>&1
is "concept-img without a lease or key file: exit 4, no upstream call" "$? $(wc -l <"$W/up.log")" "4 $n"
FLEET_LEASE_OPENROUTER=not-a-lease "$A/bin/concept-img" --asked "$ASK" --model m/x --prompt 'p' --out "$W/b.png" \
  --log "$W/s.tsv" >/dev/null 2>&1
is "concept-img with a forged lease: exit 4 (403), no upstream call" "$? $(wc -l <"$W/up.log")" "4 $n"

# 5. The listener's refusals; nothing reaches the upstream.
is "no lease, forged lease, other secret's lease: 404 403 403" \
   "$(code "$FLEET_VAULT_URL/"; echo -n ' '; code "$FLEET_VAULT_URL/x/openrouter/api/v1/key"; echo -n ' '; code "$FLEET_VAULT_URL/$LF/openrouter/api/v1/key")" \
   "404 403 403"
is "path outside the list, dot segments, PUT: 403 403 405" \
   "$(code "$FLEET_VAULT_URL/$L1/openrouter/api/v2/key"; echo -n ' '; code --path-as-is "$FLEET_VAULT_URL/$L1/openrouter/api/v1/../v2/x"; echo -n ' '; code -X PUT "$FLEET_VAULT_URL/$L1/openrouter/api/v1/key")" \
   "403 403 405"
is "refusals: no upstream call" "$(wc -l <"$W/up.log")" "$n"
is "redirect: passed back, not followed, no Location" \
   "$(curl -s -D - -o /dev/null --noproxy '*' "$FLEET_VAULT_URL/$L1/openrouter/api/v1/redirect" | grep -ci '^location' ; grep -c evil "$W/up.log")" "$(printf '0\n0')"
code "$FLEET_VAULT_URL/$L1/openrouter/api/v1/echo" >/dev/null
ev "echo: an answer that repeats the credential comes back redacted" 'grep -q "Bearer \[redacted\]" "$W/body" && ! grep -qF "$VALUE" "$W/body"'
LX=$("$S" grant openrouter --ticket T9002 --ttl 1 --asked "$ASK" 2>/dev/null); sleep 1.2
is "expired lease: 403" "$(code "$FLEET_VAULT_URL/$LX/openrouter/api/v1/key")" 403
"$S" revoke "$LF" >/dev/null 2>&1; rv1=$?; "$S" revoke "$LF" >/dev/null 2>&1; rv2=$?
is "revoke: once 0, again 1; a revoked lease: 403" "$rv1 $rv2 $(code "$FLEET_VAULT_URL/$LF/discord-bot-token/api/x")" "0 1 403"

# 6. Caps: the lease cap (0.12 per image), then the month cap from the broker's own log.
LC=$("$S" grant openrouter --ticket T9003 --cap 0.1 --asked "$ASK" 2>/dev/null)
c1=$(code -X POST -H 'Content-Type: application/json' -d '{}' "$FLEET_VAULT_URL/$LC/openrouter/api/v1/images")
c2=$(code -X POST -H 'Content-Type: application/json' -d '{}' "$FLEET_VAULT_URL/$LC/openrouter/api/v1/images")
is "lease cap 0.10: first image 200, second 403" "$c1 $c2" "200 403"
printf '{"ts":%s,"event":"use","secret":"openrouter","result":"ok","cost":9.9}\n' "$(date +%s)" >>"$W/state/uses.jsonl"
LM=$("$S" grant openrouter --ticket T9004 --asked "$ASK" 2>/dev/null)
is "month cap 10 USD: refused once the month's logged cost reaches it" "$(code "$FLEET_VAULT_URL/$LM/openrouter/api/v1/key")" 403

# 7. The log and the list: uses, refusals and last use, never a value or a full lease id.
lg=$("$S" log -n 200 2>&1)
ev "log: grant ok and refused, use ok with ticket and cost, use refused with why" \
   'grep -qE "grant +openrouter +ok" <<<"$lg" && grep -qE "grant +openrouter +refused" <<<"$lg" && grep -qE "use +openrouter +ok +ticket=T9001.*cost=0.12" <<<"$lg" && grep -qE "use +openrouter +refused.*why=lease cap" <<<"$lg"'
last=$("$S" list --json | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin) if x["name"]=="openrouter"][0]; print(r["state"], r["last_used"] is not None, r["uses_7d"] >= 4, r["refusals_7d"] >= 3)')
is "list: openrouter sealed, last use set, uses and refusals counted" "$last" "sealed True True True"
all="$lg$(cat "$W"/g? "$W/c1" "$W/d.out" "$W/state/uses.jsonl" "$W/s.tsv" "$W/ledger.tsv")"
ev "values: the fake value never in an output, a log or the spend files" '! grep -qF "$VALUE" <<<"$all"'
ev "leases: no full lease id in the broker's log or output" '! grep -qF -e "$L1" -e "$LC" -e "$LM" "$W/state/uses.jsonl" "$W/d.out"'

# 8. Live, read-only: the image key's 5 routes for this user (only once the vault is installed).
if [ -r /etc/fleet-vault/registry.toml ]; then
  K="${HARNESS_HOME:-$HOME/agents}/secrets/openrouter.key"; C=/etc/credstore.encrypted/fleet.openrouter
  r_cat=$(cat "$K" 2>/dev/null | wc -c); r_py=$(python3 -c 'import sys; print(len(open(sys.argv[1], "rb").read()))' "$K" 2>/dev/null || echo 0)
  r_cp=$(cp "$K" "$W/copy" 2>/dev/null && wc -c <"$W/copy" || echo 0)
  r_run=$(timeout 30 systemd-run --user --quiet --wait --pipe --collect cat "$C" 2>/dev/null </dev/null | wc -c)
  r_creds=$(systemd-creds decrypt --name=fleet.openrouter "$C" - 2>/dev/null </dev/null | wc -c)
  is "live: the image key reads 0 bytes by cat, python, copy, systemd-run --user, systemd-creds" \
     "$r_cat $r_py $r_cp $r_run $r_creds" "0 0 0 0 0"
else
  echo "skip live: the vault is not installed here"
fi
exit $bad
