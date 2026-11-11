#!/usr/bin/env bash
# shellcheck disable=SC2016  # ev evals its single-quoted checks
# T1624-R8: the claude adapter installer's --help/-h print usage and exit 0, an unknown flag exits 2, both write nothing.
# Fixture HOME + copied adapter; never touches the live ~/.claude.
set -uo pipefail
REAL="$HOME/agents"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FH="$W/home"; H="$FH/agents"; CTX="$FH/.claude"
mkdir -p "$H/bin" "$H/adapters" "$H/skills/one" "$CTX"
cp -r "$REAL/adapters/claude" "$H/adapters/"; cp "$REAL/bin/env.sh" "$H/bin/"
echo one >"$H/skills/one/SKILL.md"
echo '{}' >"$CTX/settings.json"; echo '# mine' >"$FH/CLAUDE.md"
run() { env -i HOME="$FH" PATH=/usr/bin:/bin HARNESS_CONFIG="$W/none.env" bash "$H/adapters/claude/install" "$@"; }
snap() { (cd "$FH" && find . -path ./agents -prune -o -print0 | sort -z | xargs -0 ls -ld --time-style=+%s.%N; cat .claude/settings.json CLAUDE.md); }

. "$HOME/agents/bin/tests/lib/assert.sh"

ev "selftest: the fixture HOME is not the real one" '[ "$FH" != "$HOME" ] && [ "$CTX" != "$HOME/.claude" ]'
before=$(snap)
for f in --help -h; do
  out=$(run "$f" 2>&1); rc=$?
  ev "$f: exit 0" '[ "$rc" = 0 ]'
  ev "$f: prints usage" 'grep -q "^usage: install" <<<"$out"'
  ev "$f: writes nothing" '[ "$(snap)" = "$before" ]'
done
out=$(run --bogus 2>&1); rc=$?
ev "unknown flag: exit 2" '[ "$rc" = 2 ]'
ev "unknown flag: names it" 'grep -q "unknown argument: --bogus" <<<"$out"'
ev "unknown flag: writes nothing" '[ "$(snap)" = "$before" ]'
run --plan >/dev/null 2>&1; rc=$?
ev "--plan still exits 0 and writes nothing" '[ "$rc" = 0 ] && [ "$(snap)" = "$before" ]'

exit $bad
