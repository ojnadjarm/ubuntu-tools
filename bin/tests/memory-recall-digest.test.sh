#!/usr/bin/env bash
# shellcheck disable=SC2016  # ev evals its single-quoted checks
# T1624-R8: the Sunday digest line `recall: N hints, N opened, N links grown, N faded (7 days)` in a fixture keeper run
# (stage, the recorded judgement, apply) and memory_fold.week's 7-day window. Sandbox only (AGENTS.md §5.6): HOME,
# AGENT_WORK, HARNESS_HOME (audit log), XDG_RUNTIME_DIR and MEMORY_HOME are temp dirs over the synthetic keeper fixture.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/assert.sh"
MEM="$(dirname "$here")/memory"
LIB="$(dirname "$(dirname "$here")")/lib"
FX="$here/fixtures/memory-keeper"
py() { python3 -c "import sys; sys.path.insert(0, '$LIB'); $1" "${@:2}"; }
REAL_STORE="$(py 'import memory_store; print(memory_store.home())')"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" AGENT_WORK="$T/aw" MEMORY_HOME="$T/store" XDG_RUNTIME_DIR="$T/run" HARNESS_HOME="$T/harness" \
       HARNESS_CONFIG=/nonexistent
unset CLAUDE_CONFIG_DIR CHAT_SEAT MEMORY_DOMAINS MEMORY_RECALL MEMORY_RECALL_DONE CLAUDE_CODE_SESSION_ID MEMORY_WORKER
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
       GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
mkdir -p "$HOME" "$AGENT_WORK" "$XDG_RUNTIME_DIR" "$HARNESS_HOME/log" "$T/proj"
S="$MEMORY_HOME"; EV="$AGENT_WORK/memory-recall/events"; AUD="$HARNESS_HOME/log/actions.jsonl"

got="$(py 'import memory_store; print(memory_store.home())')"
ok_home=0; [ "$got" = "$S" ] && [ "$(realpath -m "$got")" != "$(realpath -m "$REAL_STORE")" ] && \
  [ "$(realpath -m "$AUD")" != "$(realpath -m ~/agents/log/actions.jsonl)" ] && ok_home=1
truthy "selftest: MEMORY_HOME and the audit log are throwaway, not the real ones" "$ok_home"
[ "$bad" = 0 ] || { echo "selftest failed: no case runs"; exit 1; }

cp -r "$FX/store" "$S"; cp -r "$FX/projects/." "$T/proj/"
sed "s#@P@#$T/proj#" "$S/domains.map.in" >"$S/domains.map"; rm "$S/domains.map.in"
git -C "$S" init -q -b main && git -C "$S" add -A && git -C "$S" commit -qm seed
cp "$FX"/notes/*.md "$S/inbox/"

now() { date -d "$1" +%Y-%m-%dT%H:%M:%S%z; }
mkdir -p "$EV"
printf '%s\t%s\tc:catalogue,c:seeds\tgd02\n' "$(now '-2 min')" "$(py 'import memory_recall; print(memory_recall.session_hash(sys.argv[1]))' sessdig)" \
  >>"$EV/$(date +%Y-%m-%d).tsv"
py 'import json; print(json.dumps({"ts": sys.argv[1], "session": "sessdig", "tool": "Bash", "summary": "memory show gd02"}))' \
  "$(now '-1 min')" >>"$AUD"

ST="$("$MEM" stage)"; cp -r "$FX/recorded/." "$ST/"
"$MEM" apply "$ST" >"$T/apply.out" 2>&1; rc=$?
is "keeper run: apply green, exit 0" "$rc" 0
ev "keeper run: apply prints the digest line (1 hint, 1 opened)" \
  'grep -qE "^recall: 1 hints, 1 opened, [1-9][0-9]* links grown, 0 faded \(7 days\)$" "$T/apply.out"'
ev "keeper brief: the Sunday report carries the recall: line" 'grep -q "the \`recall:\` line" "$here/../../memory-keeper/BRIEF.md"'

F="$AGENT_WORK/memory-recall/folds.tsv"
row() { printf '%s\t%s\t%s\n' "$(now "$1")" "$(now "$2")" "$3" >>"$F"; }
row '-10 days' '-9 days' $'50\t50\t50\t50'
row '-3 days' '-2 days' $'9\t9\t9\t9'
row '-3 days' '-2 days' $'2\t1\t3\t1'
w="$(py 'import memory_fold; print(memory_fold.week())')"
is "week: older than 7 days left out, a re-fold from one cursor counted once" "$w" \
   "recall: 3 hints, 2 opened, $(( $(grep -oP '^recall: .* \K[0-9]+(?= links grown)' "$T/apply.out") + 3 )) links grown, 1 faded (7 days)"
ev "folds log: numbers only, no cue or id" '! grep -qE "c:|gd02|catalogue" "$F"'

[ "$bad" = 0 ] && echo "all memory-recall-digest cases pass"
exit $bad
