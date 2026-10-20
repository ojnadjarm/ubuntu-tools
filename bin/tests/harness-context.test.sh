#!/usr/bin/env bash
# host-only: merges this box's real ~/.claude Moodle hooks
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
if [ ! -f "$HOOKS/moodle-session-start.sh" ]; then
  echo "SKIP owner data absent: $HOOKS/moodle-session-start.sh"
elif [ "$(printf '%s' "$merged" | norm)" = "$(printf '%s' "$want" | norm)" ]; then
  ok 1 "context --json equals the two hooks merged"
else
  ok 0 "context --json equals the two hooks merged"
  diff <(printf '%s' "$want" | norm | fold -w160) <(printf '%s' "$merged" | norm | fold -w160) | head -6
fi

b1=$("$HARNESS" context --brief); b2=$("$HOME/agents/bin/pc" status --brief)
[ -n "$b1" ] && [ "${b1%% *}" = "${b2%% *}" ] && ok 1 "context --brief is the machine brief" || ok 0 "context --brief is the machine brief"

"$HARNESS" context --moodle | grep -q "MOODLE PROJECT DETECTED" && ok 1 "--moodle forces the guidelines section" || ok 0 "--moodle forces the guidelines section"
env -u AGENT_NAME -u CLAUDECODE -u HARNESS_AGENT "$HARNESS" context | grep -q "ADHD OUTPUT MODE" && ok 1 "plain text carries the output rules" || ok 0 "plain text carries the output rules"
AGENT_NAME=x "$HARNESS" context --json | grep -q "ADHD OUTPUT MODE" && ok 0 "AGENT_NAME drops the output rules" || ok 1 "AGENT_NAME drops the output rules"
AGENT_NAME=x "$HARNESS" context --json | grep -q '"hookEventName": "SessionStart"' && ok 1 "AGENT_NAME keeps the machine context" || ok 0 "AGENT_NAME keeps the machine context"
w=$("$HARNESS" context --worker)
[ "$(printf '%s\n' "$w" | wc -c)" -le 720 ] && ok 1 "--worker fits 720 bytes" || ok 0 "--worker fits 720 bytes"
case "$w" in *"6. Claims: claims add T<n>"*"wait-for --label X --until"*) ok 1 "--worker names the claims and wait-for verbs";; *) ok 0 "--worker names the claims and wait-for verbs";; esac
case "$w" in "Machine now: "*"at most 6 lines"*) ok 1 "--worker keeps the brief and report rules";; *) ok 0 "--worker keeps the brief and report rules";; esac
case "$w" in *"ADHD OUTPUT MODE"*) ok 0 "--worker drops the ADHD skill";; *) ok 1 "--worker drops the ADHD skill";; esac
"$HARNESS" bogus >/dev/null 2>&1; [ $? = 2 ] && ok 1 "unknown subcommand exits 2" || ok 0 "unknown subcommand exits 2"

# T347-03: in a Moodle cwd the context stays under Claude Code's 10,000-char hook cap and points to the rules.
fx=$(mktemp -d); trap 'rm -rf "$fx"' EXIT
mkdir -p "$fx/home" "$fx/ctx/hooks" "$fx/ctx/skills/i-have-adhd" "$fx/plugin"
if [ -f "$HOOKS/moodle-detect.sh" ]; then
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
else echo "SKIP owner data absent: $HOOKS/moodle-detect.sh"; fi

# T547: a long machine brief is cut so --worker still fits 720 bytes.
mkdir -p "$fx/bin"; cp "$HARNESS" "$fx/bin/harness"
printf '#!/bin/sh\nhead -c 900 /dev/zero | tr "\\0" b\n' > "$fx/bin/pc"; chmod +x "$fx/bin/pc"
lw=$(cd "$fx" && "$fx/bin/harness" context --worker | wc -c)
[ "$lw" -le 720 ] && ok 1 "--worker caps a 900-byte brief ($lw B)" || ok 0 "--worker caps a 900-byte brief ($lw B)"
lp=$(cd "$fx" && CLAUDECODE=1 "$fx/bin/harness" context | wc -c)
[ "$lp" -le 700 ] && ok 1 "in-agent plain caps a 900-byte brief at 700 B ($lp B)" || ok 0 "in-agent plain caps a 900-byte brief at 700 B ($lp B)"
lpt=$(cd "$fx" && CLAUDECODE=1 "$fx/bin/harness" context)
case "$lpt" in *$'\nfull rules: harness context --full') ok 1 "in-agent plain with a 900-byte brief keeps the --full line";; *) ok 0 "in-agent plain with a 900-byte brief keeps the --full line";; esac
lwt=$(cd "$fx" && "$fx/bin/harness" context --worker)
case "$lwt" in *"6. Claims: claims add T<n>"*"wait-for --label X --until"*) ok 1 "--worker with a 900-byte brief keeps rule 6";; *) ok 0 "--worker with a 900-byte brief keeps rule 6";; esac

# T602: inside an agent plain `context` is the worker form; --full and --json keep the full text.
mkdir -p "$fx/b2"; cp "$HARNESS" "$HOME/agents/bin/env.sh" "$fx/b2/"
printf '#!/bin/sh\necho FIXED-BRIEF\n' > "$fx/b2/pc"; chmod +x "$fx/b2/pc"
out() { (cd "$fx" && env -u CLAUDECODE -u HARNESS_AGENT -u AGENT_NAME "$@" "$fx/b2/harness" context ${ARGS:-}); }
human=$(out); hjson=$(ARGS=--json out)
case "$human" in *"ADHD OUTPUT MODE"*) ok 1 "outside an agent plain is the full text";; *) ok 0 "outside an agent plain is the full text";; esac
for v in CLAUDECODE=1 HARNESS_AGENT=claude; do
  a=$(out "$v")
  case "$a" in "Machine now: FIXED-BRIEF"*"at most 6 lines"*$'\nfull rules: harness context --full') ok 1 "$v plain is the worker form plus the --full line";; *) ok 0 "$v plain is the worker form plus the --full line";; esac
  [ "$(printf '%s\n' "$a" | wc -c)" -le 700 ] && ok 1 "$v plain fits 700 bytes" || ok 0 "$v plain fits 700 bytes"
  [ "$(ARGS=--full out "$v")" = "$human" ] && ok 1 "$v --full equals the outside text" || ok 0 "$v --full equals the outside text"
  [ "$(ARGS=--json out "$v")" = "$hjson" ] && ok 1 "$v --json equals the outside JSON" || ok 0 "$v --json equals the outside JSON"
done

# T993: an over-share brief drops middle fields, keeps orch= and FAIL=, and stays valid UTF-8.
mkdir -p "$fx/b3"; cp "$HARNESS" "$fx/b3/"
long="AC 79% $(for i in $(seq 62); do printf 'f%02d=xxxxxxxxx ' "$i"; done)tmux=alive orch=ok timers=24 FAIL=none"
printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$long" > "$fx/b3/pc"; chmod +x "$fx/b3/pc"
for v in --worker CLAUDECODE=1; do
  if [ "$v" = --worker ]; then o=$(cd "$fx" && env -u CLAUDECODE -u HARNESS_AGENT "$fx/b3/harness" context --worker); cap=720
  else o=$(cd "$fx" && env "$v" "$fx/b3/harness" context); cap=700; fi
  l1=${o%%$'\n'*}; n=$(printf '%s\n' "$o" | wc -c)
  case "$l1" in *"… orch=ok FAIL=none") ok 1 "$v ${#long}-byte brief keeps orch= and FAIL= ($n B)";; *) ok 0 "$v ${#long}-byte brief keeps orch= and FAIL= ($n B)";; esac
  [ "$n" -le "$cap" ] && ok 1 "$v ${#long}-byte brief fits $cap B" || ok 0 "$v ${#long}-byte brief fits $cap B"
  case "$l1" in *" f"[0-9][0-9]"=xxxxxxxxx …"*) ok 1 "$v cuts on a field boundary";; *) ok 0 "$v cuts on a field boundary";; esac
done
printf '#!/bin/sh\ncat "%s"\n' "$fx/b3/brief" > "$fx/b3/pc"
for w in 0 1 2 3; do
  { head -c $((160 + w)) /dev/zero | tr '\0' b; for i in $(seq 150); do printf '\303\251'; done; echo; } > "$fx/b3/brief"
  (cd "$fx" && CLAUDECODE=1 "$fx/b3/harness" context) | iconv -f utf-8 -t utf-8 >/dev/null 2>&1 && ok 1 "é at the cut stays valid UTF-8 (offset $w)" || ok 0 "é at the cut stays valid UTF-8 (offset $w)"
done
printf '#!/bin/sh\necho "AC 79%% ts=up orch=ok FAIL=none"\n' > "$fx/b3/pc"
[ "$(cd "$fx" && "$fx/b3/harness" context --worker | head -1)" = "Machine now: AC 79% ts=up orch=ok FAIL=none" ] && ok 1 "a brief within its share passes unchanged" || ok 0 "a brief within its share passes unchanged"

[ "$bad" = 0 ] && echo "all harness-context cases pass" || echo "$bad FAILURES"
exit $([ "$bad" = 0 ] && echo 0 || echo 1)
