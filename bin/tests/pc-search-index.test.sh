#!/usr/bin/env bash
# T450: `pc search-index`. Runs with HOME, the ledger and every external tool (systemctl,
# localsearch, tinysparql) inside a throwaway sandbox; a selftest proves that before any case runs.
set -uo pipefail
REAL_HOME=$HOME
BIN="$REAL_HOME/agents/bin"
PC="$BIN/pc-search-index"
FIX="$BIN/tests/fixtures/search-index"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
H="$WORK/home"; mkdir -p "$H/agent-work/b" "$H/sites" "$H/drop" "$H/moodle-envs/5.2"
export PC_LEDGER="$WORK/changes.jsonl"
fx() { HOME="$H" PC_FIXTURE="$FIX" "$PC" "$@"; }
real_ignores() { find "$REAL_HOME" -maxdepth 2 -name .trackerignore 2>/dev/null | sort | md5sum; }
before_real=$(real_ignores)

# 0. selftest: the sandbox is the only place the verb can see or write.
is 'selftest: tools resolve to the fixture' "$(HOME="$H" PC_FIXTURE="$FIX" bash -c '. "$1/pclib.sh"; pc_cmd localsearch status | head -1' _ "$BIN")" 'Currently indexed: 12 files, 3 folders'
is 'selftest: the verb sees the sandbox HOME' "$(fx status --json | jq -r '.busiest[0].dir')" '~/agent-work'
case "$PC_LEDGER" in "$WORK"/*) ok 'selftest: the ledger is in the sandbox';; *) nok 'selftest: ledger' "$PC_LEDGER"; exit 1;; esac
[ "$bad" = 0 ] || { echo 'selftest failed; nothing else runs'; exit 1; }

# 1. shape.
case "$(sed -n 2p "$PC")" in '# pc search-index '*' — '*) ok 'line 2 is the pc help signature';; *) nok 'line 2' "$(sed -n 2p "$PC")";; esac
fx -h >/dev/null; is '-h exits 0' "$?" 0
fx --nope >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
fx nosuch >/dev/null 2>&1; is 'unknown verb exits 2' "$?" 2

# 2. status reads cost and the busiest dirs.
s=$(fx status --json)
is 'status: CPU seconds' "$(jq -r .cpu_s <<<"$s")" 360
is 'status: seconds of CPU per hour since start' "$(jq -r '.cpu_s_per_h >= 355 and .cpu_s_per_h <= 360' <<<"$s")" true
is 'status: indexed totals' "$(jq -r .indexed <<<"$s")" '12 files, 3 folders'
is 'status: busiest dir counts files changed in 24 h' "$(jq -c '.busiest[0]' <<<"$s")" '{"changed_24h":3,"indexed":3,"dir":"~/agent-work"}'
is 'status: an old dir ranks after, rows outside HOME are dropped' "$(jq -c '[.busiest[].dir]' <<<"$s")" '["~/agent-work","~/sites"]'
is 'status: nothing excluded yet' "$(fx status | sed -n 's/^excluded: //p')" none
is 'status -n limits the list' "$(fx status --json -n 1 | jq '.busiest|length')" 1

# 3. exclude: dry run, refusals, apply, ledger, undo.
is 'a dry run prints would:' "$(fx exclude "$H/drop")" "would: search-index:$H/drop indexed → excluded"
[ -e "$H/drop/.trackerignore" ] && nok 'a dry run writes nothing' 'file exists' || ok 'a dry run writes nothing'
fx exclude "$H/moodle-envs/5.2" --apply >/dev/null 2>&1; is '~/moodle-envs is refused with exit 3' "$?" 3
fx exclude "$H/moodle-envs" --apply >/dev/null 2>&1; is '~/moodle-envs itself is refused' "$?" 3
[ -e "$H/moodle-envs/.trackerignore" ] || [ -e "$H/moodle-envs/5.2/.trackerignore" ] && nok 'refusal writes nothing' x || ok 'refusal writes nothing'
fx exclude "$H/nope" --apply >/dev/null 2>&1; is 'a missing dir exits 1' "$?" 1
fx exclude >/dev/null 2>&1; is 'no dir exits 2' "$?" 2
out=$(fx exclude "$H/drop" --apply)
id=$(tail -1 <<<"$out" | sed -n 's/^rollback: pc undo //p')
[ -n "$id" ] && ok '--apply prints the rollback line' || nok '--apply prints the rollback line' "$out"
[ -e "$H/drop/.trackerignore" ] && ok '--apply writes .trackerignore' || nok '--apply writes .trackerignore' missing
e=$(HOME="$H" "$BIN/pc-undo" show "$id" --json)
is 'the ledger verified the change' "$(jq -r .verified <<<"$e")" true
is 'the ledger records before → after' "$(jq -r '.before + " → " + .after' <<<"$e")" 'indexed → excluded'
is 'a second exclude is a no-op' "$(fx exclude "$H/drop" --apply)" "already: $H/drop excluded"
is 'status lists the excluded dir' "$(fx status | sed -n 's/^excluded: //p')" '~/drop'
HOME="$H" "$BIN/pc-undo" "$id" --apply >/dev/null
[ -e "$H/drop/.trackerignore" ] && nok 'pc undo removes .trackerignore' present || ok 'pc undo removes .trackerignore'

# 4. the real HOME was never touched.
is 'no .trackerignore appeared or vanished in the real HOME' "$(real_ignores)" "$before_real"
exit $bad
