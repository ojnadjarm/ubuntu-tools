#!/usr/bin/env bash
# oracle.sh <ticket> <solution commit> [check cmd]: run a ticket's CHECK (default: its brief's) on the real solution, in the sandbox; prints the exit code.
set -uo pipefail
SC=$(cd "$(dirname "$0")" && pwd)
OUT=${T1773_OUT:-$HOME/agent-work/research/2026-11-18/T1773}
SCR=${T1773_SCRATCH:-$HOME/.cache/t1773}
tk=${1:?ticket}; commit=${2:?commit}
brief=$(awk -F'\t' -v t="$tk" '$1==t {print $3}' "$OUT/tickets.tsv")
chk=${3:-$(sed -n 's/^CHECK: *//p' "$HOME/agent-work/briefs/$brief" | tr -d '`')}
T=$SCR/trials/oracle-$tk
chmod -R u+rwx "$T" 2>/dev/null || true; rm -rf "$T"; mkdir -p "$T"
"$SC/sandbox.sh" setup "$T" -- bash -c 'git -C "$HOME/agents" checkout -q -f --detach "$1"' _ "$commit" || exit 3
"$SC/sandbox.sh" run "$T" -- bash -c "$chk" > "$T/check.log" 2>&1
rc=$?; echo "oracle $tk $commit rc=$rc"; exit $rc
