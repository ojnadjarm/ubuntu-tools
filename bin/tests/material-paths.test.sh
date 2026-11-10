#!/usr/bin/env bash
# T1597: work material (backups, claims snapshots, toolsmith papers, published plans) resolves under $AGENT_WORK, never
# under $HARNESS_HOME; no tracked tool names the old homes except a line marked `fallback`. Fake HOME, writes nothing real.
set -uo pipefail
A="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
. "$A/bin/tests/lib/assert.sh"
bad=0
OLD='HARNESS_HOME/backups|agents/backups|state/claims-snap|agents/dashboard/plans|HERE, .plans|agents/toolsmith/(proposals|BACKLOG)|AGENTS, .toolsmith'

# scan <dir> — tool lines (not tests, not docs) naming an old home without a `fallback` mark.
scan() { grep -rnE "$OLD" "$1" --include='*' 2>/dev/null | grep -v '/tests/' | grep -v 'fallback' | grep -vE '\.(md|html)(:|$)'; }

mkdir -p "$W/neg/bin"; printf 'BAK="$HARNESS_HOME/backups/x"\n' >"$W/neg/bin/tool"
is "selftest: the scan catches an old-path writer" "$(scan "$W/neg" | wc -l)" 1

hits=$(cd "$A" && git ls-files bin lib units dashboard/dash code-review/swarm.js | grep -v '^bin/tests/' |
  xargs grep -nE "$OLD" 2>/dev/null | grep -v fallback)
is "no tracked tool names an old material home" "$hits" ""

H="$W/home"; mkdir -p "$H"
got=$(env -i HOME="$H" PATH="$PATH" bash -c ". '$A/bin/env.sh'; echo \$FLEET_BACKUPS_DIR \$CLAIMS_SNAP \$TOOLSMITH_PAPERS \$DASH_PLANS_DIR")
is "env.sh: every material key under AGENT_WORK" "$got" \
  "$H/agent-work/backups $H/agent-work/claims-snap $H/agent-work/toolsmith $H/agent-work/research/dashboard/plans"
got=$(env -i HOME="$H" PATH="$PATH" python3 -c "import sys; sys.path.insert(0, '$A/lib'); import agent_work as a; print(a.backups_dir(), a.claims_snap_dir(), a.toolsmith_papers(), a.dash_plans_dir())")
is "agent_work.py: the same defaults" "$got" \
  "$H/agent-work/backups $H/agent-work/claims-snap $H/agent-work/toolsmith $H/agent-work/research/dashboard/plans"
got=$(env -i HOME="$H" PATH="$PATH" FLEET_BACKUPS_DIR="$H/b" HARNESS_ENV_LOADED=1 bash -c ". '$A/bin/pclib.sh'; echo \$FLEET_BACKUPS_DIR")
is "pclib: a caller's FLEET_BACKUPS_DIR wins" "$got" "$H/b"
got=$(env -i HOME="$H" PATH="$PATH" HARNESS_ENV_LOADED=1 bash -c ". '$A/bin/pclib.sh'; echo \$FLEET_BACKUPS_DIR")
is "pclib: a session loaded before T1597 still gets the key" "$got" "$H/agent-work/backups"
case "$(env -i HOME="$H" PATH="$PATH" bash -c ". '$A/bin/env.sh'; echo \$FLEET_BACKUPS_DIR")" in
  "$H/agents"/*) nok "backups dir is outside HARNESS_HOME" "under $H/agents" ;; *) ok "backups dir is outside HARNESS_HOME" ;; esac

[ $bad = 0 ] && echo 'PASS material-paths' || echo 'FAIL material-paths'
exit $bad
