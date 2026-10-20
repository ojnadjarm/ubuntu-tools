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

t "both audit files start python isolated: #!/usr/bin/python3 -SI"
{ [ "$(head -1 "$HOOK")" = '#!/usr/bin/python3 -SI' ] &&
  [ "$(head -1 "$BIN/../hooks/audit-log.py")" = '#!/usr/bin/python3 -SI' ]; } && ok || no "$(head -1 "$HOOK")"
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
  printf '{"ts": "%s", "session": "c2", "tool": "Bash", "op": "sed -n", "agent_id": "ag1", "summary": "sed -n 1p b; grep foo /c", "ok": false, "error": "Exit code 1\\nother leftover"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "c2", "agent_id": "ag2", "tool": "Bash", "op": "grep x", "summary": "grep x /d", "ok": false, "error": "Exit code 1"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "c2", "tool": "Bash", "op": "pc status", "summary": "pc status", "ok": false, "error": "Exit code 3"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "c2", "tool": "Bash", "op": "ls", "summary": "ls", "ok": true}\n' "$(now '-1 hour')"; } > "$C/agents/log/actions.jsonl"
o="$(HOME="$C" "$CLI" --errors --cluster 2>/dev/null)"
t "--cluster: one row per cluster with count, sessions and agents, biggest first"
{ printf '%s\n' "$o" | head -1 | grep -qE '^count +sess +agents  cluster$' &&
  printf '%s\n' "$o" | sed -n 2p | grep -qE '^ +3 +2 +3  grep · exit 1$' &&
  printf '%s\n' "$o" | grep -qE '^ +1 +1 +1  pc status · exit 3$'; } && ok || no "$o"
t "--cluster: rate only over calls from the first logged outcome, and says so"
{ printf '%s\n' "$o" | grep -qE '^note: rate counts calls from .*\(1 older left out\)$' &&
  printf '%s\n' "$o" | tail -1 | grep -qE '^TOTAL 4 failed of 5 calls \(80\.0%\) · 2 clusters$'; } && ok || no "$o"
t "-h documents --cluster"
"$CLI" -h 2>&1 | grep -q -- '--cluster' && ok || no "no --cluster in usage"
rm -rf "$C"

# --- T468: --errors hides pcbench trials and sandbox refusals unless --all, and counts them ---
B="$(mktemp -d)"; mkdir -p "$B/agents/log"
{ printf '{"ts": "%s", "session": "b0", "tool": "Bash", "op": "ls", "summary": "ls", "ok": true}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "b1", "agent": "bench", "tool": "Bash", "op": "systemctl --user", "summary": "systemctl --user is-active pcbench-x", "ok": false, "error": "Exit code 3"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "b2", "cwd": "/x/bench/runs/r1", "tool": "Bash", "op": "systemctl --user", "summary": "systemctl --user is-active pcbench-y", "ok": false, "error": "Exit code 3"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "b3", "agent": "code-review", "tool": "Bash", "op": "git push", "summary": "git push", "ok": false, "error": "Exit code 97\\ngit: refused inside the code-review sandbox"}\n' "$(now '-1 hour')"
  printf '{"ts": "%s", "session": "b4", "tool": "Bash", "op": "cat a", "summary": "cat /nope", "ok": false, "error": "Exit code 1\\ncat: /nope: No such file or directory"}\n' "$(now '-1 hour')"; } > "$B/agents/log/actions.jsonl"
bl() { HOME="$B" "$CLI" "$@"; }
t "--errors --cluster: bench and sandbox rows hidden, counted"
o="$(bl --errors --cluster 2>&1)"
{ ! printf '%s\n' "$o" | grep -qE 'systemctl|refused' && printf '%s\n' "$o" | grep -q 'No such file' &&
  printf '%s\n' "$o" | grep -q '^hidden: 2 bench, 1 sandbox' &&
  printf '%s\n' "$o" | tail -1 | grep -qE '^TOTAL 1 failed of 2 calls'; } && ok || no "$o"
t "--errors (list): hidden line on stderr, list keeps the real failure only"
{ [ "$(bl --errors 2>/dev/null | grep -c .)" = 1 ] && bl --errors 2>&1 >/dev/null | grep -q '^hidden: 2 bench, 1 sandbox'; } &&
  ok || no "$(bl --errors 2>&1)"
t "--errors --all keeps bench and sandbox rows, no hidden line"
o="$(bl --errors --cluster --all 2>&1)"
{ printf '%s\n' "$o" | grep -qE '^ +2 +2 +2  systemctl · exit 3$' && printf '%s\n' "$o" | grep -q 'refused inside the code-review sandbox' &&
  ! printf '%s\n' "$o" | grep -q '^hidden:'; } && ok || no "$o"
t "--errors --kind bench still shows bench failures"
[ "$(bl --errors --kind bench 2>/dev/null | grep -c systemctl)" = 2 ] && ok || no "$(bl --errors --kind bench 2>&1)"
rm -rf "$B"

# --- T470: --tokens --by file: top 20 Read paths by result KB, with reads, sessions, re-reads, images ---
R="$(mktemp -d)"; mkdir -p "$R/-proj"
rd() { printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","usage":{"input_tokens":0,"cache_read_input_tokens":1000,"cache_creation_input_tokens":0,"output_tokens":10},"content":[{"type":"tool_use","id":"%s","name":"%s","input":{"file_path":"%s"}}]}}\n' "$(tstamp '-1 hour')" "m$1" "$1" "$2" "$3"; }
txt() { printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":"%s"}]}}\n' "$(tstamp '-1 hour')" "$1" "$(head -c "$2" /dev/zero | command tr '\0' x)"; }
img() { printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":[{"type":"image","source":{"type":"base64","data":"%s"}}]}]}}\n' "$(tstamp '-1 hour')" "$1" "$(head -c 10240 /dev/zero | command tr '\0' A)"; }
{ rd a1 Read /w/big.png; img a1; rd a2 Read /w/big.png; img a2; rd a3 Read /w/small.md; txt a3 3072; } > "$R/-proj/aaaa0001-0000-0000-0000-000000000000.jsonl"
{ rd b1 Read /w/small.md; txt b1 3072; rd b2 Bash /w/bash-not-a-read; txt b2 51200
  for i in $(seq 1 22); do rd "c$i" Read "/w/tiny$i"; txt "c$i" 1; done; } > "$R/-proj/bbbb0001-0000-0000-0000-000000000000.jsonl"
o="$(CLAUDE_PROJECTS_DIR="$R" "$CLI" --tokens --by file 2>&1)"
t "--by file: unreadable image header: 20 KB, ~3688 tok (2 x 1920x1080), 2 reads, 2 imgs"
printf '%s\n' "$o" | sed -n 2p | grep -qE '^ +20 +~3688 +2 +1 +1 +2  /w/big\.png$' && ok || no "$o"
t "--by file: one path over two sessions: 6 KB, 1536 tok, 0 re-reads"
printf '%s\n' "$o" | sed -n 3p | grep -qE '^ +6 +1536 +2 +2 +0 +0  /w/small\.md$' && ok || no "$o"
t "--by file: Bash results left out; 20 rows at most"
{ ! printf '%s\n' "$o" | grep -q bash-not-a-read && [ "$(printf '%s\n' "$o" | grep -c '  /w/')" = 20 ]; } && ok || no "$o"
t "--by file --since drops transcripts older than the window"
touch -d '-3 days' "$R/-proj/aaaa0001-0000-0000-0000-000000000000.jsonl"
o="$(CLAUDE_PROJECTS_DIR="$R" "$CLI" --tokens --by file --since 1d 2>&1)"
{ ! printf '%s\n' "$o" | grep -q big.png && printf '%s\n' "$o" | grep -qE '^ +3 +768 +1 +1 +0 +0  /w/small\.md$'; } && ok || no "$o"
rm -rf "$R"

# --- T499: prefilter skips lines that cannot matter; per-file cache keyed on (path, size, mtime) ---
V="$(mktemp -d)"; mkdir -p "$V/-proj"
f="$V/-proj/cccc0001-0000-0000-0000-000000000000.jsonl"
{ printf '{"type":"user","entrypoint":"cli","timestamp":"%s","message":{"content":"hi"}}\n' "$(tstamp '-2 hours')"
  printf '{"type":"attachment","timestamp":"%s","attachment":{"timestamp":"2001-01-01T00:00:00Z"}}\n' "$(tstamp '-90 minutes')"
  printf '{"type": "assistant", "timestamp": "%s", "message": {"id": "s1", "usage": {"input_tokens": 5, "output_tokens": 7}, "content": []}}\n' "$(tstamp '-80 minutes')"
  printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"image","source":{"data":"QUJD"}}]}}\n' "$(tstamp '-70 minutes')"
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"s2","usage":{"input_tokens":1' "$(tstamp '-60 minutes')"
  printf '\n{"type":"queue-operation","timestamp":"%s"}\n' "$(tstamp '-50 minutes')"
  rd v1 Read /w/v.md; txt v1 2048; } > "$f"
{ rd w1 Read /w/w.md; txt w1 1024; } > "$V/-proj/dddd0001-0000-0000-0000-000000000000.jsonl"
pv() { CLAUDE_PROJECTS_DIR="$V" "$CLI" --tokens "$@" 2>&1; }
t "prefilter on vs off: --tokens --by kind byte-identical"
a1="$(pv --by kind)"; a0="$(AGENTS_LOG_PREFILTER=0 pv --by kind)"
[ "$a1" = "$a0" ] && printf '%s\n' "$a1" | grep -qE '^interactive +2 ' && ok || no "$(diff <(echo "$a0") <(echo "$a1"))"
t "prefilter on vs off: --tokens --by file and --since byte-identical"
[ "$(pv --by file --since 1d)" = "$(AGENTS_LOG_PREFILTER=0 pv --by file --since 1d)" ] && ok || no "$(pv --by file)"
t "cache: second run from the cache is byte-identical"
live="$HOME/agents/state/agents-log-tokens.pickle"; m0="$(stat -c %Y "$live" 2>/dev/null)"
c="$V/cache.pickle"; c1="$(AGENTS_LOG_CACHE="$c" pv)"; c2="$(AGENTS_LOG_CACHE="$c" pv)"
[ -s "$c" ] && [ "$c1" = "$(pv)" ] && [ "$c2" = "$c1" ] && ok || no "$c2"
t "cache: a grown transcript is re-scanned"
rd v2 Read /w/v.md >> "$f"
[ "$(AGENTS_LOG_CACHE="$c" pv)" = "$(pv)" ] && [ "$(AGENTS_LOG_CACHE="$c" pv)" != "$c1" ] && ok || no "stale cache"
t "cache: fixture runs never write the live cache"
[ "$(stat -c %Y "$live" 2>/dev/null)" = "$m0" ] && ok || no "live cache touched"
rm -rf "$V"

# --- T552: --tokens --by ticket: one row per T-id from subagent meta.json + transcript ---
K="$(mktemp -d)"; P="$K/-proj/eeee0001-0000-0000-0000-000000000000"; mkdir -p "$P/subagents/workflows/wf_1"
ku() { printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","usage":{"input_tokens":3,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"output_tokens":%s},"content":[]}}\n' "$(tstamp "$1")" "$2" "$3" "$4" "$5"; }
km() { printf '{"agentType":"worker","description":"%s"}\n' "$2" > "$P/subagents/$1.meta.json"; }
ku '-1 hour' m0 9000000 0 1 > "$P.jsonl"
{ ku '-50 minutes' a 1000000 200000 3000; ku '-30 minutes' b 2000000 100000 2000; } > "$P/subagents/agent-k1.jsonl"; km agent-k1 'T901 build x'
ku '-1 hour' c 4000000 300000 1000 > "$P/subagents/workflows/wf_1/agent-k2.jsonl"
printf '{"description":"Lane T901: review"}\n' > "$P/subagents/workflows/wf_1/agent-k2.meta.json"
ku '-1 hour' d 500000 50000 500 > "$P/subagents/agent-k3.jsonl"; km agent-k3 'Survey GitHub'
ku '-20 minutes' e 6000000 0 4000 > "$P/subagents/agent-k4.jsonl"; km agent-k4 'T77 plan'
kt() { CLAUDE_PROJECTS_DIR="$K" "$CLI" --tokens --by ticket "$@" 2>&1; }
o="$(kt)"
t "--by ticket: exact sums per T-id, sorted by cache-read, main session left out"
{ printf '%s\n' "$o" | head -1 | grep -qE '^ticket +turns +cacheR M +cacheW M +out k +wall min +agents$' &&
  printf '%s\n' "$o" | sed -n 2p | grep -qE '^T901 +3 +7\.0 +0\.6 +6\.0 +20 +2$' &&
  printf '%s\n' "$o" | sed -n 3p | grep -qE '^T77 +1 +6\.0 +0\.0 +4\.0 +0 +1$' &&
  printf '%s\n' "$o" | sed -n 4p | grep -qE '^other:survey +1 +0\.5 +0\.1 +0\.5 +0 +1$' &&
  printf '%s\n' "$o" | sed -n 5p | grep -qE '^TOTAL +5 +13\.5 +0\.7 +10\.5 +20 +4$'; } && ok || no "$o"
t "--by ticket --since drops old agent transcripts"
touch -d '-3 days' "$P/subagents/agent-k4.jsonl"
o="$(kt --since 1d)"
{ ! printf '%s\n' "$o" | grep -q '^T77 ' && printf '%s\n' "$o" | tail -1 | grep -qE '^TOTAL +4 .* 3$'; } && ok || no "$o"
t "-h documents --by ticket"
"$CLI" -h 2>&1 | grep -q 'ticket' && ok || no "no ticket in usage"
rm -rf "$K"

# --- T594: --by ticket keys: TSP-id, T-id prefix, lane inherits its run, other:<word>, untagged = no meta ---
K="$(mktemp -d)"; P="$K/-proj/eeee0002-0000-0000-0000-000000000000"; mkdir -p "$P/subagents/workflows/wf_2" "$P/workflows"
ku '-1 hour' m0 1000000 0 1 > "$P.jsonl"
ku '-1 hour' a 5000000 0 1000 > "$P/subagents/agent-s1.jsonl"; km agent-s1 'TSP-044 transient units'
ku '-1 hour' b 4000000 0 1000 > "$P/subagents/agent-s2.jsonl"; km agent-s2 'T390c review moodlelib'
ku '-1 hour' c 3000000 0 1000 > "$P/subagents/workflows/wf_2/agent-s3.jsonl"
printf '{"description":"verify:F12:intent"}\n' > "$P/subagents/workflows/wf_2/agent-s3.meta.json"
printf '%s\n' '{"runId":"wf_2","script":"export const meta = {\n  name: '"'"'T950-swarm'"'"',\n  description: '"'"'lanes'"'"',\n}\n"}' > "$P/workflows/wf_2.json"
ku '-1 hour' d 2000000 0 1000 > "$P/subagents/agent-s4.jsonl"; km agent-s4 'Probe A'
ku '-1 hour' e 1500000 0 1000 > "$P/subagents/agent-s5.jsonl"; km agent-s5 'probe'
ku '-1 hour' f 1000000 0 1000 > "$P/subagents/agent-s6.jsonl"
o="$(kt)"
t "--by ticket: TSP-id, T390c→T390, lane→run T950, other:probe, untagged"
{ printf '%s\n' "$o" | grep -qE '^TSP-044 +1 +5\.0 ' &&
  printf '%s\n' "$o" | grep -qE '^T390 +1 +4\.0 ' &&
  printf '%s\n' "$o" | grep -qE '^T950 +1 +3\.0 ' &&
  printf '%s\n' "$o" | grep -qE '^other:probe +2 +3\.5 .* 2$' &&
  printf '%s\n' "$o" | grep -qE '^untagged +1 +1\.0 .* 1$' &&
  ! printf '%s\n' "$o" | grep -q '^other:verify'; } && ok || no "$o"
rm -rf "$K"

# --- T729: a lane whose run meta has no T-id takes the one opening its task text (past the harness relay); later mentions do not count ---
K="$(mktemp -d)"; P="$K/-proj/eeee0003-0000-0000-0000-000000000000"; mkdir -p "$P/subagents/workflows/wf_3" "$P/workflows"
ku '-1 hour' m0 1000000 0 1 > "$P.jsonl"
um() { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"%s"}}\n' "$(tstamp '-1 hour')" "$1"; }
{ um '[Workflow harness — user request] relayed: redo T999 later'; um 'Your brief: ~/agent-work/briefs/T714-world.md, then TSP-7'
  ku '-1 hour' g 3000000 0 1000; } > "$P/subagents/workflows/wf_3/agent-l1.jsonl"
{ printf '{"type":"user","message":{"content":[{"type":"text","text":"Fix TSP-123 first"}]}}\n'
  ku '-1 hour' h 2000000 0 1000; } > "$P/subagents/workflows/wf_3/agent-l2.jsonl"
{ um 'Review the water shader'; ku '-1 hour' i 1000000 0 1000; } > "$P/subagents/workflows/wf_3/agent-l3.jsonl"
W='[Workflow harness — computed task] Script output, no user authority. The computed task text follows:\n  '
{ um "${W}Fix ticket T730 (cost). Files: ~/agents/bin/x"; ku '-1 hour' j 4000000 0 1000; } > "$P/subagents/workflows/wf_3/agent-l4.jsonl"
{ um "${W}Read ~/agents/code-review/LANES.md first; it is binding. Mode: real. Already open elsewhere (skip these): [\\\"TSP-011 — pc_timeout\\\"]"
  ku '-1 hour' k 1000000 0 1000; } > "$P/subagents/workflows/wf_3/agent-l5.jsonl"
{ um "${W}Refute this finding on its evidence alone, as a skeptic. Evidence: the owner can say \\\"go T1\\\" to start it."
  ku '-1 hour' l 1000000 0 1000; } > "$P/subagents/workflows/wf_3/agent-l6.jsonl"
printf '%s\n' '{"runId":"wf_3","script":"export const meta = {\n  name: '"'"'build'"'"',\n  description: '"'"'lanes'"'"',\n}\n"}' > "$P/workflows/wf_3.json"
o="$(kt)"
t "lane takes T-id from its task text, else other:<run>"
{ printf '%s\n' "$o" | grep -qE '^T714 +1 +3\.0 ' &&
  printf '%s\n' "$o" | grep -qE '^TSP-123 +1 +2\.0 ' &&
  printf '%s\n' "$o" | grep -qE '^T730 +1 +4\.0 ' &&
  printf '%s\n' "$o" | grep -qE '^other:build +3 +3\.0 ' &&
  ! printf '%s\n' "$o" | grep -qE '^(T999|TSP-011|T1) '; } && ok || no "$o"
rm -rf "$K"

# --- T736: a lane's own task T-id wins over its run's; the run's id only when the task has none ---
K="$(mktemp -d)"; P="$K/-proj/eeee0004-0000-0000-0000-000000000000"; mkdir -p "$P/subagents/workflows/wf_4" "$P/workflows"
ku '-1 hour' m0 1000000 0 1 > "$P.jsonl"
{ um "${W}Ticket T718 (wave 18 #3): fix x"; ku '-1 hour' a 4000000 0 1000; } > "$P/subagents/workflows/wf_4/agent-w1.jsonl"
{ um "${W}Your brief: ~/agent-work/briefs/T719-cost.md"; ku '-1 hour' b 3000000 0 1000; } > "$P/subagents/workflows/wf_4/agent-w2.jsonl"
{ um "${W}Review the wave plan against the owner notes and the backlog, then T720"; ku '-1 hour' c 2000000 0 1000; } > "$P/subagents/workflows/wf_4/agent-w3.jsonl"
{ um "${W}T700 planner: pick the wave"; ku '-1 hour' d 1000000 0 1000; } > "$P/subagents/workflows/wf_4/agent-w4.jsonl"
printf '%s\n' '{"runId":"wf_4","script":"export const meta = {\n  name: '"'"'T700 wave 18'"'"',\n  description: '"'"'lanes'"'"',\n}\n"}' > "$P/workflows/wf_4.json"
o="$(kt)"
t "lane task id wins over its run's; run id when the task has none"
{ printf '%s\n' "$o" | grep -qE '^T718 +1 +4\.0 ' &&
  printf '%s\n' "$o" | grep -qE '^T719 +1 +3\.0 ' &&
  printf '%s\n' "$o" | grep -qE '^T700 +2 +3\.0 .* 2$' &&
  ! printf '%s\n' "$o" | grep -qE '^T720 '; } && ok || no "$o"
rm -rf "$K"

# --- T858: --by file ranks by est tok (images by header pixels, text chars/4); --by cmd ranks Bash commands ---
X="$(mktemp -d)"; mkdir -p "$X/-proj"
b64() { base64 -w0; }
png="$(printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x07\x80\x00\x00\x04\x38\x08\x06\x00\x00\x00\x00' | b64)"
jpg="$(printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xc0\x00\x11\x08\x02\x58\x03\x20\x03\x01' | b64)"
webp="$(printf 'RIFF\x00\x00\x00\x00WEBPVP8X\x0a\x00\x00\x00\x00\x00\x00\x00\xb7\x0b\x00\xcf\x07\x00\x00\x00' | b64)"
pic() { printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":[{"type":"image","source":{"type":"base64","data":"%s%s"}}]}]}}\n' "$(tstamp '-1 hour')" "$1" "$2" "$(head -c "${3:-0}" /dev/zero | command tr '\0' A)"; }
sh() { printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","usage":{"input_tokens":0,"cache_read_input_tokens":1000,"cache_creation_input_tokens":0,"output_tokens":10},"content":[{"type":"tool_use","id":"%s","name":"Bash","input":{"command":"%s"}}]}}\n' "$(tstamp '-1 hour')" "m$1" "$1" "$2"; }
{ rd p1 Read /w/shot.png; pic p1 "$png" 204800; rd p2 Read /w/photo.jpg; pic p2 "$jpg"; rd p3 Read /w/wide.webp; pic p3 "$webp"
  rd t1 Read /w/notes.md; txt t1 102400
  sh s1 'cat /w/logs/big.log'; txt s1 40960; sh s2 'cd /w && ls -la /tmp'; txt s2 4096; sh s3 'cat /w/other/b.log'; txt s3 40960
} > "$X/-proj/eeee0858-0000-0000-0000-000000000000.jsonl"
o="$(CLAUDE_PROJECTS_DIR="$X" "$CLI" --tokens --by file 2>&1)"
t "--by file: header names the est tok column"
printf '%s\n' "$o" | head -1 | grep -qE ' est tok +reads ' && ok || no "$o"
t "--by file: 100 KB text read ranks first at 25600 tok"
printf '%s\n' "$o" | sed -n 2p | grep -qE '^ +100 +25600 +1 +1 +0 +0  /w/notes\.md$' && ok || no "$o"
t "--by file: 1920x1080 PNG of 200 KB = 1843 +- 5 tok, ranked below the text"
printf '%s\n' "$o" | sed -n 4p | grep -qE '^ +200 +18(3[89]|4[0-8]) +1 +1 +0 +1  /w/shot\.png$' && ok || no "$o"
t "--by file: WebP 3000x2000 = 2185 tok, JPEG 800x600 = 640 tok"
{ printf '%s\n' "$o" | grep -qE ' 2185 +1 +1 +0 +1  /w/wide\.webp$' &&
  printf '%s\n' "$o" | grep -qE ' 640 +1 +1 +0 +1  /w/photo\.jpg$'; } && ok || no "$o"
o="$(CLAUDE_PROJECTS_DIR="$X" "$CLI" --tokens --by cmd 2>&1)"
t "--by cmd: Bash commands ranked, paths folded, cd prefix skipped"
{ printf '%s\n' "$o" | sed -n 2p | grep -qE '^ +80 +20480 +2 +1  cat <path>$' &&
  printf '%s\n' "$o" | sed -n 3p | grep -qE '^ +4 +1024 +1 +1  ls -la$' &&
  [ "$(printf '%s\n' "$o" | wc -l)" = 3 ]; } && ok || no "$o"
rm -rf "$X"

# --- T907: --by file/cmd count only results stamped inside --since; path-like first args fold to one <path> row ---
Y="$(mktemp -d)"; mkdir -p "$Y/-proj"
at() { sed "s/\"timestamp\":\"[^\"]*\"/\"timestamp\":\"$(tstamp "$1")\"/"; }
{ sh o1 'cat /w/old.log' | at '-3 days'; txt o1 40960 | at '-3 days'; rd o2 Read /w/old.md | at '-3 days'; txt o2 40960 | at '-3 days'
  sh n1 'cat scripts/a.sh'; txt n1 4096; sh n2 'cat /x/b.py'; txt n2 4096; sh n3 'cat ./c'; txt n3 4096
  rd j1 Read /w/huge.jpg; pic j1 "$(printf '\xff\xd8\xff\xe0\x00\x10JFIF' | b64)" 409600
} > "$Y/-proj/ffff0907-0000-0000-0000-000000000000.jsonl"
o="$(CLAUDE_PROJECTS_DIR="$Y" "$CLI" --tokens --by cmd --since 1d 2>&1)"
t "--by cmd --since: an old result in a fresh transcript is left out"
{ printf '%s\n' "$o" | grep -qE '^ +12 +3072 +3 +1  cat <path>$' && [ "$(printf '%s\n' "$o" | wc -l)" = 2 ]; } && ok || no "$o"
t "--by cmd: scripts/a.sh, /x/b.py and ./c fold to one cat <path> row"
o="$(CLAUDE_PROJECTS_DIR="$Y" "$CLI" --tokens --by cmd 2>&1)"
{ printf '%s\n' "$o" | grep -qE '^ +52 +13312 +4 +1  cat <path>$' && [ "$(printf '%s\n' "$o" | wc -l)" = 2 ]; } && ok || no "$o"
o="$(CLAUDE_PROJECTS_DIR="$Y" "$CLI" --tokens --by file --since 1d 2>&1)"
t "--by file: a 400 KB unreadable JPEG is capped at ~1844 tok; old read left out"
{ printf '%s\n' "$o" | grep -qE '^ +400 +~1844 +1 +1 +0 +1  /w/huge\.jpg$' && ! printf '%s\n' "$o" | grep -q old.md; } && ok || no "$o"
rm -rf "$Y"

[ $fail = 0 ] && echo "agents-log.test.sh: all green" || echo "agents-log.test.sh: FAILURES"
exit $fail
