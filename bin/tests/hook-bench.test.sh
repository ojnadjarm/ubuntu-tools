#!/usr/bin/env bash
# hook-bench: stub hooks with known sleeps come out ordered, --max-p95 gates, matchers and seams hold, real audit log untouched.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
HB="$BIN/hook-bench"
REAL_LOG="${HARNESS_HOME:-$HOME/agents}/log/actions.jsonl"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok - $1"; }
no() { echo "not ok - $1"; fail=1; }

mkdir -p "$T/stubs" "$T/log"
for s in fast:0.01 mid:0.03 slow:0.06; do
  printf '#!/bin/dash\ncat >/dev/null\nsleep %s\n' "${s#*:}" >"$T/stubs/${s%:*}.sh"
done
printf '#!/bin/dash\nprintf "%%s %%s %%s\\n" "$HOME" "$HARNESS_HOME" "$(grep -o "\\"tool_name\\": \\"[A-Za-z]*\\"")" >>%s/seen\n' "$T" >"$T/stubs/spy.sh"
printf '#!/bin/dash\ntouch %s/stop-ran\n' "$T" >"$T/stubs/stop.sh"
chmod +x "$T"/stubs/*.sh
for i in 1 2 3; do
  echo '{"ts": "x", "session": "fixture", "tool": "Bash", "op": "ls", "summary": "ls /tmp", "cwd": "/tmp"}'
  echo '{"ts": "x", "session": "fixture", "tool": "Read", "op": "Read a", "summary": "/tmp/a.txt", "cwd": "/tmp"}'
done >"$T/log/actions.jsonl"

cat >"$T/settings.json" <<EOF
{"hooks": {
  "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "$T/stubs/slow.sh"}]},
                 {"matcher": "Read", "hooks": [{"type": "command", "command": "$T/stubs/spy.sh"}]}],
  "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "$T/stubs/fast.sh"},
                                              {"type": "command", "command": "$T/stubs/mid.sh"}]}],
  "Stop": [{"hooks": [{"type": "command", "command": "$T/stubs/stop.sh"}]}]
}}
EOF

o=$("$HB" -n 6 --settings "$T/settings.json" --log "$T/log/actions.jsonl" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "exit 0 without --max-p95" || no "exit $rc: $o"
p50() { awk -v h="$1" '$1==h{print $6}' <<<"$o"; }
f=$(p50 fast) m=$(p50 mid) s=$(p50 slow)
awk -v f="$f" -v m="$m" -v s="$s" 'BEGIN{exit !(f>=10 && f<m && m<s && s>=60)}' \
  && ok "p50 ordered fast $f < mid $m < slow $s ms" || no "p50 order: fast=$f mid=$m slow=$s"
grep -qE '^slow PreToolUse n 6 p50 [0-9.]+ ms p95 [0-9.]+ ms$' <<<"$o" && ok "line format" || no "format: $o"
grep -q 'skipped (not tool-call events): stop(Stop)' <<<"$o" && [ ! -e "$T/stop-ran" ] \
  && ok "non-tool event listed, not run" || no "Stop hook: $o"

[ "$(wc -l <"$T/seen")" -eq 7 ] && ! grep -qv '"tool_name": "Read"' "$T/seen" \
  && ok "Read matcher gets only Read payloads (6 + warm-up)" || no "spy saw: $(cat "$T/seen")"
read -r h hh _ <"$T/seen"
case $h in "$HOME"|"") no "HOME not sandboxed: $h" ;; *) [ "$hh" = "$h/agents" ] && [ ! -e "$h" ] \
  && ok "HOME/HARNESS_HOME in a removed mktemp dir" || no "seams: HOME=$h HARNESS_HOME=$hh" ;; esac

"$HB" -n 4 --settings "$T/settings.json" --log "$T/log/actions.jsonl" --max-p95 40 >/dev/null 2>&1
[ $? -eq 1 ] && ok "--max-p95 40 exits 1 (slow hook 60 ms)" || no "--max-p95 40 did not exit 1"
"$HB" -n 4 --settings "$T/settings.json" --log "$T/log/actions.jsonl" --max-p95 5000 >/dev/null 2>&1
[ $? -eq 0 ] && ok "--max-p95 5000 exits 0" || no "--max-p95 5000 did not exit 0"
"$HB" -n 0 >/dev/null 2>&1; [ $? -eq 2 ] && ok "-n 0 is usage (2)" || no "-n 0 not 2"

AUDIT="$BIN/../adapters/claude/hooks/audit-log.py"
mkdir -p "$T/leak/log"; : >"$T/leak/log/actions.jsonl"
printf '{"hooks": {"PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "%s"}]}]}}\n' \
  "$AUDIT" >"$T/audit.json"
before=$(grep -c '"session": "hookbenc"' "$REAL_LOG" 2>/dev/null)
o=$(HARNESS_HOME="$T/leak" "$HB" -n 5 --settings "$T/audit.json" --log "$T/log/actions.jsonl" 2>&1)
after=$(grep -c '"session": "hookbenc"' "$REAL_LOG" 2>/dev/null)
grep -q 'sandbox: 6 audit rows' <<<"$o" && ok "real audit hook wrote 6 rows into the sandbox" || no "sandbox rows: $o"
[ ! -s "$T/leak/log/actions.jsonl" ] && [ "$before" = "$after" ] \
  && ok "real log and leaked HARNESS_HOME log unchanged (hookbench rows $before = $after)" \
  || no "audit rows leaked: real $before -> $after, leak $(wc -c <"$T/leak/log/actions.jsonl") B"
exit $fail
