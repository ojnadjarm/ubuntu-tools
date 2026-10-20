#!/usr/bin/env bash
# T588: claude/merge-settings.py, claude/uninstall, codex/install, codex/audit-from-stream and
# gemini/audit-from-stream against fixtures (fixtures/adapters/) in a throwaway HOME.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/assert.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
A="$ROOT/adapters"
F="$ROOT/bin/tests/fixtures/adapters"
REAL_HOME="$HOME"
real_sha() { sha256sum "$REAL_HOME/.claude/settings.json" 2>/dev/null | cut -d' ' -f1; }
real_before="$(real_sha)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
H="$tmp/home"
mkdir -p "$H/.claude" "$H/agents/skills"
export HOME="$H" HARNESS_HOME="$H/agents" HARNESS_CONTEXT_DIR="$H/.claude" HARNESS_CONFIG=/nonexistent
unset SETTINGS_OUT CODEX_SKILLS_DIR HARNESS_ENV_LOADED
S="$H/.claude/settings.json"
cp "$F/settings.json" "$S"

# Selftest: every write below lands in the fixture HOME, never the real ~/.claude.
case "$(readlink -f "$S")" in
  "$(readlink -f "$REAL_HOME")"/.claude/*) echo "FAIL selftest: fixture settings.json is under the real ~/.claude"; exit 1;;
esac
ok "selftest: fixture settings.json is outside the real ~/.claude"

# merge-settings.py install: owner hooks and keys untouched, ours added once, rerun is a no-op.
HH='$HOME/agents'
owner() { jq -c '{allow: .permissions.allow, deny0: .permissions.deny[0], model, effortLevel, stop: .hooks.Stop,
  pre: [.hooks.PreToolUse[] | select(any(.hooks[]; .command | test("owner-pre")))]}' "$1"; }
own_before="$(owner "$S")"
out="$(python3 "$A/claude/merge-settings.py" install "$S" "$A/claude/settings.fragment.json" "$HH")"
is "merge-settings.py install reports the write" "$out" "settings installed: $S"
is "merge-settings.py install keeps the owner's hooks and keys byte-identical" "$(owner "$S")" "$own_before"
pairs="$(jq -r --arg h "$HH" '.hooks | to_entries[] | .key as $e | .value[] .hooks[] | "\($e)\t\(.command | sub("@HARNESS_HOME@"; $h))"' \
  "$A/claude/settings.fragment.json" | sort -u)"
n=0; once=0
while IFS=$'\t' read -r e c; do
  n=$((n+1))
  [ "$(jq --arg e "$e" --arg c "$c" '[.hooks[$e][] .hooks[] | select(.command == $c)] | length' "$S")" = 1 ] && once=$((once+1))
done <<<"$pairs"
[ "$n" -gt 0 ] && is "merge-settings.py install adds each of our $n event hooks once" "$once" "$n" \
  || nok "merge-settings.py fragment has hook commands" "found 0"
deny="$(jq '.permissions.deny | length' "$S")"
is "merge-settings.py install appends our deny rules after the owner's" "$deny" \
  "$((1 + $(jq '.permissions.deny | length' "$A/claude/settings.fragment.json")))"
sha1="$(sha256sum "$S" | cut -d' ' -f1)"
out="$(python3 "$A/claude/merge-settings.py" install "$S" "$A/claude/settings.fragment.json" "$HH")"
is "merge-settings.py second install prints no changes" "$out" "no changes"
is "merge-settings.py second install is a no-op (sha256)" "$(sha256sum "$S" | cut -d' ' -f1)" "$sha1"

# claude/uninstall: removes only ours (settings back to the fixture byte for byte, our skill links, the include).
mkdir -p "$H/agents/skills/fleetskill" "$H/.claude/skills/mine"
echo x >"$H/agents/skills/fleetskill/SKILL.md"
echo y >"$H/.claude/skills/mine/SKILL.md"
ln -s "$H/agents/skills/fleetskill" "$H/.claude/skills/fleetskill"
printf '# mine\n\n<!-- pc-harness: the fleet contract, added by adapters/claude/install -->\n@~/agents/AGENTS.md\n' >"$H/CLAUDE.md"
"$A/claude/uninstall" >"$tmp/uninstall.out" 2>&1
is "claude/uninstall exits 0" "$?" 0
cmp -s "$S" "$F/settings.json" && ok "claude/uninstall restores the owner's settings.json byte for byte" \
  || nok "claude/uninstall restores the owner's settings.json byte for byte" "$(diff "$F/settings.json" "$S" | head -5)"
[ ! -e "$H/.claude/skills/fleetskill" ] && [ -f "$H/.claude/skills/mine/SKILL.md" ] \
  && ok "claude/uninstall unlinks our skill and keeps the owner's" || nok "claude/uninstall skills" "$(ls "$H/.claude/skills")"
is "claude/uninstall drops only the @AGENTS.md include" "$(cat "$H/CLAUDE.md")" "# mine"

# codex/install in a fixture HOME: links skills with a SKILL.md, skips the rest, rerun is a no-op.
mkdir -p "$H/agents/skills/noskill"
"$A/codex/install" >/dev/null 2>&1
is "codex/install exits 0" "$?" 0
is "codex/install links SKILL.md into ~/.agents/skills" \
  "$(readlink -f "$H/.agents/skills/fleetskill/SKILL.md")" "$H/agents/skills/fleetskill/SKILL.md"
[ ! -e "$H/.agents/skills/noskill" ] && ok "codex/install skips a dir without SKILL.md" \
  || nok "codex/install skips a dir without SKILL.md" "noskill linked"
is "codex/install second run prints no changes" "$("$A/codex/install" 2>&1)" "codex adapter: no changes"

# audit-from-stream: the row schema hooks/audit-log.py writes; malformed and non-tool lines skipped, rc 0.
mkdir -p "$tmp/ref"
echo '{"tool":"Bash","input":{"command":"ls"},"cwd":"/c","session":"s","agent":"a"}' \
  | HARNESS_HOME="$tmp/ref" python3 "$ROOT/hooks/audit-log.py"
keys="$(jq -c 'keys' "$tmp/ref/log/actions.jsonl")"
is "audit-log.py reference row has the documented keys" "$keys" '["agent","cwd","op","session","summary","tool","ts"]'
for agent in codex gemini; do
  hh="$tmp/$agent"; log="$hh/log/actions.jsonl"
  HARNESS_HOME="$hh" PWD=/env/cwd AGENT_SESSION_ID=envsess12345 AGENT_NAME=t588 \
    python3 "$A/$agent/audit-from-stream" <"$F/$agent.jsonl" 2>"$tmp/$agent.err"
  is "$agent/audit-from-stream exits 0 on a stream with a malformed line" "$?" 0
  [ -s "$tmp/$agent.err" ] && nok "$agent/audit-from-stream is silent on stderr" "$(head -2 "$tmp/$agent.err")"
  is "$agent/audit-from-stream rows share audit-log.py's keys" "$(jq -c 'keys' "$log" | sort -u)" "$keys"
  is "$agent/audit-from-stream writes no ok key" "$(jq -c '.ok' "$log" | sort -u)" null
done
is "codex/audit-from-stream: 3 tool events, 4 other lines skipped" "$(wc -l <"$tmp/codex/log/actions.jsonl")" 3
is "codex/audit-from-stream rows" "$(jq -c '[.tool,.op,.summary,.cwd,.session,.agent]' "$tmp/codex/log/actions.jsonl")" \
'["Bash","git status","git status --short","/work/repo","codex-se","t588"]
["Read","Read README.md","/work/repo/README.md","/env/cwd","envsess1","t588"]
["Bash","not json","not json at all","/env/cwd","envsess1","t588"]'
is "gemini/audit-from-stream: 2 tool events, 3 other lines skipped" "$(wc -l <"$tmp/gemini/log/actions.jsonl")" 2
is "gemini/audit-from-stream rows" "$(jq -c '[.tool,.op,.summary,.cwd,.session,.agent]' "$tmp/gemini/log/actions.jsonl")" \
'["Bash","ls -la","ls -la /tmp","/work/g","gemini-s","t588"]
["Grep","Grep TODO","TODO","/env/cwd","envsess1","t588"]'

is "the real ~/.claude/settings.json is untouched" "$(real_sha)" "$real_before"
exit $bad
