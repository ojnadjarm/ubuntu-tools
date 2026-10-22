#!/usr/bin/env bash
# adapters/claude/hooks/session-start.sh with HOME and HARNESS_HOME in a mktemp dir: exits 0, prints the SessionStart
# JSON it promises (ADHD rules + machine brief), writes nothing outside the temp dir (bwrap read-only root; selftest proves it);
# with $CLAUDE_ENV_FILE and no /usr/sbin on PATH it appends the sbin export once (T1123).
set -uo pipefail
SELF=$(readlink -f "$0"); AG=$(cd "$(dirname "$SELF")/../.." && pwd)
HOOK=$AG/adapters/claude/hooks/session-start.sh
. "$AG/bin/tests/lib/assert.sh"
. "$AG/bin/tests/lib/budget.sh"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
H=$T/home
mkdir -p "$H/agents/bin" "$H/.claude/skills/i-have-adhd" "$T/run" "$T/bin"
ln -s "$AG/bin/harness" "$H/agents/bin/harness"
printf -- '---\nname: i-have-adhd\n---\nFIXTURE ADHD RULES\n' >"$H/.claude/skills/i-have-adhd/SKILL.md"
printf '#!/bin/sh\necho "AC 50%% fixture-brief"\n' >"$T/bin/timeout"; chmod +x "$T/bin/timeout"

box() {
  bwrap --ro-bind / / --dev /dev --proc /proc --bind "$T" "$T" --chdir "$T" -- \
    env -i PATH=/usr/bin:/bin HOME="$H" HARNESS_HOME="$H/agents" XDG_RUNTIME_DIR="$T/run" TMPDIR="$T" \
    PC_TIMEOUT_BIN="$T/bin/timeout" "$@"
}

box sh -c 'touch "$0/x" 2>/dev/null' "$AG" && { echo 'FAIL selftest: the sandbox can write outside the temp dir'; exit 1; }
box sh -c 'touch "$HOME/x"' || { echo 'FAIL selftest: the sandbox cannot write its temp HOME'; exit 1; }
ok 'selftest: only the temp dir is writable'

lim=$(budget 2)
t0=$(date +%s.%N)
out=$(box "$HOOK"); rc=$?
wall=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.2f", b-a}')
is "exits 0" "$rc" 0
python3 - "$out" <<'PY'
import json, sys
j = json.loads(sys.argv[1])
ctx = j["hookSpecificOutput"]["additionalContext"]
for name, cond in [
    ("hookEventName is SessionStart", j["hookSpecificOutput"]["hookEventName"] == "SessionStart"),
    ("systemMessage: ADHD banner + machine brief", j["systemMessage"] == "Harness: ADHD mode on · Machine: AC 50% fixture-brief"),
    ("context: ADHD rules from the temp HOME, front matter stripped",
     "FIXTURE ADHD RULES" in ctx and "name: i-have-adhd" not in ctx),
    ("context: machine brief and the guide pointer", "Machine now: AC 50% fixture-brief." in ctx and "`guide <words>`" in ctx),
    ("context: no Moodle block without a detector", "MOODLE PROJECT DETECTED" not in ctx),
]:
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        sys.exit(1)
PY
is "prints the SessionStart JSON it promises" "$?" 0
awk -v w="$wall" -v l="$lim" 'BEGIN{exit !(w <= l)}'; is "wall ${wall} s <= ${lim} s" "$?" 0

LINE='export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"'
envrun() { : >"$T/env.$1"; box env CLAUDE_ENV_FILE="$T/env.$1" PATH="$2" "${3:-$HOOK}"; }
j1=$(envrun a /usr/bin:/bin); rc=$?
is "env file: exits 0" "$rc" 0
is "env file: harness JSON unchanged" "$j1" "$out"
is "env file: PATH without sbin gets the sbin export once" "$(grep -cxF "$LINE" "$T/env.a")" 1
box env CLAUDE_ENV_FILE="$T/env.a" PATH=/usr/bin:/bin "$HOOK" >/dev/null
is "env file: a second run adds nothing" "$(wc -l <"$T/env.a")" 1
envrun b /usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin >/dev/null
is "env file: PATH with /usr/sbin gets no line" "$(wc -c <"$T/env.b")" 0
touch "$T/mark"; sleep 0.01
box "$HOOK" >/dev/null
is "no CLAUDE_ENV_FILE: writes nothing" "$(find "$T" -newer "$T/mark" -type f | wc -l)" 0
sed '/>>"$CLAUDE_ENV_FILE"/d' "$HOOK" >"$T/mutant.sh"; chmod +x "$T/mutant.sh"
envrun m /usr/bin:/bin "$T/mutant.sh" >/dev/null
[ "$(grep -cxF "$LINE" "$T/env.m")" = 1 ] && nok "mutation: a hook without the export goes red" "mutant passed" \
  || ok "mutation: a hook without the export goes red"
exit $bad
