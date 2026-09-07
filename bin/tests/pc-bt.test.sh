#!/usr/bin/env bash
# PT12: `pc bt`. Sections 1-4 run against the recorded bluez tree in fixtures/bt (buds connected,
# Battery1 present, sidecar active) and touch no bus; section 5 is live and read-only apart from
# one bounded scan. Nothing connects, disconnects or switches a profile on the live adapter — the
# owner is asleep with the buds in their case, so every mutation here is a `would:` or a guard.
set -uo pipefail
BIN="$HOME/agents/bin"
PC="$BIN/pc-bt"
FIX="$BIN/tests/fixtures/bt"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
fx()  { PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" "$PC" "$@"; }

# 1. shape: the description line pc help prints, -h, the exit codes.
l=$(sed -n 2p "$PC")
case "$l" in '# pc bt '*' — '*) ok 'line 2 is the pc help signature';; *) nok 'line 2 is the pc help signature' "$l";; esac
fx -h >/dev/null; is '-h exits 0' "$?" 0
fx --nope >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
fx nosuchverb >/dev/null 2>&1; is 'unknown verb exits 2' "$?" 2
fx info zzz-no-such-device >/dev/null 2>&1; is 'an unknown device exits 1' "$?" 1

# 2. read verbs against the recording.
s=$(fx status --json)
is 'status --json reads the adapter' "$(jq -r .adapter.address <<<"$s")" 14:13:33:55:29:FE
is 'status --json counts the connected device' "$(jq -r .counts.connected <<<"$s")" 1
is 'status --json carries the battery of a connected device' "$(jq -r '.connected[0].battery' <<<"$s")" 85
is 'status --json names the sidecar' "$(jq -r '.sidecar.unit + ":" + (.sidecar.active|tostring)' <<<"$s")" dark-eye-ptt:true
is 'status --json ages the last bluez error' "$(jq -r '.error.age_seconds > 0 and (.error.message|test("profile.c"))' <<<"$s")" true
is 'devices --json shows the buds connected with a battery' \
  "$(fx devices --json | jq -r '.[]|select(.name=="WF-1000XM5")|.connected==true and .battery==85 and .paired==true')" true
is 'devices --json types the numbers as numbers' \
  "$(fx devices --json | jq -r '.[]|select(.name=="WF-1000XM5")|[(.battery|type),(.rssi|type)]|join(",")')" number,number
is 'battery --json lists the percentage' "$(fx battery --json | jq -r '.[0].percentage')" 85
is 'info --json adds the bluez5 card and its profiles' \
  "$(fx info buds --json | jq -r '.card=="bluez_card.AC_80_0A_27_65_6C" and .profile=="a2dp-sink" and (.profiles|index("headset-head-unit")!=null)')" true
is 'a MAC selector resolves' "$(fx info AC:80:0A:27:65:6C --json | jq -r .name)" WF-1000XM5
is 'a name substring resolves' "$(fx info 1000xm5 --json | jq -r .mac)" AC:80:0A:27:65:6C
is 'profile with no argument prints the active one' "$(fx profile buds)" 'bluez_card.AC_80_0A_27_65_6C a2dp-sink'

# 3. the sidecar guard — the reason this command exists.
fx profile buds hfp --apply >/dev/null 2>&1; is 'profile --apply on the buds exits 3 while the sidecar is active' "$?" 3
out=$(fx profile buds hfp --apply 2>&1); case "$out" in *dark-eye-ptt*--force*) ok 'the refusal names the sidecar and the way out';; *) nok 'the refusal names the sidecar and the way out' "$out";; esac
fx connect buds --apply >/dev/null 2>&1; is 'connect --apply on the buds exits 3 while the sidecar is active' "$?" 3
fx disconnect buds --apply >/dev/null 2>&1; is 'disconnect --apply on the buds exits 3 while the sidecar is active' "$?" 3
fx disconnect buds --apply --force >/dev/null 2>&1; is '--force without --why exits 2' "$?" 2
is 'a dry run still prints would: under the guard' \
  "$(fx disconnect buds 2>/dev/null)" 'would: AC:80:0A:27:65:6C connected → disconnected'
is 'the sidecar-inactive path reaches the profile change' \
  "$(FIX_SIDECAR=inactive fx profile buds hfp 2>&1)" 'would: bluez_card.AC_80_0A_27_65_6C a2dp-sink → headset-head-unit'
is 'an unknown profile exits 2' "$(FIX_SIDECAR=inactive fx profile buds nosuch >/dev/null 2>&1; echo $?)" 2
is 'power off is refused while a device is connected' "$(fx power off >/dev/null 2>&1; echo $?)" 3
is 'power on when it is already on is a no-op' "$(fx power on)" 'already: adapter on'

# 4. the ledger: one recorded disconnect, verified, with the inverse as its rollback.
out=$(FIX_SIDECAR=inactive PC_LEDGER="$WORK/changes.jsonl" fx disconnect buds --apply)
id=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^rollback: pc undo //p')
[ -n "$id" ] && ok '--apply prints the rollback line' || nok '--apply prints the rollback line' "$out"
e=$(PC_LEDGER="$WORK/changes.jsonl" "$BIN/pc-undo" show "$id" --json)
is 'the ledger verified the disconnect' "$(jq -r .verified <<<"$e")" true
is 'the ledger records before → after' "$(jq -r '.before + " → " + .after' <<<"$e")" 'connected → disconnected'
is 'the rollback is the inverse verb' "$(jq -r '.rollback|test("pc-bt connect AC:80:0A:27:65:6C --apply")' <<<"$e")" true
is 'the live ledger was not touched' "$(grep -c . "$WORK/changes.jsonl")" 2

# 5. live, read-only (plus one 1 s scan). Skipped when bluez is not reachable. XDG_RUNTIME_DIR
#    stays the real one here: `systemctl --user is-active` (the sidecar check) needs it.
if busctl --system status org.bluez >/dev/null 2>&1; then
  s=$("$PC" status --json)
  is 'live adapter is powered' "$(jq -r .adapter.powered <<<"$s")" true
  is 'live adapter is not discovering' "$(jq -r .adapter.discovering <<<"$s")" false
  is 'live devices lists the buds as paired' \
    "$("$PC" devices --json | jq -r '.[]|select(.name=="WF-1000XM5")|.paired')" true
  is 'live battery --json is a valid array' \
    "$("$PC" battery --json | jq -r type)" array
  # Tonight the buds are in their case: connect must stay a dry run, and it must say so.
  is 'live connect without --apply prints would:' \
    "$("$PC" connect buds 2>/dev/null | head -1 | cut -d' ' -f1)" 'would:'
  if [ "$(systemctl --user is-active dark-eye-ptt 2>/dev/null)" = active ]; then
    "$PC" profile buds hfp --apply >/dev/null 2>&1
    is 'live profile --apply on the buds exits 3 (the sidecar owns them)' "$?" 3
  else
    ok 'live sidecar guard skipped (dark-eye-ptt is not active)'
  fi
  t0=$(date +%s)
  "$PC" scan --seconds 1 >/dev/null 2>&1
  is 'scan exits 0' "$?" 0
  [ $(( $(date +%s) - t0 )) -le 4 ] && ok 'scan stops inside its window' || nok 'scan stops inside its window' 'over 4 s'
  is 'discovery is off again after the scan' \
    "$("$PC" status --fresh --json | jq -r .adapter.discovering)" false
  pgrep -x bluetoothctl >/dev/null && nok 'scan leaves no bluetoothctl behind' "$(pgrep -x bluetoothctl | tr '\n' ' ')" \
    || ok 'scan leaves no bluetoothctl behind'
  "$PC" scan --seconds 99 >/dev/null 2>&1; is 'scan caps --seconds at 60' "$?" 2
else
  ok 'live checks skipped (org.bluez is not on the system bus)'
fi

[ $bad = 0 ] && echo 'PASS pc-bt' || echo 'FAIL pc-bt'
exit $bad
