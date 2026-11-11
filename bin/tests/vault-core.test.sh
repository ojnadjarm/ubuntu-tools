#!/usr/bin/env bash
# T1634-V2: the vault's broker core on fixtures only: registry, admin ops, root seal helper (fake systemd-creds,
# temp store), fleet-vaultd + `secret` + `owner-secret` end to end, the sudo guard rule, the never-back-up list,
# the installer on a fixture root. The real store, the real broker, its unit and user are never reached.
set -uo pipefail
A=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
W=$(mktemp -d); PIDS=()
trap 'for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$W"' EXIT
. "$A/bin/tests/lib/assert.sh"
me=$(id -un)
VALUE="fixture-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"   # fake, random, never a real secret
VALUE2="fixture-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export FLEET_VAULT_SOCKET="$W/run/admin.sock" FLEET_VAULT_REGISTRY="$W/registry.toml"
mkdir -p "$W/run" "$W/state" "$W/store" "$W/creds" "$W/home/agents/secrets"
chmod 700 "$W/store"

# 0. Selftest: every path the broker, helper and client use is under the fixture dir.
for p in "$FLEET_VAULT_SOCKET" "$FLEET_VAULT_REGISTRY" "$W/store" "$W/state" "$W/seal.sock"; do
  case "$p" in "$W"/*) ;; *) echo "FAIL selftest: $p is outside the fixture"; exit 1 ;; esac
done
case "$FLEET_VAULT_SOCKET $W/store" in *credstore*|/run/fleet-vault*) echo "FAIL selftest: real path"; exit 1 ;; esac
ok "selftest: socket, registry, store and state are fixtures ($W)"

# 1. Registry: the shipped one validates; bad rows are refused.
cp "$A/vault/registry.toml" "$W/registry.toml"
printf '\n[secret.selftest-route]\nclass = "free"\nused_in = "fixture row"\n' >>"$W/registry.toml"
reg=$(python3 -I - "$A/lib" "$A/vault/registry.toml" <<'EOF'
import sys; sys.path.insert(0, sys.argv[1]); from vault import registry
e = registry.load(sys.argv[2]); print(len(e), " ".join(sorted({x.cls for x in e.values()})))
EOF
)
is "registry: shipped file loads 7 names in classes critical, free, ruled" "$reg" "7 critical free ruled"
bad=$(python3 -I - "$A/lib" <<'EOF'
import sys; sys.path.insert(0, sys.argv[1]); from vault import registry
rows = {"bad class": {"class": "paid", "used_in": "x"}, "ruled without rules": {"class": "ruled", "used_in": "x"},
        "proxy without host": {"class": "free", "used_in": "x", "modes": ["proxy"]},
        "fifth mode": {"class": "free", "used_in": "x", "modes": ["checkout"]},
        "unknown field": {"class": "free", "used_in": "x", "value": "y"}, "no used_in": {"class": "free"},
        "http reissue": {"class": "free", "used_in": "x", "reissue": "http://x.io"}}
n = 0
for why, row in rows.items():
    try: registry.entry("x", row)
    except registry.RegistryError: n += 1
for name in ("Up", "a.b", "../x", ""):
    try: registry.entry(name, {"class": "free", "used_in": "x"})
    except registry.RegistryError: n += 1
try: registry.entry("x", {"class": "free", "used_in": "x", "modes": ["unit"]}, added=True)
except registry.RegistryError: n += 1
print(n)
EOF
)
is "registry: 12 bad rows and names refused" "$bad" 12

# 2. Admin with MemorySealer: add, re-add, replace, unknown, class rules, list and log hold no value.
adm=$(python3 -I - "$A/lib" "$W/registry.toml" "$W/mem" "$VALUE" <<'EOF'
import base64, json, os, sys; sys.path.insert(0, sys.argv[1])
from vault.admin import Admin; from vault.audit import Audit; from vault.seal import MemorySealer
os.makedirs(sys.argv[3]); v = sys.argv[4]; b = base64.b64encode(v.encode()).decode()
s = MemorySealer(); a = Admin(sys.argv[2], sys.argv[3] + "/added.json", s, Audit(sys.argv[3] + "/uses.jsonl"))
r = []
r.append(a.handle({"op": "put", "name": "openrouter", "value_b64": b}, 1)["ok"])
r.append(a.handle({"op": "put", "name": "openrouter", "value_b64": b}, 1)["ok"])
r.append(a.handle({"op": "put", "name": "openrouter", "replace": True, "value_b64": b}, 1)["ok"])
r.append(a.handle({"op": "put", "name": "nope", "replace": True, "value_b64": b}, 1)["ok"])
r.append(a.handle({"op": "put", "name": "nope", "value_b64": b}, 1)["ok"])
r.append(a.handle({"op": "put", "name": "openrouter", "class": "free", "replace": True, "value_b64": b}, 1)["ok"])
r.append(a.handle({"op": "put", "name": "card-x", "class": "critical", "used_in": "a card", "value_b64": b}, 1)["ok"])
r.append(a.handle({"op": "put", "name": "y", "class": "free", "used_in": "x", "value_b64": ""}, 1)["ok"])
r.append(s.get("openrouter") == v.encode())
lst = a.handle({"op": "list"}, 1); log = a.handle({"op": "log", "n": 50}, 1)
r.append(next(x for x in lst["secrets"] if x["name"] == "card-x")["class"] == "critical")
r.append(a.handle({"op": "remove", "name": "card-x"}, 1)["ok"] and "card-x" not in a.entries)
r.append(a.handle({"op": "bogus"}, 1)["ok"])
blob = json.dumps(lst) + json.dumps(log) + open(sys.argv[3] + "/uses.jsonl").read() + open(sys.argv[3] + "/added.json").read()
r.append(v not in blob and b not in blob)
print(" ".join("1" if x else "0" for x in r)); print(len(lst["secrets"]), len(log["events"]))
EOF
)
is "admin: add, re-add refused, replace, unknown replace/add refused, class kept, critical add, empty refused" \
   "$(sed -n 1p <<<"$adm")" "1 0 1 0 0 0 1 0 1 1 1 0 1"
is "admin: list rows (7 registry + selftest-route + card-x) and 4 logged events" "$(sed -n 2p <<<"$adm")" "9 4"

# 3. Root seal helper, socket-activated per connection, with a fake systemd-creds and a temp store.
cat >"$W/fake-creds" <<'EOF'
#!/bin/sh
# Fake systemd-creds: checks the args the helper must pass and writes a hash, never the value.
[ "$1" = encrypt ] && [ "$2" = --with-key=tpm2 ] && [ "$4" = - ] || exit 9
case "$3" in --name=fleet.*) ;; *) exit 9 ;; esac
printf 'FAKESEAL %s %s\n' "${3#--name=}" "$(sha256sum | cut -d' ' -f1)" >"$5"; chmod 644 "$5"
EOF
chmod +x "$W/fake-creds"
systemd-socket-activate -l "$W/seal.sock" --inetd -a \
  python3 -I "$A/vault/fleet-vault-seal" --store "$W/store" --creds-bin "$W/fake-creds" --peer "$me" 2>/dev/null &
PIDS+=($!)
systemd-socket-activate -l "$W/seal-nobody.sock" --inetd -a \
  python3 -I "$A/vault/fleet-vault-seal" --store "$W/store" --creds-bin "$W/fake-creds" --peer nobody 2>/dev/null &
PIDS+=($!)
for _ in $(seq 50); do [ -S "$W/seal.sock" ] && [ -S "$W/seal-nobody.sock" ] && break; sleep 0.1; done
seal=$(python3 -I - "$A/lib" "$W/seal.sock" "$W/seal-nobody.sock" "$VALUE" <<'EOF'
import base64, sys; sys.path.insert(0, sys.argv[1]); from vault import wire
b = base64.b64encode(sys.argv[4].encode()).decode(); c = lambda r, s=sys.argv[2]: wire.call(s, r)
print(c({"op": "put", "name": "selftest-seal", "value_b64": b})["ok"], c({"op": "put", "name": "../x", "value_b64": b})["ok"],
      sorted(c({"op": "list"})["sealed"]), c({"op": "remove", "name": "selftest-seal"})["ok"],
      c({"op": "remove", "name": "selftest-seal"})["ok"], c({"op": "list"}, sys.argv[3])["ok"])
EOF
)
is "seal helper: put ok, bad name refused, list, remove, re-remove refused, foreign peer refused" \
   "$seal" "True False ['selftest-seal'] True False False"

# 4. fleet-vaultd from the repo + `secret` + `owner-secret`, sealing through the helper; one value preloaded at start.
printf '%s' "$VALUE2" >"$W/creds/fleet.selftest-pre"
python3 -I - "$A/lib" "$W/seal.sock" "$VALUE2" <<'EOF'
import base64, sys; sys.path.insert(0, sys.argv[1]); from vault import wire
wire.call(sys.argv[2], {"op": "put", "name": "selftest-pre", "value_b64": base64.b64encode(sys.argv[3].encode()).decode()})
EOF
python3 -I "$A/vault/fleet-vaultd" --registry "$W/registry.toml" --state "$W/state" --socket "$FLEET_VAULT_SOCKET" \
  --seal-socket "$W/seal.sock" --cred-dir "$W/creds" --clients "$me" >"$W/d.out" 2>&1 &
PIDS+=($!)
python3 -I "$A/vault/fleet-vaultd" --registry "$W/registry.toml" --state "$W/state" --socket "$W/run/other.sock" \
  --seal-socket "$W/seal.sock" --cred-dir "$W/creds" --clients nobody >/dev/null 2>&1 &
PIDS+=($!)
for _ in $(seq 50); do [ -S "$FLEET_VAULT_SOCKET" ] && [ -S "$W/run/other.sock" ] && break; sleep 0.1; done
S="$A/bin/secret"
out=$("$S" list 2>&1); rc=$?
is "secret list: rc 0" "$rc" 0
is "secret list: 7 registry names + selftest-route + selftest-pre" "$(tail -n +2 <<<"$out" | wc -l)" 9
ev "secret list: selftest-pre sealed at start" 'grep -qE "^selftest-pre +\? +sealed" <<<"$out"'
ev "secret list: openrouter ruled, fleet-backup-pass critical" \
   'grep -qE "^openrouter +ruled" <<<"$out" && grep -qE "^fleet-backup-pass +critical" <<<"$out"'
loaded=$("$S" list --json | python3 -c 'import json,sys; print([r["loaded"] for r in json.load(sys.stdin) if r["name"]=="selftest-pre"])')
is "secret list --json: the preloaded value is held by the broker" "$loaded" "[True]"
o1=$(printf '%s\n' "$VALUE" | "$S" add selftest-new --class critical --used-in "fixture card" 2>&1); r1=$?
o2=$(printf '%s\n' "$VALUE" | "$S" add selftest-new 2>&1); r2=$?
o3=$(printf '%s\n' "$VALUE2" | "$S" replace selftest-new 2>&1); r3=$?
o4=$(printf '%s\n' "$VALUE" | "$S" add selftest-nometa 2>&1); r4=$?
o5=$(printf '\n' | "$S" add selftest-empty --class free --used-in x 2>&1); r5=$?
is "secret add / re-add / replace / add without class / empty: rc 0 1 0 1 1" "$r1 $r2 $r3 $r4 $r5" "0 1 0 1 1"
eq "seal: store file fleet.selftest-new, mode 600" 600 "$(stat -c %a "$W/store/fleet.selftest-new" 2>/dev/null)"
want=$(printf '%s' "$VALUE2" | sha256sum | cut -d' ' -f1)
ev "seal: the store holds the replaced value's seal, named fleet.selftest-new" \
   'grep -qx "FAKESEAL fleet.selftest-new $want" "$W/store/fleet.selftest-new"'
eq "seal: no temp file left in the store" 0 "$(find "$W/store" -name '.*' -type f | wc -l)"
lg=$("$S" log -n 50 2>&1)
ev "secret log: add ok, add refused, replace ok" \
   'grep -qE "add +selftest-new +ok" <<<"$lg" && grep -qE "add +selftest-new +refused" <<<"$lg" && grep -qE "replace +selftest-new +ok" <<<"$lg"'
o6=$("$S" remove selftest-new 2>&1); r6=$?
is "secret remove: rc 0, store file gone" "$r6 $([ -e "$W/store/fleet.selftest-new" ] && echo kept || echo gone)" "0 gone"
"$S" list >/dev/null 2>&1 && FLEET_VAULT_SOCKET="$W/run/other.sock" "$S" list >"$W/o7" 2>&1; r7=$?
is "admin socket: a user not in --clients is refused (rc 1)" "$r7" 1
ev "admin socket: the refusal is logged" 'grep -q "\"result\":\"refused\",\"uid\":$(id -u)" "$W/state/uses.jsonl"'
FLEET_VAULT_SOCKET="$W/run/none.sock" "$S" list >/dev/null 2>&1; is "secret list: broker down: rc 1" "$?" 1
"$S" --bogus >/dev/null 2>&1; is "secret: unknown flag rc 2" "$?" 2
"$S" --help >/dev/null 2>&1; is "secret --help: rc 0" "$?" 0
"$S" known openrouter; k1=$?; "$S" known tok; k2=$?
is "secret known: registry name 0, other 1" "$k1 $k2" "0 1"

# owner-secret: a registry name is sealed by the broker, any other name stays a file (fixture HOME).
o8=$(printf '%s\n' "$VALUE" | HOME="$W/home" "$A/bin/owner-secret" selftest-route 2>&1); r8=$?
o9=$(printf '%s\n' "$VALUE" | HOME="$W/home" "$A/bin/owner-secret" tok 2>&1); r9=$?
is "owner-secret: registry name sealed through the broker (rc 0, store file, no secrets file)" \
   "$r8 $([ -e "$W/store/fleet.selftest-route" ] && echo sealed) $([ -e "$W/home/agents/secrets/selftest-route" ] && echo file || echo nofile)" \
   "0 sealed nofile"
is "owner-secret: other names still write the file" "$r9 $(cat "$W/home/agents/secrets/tok" 2>/dev/null | wc -c)" "0 $(( ${#VALUE} + 1 ))"
o10=$(printf '%s\n' "$VALUE2" | HOME="$W/home" "$A/bin/owner-secret" --replace selftest-route 2>&1)
is "owner-secret --replace: routed to secret replace" "$?" 0

# No value anywhere it must not be: outputs, audit log, added rows, daemon log.
all="$out$o1$o2$o3$o4$o5$o6$lg$o8$o9$o10$("$S" list --json)$(cat "$W/o7" "$W/d.out" "$W/state/"*)"
ev "values: never printed or logged (2 fake values, plain and base64)" \
   '! grep -qF -e "$VALUE" -e "$VALUE2" -e "$(printf %s "$VALUE" | base64)" -e "$(printf %s "$VALUE2" | base64)" <<<"$all"'
eq "state: audit log mode 600" 600 "$(stat -c %a "$W/state/uses.jsonl")"

# 5. Sudo guard: the plain routes to the vault are refused; reading and restarting its unit stay open.
mkdir -p "$W/real"; printf '#!/bin/sh\necho "REAL sudo $*"\n' >"$W/real/sudo"; chmod +x "$W/real/sudo"
g() { HARNESS_GUARD_LOG="$W/guards.jsonl" PATH="$A/bin/guards:$W/real:/usr/bin:/bin" sudo "$@" >/dev/null 2>&1; echo -n "$? "; }
refused=$(g cat /etc/credstore.encrypted/fleet.x; g -u fleet-vault id; g systemd-creds decrypt /tmp/x -
          g systemd-run -p ImportCredential=fleet.* cat; g systemctl stop fleet-vault; g systemctl edit fleet-vault
          g cat /run/credentials/fleet-vault.service/fleet.x; g cp x /opt/fleet-vault/bin/fleet-vaultd
          g -u fleet-vault systemctl status x; g ls /var/lib/fleet-vault)
is "guard: 10 sudo routes to the store, user, unit, state and code refused (exit 3)" "$refused" "3 3 3 3 3 3 3 3 3 3 "
open=$(g systemctl restart fleet-vault.service; g systemctl status fleet-vault; g journalctl -u fleet-vault
       g systemd-creds list; g ls /etc; g -n "$A/vault/install" --apply)
is "guard: restart, status, journal, creds list, unrelated sudo and the installer pass" "$open" "0 0 0 0 0 0 "
ev "guard: refusals logged with the vault rule" 'grep -c "T1634 vault" "$W/guards.jsonl" | grep -qx 10'

# 6. fleet-backup never backs up the store or the broker's state.
nv=$(HARNESS_HOME="$W/h" HOME="$W/home" CLAUDE="$W/c" STATE="$W/none" bash -c \
  "$(sed -n '/^never() {/,/^}/p' "$A/bin/fleet-backup"); never")
ev "fleet-backup never(): /etc/credstore.encrypted and /var/lib/fleet-vault listed" \
   'grep -qx /etc/credstore.encrypted <<<"$nv" && grep -qx /var/lib/fleet-vault <<<"$nv"'

# 7. Units: own user, credentials imported at start, sandboxed; shipped outside units/ (that dir becomes user units).
U="$A/vault/fleet-vault.service"
ev "unit: User=fleet-vault, ImportCredential=fleet.*, ProtectHome, NoNewPrivileges, empty capabilities" \
   'grep -qx User=fleet-vault "$U" && grep -qx "ImportCredential=fleet.\*" "$U" && grep -qx ProtectHome=yes "$U" && grep -qx NoNewPrivileges=yes "$U" && grep -qx CapabilityBoundingSet= "$U"'
ev "unit: seal socket 0660 root:fleet-vault, one helper per connection" \
   'grep -qx SocketMode=0660 "$A/vault/fleet-vault-seal.socket" && grep -qx SocketGroup=fleet-vault "$A/vault/fleet-vault-seal.socket" && grep -qx Accept=yes "$A/vault/fleet-vault-seal.socket"'
ev "unit: no vault unit under units/ (install.sh would make it a user unit)" '! ls "$A"/units/fleet-vault* >/dev/null 2>&1'

# 8. Installer on a fixture root: dry run writes nothing; apply places code, config, store dir and units; remove undoes.
FR="$W/root"; mkdir -p "$FR/etc"; printf '# etckeeper\n' >"$FR/etc/.gitignore"
FLEET_VAULT_ROOT="$FR" FLEET_VAULT_CLIENTS=fixture-user bash "$A/vault/install" >"$W/i0" 2>&1
is "install dry run: rc 0, nothing written" "$? $(find "$FR" -type f | wc -l)" "0 1"
FLEET_VAULT_ROOT="$FR" FLEET_VAULT_CLIENTS=fixture-user bash "$A/vault/install" --apply >"$W/i1" 2>&1; ri=$?
FLEET_VAULT_ROOT="$FR" FLEET_VAULT_CLIENTS=fixture-user bash "$A/vault/install" --apply >/dev/null 2>&1
is "install --apply: rc 0" "$ri" 0
is "install: modes (daemon, helper, registry, store dir)" \
   "$(stat -c %a "$FR/opt/fleet-vault/bin/fleet-vaultd" "$FR/opt/fleet-vault/bin/fleet-vault-seal" "$FR/etc/fleet-vault/registry.toml" "$FR/etc/credstore.encrypted" | tr '\n' ' ')" \
   "755 755 644 700 "
is "install: lib modules copied" "$(ls "$FR/opt/fleet-vault/lib/vault" | tr '\n' ' ')" \
   "$(ls "$A/lib/vault" | grep '\.py$' | tr '\n' ' ')"
ev "install: vault.env names the client; store kept out of etckeeper (once, after 2 runs); 3 units" \
   'grep -qx FLEET_VAULT_CLIENTS=fixture-user "$FR/etc/fleet-vault/vault.env" && [ "$(grep -cx /credstore.encrypted/ "$FR/etc/.gitignore")" = 1 ] && [ "$(ls "$FR/etc/systemd/system" | wc -l)" = 3 ]'
FLEET_VAULT_ROOT="$FR" bash "$A/vault/install" --remove --apply >/dev/null 2>&1
is "install --remove: code, config and units gone" \
   "$(find "$FR/opt" "$FR/etc/fleet-vault" "$FR/etc/systemd/system" -type f 2>/dev/null | wc -l)" 0

exit $bad
