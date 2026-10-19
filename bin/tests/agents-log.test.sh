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
  printf '{"ts": "%s", "session": "aaaa1111", "cwd": "/w/agents", "tool": "Bash", "op": "pactl set-default-sink", "summary": "pactl set-default-sink hdmi && pc see"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "bbbb2222", "cwd": "/w/agents", "tool": "Bash", "op": "pactl list", "summary": "pactl list sinks"}\n' "$(now '-2 hours')"
  printf '{"ts": "%s", "session": "bbbb2222", "cwd": "/w/agents", "tool": "Bash", "op": "docker restart", "summary": "docker restart example-app; pactl list"}\n' "$(now '-3 hours')"
  printf '{"ts": "%s", "session": "bbbb2222", "cwd": "/w/agents", "tool": "Bash", "op": "systemctl --user", "summary": "systemctl --user restart ydotoold"}\n' "$(now '-3 hours')"
  printf '{"ts": "%s", "session": "bbbb2222", "cwd": "/w/agents", "tool": "Bash", "op": "nmcli device", "summary": "nmcli device wifi list"}\n' "$(now '-4 hours')"
  printf '{"ts": "%s", "session": "cccc3333", "cwd": "/w/agents", "tool": "Read", "op": "", "summary": "pactl in a file I only read"}\n' "$(now '-5 hours')"
  printf '{"ts": "%s", "session": "dddd4444", "cwd": "/w/agents", "tool": "Bash", "op": "tailscale status", "summary": "tailscale status"}\n' "$(now '-3 days')"
  printf '{"ts": "%s", "session": "ffff6666", "cwd": "/w/agents", "tool": "Bash", "op": "pc net", "summary": "pc net tailscale"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "ffff6666", "cwd": "/w/agents", "tool": "Bash", "op": "grep tailscale", "summary": "grep tailscale x"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "ffff6666", "cwd": "/w/agents", "tool": "Bash", "op": "tailscale serve", "summary": "tailscale serve --bg 80"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "ffff6666", "cwd": "/w/agents", "tool": "Bash", "op": "tailscale status", "summary": "tailscale status"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "ffff6666", "cwd": "/w/agents", "tool": "Bash", "op": "tailscale status", "summary": "cd ~ && tailscale status"}\n' "$(now '-1 hour')"
  printf 'not json at all\n'
} > "$H/agents/log/actions.jsonl"
run() { HOME="$H" "$CLI" "$@"; }

t "selftest: the fixture HOME is used, the live log is not"
{ [ -s "$H/agents/log/actions.jsonl" ] && [ "$H" != "$HOME" ] &&
  ! run --raw 2>/dev/null | grep -q 'ydotoold\b.*live'; } && ok || no "fixture HOME not in force"

R="$(run --raw 2>/dev/null)"

t "--raw prints the five-column header with class"
printf '%s\n' "$R" | head -1 | grep -qE 'raw verb +class +pc verb +count +sessions' &&
  ok || no "$(printf '%s\n' "$R" | head -1)"

t "a raw tool maps to its class and pc verb with count and sessions"
printf '%s\n' "$R" | grep -qE '^pactl +covered +pc audio +2 +2$' &&
  ok || no "$(printf '%s\n' "$R" | grep '^pactl' || echo 'no pactl row')"

t "only the op at command position counts, not a later segment"
[ "$(printf '%s\n' "$R" | grep -cE '^pactl ')" = 1 ] &&
  printf '%s\n' "$R" | grep -qE '^docker restart +covered +pc docker restart +1 +1$' &&
  ok || no "$(printf '%s\n' "$R" | grep -E 'pactl|docker' || echo 'no rows')"

t "the subcommand skips flags: systemctl --user restart"
printf '%s\n' "$R" | grep -qE '^systemctl restart +covered +pc units restart +1 +1$' &&
  ok || no "$(printf '%s\n' "$R" | grep systemctl || echo 'no systemctl row')"

t "a raw tool with no pc verb is a gap with the dash"
printf '%s\n' "$R" | grep -qE '^nmcli +gap +— +1 +1$' &&
  ok || no "$(printf '%s\n' "$R" | grep '^nmcli' || echo 'no nmcli row')"

t "tailscale: the word elsewhere is not a call; serve is by-design"
T="$(run --raw --session ffff 2>/dev/null)"
{ printf '%s\n' "$T" | grep -qE '^tailscale status +covered +pc net tailscale +2 +1$' &&
  printf '%s\n' "$T" | grep -qE '^tailscale serve +by-design +— +1 +1$' &&
  printf '%s\n' "$T" | grep -qE '^TOTAL +covered 2 · by-design 1 · gap 0 +of 3 raw calls'; } &&
  ok || no "$T"

t "TOTAL footer splits covered, by-design and gap"
printf '%s\n' "$R" | grep -qE '^TOTAL +covered 7 · by-design 1 · gap 1 +of 9 raw calls \(88% coverable\)' &&
  ok || no "$(printf '%s\n' "$R" | grep '^TOTAL' || echo 'no TOTAL')"

t "--since filters: the 3-day-old tailscale row drops out"
S="$(run --raw --since 1d 2>/dev/null)"
{ printf '%s\n' "$S" | grep -qE '^tailscale status +covered +pc net tailscale +2 +1$' &&
  printf '%s\n' "$R" | grep -qE '^tailscale status +covered +pc net tailscale +3 +2$'; } &&
  ok || no "--since did not filter"

t "--raw composes with --session"
[ "$(run --raw --session bbbb 2>/dev/null | grep -cE '^(pactl|docker restart|systemctl restart|nmcli) ')" = 4 ] &&
  ok || no "$(run --raw --session bbbb 2>/dev/null)"

t "an empty log prints the header and a zero TOTAL, exit 0"
E="$(mktemp -d)"; mkdir -p "$E/agents/log"; : > "$E/agents/log/actions.jsonl"
o="$(HOME="$E" "$CLI" --raw 2>/dev/null)"; rc=$?
{ [ $rc = 0 ] && printf '%s\n' "$o" | grep -qE '^TOTAL +covered 0 · by-design 0 · gap 0 +of 0 raw calls'; } &&
  ok || no "rc=$rc: $o"
rm -rf "$E"

# --- TSP-012: --kind agent|bench|interactive, from the row's agent field (bench also by cwd) ---
K="$(mktemp -d)"; mkdir -p "$K/agents/log"
kr() { printf '{"ts": "%s", "session": "%s", %s"tool": "Bash", "op": "pactl list", "summary": "pactl list && pc see"}\n' "$(now '-1 hour')" "$1" "$2"; }
{ kr agnt0001 '"agent": "toolsmith", "cwd": "/w/agents/toolsmith", '
  kr intr0001 '"agent": "", "cwd": "/w/agents", '
  kr intr0002 '"cwd": "/w/agents", '
  kr bnch0001 '"agent": "bench", "cwd": "/tmp/x", '
  kr bnch0002 '"cwd": "/w/agents/bench/runs/r1/D01/new/0", '; } > "$K/agents/log/actions.jsonl"
kl() { HOME="$K" "$CLI" "$@"; }

t "--kind agent counts rostered agent runs only"
kl --raw --kind agent 2>/dev/null | grep -qE '^TOTAL +covered 1 .* of 1 raw calls' &&
  ok || no "$(kl --raw --kind agent 2>&1 | tail -1)"

t "--kind interactive takes rows with an empty or missing agent"
[ "$(kl --stats --kind interactive 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ')" = "intr0001 intr0002 " ] &&
  ok || no "$(kl --stats --kind interactive 2>&1 | tr '\n' ' ')"

t "--kind bench takes agent=bench and legacy bench/runs cwds"
[ "$(kl --stats --kind bench 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ')" = "bnch0001 bnch0002 " ] &&
  ok || no "$(kl --stats --kind bench 2>&1 | tr '\n' ' ')"

t "--kind composes with --pc and the plain view"
{ kl --pc --kind agent 2>/dev/null | grep -qE '^agnt0001 +0 +1 ' &&
  [ "$(kl --kind agent 2>/dev/null | wc -l)" = 1 ]; } && ok || no "$(kl --pc --kind agent 2>&1)"

t "-h documents --kind; a bad kind exits non-zero"
{ "$CLI" -h 2>&1 | grep -q -- '--kind' && ! kl --kind robot >/dev/null 2>&1; } && ok || no "usage or validation"

t "hook: AGENT_NAME lands in the row's agent field (fake HOME + HARNESS_HOME)"
HOOK="$BIN/../adapters/claude/hooks/audit-log.py"
live="$HOME/agents/log/actions.jsonl"; n0=$(grep -c hook0001 "$live" 2>/dev/null)
ev='{"tool_name": "Bash", "tool_input": {"command": "pactl list"}, "cwd": "/w", "session_id": "hook0001xx"}'
printf '%s' "$ev" | env -u PCBENCH_RUN HOME="$K" HARNESS_HOME="$K/agents" AGENT_NAME=toolsmith python3 "$HOOK"
printf '%s' "$ev" | env -u PCBENCH_RUN -u AGENT_NAME HOME="$K" HARNESS_HOME="$K/agents" python3 "$HOOK"
printf '%s' "$ev" | HOME="$K" HARNESS_HOME="$K/agents" AGENT_NAME=toolsmith PCBENCH_RUN=r1 python3 "$HOOK"
n1=$(grep -c hook0001 "$live" 2>/dev/null)
[ "$(tail -3 "$K/agents/log/actions.jsonl" | jq -r '.agent' | tr '\n' ' ')" = "toolsmith  bench " ] && [ "$n0" = "$n1" ] &&
  ok || no "$(tail -3 "$K/agents/log/actions.jsonl" | jq -c .agent | tr '\n' ' ') live $n0→$n1"
rm -rf "$K"

t "the other views still work"
{ run --stats 2>/dev/null | grep -q 'bbbb2222' &&
  run --pc 2>/dev/null | grep -q '^TOTAL' &&
  run --grep nmcli 2>/dev/null | grep -q 'nmcli'; } && ok || no "a pre-existing view broke"

t "-h documents --raw"
"$CLI" -h 2>&1 | grep -q -- '--raw' && ok || no "no --raw in usage"

t "no live session leaks in: only the fixture's sessions are listed"
[ "$(run --stats 2>/dev/null | cut -d' ' -f1 | sort | tr '\n' ' ')" \
  = "aaaa1111 bbbb2222 cccc3333 dddd4444 ffff6666 " ] &&
  ok || no "$(run --stats 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ')"

# --- F03: --since reads the rotated .N.gz files too, oldest first ---
G="$(mktemp -d)"; mkdir -p "$G/agents/log"
row() { printf '{"ts": "%s", "session": "%s", "tool": "Bash", "op": "pc", "summary": "pc see"}\n' "$(now "$1")" "$2"; }
row '-1 hour' live0001 > "$G/agents/log/actions.jsonl"
row '-3 days' rot10001 | gzip > "$G/agents/log/actions.jsonl.1.gz"
row '-6 days' rot20001 | gzip > "$G/agents/log/actions.jsonl.2.gz"
row '-20 days' old30001 | gzip > "$G/agents/log/actions.jsonl.3.gz"
gl() { HOME="$G" "$CLI" "$@"; }

t "--since 7d reaches into the rotated .gz files"
[ "$(gl --since 7d --stats 2>/dev/null | cut -d' ' -f1 | sort | tr '\n' ' ')" \
  = "live0001 rot10001 rot20001 " ] && ok || no "$(gl --since 7d --stats 2>&1 | tr '\n' ' ')"

t "rotated rows print oldest first"
[ "$(gl --since 7d 2>/dev/null | awk '{print $2}' | tr '\n' ' ')" = "rot20001 rot10001 live0001 " ] &&
  ok || no "$(gl --since 7d 2>/dev/null | tr '\n' ' ')"

t "--since 1d does not open the rotated files' old rows"
[ "$(gl --since 1d --stats 2>/dev/null | cut -d' ' -f1)" = live0001 ] && ok || no "$(gl --since 1d --stats 2>&1)"

t "a window older than the whole log says so on stderr"
rm "$G/agents/log/actions.jsonl.3.gz"
{ gl --since 30d --pc 2>&1 >/dev/null | grep -q 'log starts' &&
  [ -z "$(gl --since 5d --pc 2>&1 >/dev/null)" ]; } && ok || no "$(gl --since 30d --pc 2>&1 >/dev/null)"
rm -rf "$G"

# --- TS/T2: --tokens reads transcripts, fixtures only (CLAUDE_PROJECTS_DIR override) ---
P="$(mktemp -d)"
mkdir -p "$P/-fixture-project"
tstamp() { date -u -d "$1" +%Y-%m-%dT%H:%M:%S.000Z; }
big="$(head -c 2048 /dev/zero | tr '\0' x)"
{
  printf '{"type":"assistant","timestamp":"%s","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":90000,"cache_creation_input_tokens":9990,"output_tokens":1000},"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/w/a.md"}}]}}\n' "$(tstamp 'yesterday 12:00')"
  printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"%s"}]}}\n' "$(tstamp 'yesterday 12:00')" "$big"
  printf '{"type":"assistant","timestamp":"%s","message":{"usage":{"input_tokens":0,"cache_read_input_tokens":180000,"cache_creation_input_tokens":20000,"output_tokens":2000},"content":[{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/w/a.md"}}]}}\n' "$(tstamp 'yesterday 13:00')"
  printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"image","source":{"type":"base64","data":"AAAA"}}]}]}}\n' "$(tstamp 'yesterday 13:00')"
  printf '{"type":"queue-operation","timestamp":"%s","note":"an unknown line the reader must tolerate"}\n' "$(tstamp 'yesterday 13:00')"
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

t "one message split over 3 lines counts as 1 turn, usage once"
D="$P/-split"; mkdir -p "$D"
for b in '{"type":"thinking","thinking":"x"}' '{"type":"text","text":"y"}' \
         '{"type":"tool_use","id":"s1","name":"Bash","input":{}}'; do
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"msg_1","usage":{"input_tokens":0,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":0,"output_tokens":50000},"content":[%s]}}\n' "$(tstamp '-1 hour')" "$b"
done > "$D/eeee5555-0000-0000-0000-000000000000.jsonl"
o="$(tok --session eeee 2>/dev/null | grep '^eeee5555')"
printf '%s\n' "$o" | grep -qE '^eeee5555 +1 +1,000,000 +1,000,000 +1,000,000 +1\.0 +50\.0 ' &&
  ok || no "${o:-no row}"

t "--tokens keys day lines by local date, not UTC"
L="$(mktemp -d)"; mkdir -p "$L/-tz"
for w in 2026-10-16T22:30:00.000Z 2026-10-17T00:30:00.000Z; do
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"m%s","usage":{"input_tokens":0,"cache_read_input_tokens":1000,"cache_creation_input_tokens":0,"output_tokens":10},"content":[]}}\n' "$w" "${w//[^0-9]/}"
done > "$L/-tz/7777bbbb-0000-0000-0000-000000000000.jsonl"
o="$(TZ=Europe/Madrid CLAUDE_PROJECTS_DIR="$L" "$CLI" --tokens 2>/dev/null)"
{ printf '%s\n' "$o" | grep -qE '^2026-10-17 +turns +2 ' &&
  ! printf '%s\n' "$o" | grep -q '^2026-10-16 '; } && ok || no "$(printf '%s\n' "$o" | tail -2)"
rm -rf "$L"

rm -rf "$P"

# --- T347: one line per audit row; --tokens --since keeps its day lines inside the window ---
N="$(mktemp -d)"; mkdir -p "$N/agents/log"
printf '{"ts": "%s", "session": "nl000001", "tool": "Bash", "op": "python3 -c", "summary": "python3 -c \\"\\nimport json\\nprint(1)\\""}\n' "$(now '-1 hour')" > "$N/agents/log/actions.jsonl"
t "the default view prints a multi-line summary as one line"
[ "$(HOME="$N" "$CLI" --since 1d 2>/dev/null | wc -l)" = 1 ] && ok || no "$(HOME="$N" "$CLI" --since 1d 2>&1)"
rm -rf "$N"

Q="$(mktemp -d)"; mkdir -p "$Q/-old"
for w in '-3 days' '-1 hour'; do
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"m%s","usage":{"input_tokens":0,"cache_read_input_tokens":1000,"cache_creation_input_tokens":0,"output_tokens":10},"content":[]}}\n' "$(tstamp "$w")" "${w//[^0-9]/}"
done > "$Q/-old/9999aaaa-0000-0000-0000-000000000000.jsonl"
old=$(date -d '-3 days' +%F)
t "--tokens --since prints day lines only inside the window"
{ CLAUDE_PROJECTS_DIR="$Q" "$CLI" --tokens 2>/dev/null | grep -q "^$old " &&
  ! CLAUDE_PROJECTS_DIR="$Q" "$CLI" --tokens --since 1d 2>/dev/null | grep -q "^$old "; } &&
  ok || no "$(CLAUDE_PROJECTS_DIR="$Q" "$CLI" --tokens --since 1d 2>&1 | tail -3)"

t "--tokens --since skips transcripts last written before the window"
f="$Q/-old/9999aaaa-0000-0000-0000-000000000000.jsonl"
touch -d '-2 days' "$f"; chmod 000 "$f"
o="$(CLAUDE_PROJECTS_DIR="$Q" "$CLI" --tokens --since 1d 2>&1)"; rc=$?
chmod 600 "$f"
{ [ $rc = 0 ] && printf '%s\n' "$o" | grep -qE '^TOTAL +0 '; } && ok || no "rc=$rc: $(printf '%s\n' "$o" | tail -2)"
rm -rf "$Q"

# --- T347-07: failed calls (PostToolUseFailure), agent_id/agent_type, --errors and --agent ---
F="$(mktemp -d)"; mkdir -p "$F/agents/log"
HOOK="$BIN/../adapters/claude/hooks/audit-log.py"
live="$HOME/agents/log/actions.jsonl"; n0=$(grep -c fail0001 "$live" 2>/dev/null)
hk() { printf '%s' "$1" | env -u PCBENCH_RUN -u AGENT_NAME HOME="$F" HARNESS_HOME="$F/agents" "$HOOK"; }
hk '{"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": {"command": "true"}, "cwd": "/w", "session_id": "fail0001xx"}'
hk '{"hook_event_name": "PostToolUseFailure", "tool_name": "Bash", "tool_input": {"command": "echo probe; exit 3"}, "cwd": "/w", "session_id": "fail0001xx", "error": "Exit code 3 token=abc123secret '"$(head -c 400 /dev/zero | tr '\0' y)"'"}'
hk '{"hook_event_name": "PostToolUse", "tool_name": "Read", "tool_input": {"file_path": "/w/a.md"}, "cwd": "/w", "session_id": "fail0001xx", "agent_id": "agt9876543", "agent_type": "worker"}'
L="$F/agents/log/actions.jsonl"
n1=$(grep -c fail0001 "$live" 2>/dev/null)

t "selftest: hook rows land in the fixture log, not the live one"
{ [ "$(wc -l < "$L")" = 3 ] && [ "$n0" = "$n1" ]; } && ok || no "fixture $(wc -l < "$L") rows, live $n0→$n1"

t "hook: a success row carries ok:true and no error"
[ "$(sed -n 1p "$L" | jq -c '[.ok, has("error")]')" = '[true,false]' ] && ok || no "$(sed -n 1p "$L")"

t "hook: a PostToolUseFailure row carries ok:false and the error"
[ "$(sed -n 2p "$L" | jq -c '[.ok, (.error|startswith("Exit code 3"))]')" = '[false,true]' ] && ok || no "$(sed -n 2p "$L")"

t "hook: the error is redacted and at most 403 chars (head + … + tail)"
{ sed -n 2p "$L" | jq -r .error | grep -q '<redacted>' && ! grep -q abc123secret "$L" &&
  [ "$(sed -n 2p "$L" | jq -r '.error|length')" -le 403 ]; } && ok || no "$(sed -n 2p "$L" | jq -c .error)"

t "hook: agent_id and agent_type kept when present, absent otherwise"
{ [ "$(sed -n 3p "$L" | jq -c '[.agent_id,.agent_type]')" = '["agt9876543","worker"]' ] &&
  [ "$(sed -n 1p "$L" | jq -c '[has("agent_id"),has("agent_type")]')" = '[false,false]' ]; } &&
  ok || no "$(sed -n 3p "$L" | jq -c .)"

t "--errors lists only the failed calls"
o="$(HOME="$F" "$CLI" --errors 2>/dev/null)"
{ [ "$(printf '%s\n' "$o" | grep -c .)" = 1 ] && printf '%s\n' "$o" | grep -q 'exit 3'; } && ok || no "$o"

t "the plain view shows a failed call's error"
HOME="$F" "$CLI" 2>/dev/null | grep 'exit 3' | grep -q 'Exit code 3' && ok || no "$(HOME="$F" "$CLI" 2>&1)"

t "--agent ID filters on the agent_id prefix"
o="$(HOME="$F" "$CLI" --agent agt98 2>/dev/null)"
{ [ "$(printf '%s\n' "$o" | grep -c .)" = 1 ] && printf '%s\n' "$o" | grep -q 'a.md' &&
  [ -z "$(HOME="$F" "$CLI" --agent zzz 2>/dev/null)" ]; } && ok || no "$o"

t "-h documents --errors and --agent"
{ "$CLI" -h 2>&1 | grep -q -- '--errors' && "$CLI" -h 2>&1 | grep -q -- '--agent'; } && ok || no "usage"

t "both audit files start python isolated: #!/usr/bin/python3 -IS"
{ [ "$(head -1 "$HOOK")" = '#!/usr/bin/python3 -IS' ] &&
  [ "$(head -1 "$BIN/../hooks/audit-log.py")" = '#!/usr/bin/python3 -IS' ]; } && ok || no "$(head -1 "$HOOK")"
rm -rf "$F"

# --- T374: subagent and workflow-lane transcripts roll up under their parent session; --by kind ---
W="$(mktemp -d)"; S="$W/-proj/5e550001-0000-0000-0000-000000000000"
mkdir -p "$S/subagents/workflows/wf_1"
tr() { printf '{"type":"assistant","timestamp":"%s","entrypoint":"%s","message":{"id":"%s","usage":{"input_tokens":0,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0,"output_tokens":1000},"content":[]}}\n' "$(tstamp '-1 hour')" "$1" "$2" "$3"; }
tr cli m1 1000000 > "$S.jsonl"
tr cli w1 2000000 > "$S/subagents/agent-a1.jsonl"
{ tr cli l1 3000000; tr cli l2 4000000; } > "$S/subagents/workflows/wf_1/agent-b1.jsonl"
printf '{"type":"launched"}\n' > "$S/subagents/workflows/wf_1/journal.jsonl"
tr sdk-cli h1 500000 > "$W/-proj/4ead0001-0000-0000-0000-000000000000.jsonl"
wt() { CLAUDE_PROJECTS_DIR="$W" "$CLI" --tokens "$@" 2>/dev/null; }

t "lanes roll up: one parent row with 4 turns and 10.0 M cache-read"
{ [ "$(wt | grep -cE '^5e550001 ')" = 1 ] && wt | grep -qE '^5e550001 +4 .* 10\.0 +4\.0 '; } &&
  ok || no "$(wt | grep -E '^(5e55|TOTAL)')"

t "the TOTAL counts every lane: 5 turns, 10.5 M"
wt | grep -qE '^TOTAL +5 .* 10\.5 +5\.0 ' && ok || no "$(wt | grep '^TOTAL')"

t "--by kind splits interactive, headless, worker, workflow"
o="$(wt --by kind)"
{ printf '%s\n' "$o" | grep -qE '^interactive +1 +1\.0 ' && printf '%s\n' "$o" | grep -qE '^headless +1 +0\.5 ' &&
  printf '%s\n' "$o" | grep -qE '^worker +1 +2\.0 ' && printf '%s\n' "$o" | grep -qE '^workflow +2 +7\.0 +2\.0 +67%$'; } &&
  ok || no "$(printf '%s\n' "$o" | tail -5)"

t "--session on the parent id keeps its lanes; --since drops old lane files"
touch -d '-3 days' "$S/subagents/workflows/wf_1/agent-b1.jsonl"
{ wt --session 5e55 | grep -qE '^5e550001 +4 ' && wt --since 1d | grep -qE '^5e550001 +2 '; } &&
  ok || no "$(wt --since 1d | grep '^5e55')"

t "-h documents --by"
"$CLI" -h 2>&1 | grep -q -- '--by' && ok || no "no --by in usage"
rm -rf "$W"

# --- T380/T386: --errors --cluster groups repeats by the failing command + the line naming the error ---
C="$(mktemp -d)"; mkdir -p "$C/agents/log"
{ printf '{"ts": "%s", "session": "c0", "tool": "Bash", "op": "ls", "summary": "ls"}\n' "$(now '-2 hour')"
  printf '{"ts": "%s", "session": "c1", "tool": "Bash", "op": "cat a", "summary": "cat a; grep -E x /a", "ok": false, "error": "Exit code 1\\nleftover 12"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "c2", "tool": "Bash", "op": "sed -n", "summary": "sed -n 1p b; grep foo /c", "ok": false, "error": "Exit code 1\\nother leftover"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "c2", "tool": "Bash", "op": "pc status", "summary": "pc status", "ok": false, "error": "Exit code 3"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "c2", "tool": "Bash", "op": "ls", "summary": "ls", "ok": true}\n' "$(now '-1 hour')"; } > "$C/agents/log/actions.jsonl"
o="$(HOME="$C" "$CLI" --errors --cluster 2>/dev/null)"
t "--cluster: one row per cluster with count and sessions, biggest first"
{ printf '%s\n' "$o" | sed -n 2p | grep -qE '^ +2 +2  grep · exit 1$' &&
  printf '%s\n' "$o" | grep -qE '^ +1 +1  pc status · exit 3$'; } && ok || no "$o"
t "--cluster: rate only over calls from the first logged outcome, and says so"
{ printf '%s\n' "$o" | grep -qE '^note: rate counts calls from .*\(1 older left out\)$' &&
  printf '%s\n' "$o" | tail -1 | grep -qE '^TOTAL 3 failed of 4 calls \(75\.0%\) · 2 clusters$'; } && ok || no "$o"
t "-h documents --cluster"
"$CLI" -h 2>&1 | grep -q -- '--cluster' && ok || no "no --cluster in usage"
rm -rf "$C"

[ $fail = 0 ] && echo "agents-log.test.sh: all green" || echo "agents-log.test.sh: FAILURES"
exit $fail
