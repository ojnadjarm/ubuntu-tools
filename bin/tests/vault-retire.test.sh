#!/usr/bin/env bash
# T1634-V10: retire and document. `secret scan` (the broker looks for live values in files the client opens and hands
# over by descriptor; names and counts out, never a value; refused inside an agent), `secret reissue` (the checklist),
# `secret add` keeps a multi-line value, the mask and key-path blanking are gone, the never and hide lists name the
# vault's paths, guide + skill + INDEX line exist. Fixtures only: a repo fleet-vaultd on a temp state, registry, creds
# dir and seal helper (fake systemd-creds), a fake cgroup tree, fake values; the real store and broker are never reached.
set -uo pipefail
A=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
W=$(mktemp -d); PIDS=()
trap 'for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; chmod -R u+rwx "$W" 2>/dev/null; rm -rf "$W"' EXIT
. "$A/bin/tests/lib/assert.sh"
. "$A/bin/tests/lib/vault-seam.sh"
me=$(id -un); uid=$(id -u)
rnd() { head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
KEY="fxkey-$(rnd)"; PASS="fxpass-$(rnd)"; CSEC="fxclientsecret-$(rnd)"   # fake, random, never a real secret
export FLEET_VAULT_SOCKET="$W/run/admin.sock" FLEET_VAULT_REGISTRY="$W/registry.toml" HARNESS_CONFIG=/dev/null
CG="$W/cg"; SLICE="$CG/user.slice/user-$uid.slice/user@$uid.service/agents.slice"
mkdir -p "$W/run" "$W/state" "$W/store" "$W/creds" "$W/files/sub" "$SLICE/run-fx.scope"; chmod 700 "$W/store"
: >"$SLICE/run-fx.scope/cgroup.procs"
S="$A/bin/secret"

# 0. Selftest: every path is a fixture.
for p in "$FLEET_VAULT_SOCKET" "$FLEET_VAULT_REGISTRY" "$W/store" "$W/state" "$W/seal.sock" "$CG"; do
  case "$p" in "$W"/*) ;; *) echo "FAIL selftest: $p is outside the fixture"; exit 1 ;; esac
done
case "$FLEET_VAULT_SOCKET" in /run/fleet-vault*) echo "FAIL selftest: real socket"; exit 1 ;; esac
ok "selftest: socket, registry, store, state, seal socket and cgroup tree are fixtures"

# 1. Units: needles and the chunked count.
unit=$(python3 -I - "$A/lib" <<'EOF'
import io, sys; sys.path.insert(0, sys.argv[1]); from vault import scan
r = []
r.append(scan.needles(b"SF_USERNAME=a@b.example\nSF_PASSWORD=pw-12345678\nSF_LOGIN_URL=https://x.example\n") == [b"pw-12345678"])
r.append(scan.needles(b"clientid0123456789:secret0123456789ab\n") == sorted([b"clientid0123456789:secret0123456789ab", b"secret0123456789ab"]))
r.append(scan.needles(b"short") == [] and scan.needles(b"") == [] and scan.needles(None) == [])
r.append(scan.needles(b"https://host.example/path:abc") == [b"https://host.example/path:abc"])
scan.CHUNK = 7
r.append(scan.count(io.BytesIO(b"xxxxNEEDLE-01xxNEEDLE-01xxxxxxxxNEEDLE-01"), [b"NEEDLE-01", b"absent-x"]) == {0: 3})
print(" ".join("1" if x else "0" for x in r))
EOF
)
is "units: env file -> secret keys only; id:secret -> both; short/empty none; a URL whole; count across chunk edges" \
   "$unit" "1 1 1 1 1"

# 2. A fixture broker: the shipped registry + 3 rows; two values sealed at start, one added later by `secret add`.
cp "$A/vault/registry.toml" "$W/registry.toml"
for n in selftest-key selftest-client; do
  printf '\n[secret.%s]\nclass = "free"\nused_in = "fixture"\n' "$n" >>"$W/registry.toml"
done
printf '%s' "$KEY" >"$W/creds/fleet.selftest-key"; printf 'clientid-fixture-0001:%s' "$CSEC" >"$W/creds/fleet.selftest-client"
cat >"$W/fake-creds" <<'EOF'
#!/bin/sh
[ "$1" = encrypt ] && [ "$2" = --with-key=tpm2 ] && [ "$4" = - ] || exit 9
printf 'FAKESEAL %s %s\n' "${3#--name=}" "$(sha256sum | cut -d' ' -f1)" >"$5"; chmod 644 "$5"
EOF
chmod +x "$W/fake-creds"
systemd-socket-activate -l "$W/seal.sock" --inetd -a \
  python3 -I "$A/vault/fleet-vault-seal" --store "$W/store" --creds-bin "$W/fake-creds" --peer "$me" 2>/dev/null &
PIDS+=($!)
wait-for --label vault-retire-seal --every 0.1 --until "test -S '$W/seal.sock'" >/dev/null
python3 -I "$A/vault/fleet-vaultd" --registry "$W/registry.toml" --state "$W/state" --socket "$FLEET_VAULT_SOCKET" \
  --seal-socket "$W/seal.sock" --cred-dir "$W/creds" --clients "$me" --cgroup-root "$CG" >"$W/d.out" 2>&1 &
PIDS+=($!)
wait-for --label vault-retire-broker --every 0.1 --until "test -S '$FLEET_VAULT_SOCKET'" >/dev/null

# 3. secret add keeps every line of piped stdin (one trailing newline dropped).
printf 'SF_USERNAME=fx@example.org\nSF_PASSWORD=%s\n' "$PASS" | "$S" add selftest-env --class free --used-in "fixture env" >/dev/null 2>&1
want=$(printf 'SF_USERNAME=fx@example.org\nSF_PASSWORD=%s' "$PASS" | sha256sum | cut -d' ' -f1)
is "secret add: a two-line value is sealed whole (hash of both lines, no trailing newline)" \
   "$(cut -d' ' -f3 "$W/store/fleet.selftest-env" 2>/dev/null)" "$want"

# 4. secret scan: clean files exit 0; planted values (plain, gzip, env password, client secret) are found by name.
printf 'nothing here\n' >"$W/files/clean.log"
"$S" scan "$W/files" >"$W/scan0.out" 2>&1; rc=$?
ev "scan, clean: exit 0, 1 file, 0 hits, 3 live values checked" \
   '[ $rc = 0 ] && grep -qE "1 files, .* 3 live values, 0 hits" "$W/scan0.out"'
printf 'log line %s end\n' "$KEY" >"$W/files/leak.log"
printf 'x %s y %s\n' "$PASS" "$PASS" | gzip >"$W/files/sub/old.log.gz"
printf '{"t":"%s"}\n' "$CSEC" >"$W/files/sub/t.jsonl"
printf '%s\n' "$KEY" >"$W/files/locked.log"; chmod 000 "$W/files/locked.log"
ln -s "$W/creds/fleet.selftest-key" "$W/files/link.log"
"$S" scan "$W/files" >"$W/scan1.out" 2>&1; rc=$?
is "scan, planted: exit 1" "$rc" 1
ev "scan, planted: HIT lines name selftest-key, selftest-env x2 (inside .gz), selftest-client with their files" \
   'grep -qx "HIT selftest-key x1 $W/files/leak.log" "$W/scan1.out" && grep -qx "HIT selftest-env x2 $W/files/sub/old.log.gz" "$W/scan1.out" && grep -qx "HIT selftest-client x1 $W/files/sub/t.jsonl" "$W/scan1.out"'
ev "scan, planted: 4 files scanned, the unreadable one skipped, the symlink not followed" \
   'grep -qE "4 files, .* 4 hits, 1 skipped" "$W/scan1.out" && ! grep -q "link.log" "$W/scan1.out"'
ev "scan: no value in the output, the broker's log or its journal" \
   '! grep -qF -e "$KEY" -e "$PASS" -e "$CSEC" "$W/scan0.out" "$W/scan1.out" "$W/state/uses.jsonl" "$W/d.out"'
ev "scan: the broker logs each batch (ok, then hit), no file names" \
   'grep "\"event\":\"scan\"" "$W/state/uses.jsonl" | grep -q "\"result\":\"ok\"" && grep "\"event\":\"scan\"" "$W/state/uses.jsonl" | grep -q "\"result\":\"hit\"" && ! grep -q leak.log "$W/state/uses.jsonl"'

# 5. Asked from inside an agent (the caller's pid in agents.slice), the scan is refused and logged.
inside=$(python3 -I - "$A/lib" "$FLEET_VAULT_SOCKET" "$SLICE/run-fx.scope/cgroup.procs" "$W/files/leak.log" <<'EOF'
import os, sys; sys.path.insert(0, sys.argv[1]); from vault import scanwalk
open(sys.argv[3], "w").write(f"{os.getpid()}\n")
r = scanwalk.batch(sys.argv[2], [sys.argv[4]], "fx-agent")
print(r.get("ok"), r.get("error"))
EOF
)
is "scan from inside an agent: refused" "$inside" "False refused: scan runs outside an agent"
ev "scan from inside an agent: one refused row in the broker log" \
   'grep "\"event\":\"scan\"" "$W/state/uses.jsonl" | grep -q "\"result\":\"refused\""'
: >"$SLICE/run-fx.scope/cgroup.procs"

# 6. secret reissue: the whole checklist (7 vault rows + 5 tool credentials), one name, an unknown name.
out=$(FLEET_VAULT_REGISTRY="$A/vault/registry.toml" "$S" reissue --all 2>&1); rc=$?
ev "reissue --all: exit 0, 12 numbered items, the OpenRouter link, the GitHub token and the SSH key" \
   '[ $rc = 0 ] && [ "$(grep -cE "^[0-9]+\. " <<<"$out")" = 12 ] && grep -q "https://openrouter.ai/settings/keys" <<<"$out" && grep -q "^8\. github-token (tool" <<<"$out" && grep -q "ssh-key" <<<"$out"'
ev "reissue --all: every vault row has its next step" '[ "$(grep -c "then:    -$" <<<"$out")" = 0 ]'
out=$(FLEET_VAULT_REGISTRY="$A/vault/registry.toml" "$S" reissue discord-bot-token 2>&1); rc=$?
ev "reissue <name>: one item, its link" '[ $rc = 0 ] && [ "$(grep -cE "^[0-9]+\. " <<<"$out")" = 1 ] && grep -q "discord.com/developers" <<<"$out"'
FLEET_VAULT_REGISTRY="$A/vault/registry.toml" "$S" reissue nope >/dev/null 2>&1; is "reissue <unknown>: exit 1" "$?" 1

# 7. Retired: no mask or key path in the launchers; the never and hide lists name the vault's paths; docs exist.
ev "retired: po-work and the liaison name no secret-mask, no OPENROUTER_KEY_FILE, no secrets/openrouter.key" \
   '! grep -q -e secret-mask -e OPENROUTER_KEY_FILE -e openrouter.key "$A/bin/po-work" "$A/discord-liaison/liaison/cli.py"'
ev "never list: the store, broker state and systemd credentials dirs" \
   'grep -q "/etc/credstore.encrypted /var/lib/fleet-vault /run/credentials" "$A/bin/fleet-backup"'
ev "code-review sandbox: hides the broker's sockets and the credentials dir; its selftest probes the admin socket" \
   'grep -q "/run/fleet-vault /run/credentials" "$A/bin/code-review-sandbox" && grep -q "fleet-vault-seal.sock" "$A/bin/code-review-sandbox" && grep -q "REACHABLE vault admin socket" "$A/bin/code-review-sandbox"'
ev "AGENTS.md section 2 sends secrets to the vault" 'sed -n "/^## 2/,/^## 3/p" "$A/AGENTS.md" | grep -q "secret list"'
ev "guide secrets-vault, its INDEX line naming skill /secrets, and the skill" \
   'test -s "$A/KB/guides/secrets-vault.md" && grep -q "^- secrets-vault .*skill /secrets" "$A/KB/guides/INDEX.md" && test -s "${SKILLS_DIR:-$HOME/.claude/skills}/secrets/SKILL.md"'
exit $bad
