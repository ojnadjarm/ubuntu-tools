#!/usr/bin/env bash
# T450/T732: `pc search-index`. Runs with HOME, the ledger and every external tool (systemctl,
# localsearch, tinysparql, journalctl, gsettings) inside a throwaway sandbox; a selftest proves that
# before any case runs. gsettings is a stateful stub on $GS_STATE: the real schema is never read or written.
set -uo pipefail
REAL_HOME=$HOME
BIN="$REAL_HOME/agents/bin"
PC="$BIN/pc-search-index"
FIX="$BIN/tests/fixtures/search-index"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
H="$WORK/home"; mkdir -p "$H/agent-work/b" "$H/sites" "$H/drop" "$H/moodle-envs/5.2"
export PC_LEDGER="$WORK/changes.jsonl"
export GS_STATE="$WORK/ignored-directories"; echo "['po', 'CVS']" >"$GS_STATE"
fx() { HOME="$H" PC_FIXTURE="$FIX" "$PC" "$@"; }
real_ignores() { find "$REAL_HOME" -maxdepth 2 -name .trackerignore 2>/dev/null | sort | md5sum; }
before_real=$(real_ignores)

# 0. selftest: the sandbox is the only place the verb can see or write.
is 'selftest: tools resolve to the fixture' "$(HOME="$H" PC_FIXTURE="$FIX" bash -c '. "$1/pclib.sh"; pc_cmd localsearch status | head -1' _ "$BIN")" 'Currently indexed: 12 files, 3 folders'
is 'selftest: the verb sees the sandbox HOME' "$(fx status --json | jq -r '.busiest[0].dir')" '~/agent-work'
is 'selftest: gsettings resolves to the stub' "$(fx exclude --name x)" "would: search-index:name:x ['po', 'CVS'] → ['po', 'CVS', 'x']"
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
is 'status: CPU over 24 h = Consumed lines (pro rata by wall time) + the running process' "$(jq -r .cpu_s_24h <<<"$s")" 2023
is 'status: crashes over 24 h = status=11 lines' "$(jq -r .crashes_24h <<<"$s")" 2
is 'status: the text row' "$(fx status | grep '^cpu 24 h')" 'cpu 24 h 2023 s (journal), crashes 24 h 2'
is 'status: excluded names' "$(fx status | sed -n 's/^excluded names: //p')" "['po', 'CVS']"
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

# 4. exclude --name: gsettings ignored-directories, ledgered, undo restores the list.
for bad_name in '' / a/b "it's"; do
  fx exclude --name "$bad_name" --apply >/dev/null 2>&1; is "--name '$bad_name' is refused with exit 2" "$?" 2
done
is 'refusals leave the list alone' "$(cat "$GS_STATE")" "['po', 'CVS']"
is '--name dry run prints would: [...] → [...]' "$(fx exclude --name moodledata)" "would: search-index:name:moodledata ['po', 'CVS'] → ['po', 'CVS', 'moodledata']"
is '--name dry run writes nothing' "$(cat "$GS_STATE")" "['po', 'CVS']"
out=$(fx exclude --name moodledata --apply)
nid=$(tail -1 <<<"$out" | sed -n 's/^rollback: pc undo //p')
is '--name --apply appends the basename' "$(cat "$GS_STATE")" "['po', 'CVS', 'moodledata']"
is '--name: the ledger verified the change' "$(HOME="$H" "$BIN/pc-undo" show "$nid" --json | jq -r .verified)" true
is 'a second --name is a no-op' "$(fx exclude --name moodledata --apply)" 'already: moodledata excluded by name'
HOME="$H" "$BIN/pc-undo" "$nid" --apply >/dev/null
is 'pc undo restores the previous list' "$(cat "$GS_STATE")" "['po', 'CVS']"
echo '@as []' >"$GS_STATE"; fx exclude --name behatdata --apply >/dev/null
is '--name on an empty list' "$(cat "$GS_STATE")" "['behatdata']"

# 6. T940: a second sandbox fixture: an index with Moodle churn and a shared `cache` name, and a
# gsettings stub that keeps one file per key next to $GS_STATE.
F2="$WORK/fix2"; mkdir -p "$F2/bin"
for t in systemctl journalctl localsearch; do ln -s "$FIX/bin/$t" "$F2/bin/$t"; done
cat >"$F2/bin/gsettings" <<'STUB'
#!/bin/sh
[ -n "${GS_STATE:-}" ] && [ "$2" = org.freedesktop.Tracker3.Miner.Files ] || exit 1
f="$GS_STATE.$3"; [ "$3" = ignored-directories ] && f=$GS_STATE
case $1 in get) cat "$f";; set) printf '%s\n' "$4" >"$f";; *) exit 1;; esac
STUB
cat >"$F2/bin/tinysparql" <<'STUB'
#!/bin/sh
now=$(date -u +%Y-%m-%dT%H:%M:%SZ); m=$HOME/moodle-envs
printf 'Results:\n'
for f in 5.2/moodledata/cache/a 5.2/moodledata/cache/b 5.2/moodledata/sessions/s 5.3/moodledata/cache/c projects/app/cache/y; do
  printf '  file://%s/%s, %s\n' "$m" "$f" "$now"; done | sed "s|$m/projects|$HOME/projects|"
printf '  file://%s/5.2/behatfaildumps/old.html, 2020-01-01T00:00:00Z\n' "$m"
STUB
chmod +x "$F2/bin/gsettings" "$F2/bin/tinysparql"
f2() { HOME="$H" PC_FIXTURE="$F2" "$PC" "$@"; }
echo "['\$HOME']" >"$GS_STATE.index-recursive-directories"; echo '@as []' >"$GS_STATE.index-single-directories"
mkdir -p "$H/projects"

# 6a. status --under: a depth breakdown read from the index.
is 'under depth 1 groups by version' "$(f2 status --under "$H/moodle-envs" --json | jq -c '[.groups[] | [.changed_24h, .indexed, .path]]')" \
  '[[3,4,"~/moodle-envs/5.2"],[1,1,"~/moodle-envs/5.3"]]'
is 'under depth 3 splits cache from sessions' "$(f2 status --under "$H/moodle-envs" --depth 3 | sed -n 2p)" '  2	2	~/moodle-envs/5.2/moodledata/cache'
is 'under -n limits the groups' "$(f2 status --under "$H/moodle-envs" --depth 3 -n 1 --json | jq '.groups|length')" 1
f2 status --under "$H/moodle-envs" --depth 0 >/dev/null 2>&1; is 'under --depth 0 exits 2' "$?" 2

# 6b. the guard: a name shared with indexed files outside DIR is refused unless --force.
echo "['po']" >"$GS_STATE"
f2 exclude --name cache --under "$H/moodle-envs" --apply >/dev/null 2>&1; is 'a shared name is refused with exit 3' "$?" 3
is 'the refusal names the count elsewhere' "$(f2 exclude --name cache --under "$H/moodle-envs" 2>&1)" \
  "pc search-index: refused — 'cache' would also drop 1 files elsewhere (outside $H/moodle-envs); --force overrides"
is 'the refusal writes nothing' "$(cat "$GS_STATE")" "['po']"
is 'a name only under DIR passes the guard' "$(f2 exclude --name sessions --under "$H/moodle-envs")" "would: search-index:name:sessions ['po'] → ['po', 'sessions']"
f2 exclude --name cache --under "$H/moodle-envs" --force --apply >/dev/null; is '--force overrides the guard' "$(cat "$GS_STATE")" "['po', 'cache']"

# 6c. scope --drop: dry run, apply, ledger, undo.
sc() { echo "recursive=$(cat "$GS_STATE.index-recursive-directories") single=$(cat "$GS_STATE.index-single-directories")"; }
echo "['.trackerignore', '.git']" >"$GS_STATE.ignored-directories-with-content"; mkdir -p "$H/sites/.git"
want="recursive=['$H/agent-work', '$H/drop', '$H/projects'] single=['\$HOME']"
is 'scope dry run prints would:' "$(f2 scope --drop "$H/moodle-envs" | head -1)" "would: search-index:scope:~/moodle-envs recursive=['\$HOME'] single=@as [] → $want"
grep -q "'$H/sites'" <<<"$(f2 scope --drop "$H/moodle-envs")" && nok 'scope keeps a .git-marked dir out' sites || ok 'scope keeps a .git-marked dir out (a root ignores its own marker)'
is 'scope dry run writes nothing' "$(sc)" "recursive=['\$HOME'] single=@as []"
f2 scope --drop "$H/moodle-envs/5.2" >/dev/null 2>&1; is 'scope refuses a dir below the top level' "$?" 2
f2 scope >/dev/null 2>&1; is 'scope without --drop exits 2' "$?" 2
out=$(f2 scope --drop "$H/moodle-envs" --apply)
sid=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
is 'scope --apply writes both keys' "$(sc)" "$want"
grep -q '^note: a top-level dir made under ~ later' <<<"$out" && ok 'scope prints the re-run note' || nok 'scope note' "$out"
is 'scope: the ledger verified the change' "$(HOME="$H" "$BIN/pc-undo" show "$sid" --json | jq -r .verified)" true
is 'a second scope is a no-op' "$(f2 scope --drop "$H/moodle-envs" --apply)" 'already: ~/moodle-envs out of scope'
HOME="$H" "$BIN/pc-undo" "$sid" --apply >/dev/null
is 'pc undo restores both keys' "$(sc)" "recursive=['\$HOME'] single=@as []"

# 5. the real HOME was never touched.
is 'no .trackerignore appeared or vanished in the real HOME' "$(real_ignores)" "$before_real"
exit $bad
