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
. "$HOME/agents/bin/tests/lib/assert.sh"

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

# 5b. undoing the undo re-applies the original change, and that can be undone again.
out=$("$BIN/pc-undo" "$uid" --apply 2>&1); rc=$?
is 'undo of an undo exits 0' "$rc" 0
is 'undo of an undo re-applies the change' "$(cat "$FAKE_FILE")" blue
uid2=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^rollback: pc undo //p')
"$BIN/pc-undo" "$uid2" --apply >/dev/null 2>&1
is 'undo of an undo of an undo restores again' "$(cat "$FAKE_FILE")" red
: >"$PC_LEDGER"; printf red >"$FAKE_FILE"; "$FAKE" blue --apply >/dev/null; "$BIN/pc-undo" --last --apply >/dev/null
id=$(head -1 "$PC_LEDGER" | jq -r .id)

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

# 9. verify re-runs the stored read: equal appends one late-verify row and exits 0, else exits 1 (TSP-034).
VL="$WORK/verify.jsonl"
cat >"$VL" <<'EOF'
{"ts":"2026-01-01T00:00:00+0000","id":"fakelate1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":"echo b"}
{"id":"fakelate1","verified":false,"observed":"a"}
{"ts":"2026-01-01T00:00:00+0000","id":"fakestill1","session":"s1","cmd":"foo","target":"t","before":"a","after":"b","rollback":"r","read":"echo a"}
{"id":"fakestill1","verified":false,"observed":"a"}
EOF
out=$(PC_LEDGER="$VL" "$BIN/pc-undo" verify fakelate1); rc=$?
is 'verify of a now-true row exits 0' "$rc" 0
is 'verify prints after / at apply / now' "$out" 'after: b · observed at apply: a · observed now: b'
is 'verify appends one late-verify row' "$(tail -1 "$VL")" '{"id":"fakelate1","verified":true,"observed":"b","late":true}'
PC_LEDGER="$VL" "$BIN/pc-undo" verify fakestill1 >/dev/null; rc=$?
is 'verify of a still-false row exits 1' "$rc" 1
is 'a false verify appends nothing' "$(wc -l <"$VL")" 5

# 10. apply and ack rows record who: session from CLAUDE_CODE_SESSION_ID (old name as fallback) and agent (TSP-035).
SL="$WORK/who.jsonl"; printf red >"$FAKE_FILE"
env -u CLAUDE_SESSION_ID PC_LEDGER="$SL" AGENT_NAME=fx CLAUDE_CODE_SESSION_ID=abc12345 "$FAKE" blue --apply >/dev/null
w=$(head -1 "$SL")
is 'apply row session from CLAUDE_CODE_SESSION_ID' "$(jq -r .session <<<"$w")" abc12345
is 'apply row agent from AGENT_NAME' "$(jq -r .agent <<<"$w")" fx
env -u CLAUDE_CODE_SESSION_ID -u AGENT_NAME PC_LEDGER="$SL" CLAUDE_SESSION_ID=old99999 "$FAKE" red --apply >/dev/null
is 'old CLAUDE_SESSION_ID still fills session' "$(grep -F '"cmd"' "$SL" | tail -1 | jq -r .session)" old99999
env -u CLAUDE_SESSION_ID PC_LEDGER="$SL" AGENT_NAME=fx CLAUDE_CODE_SESSION_ID=abc12345 "$BIN/pc-undo" ack fakewho1 --why x >/dev/null
is 'ack row session and agent' "$(tail -1 "$SL" | jq -r '.session + " " + .agent')" 'abc12345 fx'
is 'list shows the agent in the by column' \
  "$(PC_LEDGER="$SL" "$BIN/pc-undo" list | awk 'END{print $NF}')" fx
is 'list falls back to the session prefix' \
  "$(PC_LEDGER="$SL" "$BIN/pc-undo" list | awk 'NR==1{print $NF}')" old99999

# 11. entries span logrotate's compressed rotations, so an id from before the last rotation still resolves (F08).
RL="$WORK/rot.jsonl"
printf '%s\n' '{"ts":"2026-01-01T00:00:00+0000","id":"rotold2","cmd":"c","target":"t","before":"a","after":"b","rollback":"r"}' | gzip >"$RL.2.gz"
printf '%s\n' '{"ts":"2026-01-02T00:00:00+0000","id":"rotold1","cmd":"c","target":"t","before":"b","after":"c","rollback":"r"}' '{"id":"rotold1","verified":true,"observed":"c"}' | gzip >"$RL.1.gz"
printf '%s\n' '{"ts":"2026-01-03T00:00:00+0000","id":"rotlive","cmd":"c","target":"t","before":"c","after":"d","rollback":"r"}' >"$RL"
is 'show finds an id in a rotated .gz' "$(PC_LEDGER="$RL" "$BIN/pc-undo" show rotold1 --json | jq -r '.after + " " + (.verified|tostring)')" 'c true'
is 'list orders live then rotations, newest first' "$(PC_LEDGER="$RL" "$BIN/pc-undo" list --json | jq -r 'map(.id) | join(",")')" 'rotlive,rotold1,rotold2'

[ $bad = 0 ] && echo 'PASS pc-undo' || echo 'FAIL pc-undo'
exit $bad
