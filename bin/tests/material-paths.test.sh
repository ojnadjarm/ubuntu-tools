#!/usr/bin/env bash
# T1597, T1603: work material (backups, claims snapshots, toolsmith papers, published plans, liaison jobs, bench runs/arms,
# PO done/, the voice corpus, improve queue/metrics, code-review runs, gamedev-perf) resolves under $AGENT_WORK, never
# under $HARNESS_HOME; no tracked tool names the old homes except a line marked `fallback`. Fake HOME, writes nothing real.
set -uo pipefail
A="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
. "$A/bin/tests/lib/assert.sh"
bad=0
OLD='HARNESS_HOME''/backups|agents''/backups|state/claims-snap|agents/dashboard/plans|HERE, .plans|agents/toolsmith/(proposals|BACKLOG)|AGENTS, .toolsmith'
OLD="$OLD"'|discord-liaison/state/(jobs|art|escalations|work)|.state., .(jobs|art|escalations|work).|agents/bench/(runs|state|arms/(new|old))'
OLD="$OLD"'|BENCH, "runs"|\$BENCH/(state|arms/\$arm)|SRC/bench/arms/(new|old)|"\$dir/done"|"\$s/done"|agents/asr-corpus|"agents", "asr-corpus"'
OLD="$OLD"'|AGENTS \+ "/asr-corpus"|\$A/asr-corpus|agents/improve|AGENTS, .improve|.improve., .queue.|STATE, .runs.|state/gamedev-perf|.state., .gamedev-perf.'

# scan <dir> — tool lines (not tests, not docs) naming an old home without a `fallback` mark.
scan() { grep -rnE "$OLD" "$1" --include='*' 2>/dev/null | grep -v '/tests/' | grep -v 'fallback' | grep -vE '\.(md|html)(:|$)'; }

mkdir -p "$W/neg/bin"; printf 'BAK="$HARNESS_HOME/%s/x"\n' backups >"$W/neg/bin/tool"
is "selftest: the scan catches an old-path writer" "$(scan "$W/neg" | wc -l)" 1
printf 'J = os.path.join(self.home, %s, %s)\nD="$dir/%s"\n' "'state'" "'jobs'" done >"$W/neg/bin/tool2"
is "selftest: the scan catches a T1603 old-path writer (liaison jobs, PO done)" "$(scan "$W/neg" | wc -l)" 3

hits=$(cd "$A" && git ls-files bin lib units dashboard/dash code-review/swarm.js code-review/selftest discord-liaison/liaison bench/arms | grep -v '^bin/tests/' |
  xargs grep -nE "$OLD" 2>/dev/null | grep -v fallback | grep -vE '^[^:]+\.(md|html):')
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
K='LIAISON_PAPERS BENCH_PAPERS PO_PAPERS ASR_CORPUS IMPROVE_PAPERS CODE_REVIEW_PAPERS GAMEDEV_PERF_DIR'
T="$H/agent-work/discord-liaison $H/agent-work/bench $H/agent-work/po $H/agent-work/owner/asr-corpus $H/agent-work/improve $H/agent-work/code-review $H/agent-work/gamedev-perf"
got=$(env -i HOME="$H" PATH="$PATH" bash -c ". '$A/bin/env.sh'; for k in $K; do printf '%s ' \"\${!k}\"; done")
is "env.sh: the T1603 keys under AGENT_WORK" "$got" "$T "
got=$(env -i HOME="$H" PATH="$PATH" python3 -c "import sys; sys.path.insert(0, '$A/lib'); import agent_work as a; print(a.liaison_papers(), a.bench_papers(), a.po_papers(), a.asr_corpus(), a.improve_papers(), a.code_review_papers(), a.gamedev_perf_dir())")
is "agent_work.py: the same T1603 defaults" "$got" "$T"
got=$(env -i HOME="$H" PATH="$PATH" HARNESS_ENV_LOADED=1 FLEET_BACKUPS_DIR="$H/b" bash -c ". '$A/bin/pclib.sh'; echo \$LIAISON_PAPERS")
is "pclib: a session loaded before T1603 still gets LIAISON_PAPERS" "$got" "$H/agent-work/discord-liaison"
got=$(env -i HOME="$H" PATH="$PATH" HARNESS_ENV_LOADED=1 FLEET_BACKUPS_DIR="$H/b" bash -c ". '$A/bin/polib.sh'; po_done fx")
is "polib: po_done under PO_PAPERS" "$got" "$H/agent-work/po/fx/done"
case "$(env -i HOME="$H" PATH="$PATH" bash -c ". '$A/bin/env.sh'; echo \$FLEET_BACKUPS_DIR")" in
  "$H/agents"/*) nok "backups dir is outside HARNESS_HOME" "under $H/agents" ;; *) ok "backups dir is outside HARNESS_HOME" ;; esac

[ $bad = 0 ] && echo 'PASS material-paths' || echo 'FAIL material-paths'
exit $bad
