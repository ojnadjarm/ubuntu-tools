#!/usr/bin/env bash
# TS04: agents-log --raw. Fixtures only (AGENTS.md §5.6) — HOME points at a temp dir whose
# agents/log/actions.jsonl is written here, so the live audit log is never read or touched.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$BIN/agents-log"
fail=0
t() { printf '%-56s' "agents-log: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }

H="$(mktemp -d)"
trap 'rm -rf "$H"' EXIT
mkdir -p "$H/agents/log"
now() { date -d "$1" +%Y-%m-%dT%H:%M:%S%z; }
{
  printf '{"ts": "%s", "session": "aaaa1111", "cwd": "/w/agents", "tool": "Bash", "op": "pactl", "summary": "pactl set-default-sink hdmi && pc see"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "bbbb2222", "cwd": "/w/agents", "tool": "Bash", "op": "pactl", "summary": "pactl list sinks"}\n' "$(now '-2 hours')"
  printf '{"ts": "%s", "session": "bbbb2222", "cwd": "/w/agents", "tool": "Bash", "op": "docker", "summary": "docker restart example-app; systemctl --user restart ydotoold"}\n' "$(now '-3 hours')"
  printf '{"ts": "%s", "session": "bbbb2222", "cwd": "/w/agents", "tool": "Bash", "op": "nmcli", "summary": "nmcli device wifi list"}\n' "$(now '-4 hours')"
  printf '{"ts": "%s", "session": "cccc3333", "cwd": "/w/agents", "tool": "Read", "op": "", "summary": "pactl in a file I only read"}\n' "$(now '-5 hours')"
  printf '{"ts": "%s", "session": "dddd4444", "cwd": "/w/agents", "tool": "Bash", "op": "tailscale", "summary": "tailscale status"}\n' "$(now '-3 days')"
  printf 'not json at all\n'
} > "$H/agents/log/actions.jsonl"
run() { HOME="$H" "$CLI" "$@"; }

t "selftest: the fixture HOME is used, the live log is not"
{ [ -s "$H/agents/log/actions.jsonl" ] && [ "$H" != "$HOME" ] &&
  ! run --raw 2>/dev/null | grep -q 'ydotoold\b.*live'; } && ok || no "fixture HOME not in force"

R="$(run --raw 2>/dev/null)"

t "--raw prints the four-column header"
printf '%s\n' "$R" | head -1 | grep -qE 'raw verb +pc verb +count +sessions' &&
  ok || no "$(printf '%s\n' "$R" | head -1)"

t "a raw tool maps to its pc verb with count and session count"
printf '%s\n' "$R" | grep -qE '^pactl +pc audio +2 +2$' &&
  ok || no "$(printf '%s\n' "$R" | grep '^pactl' || echo 'no pactl row')"

t "systemctl restart and docker restart are counted separately"
{ printf '%s\n' "$R" | grep -qE '^systemctl restart +pc units +1 +1$' &&
  printf '%s\n' "$R" | grep -qE '^docker restart +pc docker restart +1 +1$'; } &&
  ok || no "$(printf '%s\n' "$R" | grep -E 'systemctl|docker' || echo 'no rows')"

t "a raw tool with no pc verb prints the gap dash"
printf '%s\n' "$R" | grep -qE '^nmcli +— +1 +1$' &&
  ok || no "$(printf '%s\n' "$R" | grep '^nmcli' || echo 'no nmcli row')"

t "only Bash rows count: a Read row naming pactl is ignored"
[ "$(printf '%s\n' "$R" | grep -cE '^pactl ')" = 1 ] &&
  printf '%s\n' "$R" | grep -qE '^pactl +pc audio +2 ' && ok || no "Read row counted"

t "TOTAL says how many raw calls a pc verb covers"
printf '%s\n' "$R" | grep -qE '^TOTAL +pc-coverable +5 .*of 6 raw calls \(83%\)' &&
  ok || no "$(printf '%s\n' "$R" | grep '^TOTAL' || echo 'no TOTAL')"

t "--since filters: the 3-day-old tailscale row drops out"
S="$(run --raw --since 1d 2>/dev/null)"
{ ! printf '%s\n' "$S" | grep -q '^tailscale' &&
  printf '%s\n' "$R" | grep -q '^tailscale'; } && ok || no "--since did not filter"

t "--raw composes with --session"
[ "$(run --raw --session bbbb 2>/dev/null | grep -cE '^(pactl|docker restart|systemctl restart|nmcli) ')" = 4 ] &&
  ok || no "$(run --raw --session bbbb 2>/dev/null)"

t "an empty log prints the header and a zero TOTAL, exit 0"
E="$(mktemp -d)"; mkdir -p "$E/agents/log"; : > "$E/agents/log/actions.jsonl"
o="$(HOME="$E" "$CLI" --raw 2>/dev/null)"; rc=$?
{ [ $rc = 0 ] && printf '%s\n' "$o" | grep -qE '^TOTAL +pc-coverable +0 .*of 0 raw calls'; } &&
  ok || no "rc=$rc: $o"
rm -rf "$E"

t "the other views still work"
{ run --stats 2>/dev/null | grep -q 'bbbb2222' &&
  run --pc 2>/dev/null | grep -q '^TOTAL' &&
  run --grep nmcli 2>/dev/null | grep -q 'nmcli'; } && ok || no "a pre-existing view broke"

t "-h documents --raw"
"$CLI" -h 2>&1 | grep -q -- '--raw' && ok || no "no --raw in usage"

t "no live session leaks in: only the fixture's sessions are listed"
[ "$(run --stats 2>/dev/null | cut -d' ' -f1 | sort | tr '\n' ' ')" \
  = "aaaa1111 bbbb2222 cccc3333 dddd4444 " ] &&
  ok || no "$(run --stats 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ')"

# --- TS/T2: --tokens reads transcripts, fixtures only (CLAUDE_PROJECTS_DIR override) ---
P="$(mktemp -d)"
mkdir -p "$P/-fixture-project"
tstamp() { date -u -d "$1" +%Y-%m-%dT%H:%M:%S.000Z; }
big="$(head -c 2048 /dev/zero | tr '\0' x)"
{
  printf '{"type":"assistant","timestamp":"%s","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":90000,"cache_creation_input_tokens":9990,"output_tokens":1000},"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/w/a.md"}}]}}\n' "$(tstamp '-2 hours')"
  printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"%s"}]}}\n' "$(tstamp '-2 hours')" "$big"
  printf '{"type":"assistant","timestamp":"%s","message":{"usage":{"input_tokens":0,"cache_read_input_tokens":180000,"cache_creation_input_tokens":20000,"output_tokens":2000},"content":[{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/w/a.md"}}]}}\n' "$(tstamp '-1 hour')"
  printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"image","source":{"type":"base64","data":"AAAA"}}]}]}}\n' "$(tstamp '-1 hour')"
  printf '{"type":"queue-operation","timestamp":"%s","note":"an unknown line the reader must tolerate"}\n' "$(tstamp '-1 hour')"
  printf 'not json at all\n'
} > "$P/-fixture-project/abcd1234-0000-0000-0000-000000000000.jsonl"
tok() { CLAUDE_PROJECTS_DIR="$P" "$CLI" --tokens "$@"; }

t "selftest: --tokens reads the fixture dir, never ~/.claude/projects"
{ [ "$P" != "$HOME/.claude/projects" ] &&
  [ "$(tok 2>/dev/null | grep -cE '^[0-9a-f]{8} ')" = 1 ]; } &&
  ok || no "$(tok 2>/dev/null | head -3)"

K="$(tok 2>/dev/null)"

t "--tokens prints the session row: turns, mean, median, max context"
printf '%s\n' "$K" | grep -qE '^abcd1234 +2 +150,000 +150,000 +200,000 ' &&
  ok || no "$(printf '%s\n' "$K" | grep '^abcd1234' || echo 'no row')"

t "cache-read, output, images and same-session re-reads are counted"
printf '%s\n' "$K" | grep -qE '^abcd1234 .* 0\.3 +3\.0 +1 +1 ' &&
  ok || no "$(printf '%s\n' "$K" | grep '^abcd1234' || echo 'no row')"

t "tool result bytes are attributed to the tool that asked"
printf '%s\n' "$K" | grep -qE 'Read:2( |$)' &&
  ok || no "$(printf '%s\n' "$K" | grep '^abcd1234' || echo 'no row')"

t "a TOTAL row sums the sessions"
printf '%s\n' "$K" | grep -qE '^TOTAL +2 +150,000 ' &&
  ok || no "$(printf '%s\n' "$K" | grep '^TOTAL' || echo 'no TOTAL')"

t "a per-day line follows the TOTAL"
printf '%s\n' "$K" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} +turns +2 +mean ctx +150,000' &&
  ok || no "$(printf '%s\n' "$K" | tail -2)"

t "--session filters by id prefix"
{ [ -n "$(tok --session abcd 2>/dev/null | grep '^abcd1234')" ] &&
  [ -z "$(tok --session zzzz 2>/dev/null | grep '^abcd1234')" ]; } &&
  ok || no "--session did not filter"

t "--since drops a session whose last turn is older than the window"
[ -z "$(tok --since 30m 2>/dev/null | grep '^abcd1234')" ] &&
  ok || no "$(tok --since 30m 2>/dev/null | head -2)"

t "an empty transcript dir prints the header and a zero TOTAL, exit 0"
Z="$(mktemp -d)"; mkdir -p "$Z/-empty"
o="$(CLAUDE_PROJECTS_DIR="$Z" "$CLI" --tokens 2>/dev/null)"; rc=$?
{ [ $rc = 0 ] && printf '%s\n' "$o" | grep -qE '^TOTAL +0 '; } && ok || no "rc=$rc: $o"
rm -rf "$Z"

t "-h documents --tokens"
"$CLI" -h 2>&1 | grep -q -- '--tokens' && ok || no "no --tokens in usage"

rm -rf "$P"

[ $fail = 0 ] && echo "agents-log.test.sh: all green" || echo "agents-log.test.sh: FAILURES"
exit $fail
