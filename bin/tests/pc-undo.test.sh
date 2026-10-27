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

# 12. drift: one row per target's latest entry, classed same|superseded|transient|acked|noread|drift; rc 1 only on drift (T1164).
DL="$WORK/drift.jsonl"; D="$WORK/d"; mkdir -p "$D/bin"
cat >"$D/bin/pc-conf" <<'EOF'
#!/usr/bin/env bash
[ -e "$2" ] && echo "sha:$(sha256sum "$2" | cut -c1-12)" || echo absent
EOF
cat >"$D/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in *".timer -p Type"*) echo;; *"-p Type"*) echo oneshot;; *"z.timer -p UnitFileState"*) cat "${0%/bin/*}/zufs";; *"-p UnitFileState"*) echo enabled;; *".timer -p ActiveState"*) echo active;; *) echo failed;; esac
EOF
chmod +x "$D/bin/pc-conf" "$D/bin/systemctl"
echo 0 >"$D/k1"; echo 5 >"$D/k2"; echo 1 >"$D/k3"; echo 500 >"$D/k4"; echo old >"$D/s.conf"
sha_old=$("$D/bin/pc-conf" state "$D/s.conf"); echo new >"$D/s.conf"; sha_new=$("$D/bin/pc-conf" state "$D/s.conf")
row() { jq -nc --arg id "$1" --arg t "$2" --arg a "$3" --arg r "$4" '{ts:"2026-01-01T00:00:00+0000",id:$id,cmd:"c",target:$t,before:"x",after:$a,rollback:"r",read:(if $r == "" then null else $r end)}'; }
{ row dold   t.same  old  'echo b'
  row dsame  t.same  b    'echo b'
  row dk1    k.one   "0 file=$sha_old" "echo \"\$(cat $D/k1) file=\$(pc-conf state $D/s.conf)\""
  row dk3    k.three "0 file=$sha_old" "echo \"\$(cat $D/k3) file=\$(pc-conf state $D/s.conf)\""
  row dk2    k.two   "5 file=$sha_new" "echo \"\$(cat $D/k2) file=\$(pc-conf state $D/s.conf)\""
  row dg1    g.one   '[a]'    "cat $D/g"
  row dg2    g.two   '[a, b]' "cat $D/g"
  row dswap  swap    '0 MB'   'echo 142 MB'
  row dcont  container:x exited 'echo running'
  row dshot  x.service inactive 'systemctl --user show x.service -p ActiveState --value'
  row dshot2 x2      inactive 'systemctl --user show x2 -p ActiveState --value'
  row dtimer y.timer "enabled inactive" 'echo $(systemctl --user show y.timer -p UnitFileState --value) $(systemctl --user show y.timer -p ActiveState --value)'
  row dtimz  z.timer "disabled inactive" 'echo $(systemctl --user show z.timer -p UnitFileState --value) $(systemctl --user show z.timer -p ActiveState --value)'
  row dlink  /f/cache.bin linked 'echo copy'
  row dsys   vm.k    1500    "cat $D/k4"
  row dack   cups    active  'echo inactive'
  row dnone  tmp     done    ''
  row dsbin  k.ostype "$(cat /proc/sys/kernel/ostype)" 'sysctl -n kernel.ostype'
  echo '{"id":"dack","ack":true,"why":"off by hand"}'; } >"$DL"
echo '[a, b]' >"$D/g"; echo enabled >"$D/zufs"
dr() { env PATH="$D/bin:/usr/bin:/bin" PC_LEDGER="$DL" "$BIN/pc-undo" drift "$@"; }
out=$(dr --json); rc=$?
cls() { jq -r --arg t "$1" '.[] | select(.target == $t) | .class' <<<"$out"; }
is 'drift --json is one row per target' "$(jq 'length' <<<"$out")" 17
is 'drift takes the latest entry of a target' "$(jq -r '.[] | select(.target == "t.same") | .id' <<<"$out")" dsame
is 'drift: read equals after → same'                   "$(cls t.same)" same
is 'drift: file sha changed by a later entry → superseded' "$(cls k.one)" superseded
is 'drift: later entry, live value changed → drift'    "$(cls k.three)" drift
is 'drift: the later entry itself → same'              "$(cls k.two)" same
is 'drift: same read rewritten later → superseded'     "$(cls g.one)" superseded
is 'drift: swap → transient'                           "$(cls swap)" transient
is 'drift: container:* → transient'                    "$(cls container:x)" transient
is 'drift: oneshot run state → transient'              "$(cls x.service)" transient
is 'drift: oneshot named without .service → transient' "$(cls x2)" transient
is 'drift: timer waiting, same unit file state → transient' "$(cls y.timer)" transient
is 'drift: timer unit file state changed → drift'      "$(cls z.timer)" drift
is 'drift: reclaimed hardlink rewritten by its owner → transient' "$(cls /f/cache.bin)" transient
is 'drift: live sysctl changed → drift'                "$(cls vm.k)" drift
is 'drift: drift row carries now'                      "$(jq -r '.[] | select(.target == "vm.k") | .now' <<<"$out")" 500
is 'drift: acked id → acked'                           "$(cls cups)" acked
is 'drift: no stored read → noread'                    "$(cls tmp)" noread
is 'drift: reads get /usr/sbin on PATH'                "$(cls k.ostype)" same
is 'drift exits 1 on drift' "$rc" 1
txt=$(dr); is 'drift text ends with the counts' "$(tail -1 <<<"$txt")" '4 same, 2 superseded, 6 transient, 1 acked, 1 noread, 3 drift'
echo 0 >"$D/k3"; echo 1500 >"$D/k4"; echo disabled >"$D/zufs"
dr >/dev/null; is 'drift exits 0 when nothing drifts' "$?" 0

[ $bad = 0 ] && echo 'PASS pc-undo' || echo 'FAIL pc-undo'
exit $bad
