#!/usr/bin/env bash
# T1634-V9: exchange mode and the backup password by unit mode, on fixtures. A repo fleet-vaultd on a temp state, fake
# values, a fake SOAP login on loopback (never Salesforce): a lease buys a session token, never the password. A loopback
# vfat image as a fake stick: fleet-backup runs with the password from a fixture credentials dir (unit mode), falls
# back to the stick's key, never writes a password file. Last: the backup password's routes on the live machine,
# read-only, never a value read.
set -uo pipefail
A=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
W=$(mktemp -d); PIDS=(); LOOP=""
cleanup() {
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
  if [ -n "$LOOP" ]; then
    udisksctl unmount --no-user-interaction -b "$LOOP" >/dev/null 2>&1
    timeout 20 wait-for --label "V9 detach $LOOP" --every 1 --until "! losetup $LOOP >/dev/null 2>&1 || udisksctl loop-delete --no-user-interaction -b $LOOP >/dev/null 2>&1" >/dev/null
  fi
  rm -rf "$W"
}
trap cleanup EXIT
. "$A/bin/tests/lib/assert.sh"
me=$(id -un)
rnd() { head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
PASS="pw-$(rnd)<&>"; SID="sid-$(rnd)"; BPASS="bk-$(rnd)"   # fake, random, never a real secret
export FLEET_VAULT_SOCKET="$W/run/admin.sock" FLEET_VAULT_REGISTRY="$W/registry.toml" NO_PROXY=127.0.0.1 no_proxy=127.0.0.1
export HARNESS_CONFIG=/dev/null
mkdir -p "$W/run" "$W/state" "$W/store" "$W/creds" "$W/bcreds"; chmod 700 "$W/store"
S="$A/bin/secret"

# 0. Selftest: every path the broker, the client and the backup use is a fixture.
for p in "$FLEET_VAULT_SOCKET" "$FLEET_VAULT_REGISTRY" "$W/store" "$W/state" "$W/creds" "$W/bcreds"; do
  case "$p" in "$W"/*) ;; *) echo "FAIL selftest: $p is outside the fixture"; exit 1 ;; esac
done
ok "selftest: socket, registry, store, state and credentials are fixtures ($W)"

# 1. Units: value fields, the shipped registry rows, the grant policy.
unit=$(python3 -I - "$A/lib" "$A/vault/registry.toml" <<'EOF'
import sys; sys.path.insert(0, sys.argv[1])
from vault import registry; from vault.exchange import fields; from vault.grants import refusal
f = fields(b'# c\nSF_USERNAME="u@x"\nSF_PASSWORD=\'p=q\'\n\nnoeq\n')
print(f == {"SF_USERNAME": "u@x", "SF_PASSWORD": "p=q"})
e = registry.load(sys.argv[2]); s, b = e["salesforce"], e["fleet-backup-pass"]
print(s.cls, list(s.modes), list(s.hosts), s.paths[0].startswith("/services/Soap/u/"), refusal(s, {}))
print(b.cls, list(b.modes), bool(refusal(b, {})))
EOF
)
is "fields: KEY=value lines, quotes stripped, '=' inside a value kept, comments skipped" "$(sed -n 1p <<<"$unit")" True
is "registry: salesforce free, exchange, pinned login host and SOAP path, leased with no rule" "$(sed -n 2p <<<"$unit")" \
   "free ['exchange'] ['login.salesforce.com'] True None"
is "registry: fleet-backup-pass critical, unit mode, never leased" "$(sed -n 3p <<<"$unit")" "critical ['unit'] True"

# 2. Fake SOAP login: checks the credential, answers a session; one user gets a fault that echoes the password,
#    one a redirect. Records each call.
printf 'SF_INSTANCE_URL=https://x.example\nSF_LOGIN_URL=https://login.example\nSF_USERNAME=u1@fixture\nSF_PASSWORD=%s\n' "$PASS" >"$W/creds/fleet.selftest-sf"
printf 'SF_USERNAME=bad@fixture\nSF_PASSWORD=%s\n' "$PASS" >"$W/creds/fleet.selftest-sf-bad"
printf 'SF_USERNAME=moved@fixture\nSF_PASSWORD=%s\n' "$PASS" >"$W/creds/fleet.selftest-sf-302"
printf 'SF_USERNAME=u1@fixture\n' >"$W/creds/fleet.selftest-sf-nopw"
printf '%s' "$PASS" >"$W/pass"; printf '%s' "$SID" >"$W/sid"
cat >"$W/up.py" <<'PY'
import http.server, sys, xml.etree.ElementTree as ET
from xml.sax.saxutils import escape
w = sys.argv[1]; pw = open(f"{w}/pass").read(); sid = open(f"{w}/sid").read()
OK = ('<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="urn:partner.soap.sforce.com">'
      '<soapenv:Body><loginResponse><result><serverUrl>https://fixture.my.salesforce.com/services/Soap/u/59.0/00D</serverUrl>'
      '<sessionId>{sid}</sessionId><userInfo><sessionSecondsValid>7200</sessionSecondsValid></userInfo></result>'
      '</loginResponse></soapenv:Body></soapenv:Envelope>')
FAULT = ('<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"><soapenv:Body><soapenv:Fault>'
         '<faultcode>INVALID_LOGIN</faultcode><faultstring>INVALID_LOGIN: bad password {pw}</faultstring>'
         '</soapenv:Fault></soapenv:Body></soapenv:Envelope>')
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body, extra=()):
        b = body.encode(); self.send_response(code)
        for k, v in extra: self.send_header(k, v)
        self.send_header("Content-Type", "text/xml"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        x = ET.fromstring(self.rfile.read(int(self.headers["Content-Length"])))
        n = {"p": "urn:partner.soap.sforce.com"}
        u, p = x.find(".//p:username", n).text, x.find(".//p:password", n).text
        open(f"{w}/up.log", "a").write(f"POST {self.path} {self.headers.get('SOAPAction')} {u} {p == pw}\n")
        if u == "moved@fixture": return self.send(302, "", [("Location", "http://127.0.0.1:9/evil")])
        if u != "u1@fixture" or p != pw: return self.send(500, FAULT.format(pw=escape(pw)))
        self.send(200, OK.format(sid=sid))
    def do_GET(self):
        open(f"{w}/up.log", "a").write(f"GET {self.path}\n"); self.send(200, "<x/>")
s = http.server.HTTPServer(("127.0.0.1", 0), H); open(f"{w}/up.port", "w").write(str(s.server_port)); s.serve_forever()
PY
python3 -I "$W/up.py" "$W" & PIDS+=($!)
cat >"$W/fake-creds" <<'EOF'
#!/bin/sh
printf 'FAKESEAL %s\n' "${3#--name=}" >"$5"
EOF
chmod +x "$W/fake-creds"
for n in selftest-sf selftest-sf-bad selftest-sf-302 selftest-sf-nopw; do printf 'FAKESEAL fleet.%s\n' "$n" >"$W/store/fleet.$n"; done
systemd-socket-activate -l "$W/seal.sock" --inetd -a \
  python3 -I "$A/vault/fleet-vault-seal" --store "$W/store" --creds-bin "$W/fake-creds" --peer "$me" 2>/dev/null &
PIDS+=($!)
cp "$A/vault/registry.toml" "$W/registry.toml"
for n in selftest-sf selftest-sf-bad selftest-sf-302 selftest-sf-nopw; do
  printf '\n[secret.%s]\nclass = "free"\nused_in = "fixture org"\nmodes = ["exchange"]\nhosts = ["example.org"]\npaths = ["/services/Soap/u/59.0"]\n' "$n" >>"$W/registry.toml"
done
wait-for --label vault-exchange-up --every 0.1 --until "test -s '$W/up.port' && test -S '$W/seal.sock'" >/dev/null
python3 -I "$A/vault/fleet-vaultd" --registry "$W/registry.toml" --state "$W/state" --socket "$FLEET_VAULT_SOCKET" \
  --seal-socket "$W/seal.sock" --cred-dir "$W/creds" --clients "$me" --upstream "http://127.0.0.1:$(cat "$W/up.port")" \
  --cgroup-root "$W/cg" >"$W/d.out" 2>&1 &
PIDS+=($!)
wait-for --label vault-exchange-broker --every 0.1 --until "test -S '$FLEET_VAULT_SOCKET' && test -s '$W/state/port'" >/dev/null
U="http://127.0.0.1:$(cat "$W/state/port")"
code() { curl -s -o "$W/body" -w '%{http_code}' --noproxy '*' "$@"; }

# 3. A lease buys a session token: the upstream got the right user and password, the agent got only the session.
L=$("$S" grant selftest-sf --ticket T9101 2>/dev/null); rg=$?
c=$(code -X POST "$U/$L/selftest-sf/session")
sess=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("access_token") == sys.argv[2], d.get("instance_url"), d.get("expires_in"), sorted(d))' "$W/body" "$SID")
is "exchange: free grant 0, POST /session 200" "$rg $c" "0 200"
is "exchange: the session token, the instance URL, its lifetime; nothing else" "$sess" \
   "True https://fixture.my.salesforce.com 7200 ['access_token', 'expires_in', 'instance_url']"
is "upstream: one SOAP login to the pinned path with the sealed user and password" "$(cat "$W/up.log")" \
   "POST /services/Soap/u/59.0 login u1@fixture True"
ev "exchange: the password never in the answer" '! grep -qF "$PASS" "$W/body"'

# 4. Refusals: method, path, no lease, another secret's lease, a bad login, a redirect, a value without a password.
n=$(wc -l <"$W/up.log")
LB=$("$S" grant selftest-sf-bad --ticket T9101 2>/dev/null); L3=$("$S" grant selftest-sf-302 --ticket T9101 2>/dev/null)
LN=$("$S" grant selftest-sf-nopw --ticket T9101 2>/dev/null)
is "GET /session 405, POST /other 403, no lease 403, other secret's lease 403" \
   "$(code "$U/$L/selftest-sf/session"; echo -n ' '; code -X POST "$U/$L/selftest-sf/other"; echo -n ' '; code -X POST "$U/nope/selftest-sf/session"; echo -n ' '; code -X POST "$U/$LB/selftest-sf/session")" \
   "405 403 403 403"
is "refusals: no upstream call" "$(wc -l <"$W/up.log")" "$n"
cb=$(code -X POST "$U/$LB/selftest-sf-bad/session")
ev "bad login: 401, the fault's reason passed back with the echoed password redacted" \
   '[ "$cb" = 401 ] && grep -q "login refused: INVALID_LOGIN" "$W/body" && grep -qF "[redacted]" "$W/body" && ! grep -qF "$PASS" "$W/body"'
c3=$(code -X POST "$U/$L3/selftest-sf-302/session")
is "redirect: 502, not followed (no GET to the Location)" "$c3 $(grep -c '^GET' "$W/up.log")" "502 0"
cn=$(code -X POST "$U/$LN/selftest-sf-nopw/session")
is "a sealed value without SF_PASSWORD: 503, no upstream call for it" "$cn $(grep -c 'u1@fixture' "$W/up.log")" "503 1"

# 5. Unit mode in the broker: a unit-mode secret logs its use; an exchange secret cannot; the critical one gets no lease.
"$S" used fleet-backup-pass --target fleet-backup-run.service --ticket nightly >/dev/null 2>&1; u1=$?
"$S" used selftest-sf --target x.service >/dev/null 2>&1; u2=$?
"$S" used fleet-backup-pass >/dev/null 2>&1; u3=$?
"$S" grant fleet-backup-pass --ticket T9101 >/dev/null 2>&1; u4=$?
is "used: unit-mode 0, exchange-mode 1, no --target 2; grant on fleet-backup-pass 1" "$u1 $u2 $u3 $u4" "0 1 2 1"

# 6. Log and list: uses with the target, never a value, a session token or a full lease id.
lg=$("$S" log -n 200 2>&1)
ev "log: use selftest-sf ok with its target, refused bad path, the unit-mode use with its unit" \
   'grep -qE "use +selftest-sf +ok +ticket=T9101.*target=POST example.org/services/Soap/u/59.0" <<<"$lg" && grep -qE "use +selftest-sf +refused.*why=path not allowed" <<<"$lg" && grep -qE "use +fleet-backup-pass +ok +ticket=nightly.*target=fleet-backup-run.service" <<<"$lg"'
last=$("$S" list --json | python3 -c 'import json,sys; r={x["name"]: x for x in json.load(sys.stdin)}; print(r["selftest-sf"]["last_used"] is not None, r["fleet-backup-pass"]["last_used"] is not None)')
is "list: last use set for the exchange and the unit-mode secret" "$last" "True True"
all="$lg$(cat "$W/d.out" "$W/state/uses.jsonl")"
ev "values: the fake password and the session token never in a log or the broker's output" \
   '! grep -qF -e "$PASS" -e "$SID" <<<"$all"'
ev "leases: no full lease id in the broker's log or output" '! grep -qF -e "$L" -e "$LB" "$W/state/uses.jsonl" "$W/d.out"'

# 7. Units and installer: the system unit loads the sealed credential; the user timer's verb starts it.
SU="$A/vault/fleet-backup-run.service"
ev "unit: system unit loads fleet.fleet-backup-pass, runs as the installed user, no %h" \
   'grep -qx LoadCredentialEncrypted=fleet.fleet-backup-pass "$SU" && grep -qx User=@USER@ "$SU" && ! grep -q "%h" "$SU" && grep -qx NoNewPrivileges=yes "$SU"'
ev "unit: the user unit runs fleet-backup nightly" 'grep -qx "ExecStart=%h/agents/bin/fleet-backup nightly" "$A/units/fleet-backup.service"'
FR="$W/root"; mkdir -p "$FR"
FLEET_VAULT_ROOT="$FR" FLEET_BACKUP_USER="$me" bash "$A/vault/install-backup" >/dev/null 2>&1; r0=$?
is "install-backup dry run: rc 0, nothing written" "$r0 $(find "$FR" -type f | wc -l)" "0 0"
FLEET_VAULT_ROOT="$FR" FLEET_BACKUP_USER="$me" bash "$A/vault/install-backup" --apply >/dev/null 2>&1; r1=$?
IU="$FR/etc/systemd/system/fleet-backup-run.service"
ev "install-backup --apply: unit 644 with the user, uid and home filled, no placeholder left" \
   '[ $r1 = 0 ] && [ "$(stat -c %a "$IU")" = 644 ] && grep -qx "User=$me" "$IU" && grep -q "XDG_RUNTIME_DIR=/run/user/$(id -u) " "$IU" && grep -qx "ExecStart=$HOME/agents/bin/fleet-backup run" "$IU" && ! grep -q @ "$IU"'
FLEET_VAULT_ROOT="$FR" bash "$A/vault/install-backup" --remove --apply >/dev/null 2>&1
is "install-backup --remove: unit gone" "$(find "$FR" -type f | wc -l)" 0

# 8. fleet-backup by unit mode on a fake stick: the credential is the password, no file is written, the stick's key follows.
if command -v restic >/dev/null && command -v udisksctl >/dev/null; then
  LBL="FBV$((RANDOM % 9000 + 1000))"; H="$W/home"
  mkdir -p "$H/agents/state" "$H/finance" "$H/agent-work" "$H/.claude" "$H/memory"; echo money >"$H/finance/f.txt"
  printf 'FLEET_BACKUP_LABEL=%s\nFLEET_BACKUP_BUDGET_MB=6\nFLEET_BACKUP_MIN_FREE_MB=1\n' "$LBL" >"$W/config.env"
  printf '%s' "$BPASS" >"$W/bcreds/fleet.fleet-backup-pass"; chmod 400 "$W/bcreds/fleet.fleet-backup-pass"
  img="$W/stick.img"; truncate -s 64M "$img"; mkfs.vfat -n "$LBL" "$img" >/dev/null
  LOOP=$(udisksctl loop-setup --no-user-interaction -f "$img" | sed -n 's/.* as \(\/dev\/loop[0-9]*\)\.$/\1/p')
  udisksctl mount --no-user-interaction -b "$LOOP" >/dev/null 2>&1
  wait-for --label "V9 stick" --every 1 --until "findmnt -n -o TARGET $LOOP >/dev/null" >/dev/null
  M=$(findmnt -n -o TARGET "$LOOP")
  ev "selftest: the fake stick is a loop device, HOME and the credential are fixtures" \
     'findmnt -n -o SOURCE "$M" | grep -q "^/dev/loop" && case "$H" in "$W"/*) true;; *) false;; esac'
  fb() { env -i PATH="$PATH" HOME="$H" USER="$USER" XDG_RUNTIME_DIR="$W" HARNESS_CONFIG="$W/config.env" \
    HARNESS_HOME="$H/agents" AGENT_WORK="$H/agent-work" HARNESS_CONTEXT_DIR="$H/.claude" MEMORY_HOME="$H/memory" \
    FLEET_VAULT_SOCKET="$FLEET_VAULT_SOCKET" "$@"; }
  OLD="$H/agents/secrets/fleet-backup.pass"
  fb CREDENTIALS_DIRECTORY="$W/bcreds" "$A/bin/fleet-backup" run >"$W/b1" 2>&1; b1=$?
  ev "unit mode: run exit 0, a snapshot opens with the credential, no password file written" \
     '[ $b1 = 0 ] && restic -r "$M/fleet-backup/restic" --password-file "$W/bcreds/fleet.fleet-backup-pass" snapshots --json 2>/dev/null | jq -e "length == 1" >/dev/null && [ ! -e "$OLD" ]'
  ev "unit mode: the stick's key holds the vault's password" 'cmp -s "$W/bcreds/fleet.fleet-backup-pass" "$M/fleet-backup/restic-key.txt"'
  ev "unit mode: the run logged its use in the vault (target the system unit)" \
     '[ "$("$S" log -n 50 fleet-backup-pass | grep -c "use .*ticket=nightly.*target=fleet-backup-run.service")" = 2 ]'
  n0=$(grep -c fleet-backup-pass "$W/state/uses.jsonl")
  fb "$A/bin/fleet-backup" --check >"$W/c1" 2>&1; c1=$?
  fb "$A/bin/fleet-backup" run >"$W/b2" 2>&1; b2=$?
  ev "no credential: --check green on the stick's key, run exit 0, still no password file, no vault use" \
     '[ $c1 = 0 ] && grep -q "ok password: the stick.s key" "$W/c1" && [ $b2 = 0 ] && [ ! -e "$OLD" ] && [ "$(grep -c fleet-backup-pass "$W/state/uses.jsonl")" = "$n0" ]'
  mv "$M/fleet-backup/restic-key.txt" "$W/key.bak"
  fb "$A/bin/fleet-backup" run >"$W/b3" 2>&1; b3=$?
  ev "no password anywhere and a repo exists: run fails, writes no new password (file or stick)" \
     '[ $b3 = 1 ] && grep -q "FAIL: no password for the existing repo" "$H/agents/state/fleet-backup/run.log" && [ ! -e "$OLD" ] && [ ! -e "$M/fleet-backup/restic-key.txt" ]'
  printf '%s\n' "$BPASS" >"$M/fleet-backup/restic-key.txt"
  fb CREDENTIALS_DIRECTORY="$W/bcreds" "$A/bin/fleet-backup" run >/dev/null 2>&1; b4=$?
  ev "a trailing newline on the stick's key is the same key: run 0, the stick copy left as it was" \
     '[ $b4 = 0 ] && [ "$(tail -c 1 "$M/fleet-backup/restic-key.txt" | od -An -c | tr -d " ")" = "\n" ]'
  sed "s/^FLEET_BACKUP_LABEL=.*/FLEET_BACKUP_LABEL=NOSUCHFBV/" "$W/config.env" >"$W/absent.env"
  fb HARNESS_CONFIG="$W/absent.env" FLEET_BACKUP_UNIT=nosuch-v9.service "$A/bin/fleet-backup" nightly >/dev/null 2>&1; b5=$?
  ev "nightly without the system unit runs in place (absent stick: skip, exit 0)" \
     '[ $b5 = 0 ] && tail -1 "$H/agents/state/fleet-backup/run.log" | grep -q "skip: stick absent"'
  ev "backup: the fake password never in an output or the run log" \
     '! grep -qF "$BPASS" "$W/b1" "$W/b2" "$W/b3" "$W/c1" "$H/agents/state/fleet-backup/run.log"'
else
  echo "skip backup cases: restic or udisksctl missing"
fi

# 9. Live, read-only: the backup password's routes for this user (only once the vault is installed).
C=/etc/credstore.encrypted/fleet.fleet-backup-pass
if [ -r /etc/fleet-vault/registry.toml ]; then
  r_cat=$(cat "$C" 2>/dev/null | wc -c)
  r_run=$(timeout 30 systemd-run --user --quiet --wait --pipe --collect cat "$C" 2>/dev/null </dev/null | wc -c)
  r_creds=$(systemd-creds decrypt --name=fleet.fleet-backup-pass "$C" - 2>/dev/null </dev/null | wc -c)
  is "live: the sealed backup password reads 0 bytes by cat, systemd-run --user, systemd-creds" "$r_cat $r_run $r_creds" "0 0 0"
else
  echo "skip live: the vault is not installed here"
fi
exit $bad
