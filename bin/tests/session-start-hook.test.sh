#!/usr/bin/env bash
# adapters/claude/hooks/session-start.sh with HOME and HARNESS_HOME in a mktemp dir: exits 0, prints the SessionStart
# JSON it promises (ADHD rules + machine brief), writes nothing outside the temp dir (bwrap read-only root; selftest proves it).
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
exit $bad
