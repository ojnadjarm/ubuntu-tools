#!/usr/bin/env bash
# PT01: the change ledger, pc_apply's --apply gate, `pc undo`, and pc_guard's deny-list.
# Everything runs against a temp ledger and a temp target file — the machine is not touched.
set -uo pipefail
BIN="$HOME/agents/bin"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export PC_LEDGER="$WORK/changes.jsonl"
export FAKE_FILE="$WORK/target"
export PCLIB="$BIN/pclib.sh"
FAKE="$BIN/tests/fixtures/undo/pc-fake"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

printf 'red' >"$FAKE_FILE"

# 1. read-only by default: a `would:` line, no ledger, no change.
out=$("$FAKE" blue)
is 'dry run prints would:' "$out" "would: $FAKE_FILE red → blue"
is 'dry run changes nothing' "$(cat "$FAKE_FILE")" red
[ -e "$PC_LEDGER" ] && nok 'dry run writes no ledger entry' "ledger exists" || ok 'dry run writes no ledger entry'

# 2. --apply: change made, entry + verification recorded, rollback printed last.
out=$("$FAKE" blue --apply)
is 'apply changes the target' "$(cat "$FAKE_FILE")" blue
id=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^rollback: pc undo //p')
[ -n "$id" ] && ok 'apply prints the rollback line last' || nok 'apply prints the rollback line last' "$out"
is 'ledger has two lines' "$(wc -l <"$PC_LEDGER")" 2
e=$(head -1 "$PC_LEDGER")
is 'entry id matches'      "$(jq -r .id      <<<"$e")" "$id"
is 'entry records before'  "$(jq -r .before  <<<"$e")" red
is 'entry records after'   "$(jq -r .after   <<<"$e")" blue
is 'entry records target'  "$(jq -r .target  <<<"$e")" "$FAKE_FILE"
[ -n "$(jq -r .rollback <<<"$e")" ] && ok 'entry records a rollback command' || nok 'entry records a rollback command' 'empty'
v=$(tail -1 "$PC_LEDGER")
is 'verification is true'  "$(jq -r .verified <<<"$v")" true
is 'verification observed' "$(jq -r .observed <<<"$v")" blue

# 3. list / show read the ledger back.
is 'undo list --json is an array' "$("$BIN/pc-undo" list --json | jq -r 'type')" array
is 'undo list --json has one entry' "$("$BIN/pc-undo" list --json | jq 'length')" 1
is 'undo show finds the id' "$("$BIN/pc-undo" show "$id" --json | jq -r .after)" blue

# 4. undo without --apply is a dry run too.
out=$("$BIN/pc-undo" --last)
is 'undo dry run prints would:' "$out" "would: $FAKE_FILE blue → red"
is 'undo dry run changes nothing' "$(cat "$FAKE_FILE")" blue

# 5. undo --last --apply restores and is itself ledgered.
out=$("$BIN/pc-undo" --last --apply)
is 'undo restores the value' "$(cat "$FAKE_FILE")" red
is 'undo appends its own pair' "$(wc -l <"$PC_LEDGER")" 4
uid=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^rollback: pc undo //p')
u=$(grep -F "\"id\":\"$uid\"" "$PC_LEDGER" | head -1)
is 'undo entry inverts before/after' "$(jq -r '.before + "→" + .after' <<<"$u")" 'blue→red'
is 'undo entry is verified' "$("$BIN/pc-undo" show "$uid" --json | jq -r .verified)" true

# 6. undo refuses when the world moved on, unless --force.
printf 'green' >"$FAKE_FILE"
out=$("$BIN/pc-undo" "$id" --apply 2>&1); rc=$?
is 'stale undo exits 4' "$rc" 4
case "$out" in *green*) ok 'stale undo says what it found';; *) nok 'stale undo says what it found' "$out";; esac
"$BIN/pc-undo" "$id" --apply --force >/dev/null 2>&1
is 'forced undo rolls back anyway' "$(cat "$FAKE_FILE")" red

# 7. pc_guard: the FLEET §5 deny-list exits 3 with the reason.
out=$(bash -c '. "$1"; pc_guard systemctl stop ssh' _ "$PCLIB" 2>&1); rc=$?
is 'guard exits 3 on systemctl stop ssh' "$rc" 3
case "$out" in *FLEET*) ok 'guard prints the FLEET line';; *) nok 'guard prints the FLEET line' "$out";; esac
for g in 'busctl call ... DisplayConfig.ApplyMonitorsConfig' 'tmux kill-session -t claude' \
         'tee /etc/sudoers.d/x' 'systemctl restart dark-eye.service' 'echo 1 > /sys/.../pwm1_enable'; do
  bash -c '. "$1"; pc_guard "$2"' _ "$PCLIB" "$g" >/dev/null 2>&1
  [ $? = 3 ] && ok "guard denies: $g" || nok "guard denies: $g" "exit $?"
done
bash -c '. "$1"; pc_guard cat /sys/class/power_supply/BAT0/capacity' _ "$PCLIB" >/dev/null 2>&1 \
  && ok 'guard allows a read' || nok 'guard allows a read' "exit $?"
PC_ORCHESTRATOR=1 bash -c '. "$1"; pc_guard systemctl restart dark-eye.service' _ "$PCLIB" >/dev/null 2>&1 \
  && ok 'guard allows dark-eye under PC_ORCHESTRATOR' || nok 'guard allows dark-eye under PC_ORCHESTRATOR' "exit $?"

# 8. ack appends one note line, never touches existing lines.
before_ack=$(cat "$PC_LEDGER")
before_lines=$(wc -l <"$PC_LEDGER")
"$BIN/pc-undo" ack fake0id00 --why "known non-issue" >/dev/null
is 'ack appends exactly one line' "$(wc -l <"$PC_LEDGER")" "$((before_lines + 1))"
is 'ack leaves prior lines untouched' "$(head -n "$before_lines" "$PC_LEDGER")" "$before_ack"
a=$(tail -1 "$PC_LEDGER")
is 'ack line id'  "$(jq -r .id  <<<"$a")" fake0id00
is 'ack line ack' "$(jq -r .ack <<<"$a")" true
is 'ack line why' "$(jq -r .why <<<"$a")" "known non-issue"
[ -n "$(jq -r .ts <<<"$a")" ] && ok 'ack line has a ts' || nok 'ack line has a ts' 'empty'
jq -e 'has("session")' <<<"$a" >/dev/null && ok 'ack line has a session field' || nok 'ack line has a session field' "$a"

[ $bad = 0 ] && echo 'PASS pc-undo' || echo 'FAIL pc-undo'
exit $bad
