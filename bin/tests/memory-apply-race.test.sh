#!/usr/bin/env bash
# T2060: a writer that changes a store file while `memory apply` runs its gate (after the stage-time three-way check)
# must not lose its line: apply goes red, nothing moves, his line stays. Sandbox only (AGENTS.md §5.6): HOME,
# AGENT_WORK and MEMORY_HOME are temp dirs over the synthetic memory-keeper fixture.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$BIN/.." && pwd)"
FX="$BIN/tests/fixtures/memory-keeper"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$ROOT/lib")"
fail=0
t() { printf '%-92s' "memory-apply-race: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
       GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
St="$T/store" CARD="domains/garden/DOMAIN.md"
HIS='- Seed photos are 1200 px wide. (26-11-28) ^gd01'
mem() { "$BIN/memory" "$@"; }
swap() { python3 -c 'import sys; p, a, b = sys.argv[1:]; s = open(p).read(); assert a + "\n" in s; open(p, "w").write(s.replace(a + "\n", b + "\n"))' "$@"; }
setup() {
  rm -rf "$St" "$HOME" "$AGENT_WORK" "$T/proj"
  mkdir -p "$HOME" "$AGENT_WORK" "$T/proj"/{garden,kiln,harbor}
  cp -r "$FX/store" "$St"
  sed "s#@P@#$T/proj#" "$St/domains.map.in" >"$St/domains.map" && rm "$St/domains.map.in"
  git -C "$St" init -q -b main && git -C "$St" add -A && git -C "$St" commit -q -m seed
}
apply_racing() {  # memory apply on $1; the other writer edits the store card while the gate runs
  python3 - "$ROOT/lib" "$St" "$1" "$CARD" "$HIS" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import memory_check, memory_store, memory_txn
store, staging, card, his = memory_store.Store(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
gate = memory_check.run
def racing(*a, **k):
    p = store.path(card)
    s = open(p).read()
    open(p, "w").write(s.replace("- Seed photos are 800 px wide. (26-02-01) ^gd01\n", his + "\n"))
    return gate(*a, **k)
memory_check.run = racing
sys.exit(memory_txn.apply(store, staging))
PY
}

t "selftest: the store is the sandbox fixture, never the real one"
setup
h="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$ROOT/lib")"
{ [ "$h" = "$St" ] && [ "$(realpath -m "$h")" != "$(realpath -m "$REAL_STORE")" ]; } && ok || { no "not the fixture: $h"; exit 1; }

t "a line written during the gate survives: apply red, nothing moved, his line kept"
S="$(mem stage)"
swap "$S/$CARD" '- The catalogue builds with `make seeds`. (26-02-02) ^gd02' '- The catalogue builds with `make catalogue`. (26-02-02) ^gd02'
apply_racing "$S" >"$T/a.out" 2>&1; rc=$?
{ [ "$rc" = 1 ] && grep -qxF -- "$HIS" "$St/$CARD" && grep -q 'changed in the store while apply ran' "$T/a.out" \
  && ! grep -q 'make catalogue' "$St/$CARD" && [ "$(git -C "$St" log --format=%s)" = seed ]; } \
  && ok || no "rc $rc: $(cat "$T/a.out"; grep gd0 "$St/$CARD")"

t "the next stage and apply land both lines"
S="$(mem stage)"
swap "$S/$CARD" '- The catalogue builds with `make seeds`. (26-02-02) ^gd02' '- The catalogue builds with `make catalogue`. (26-02-02) ^gd02'
mem apply "$S" >"$T/b.out" 2>&1; rc=$?
{ [ "$rc" = 0 ] && grep -qxF -- "$HIS" "$St/$CARD" && grep -q 'make catalogue' "$St/$CARD" && [ -z "$(git -C "$St" status --porcelain)" ]; } \
  && ok || no "rc $rc: $(cat "$T/b.out")"

exit "$fail"
