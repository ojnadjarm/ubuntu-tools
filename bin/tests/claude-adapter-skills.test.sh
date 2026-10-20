#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # ev evals its single-quoted checks
# T531: the claude adapter links an absent skill as a whole dir, keeps a real dir's SKILL.md link, is idempotent,
# and its uninstaller removes both. Fixture HOME + copied adapter; never touches the live ~/.claude.
set -uo pipefail
REAL="$HOME/agents"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FH="$W/home"; H="$FH/agents"; CTX="$FH/.claude"
mkdir -p "$H/bin" "$H/adapters" "$H/skills/new/scripts" "$H/skills/old" "$CTX/skills/old"
cp -r "$REAL/adapters/claude" "$H/adapters/"; cp "$REAL/bin/env.sh" "$H/bin/"
for s in new old; do echo "$s" >"$H/skills/$s/SKILL.md"; done
echo x >"$H/skills/new/scripts/tool"
run() { env -i HOME="$FH" PATH=/usr/bin:/bin HARNESS_CONFIG="$W/none.env" bash "$H/adapters/claude/$1"; }

. "$HOME/agents/bin/tests/lib/assert.sh"

o1=$(run install)
ev "absent skill linked as a dir" '[ -L "$CTX/skills/new" ] && [ "$(readlink -f "$CTX/skills/new")" = "$H/skills/new" ]'
ev "dir link reaches its scripts" '[ -f "$CTX/skills/new/scripts/tool" ]'
ev "real dir keeps a SKILL.md link" '[ ! -L "$CTX/skills/old" ] && [ -L "$CTX/skills/old/SKILL.md" ]'
ev "first run reports both links" '[ "$(grep -c "^linked " <<<"$o1")" = 2 ]'
o2=$(run install)
ev "second run: no skill changes" '! grep -q "^linked " <<<"$o2"'
run uninstall >/dev/null
ev "uninstall removes the dir link" '[ ! -e "$CTX/skills/new" ] && [ ! -L "$CTX/skills/new" ]'
ev "uninstall removes the SKILL.md link" '[ ! -e "$CTX/skills/old" ]'
ev "skill sources kept" '[ -f "$H/skills/new/scripts/tool" ] && [ -f "$H/skills/old/SKILL.md" ]'

exit $bad
