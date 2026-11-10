#!/usr/bin/env bash
# T1599-M11: the new-PC memory drill (PLAN §9): a throwaway HOME, a clone from a local bare copy of the store (never
# GitHub, never a push), `memory install`, `memory check --live`; pass = 5/5 in under 600 s, seconds printed.
# Source: MEMORY_DRILL_SOURCE (default the synthetic fixtures/memory-drill/store); it is only read. The model is a stub
# that answers with `memory load` unless MEMORY_LIVE=1 (real haiku through the adapter, credentials linked read-only).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
BIN="$(dirname "$here")"; ROOT="$(dirname "$BIN")"
REAL_HOME="$HOME"
REAL_STORE="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$ROOT/lib")"
LIMIT=600

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"; S="$H/memory"; mkdir -p "$H/proj/alpha" "$H/agents" "$WORK/bin"
SRC="${MEMORY_DRILL_SOURCE:-$here/fixtures/memory-drill/store}"
export GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
       GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
src_state() { git -C "$SRC" rev-parse HEAD 2>/dev/null; git -C "$SRC" status --porcelain 2>/dev/null | sha256sum; }
fx() { env -u CLAUDE_CONFIG_DIR -u CHAT_SEAT -u MEMORY_DOMAINS -u HARNESS_ENV_LOADED -u AGENT_WORK \
  HOME="$H" MEMORY_HOME="$S" HARNESS_CONFIG="$WORK/none.env" PATH="$WORK/bin:$PATH" "$@"; }

# Selftest: HOME and MEMORY_HOME are the throwaway ones, never the real store.
got=$(fx python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import memory_store; print(memory_store.home())' "$ROOT/lib")
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && [ "$H" != "$REAL_HOME" ] && ok_home=1
truthy "selftest: MEMORY_HOME and HOME are throwaway, not the real ones" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

# A source that is not a repo (the fixture) becomes one in WORK; a repo is read by `git clone --bare` only.
if [ "$(git -C "$SRC" rev-parse --show-toplevel 2>/dev/null)" != "$(realpath "$SRC")" ]; then
  cp -r "$SRC" "$WORK/src"; SRC="$WORK/src"
  git -C "$SRC" init -q -b main && git -C "$SRC" add -A && git -C "$SRC" commit -qm fixture
fi
before=$(src_state)
printf '# home\n@~/agents/AGENTS.md\n' >"$H/CLAUDE.md"
ln -s "$BIN/memory" "$WORK/bin/memory"
if [ "${MEMORY_LIVE:-}" = 1 ]; then
  HOME="$REAL_HOME" plan-usage --check 80 >/dev/null 2>&1 || { nok "live: plan-usage --check 80" "over 80 % or unreadable"; exit 1; }
  mkdir -p "$H/.claude"; ln -s "$REAL_HOME/.claude/.credentials.json" "$H/.claude/.credentials.json"
else
  printf '#!/usr/bin/env bash\ncat >/dev/null; m=$(memory load | tr "\\n" " ")\nfor i in 1 2 3 4 5; do echo "$i: $m"; done\n' >"$WORK/bin/quiz-stub"
  chmod +x "$WORK/bin/quiz-stub"; export MEMORY_QUIZ_CMD=quiz-stub
fi

# The drill: the 4 commands of PLAN §9, the clone from a local bare copy; install.sh is the fleet step outside this test.
t0=$(date +%s)
git clone -q --bare "$SRC" "$WORK/bare.git"; rc_bare=$?
fx git clone -q "$WORK/bare.git" "$S"; rc_clone=$?
inst=$(fx HARNESS_HOME="$H/agents" memory install 2>&1); rc_inst=$?
live=$(cd "$WORK" && fx HARNESS_HOME="$ROOT" memory check --live 2>&1); rc_live=$?
secs=$(( $(date +%s) - t0 ))

is "clone from a local bare copy: rc 0" "$rc_bare $rc_clone" "0 0"
is "the clone's origin is the local bare copy, not a network remote" "$(git -C "$S" remote get-url origin)" "$WORK/bare.git"
is "memory install: rc 0" "$rc_inst" 0
is "~/CLAUDE.md imports the core card" "$(grep -cx '@~/memory/core/CORE.md' "$H/CLAUDE.md")" 1
ev "memory check --live: rc 0 and 5/5" '[ "$rc_live" = 0 ] && grep -qx "live · 5/5" <<<"$live"'
[ "$rc_live" = 0 ] || printf '%s\n' "$live" | grep -v '^approval' | tail -8
ev "drill under $LIMIT s" '[ "$secs" -lt "$LIMIT" ]'
is "the source is only read (HEAD and status unchanged)" "$(src_state)" "$before"
echo "memory-drill: ${secs} s ($([ "${MEMORY_LIVE:-}" = 1 ] && echo live haiku || echo stub)), source $([ -n "${MEMORY_DRILL_SOURCE:-}" ] && echo MEMORY_DRILL_SOURCE || echo fixture)"
exit $bad
