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

# T347-03: in a Moodle cwd the context stays under Claude Code's 10,000-char hook cap and points to the rules.
fx=$(mktemp -d); trap 'rm -rf "$fx"' EXIT
mkdir -p "$fx/home" "$fx/ctx/hooks" "$fx/ctx/skills/i-have-adhd" "$fx/plugin"
cp "$HOOKS/moodle-detect.sh" "$fx/ctx/hooks/"
cp "${HARNESS_CONTEXT_DIR:-$HOME/.claude}/skills/i-have-adhd/SKILL.md" "$fx/ctx/skills/i-have-adhd/"
for f in moodle-guidelines moodle-tips moodle-coding-style; do
  { echo "FIXTURE-BODY-$f"; head -c 12000 /dev/zero | tr '\0' 'x'; } > "$fx/ctx/$f.md"
done
printf '<?php\n$plugin->component = "local_fx";\n' > "$fx/plugin/version.php"
mctx() { (cd "$fx/plugin" && env -u CLAUDE_PROJECT_DIR HOME="$fx/home" HARNESS_CONTEXT_DIR="$fx/ctx" "$@" "$HARNESS" context --json) |
  python3 -c 'import json,sys;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }
for mode in human headless; do
  if [ "$mode" = human ]; then c=$(mctx env -u AGENT_NAME); else c=$(mctx env AGENT_NAME=x); fi
  [ "${#c}" -lt 9500 ] && ok 1 "$mode Moodle context under 9500 chars (${#c})" || ok 0 "$mode Moodle context under 9500 chars (${#c})"
  for f in moodle-guidelines moodle-tips moodle-coding-style; do
    case "$c" in *"$fx/ctx/$f.md"*) ok 1 "$mode context points to $f.md";; *) ok 0 "$mode context points to $f.md";; esac
  done
  case "$c" in *FIXTURE-BODY-*) ok 0 "$mode context inlines no rule file";; *) ok 1 "$mode context inlines no rule file";; esac
  case "$c" in *"/moodle-ci"*) ok 1 "$mode context names /moodle-ci";; *) ok 0 "$mode context names /moodle-ci";; esac
done
case "$(mctx env -u AGENT_NAME)" in *"ADHD OUTPUT MODE"*) ok 1 "human Moodle context keeps the output rules";; *) ok 0 "human Moodle context keeps the output rules";; esac

[ "$bad" = 0 ] && echo "all harness-context cases pass" || echo "$bad FAILURES"
exit $([ "$bad" = 0 ] && echo 0 || echo 1)
