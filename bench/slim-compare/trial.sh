#!/usr/bin/env bash
# trial.sh <ticket> <old|slim>: replay one past ticket under one instruction arm inside the sandbox; results in $OUT/runs/<ticket>-<arm>/.
set -euo pipefail
SC=$(cd "$(dirname "$0")" && pwd)
OUT=${T1773_OUT:-$HOME/agent-work/research/2026-11-18/T1773}
SCR=${T1773_SCRATCH:-$HOME/.cache/t1773}
tk=${1:?ticket}; arm=${2:?arm}
row=$(awk -F'\t' -v t="$tk" '$1==t' "$OUT/tickets.tsv")
[ -n "$row" ] || { echo "trial: $tk not in tickets.tsv" >&2; exit 2; }
IFS=$'\t' read -r _ class brief commit hide fix chk <<<"$row"
A=$SCR/arms/$arm; T=$SCR/trials/$tk-$arm; R=$OUT/runs/$tk-$arm
[ -d "$A" ] || { echo "trial: no arm $A (build_arms.py)" >&2; exit 2; }
[ -n "${T1773_RECHECK:-}" ] || { chmod -R u+rwx "$T" 2>/dev/null || true; rm -rf "$T"; mkdir -p "$T"; }
src=$OUT/briefs-slim/$brief; [ "$arm" = old ] && src=$HOME/agent-work/briefs/$brief

if [ -z "${T1773_RECHECK:-}" ]; then
# Setup layer: ticket-time tree, arm instruction files, ticket outputs hidden.
"$SC/sandbox.sh" setup "$T" -- bash -euo pipefail -c '
  A=$1 commit=$2 brief=$3 src=$4 hide=$5 fix=$6
  g() { git -C "$HOME/$1" "${@:2}"; }
  g agents checkout -q -f --detach "$commit"
  for r in $(g agents remote); do g agents remote remove "$r"; done
  (cd "$A/agents" && find . -type f) | while read -r f; do cp -f "$A/agents/$f" "$HOME/agents/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$HOME/agents/$f"; done < "$A/agents.absent"
  rm -rf "$HOME/agents/secrets"/* 2>/dev/null || true
  g memory checkout -q -f --detach "$(cat "$A/memory.commit")"
  for r in $(g memory remote); do g memory remote remove "$r"; done
  (cd "$A/claude" && find . -type f) | while read -r f; do cp -f "$A/claude/$f" "$HOME/.claude/$f"; done
  # Test-infra repairs from later commits (environment drift), committed so they read as the starting tree.
  if [ "$fix" != - ] && [ -n "$fix" ]; then
    for cp in ${fix//,/ }; do g agents show "$cp" > "$HOME/agents/${cp#*:}"; g agents add -- "${cp#*:}"; done
    g agents commit -q -m "fixture: test repair" >&2
  fi
  [ "$brief" = - ] && { g agents rev-parse HEAD; exit 0; }
  [ "$src" -ef "$HOME/agent-work/briefs/$brief" ] || cp -f "$src" "$HOME/agent-work/briefs/$brief"
  t=${brief%%-*}
  cd "$HOME/agent-work"; for h in $hide research/*/"$t" evidence/"$t" research/2026-11-18/T1773; do rm -rf "$h"; done
  rm -rf "$HOME/drop/$t" "$HOME/drop/${t,,}"
  g agents rev-parse HEAD
' _ "$A" "$commit" "$brief" "$src" "${hide//,/ }" "${fix:--}" > "$T/setup.head" 2> "$T/setup.err" || { cat "$T/setup.err" >&2; exit 3; }

[ -z "${T1773_SETUP_ONLY:-}" ] || exit 0
fi
# The CHECK the sandbox can run (tickets.tsv column 7, validated by oracle.sh on the real solution), else the brief's.
[ -n "${chk:-}" ] && [ "$chk" != - ] || chk=$(sed -n 's/^CHECK: *//p' "$src" | tr -d '`')
if [ -z "${T1773_RECHECK:-}" ]; then
rm -rf "$R"; mkdir -p "$R"

cat > "$T/prompt.txt" <<EOF
Spawn exactly one agent with the Agent tool: subagent_type "worker", description "$tk", and as its prompt exactly the text between the two lines of dashes. Do nothing else yourself; when it returns, print its report verbatim and stop.
-----
Your brief is the file ~/agent-work/briefs/$brief. Read it whole and do exactly that. Run \`agent-verify ~/agent-work/briefs/$brief\` before handback. If a permission is refused, do not work around it: stop and report. Report: max 6 lines, numbers only.
-----
EOF
date -Is > "$R/start"
set +e
timeout "${T1773_TRIAL_S:-3600}" "$SC/sandbox.sh" run "$T" -- bash -c 'cd "$HOME" && exec claude -p "$(cat "$1")" --model opus \
  --permission-mode bypassPermissions --output-format stream-json --verbose --name "t1773-$2" < /dev/null' _ "$T/prompt.txt" "$tk-$arm" \
  > "$R/stream.jsonl" 2> "$R/stderr.log"
echo $? > "$R/exit"
fi
# The brief's CHECK and the git facts, read inside the same sandbox after the agent ends.
"$SC/sandbox.sh" run "$T" -- bash -c '
  bash -c "$3" > /tmp/v.out 2>&1; echo "check_exit=$?"; tail -5 /tmp/v.out | sed "s/^/check: /"
  echo "commits:"; git -C "$HOME/agents" log --format=%h --name-only "$2..HEAD" 2>/dev/null | sed "s/^/  /"
  echo "tests_changed:"; git -C "$HOME/agents" diff --name-only --diff-filter=MD "$2" 2>/dev/null | grep -E "(^|/)tests?/" | sed "s/^/  /"
' _ "$brief" "$(cat "$T/setup.head")" "$chk" > "$R/check.txt" 2>&1
set -e
date -Is > "$R/end"
python3 "$SC/measure.py" "$tk" "$arm" "$T" "$R" "$src" > "$R/measures.json"
cat "$R/measures.json"
