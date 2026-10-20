#!/usr/bin/env bash
# T1000: agents-log --tokens --by cmd buckets chained Bash commands; fixture transcripts only (AGENTS.md §5.6).
set -uo pipefail
CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/agents-log"
fail=0
t() { printf '%-72s' "agents-log-chain: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }

X="$(mktemp -d)"
trap 'rm -rf "$X"' EXIT
mkdir -p "$X/-proj"
python3 - "$X/-proj/eeee1000-0000-0000-0000-000000000000.jsonl" <<'PY'
import json, sys, datetime
ts = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%S.000Z')
cases = [
    ('harness context --worker; cat /x/brief.md', 8192),
    ('mkdir -p /x/s && claims add T1 a b >/dev/null && ls -la /x', 7168),
    ('cd /w && git status', 6144),
    ("grep -E 'a|b;c' /w/f", 5120),
    ("cat > /x/f <<'EOF'\na && b | c; d\nEOF\npython3 /x/f", 4096),
    ('git status; git diff', 3072),
    ('foo 2>&1 | head -5', 2048),
    ('uptime', 1024),
    ('((\n  (a + b) > 3 )) && echo big', 10240),
    ('(cd /tmp && make) | tail -3', 11264),
    ('echo $((a > b)); ls', 12288),
    ('for f in a b; do wc -l $f; done', 13312),
]
with open(sys.argv[1], 'w') as h:
    for i, (cmd, n) in enumerate(cases):
        use = {'type': 'tool_use', 'id': f'b{i}', 'name': 'Bash', 'input': {'command': cmd}}
        h.write(json.dumps({'type': 'assistant', 'timestamp': ts, 'message': {'id': f'm{i}', 'usage': {
            'input_tokens': 0, 'cache_read_input_tokens': 1000, 'cache_creation_input_tokens': 0,
            'output_tokens': 10}, 'content': [use]}}) + '\n')
        h.write(json.dumps({'type': 'user', 'timestamp': ts, 'message': {'content': [
            {'type': 'tool_result', 'tool_use_id': f'b{i}', 'content': 'x' * n}]}}) + '\n')
PY
o="$(CLAUDE_PROJECTS_DIR="$X" timeout 20 "$CLI" --tokens --by cmd 2>&1)"
row() { printf '%s\n' "$o" | grep -qE "^ +$1 +[0-9]+ +$2 +1  $3\$"; }

t "a; b with different words -> chain: <first> + <last>"
row 8 1 'chain: harness \+ cat' && ok || no "$o"
t "mkdir, claims add >/dev/null are silent -> the one producer"
row 7 1 'ls -la' && ok || no "$o"
t "cd prefix skipped (same bucket as before), joins git status"
row 9 2 'git status' && ok || no "$o"
t "operators inside quotes do not split"
row 5 1 'grep -E' && ok || no "$o"
t "heredoc body is not split; cat > file is silent"
row 4 1 'python3 <path>' && ok || no "$o"
t "a pipe counts as a chain: foo | head"
row 2 1 'chain: foo \+ head' && ok || no "$o"
t "single command keeps its bucket"
row 1 1 'uptime' && ok || no "$o"
t "(( arithmetic )) then a newline and ( does not hang"
row 10 1 'echo big' && ok || no "$o"
t "subshell members count: (cd && make) | tail"
row 11 1 'chain: make \+ tail' && ok || no "$o"
t "> inside \$(( )) is no redirect"
row 12 1 'chain: echo \+ ls' && ok || no "$o"
t "for/do/done loop -> its body command"
row 13 1 'wc -l' && ok || no "$o"
t "12 calls in 11 rows, no other chain row"
{ [ "$(printf '%s\n' "$o" | wc -l)" = 12 ] && [ "$(printf '%s\n' "$o" | grep -c 'chain:')" = 4 ]; } && ok || no "$o"

o="$(CLAUDE_PROJECTS_DIR="$X" timeout 20 "$CLI" --tokens --by cmd --split 2>&1)"
w() { printf '%s\n' "$o" | grep -qE "^ +$1 +1  $2\$"; }
t "--split: calls per member word, a word counted once per call"
{ printf '%s\n' "$o" | head -1 | grep -qE '^ +calls +sess  word$' && w 2 cat && w 2 git && w 1 claims && w 1 mkdir &&
  w 1 head && w 1 uptime && w 2 echo && w 1 make && [ "$(printf '%s\n' "$o" | wc -l)" = 17 ]; } && ok || no "$o"
t "--split lists no shell keywords"
! printf '%s\n' "$o" | grep -qE '  (for|done|fi|esac|case|[{}()])$' && ok || no "$o"
t "--split without --by cmd is an error"
! CLAUDE_PROJECTS_DIR="$X" "$CLI" --tokens --split >/dev/null 2>&1 && ok || no "exit 0"

[ "$fail" = 0 ] && echo "agents-log-chain.test.sh: all green"
exit "$fail"
