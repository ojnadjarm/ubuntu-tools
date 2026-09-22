#!/usr/bin/env bash
# GH08: `harness context --json` must carry exactly what the two live SessionStart hooks inject,
# in their settings.json order (moodle-session-start, then machine-status).
set -uo pipefail
HARNESS="$HOME/agents/bin/harness"
HOOKS="${HARNESS_CONTEXT_DIR:-$HOME/.claude}/hooks"
bad=0
ok() { if [ "$1" = 1 ]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad+1)); fi; }

merged=$("$HARNESS" context --json) || merged=""
want=$(python3 - "$HOOKS" <<'PY'
import json, os, subprocess, sys
hooks = sys.argv[1]
def run(name):
    p = os.path.join(hooks, name)
    out = subprocess.run([p], capture_output=True, text=True).stdout.strip()
    return json.loads(out) if out else {}
a, b = run("moodle-session-start.sh"), run("machine-status.sh")
ctx = lambda d: (d.get("hookSpecificOutput") or {}).get("additionalContext", "")
print(json.dumps({
    "systemMessage": " · ".join(x for x in (a.get("systemMessage",""), b.get("systemMessage","")) if x),
    "hookSpecificOutput": {"hookEventName": "SessionStart",
                           "additionalContext": "\n\n".join(x for x in (ctx(a), ctx(b)) if x)},
}))
PY
)
# The machine brief is sampled live, so ram/load/temp differ between two calls milliseconds
# apart; blank the brief itself and compare everything the composition owns.
norm() { sed -E 's/(Machine: |Machine now: )[^"]*?(\\.|")/\\1<brief>\\2/g; s/Machine: [^"]*/Machine: <brief>/g; s/Machine now: [^.]*\\./Machine now: <brief>./g'; }
if [ "$(printf '%s' "$merged" | norm)" = "$(printf '%s' "$want" | norm)" ]; then
  ok 1 "context --json equals the two hooks merged"
else
  ok 0 "context --json equals the two hooks merged"
  diff <(printf '%s' "$want" | norm | fold -w160) <(printf '%s' "$merged" | norm | fold -w160) | head -6
fi

b1=$("$HARNESS" context --brief); b2=$("$HOME/agents/bin/pc" status --brief)
[ -n "$b1" ] && [ "${b1%% *}" = "${b2%% *}" ] && ok 1 "context --brief is the machine brief" || ok 0 "context --brief is the machine brief"

"$HARNESS" context --moodle | grep -q "MOODLE PROJECT DETECTED" && ok 1 "--moodle forces the guidelines section" || ok 0 "--moodle forces the guidelines section"
env -u AGENT_NAME "$HARNESS" context | grep -q "ADHD OUTPUT MODE" && ok 1 "plain text carries the output rules" || ok 0 "plain text carries the output rules"
AGENT_NAME=x "$HARNESS" context --json | grep -q "ADHD OUTPUT MODE" && ok 0 "AGENT_NAME drops the output rules" || ok 1 "AGENT_NAME drops the output rules"
AGENT_NAME=x "$HARNESS" context --json | grep -q '"hookEventName": "SessionStart"' && ok 1 "AGENT_NAME keeps the machine context" || ok 0 "AGENT_NAME keeps the machine context"
"$HARNESS" bogus >/dev/null 2>&1; [ $? = 2 ] && ok 1 "unknown subcommand exits 2" || ok 0 "unknown subcommand exits 2"

[ "$bad" = 0 ] && echo "all harness-context cases pass" || echo "$bad FAILURES"
exit $([ "$bad" = 0 ] && echo 0 || echo 1)
