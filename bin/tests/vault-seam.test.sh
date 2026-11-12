#!/usr/bin/env bash
# T1693: vault tests never push the owner. A refused grant inside a fixture agents.slice raises into the seam's recorder
# ($W/seam), the real notify.log gains 0 lines; a lint fails any vault-*.test.sh that does not source the seam.
# Fixtures only: bwrap --unshare-net, the real notify.log read-only, the real broker socket dir hidden, a repo fleet-vaultd
# on a temp state, registry and creds dir, a fake cgroup tree.
set -uo pipefail
SELF=$(readlink -f "$0"); A=$(cd "$(dirname "$SELF")/../.." && pwd)
REAL_LOG="$A/log/notify.log"
if [ -z "${VAULT_SEAM_SANDBOXED:-}" ]; then
  binds=()
  for f in "$REAL_LOG" "$A/log/notify-keys.tsv"; do [ -e "$f" ] && binds+=(--ro-bind "$f" "$f"); done
  [ -d /run/fleet-vault ] && binds+=(--tmpfs /run/fleet-vault)
  exec bwrap --dev-bind / / --unshare-net "${binds[@]}" --setenv VAULT_SEAM_SANDBOXED 1 -- bash "$SELF"
fi
W=$(mktemp -d); PIDS=()
trap 'for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$W"' EXIT
. "$A/bin/tests/lib/assert.sh"
. "$A/bin/tests/lib/vault-seam.sh"
me=$(id -un); uid=$(id -u)
export FLEET_VAULT_SOCKET="$W/run/admin.sock" FLEET_VAULT_REGISTRY="$W/registry.toml" HARNESS_CONFIG=/dev/null
CG="$W/cg"; SLICE="$CG/user.slice/user-$uid.slice/user@$uid.service/agents.slice"
mkdir -p "$W/run" "$W/state" "$W/creds" "$SLICE/run-fx.scope"; : >"$SLICE/run-fx.scope/cgroup.procs"
S="$A/bin/secret"

# 0. Selftest: no route out, the real log unwritable, the real broker socket gone, every push path in the fixture.
if curl -sS -m 3 -o /dev/null https://ntfy.sh 2>/dev/null; then echo 'FAIL selftest: sandbox reaches the network'; exit 1; fi
if [ -e "$REAL_LOG" ] && [ -w "$REAL_LOG" ]; then echo "FAIL selftest: $REAL_LOG is writable"; exit 1; fi
if [ -e /run/fleet-vault/admin.sock ]; then echo 'FAIL selftest: the real broker socket is visible'; exit 1; fi
for p in "$FLEET_VAULT_SOCKET" "$CG" "${SECRET_RAISE_CMD%% *}" "$(command -v notify-owner)" "$NTFY_LOG_FILE" "$NTFY_KEYS_FILE"; do
  case "$p" in "$W"/*) ;; *) echo "FAIL selftest: $p is outside the fixture"; exit 1 ;; esac
done
ok "selftest: no network, real notify.log read-only, real broker hidden, raise and notify-owner are the seam ($W/seam)"
before=$(wc -l <"$REAL_LOG" 2>/dev/null || echo 0)

# 1. A fixture broker; a grant asked from inside the fixture agents.slice is refused and raised into the recorder.
cp "$A/vault/registry.toml" "$W/registry.toml"
printf '\n[secret.selftest-free]\nclass = "free"\nused_in = "fixture"\nmodes = ["proxy"]\nhosts = ["example.org"]\npaths = ["/"]\n' >>"$W/registry.toml"
python3 -I "$A/vault/fleet-vaultd" --registry "$W/registry.toml" --state "$W/state" --socket "$FLEET_VAULT_SOCKET" \
  --seal-socket "$W/no-seal.sock" --cred-dir "$W/creds" --clients "$me" --cgroup-root "$CG" >"$W/d.out" 2>&1 &
PIDS+=($!)
wait-for --label vault-seam-broker --every 0.1 --until "test -S '$FLEET_VAULT_SOCKET' && test -s '$W/state/port'" >/dev/null
bash -c 'echo $$ >"$1"; exec env AGENT_NAME=fx-seam "$2" grant selftest-free --ticket T9301' _ "$SLICE/run-fx.scope/cgroup.procs" "$S" \
  >"$W/cli.out" 2>"$W/cli.err"; rc=$?
: >"$SLICE/run-fx.scope/cgroup.procs"
is "refusal: \`secret grant\` inside an agent exits 1 with no lease" "$rc $(wc -c <"$W/cli.out")" "1 0"
is "refusal: 1 line in the seam's recorder" "$(wc -l <"$W/seam/pushes.log" 2>/dev/null || echo 0)" 1
ev "refusal: the recorded push is the high raise for selftest-free (T9301)" \
   'grep -q "^-p high vault: fx-seam asked a lease on selftest-free (T9301) from inside an agent" "$W/seam/pushes.log"'

# 2. notify-owner by its repo path also logs into the seam, not the real log.
"$A/bin/notify-owner" -p high "vault-seam fixture line" >/dev/null 2>&1
ev "notify-owner by path: logged in the seam's notify.log" 'grep -q "vault-seam fixture line" "$NTFY_LOG_FILE"'
is "the real notify.log gained 0 lines" "$(wc -l <"$REAL_LOG" 2>/dev/null || echo 0)" "$before"

# 3. Lint: every vault-*.test.sh sources the seam; a file that does not is named.
seam_lint() { for f in "$1"/vault-*.test.sh; do grep -qxF '. "$A/bin/tests/lib/vault-seam.sh"' "$f" || echo "${f##*/}"; done; }
is "lint: every bin/tests/vault-*.test.sh sources the seam" "$(seam_lint "$A/bin/tests")" ""
mkdir -p "$W/lint"; printf '#!/usr/bin/env bash\n. "$A/bin/tests/lib/assert.sh"\n' >"$W/lint/vault-bare.test.sh"
is "lint: a vault test without the seam is named" "$(seam_lint "$W/lint")" "vault-bare.test.sh"
exit $bad
