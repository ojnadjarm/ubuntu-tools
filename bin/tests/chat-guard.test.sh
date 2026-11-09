#!/usr/bin/env bash
# chat guard (T1515-P5): lib/chat_guard.check holds secrets, protected paths and deny words, fails closed;
# hooks/audit-log.py redacts through the one pattern module lib/redact.py. Fixture config only; nothing is written.
set -uo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
. "$ROOT/bin/tests/lib/assert.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
unset PROTECTED_PROJECTS WORK_REPO_ROOTS PC_NOT_OURS HARNESS_ENV_LOADED CHAT_DENY_WORDS
export HOME="$WORK/home" HARNESS_CONFIG="$WORK/config.env"
mkdir -p "$HOME"
cat >"$HARNESS_CONFIG" <<'EOF'
PROTECTED_PROJECTS="acme"
PROTECTED_ACME_REPOS="~/acme"
PROTECTED_ACME_PATHS="/srv/acme-4.5"
CHAT_DENY_WORDS="globex ledgerbook"   # fixture words
EOF
case "$HARNESS_CONFIG" in "$WORK"/*) ok 'selftest: config is the fixture';; *) nok selftest "$HARNESS_CONFIG"; exit 1;; esac

# guard <text> [seat]: prints "ok" or "held: <reason>".
guard() {
  python3 - "$1" "${2:-po-x}" <<PY
import sys; sys.path.insert(0, '$ROOT/lib')
import chat_guard
ok, why = chat_guard.check(sys.argv[1], sys.argv[2])
print('ok' if ok else 'held: ' + why)
PY
}

is 'plain text is allowed' "$(guard 'build is green, 12 tests pass')" ok
is 'a sha256 digest is allowed' "$(guard 'image sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef')" ok
for s in 'key sk-ant-api03-AAAAAAAAAAAAAAAAAAAA' 'use ghp_abcdefghijklmnopqrstuvwxyz0123' \
         'password: hunter2' 'curl https://bob:hunter2@example.org/x' 'AKIAABCDEFGHIJKLMNOP is the id' \
         'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIx.abc'; do
  is "secret held: ${s:0:24}" "$(guard "$s")" 'held: secret'
done

is 'protected path held: absolute' "$(guard "see $HOME/acme/src/lib.php")" 'held: protected path'
is 'protected path held: ~ form' "$(guard 'look at ~/acme for it')" 'held: protected path'
is 'protected path held: $HOME form' "$(guard 'cat $HOME/acme/README')" 'held: protected path'
is 'protected path held: the root itself' "$(guard "/srv/acme-4.5")" 'held: protected path'
is 'sibling path allowed' "$(guard "$HOME/acme2/x and /srv/acme-4.55")" ok

is 'deny word held, any case' "$(guard 'the GLOBEX ticket moved')" 'held: deny word'
is 'deny word held in a folder name' "$(guard 'files in ~/ledgerbook/2026')" 'held: deny word'
is 'longer word allowed' "$(guard 'globexy is fine')" ok
is 'env CHAT_DENY_WORDS wins over the file' "$(CHAT_DENY_WORDS=initech guard 'initech' ; CHAT_DENY_WORDS=initech guard globex)" \
   "$(printf 'held: deny word\nok')"
is 'a held reason never names the text' "$(guard 'globex')" 'held: deny word'

r=$(python3 - <<PY
import os, sys, time; sys.path.insert(0, '$ROOT/lib')
import chat_guard
a = chat_guard.check('initrode', 'po-x')
with open(os.environ['HARNESS_CONFIG'], 'a') as f: f.write('CHAT_DENY_WORDS="initrode"\n')
t = time.time() + 5; os.utime(os.environ['HARNESS_CONFIG'], (t, t))
print(a, chat_guard.check('initrode', 'po-x'))
PY
)
is 'config change is read without a restart' "$r" "(True, '') (False, 'deny word')"

r=$(python3 - <<PY
import sys; sys.path.insert(0, '$ROOT/lib')
import chat_guard
chat_guard.BIN = '$WORK/no-such-bin'
print(chat_guard.check('hello', 'po-x'), chat_guard.check(None, 'po-x'))
PY
)
is 'fails closed: matcher missing or text not a string' "$r" "(False, 'guard error: FileNotFoundError') (False, 'not text')"

# One source: the audit core defines no patterns and redacts exactly as lib/redact.py.
! grep -qE '^(def (patterns|may_hold_secret)|TRIGGERS|CASED) ' "$ROOT/hooks/audit-log.py" \
  && grep -q "_lib('redact')" "$ROOT/hooks/audit-log.py" && ok 'audit-log.py holds no patterns, loads lib/redact' \
  || nok 'one source' 'audit-log.py still defines patterns'
r=$(python3 - "$ROOT" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location('audit_core', sys.argv[1] + '/hooks/audit-log.py')
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
sys.path.insert(0, sys.argv[1] + '/lib'); import redact
x = 'token=abc123 curl -u a:b https://x ghp_abcdefghijklmnopqrstuvwxyz0123'
print(m.redact is redact.redact or m.redact(x) == redact.redact(x), '<redacted>' in m.redact(x))
PY
)
is 'audit core redact == lib/redact.redact' "$r" 'True True'
exit $bad
