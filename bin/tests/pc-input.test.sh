#!/usr/bin/env bash
# PT10: pc input against tests/fixtures/input (device parsing, fd holders, the sidecar grab)
# plus one live --device-only uinput round trip: the events are read back from the virtual
# device's own node while it is grabbed, so nothing reaches libinput or gnome-shell.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/input"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
fx() { PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-input" "$@"; }

# 1. devices: the recorded tree parses into nodes with names, buses and EV types.
J=$(fx devices --json)
is 'devices is an array'      "$(jq -r 'type' <<<"$J")" array
is 'four fixture nodes'       "$(jq 'length' <<<"$J")" 4
is 'the i8042 keyboard is listed' \
  "$(jq -r '.[]|select(.path=="/dev/input/event3")|.name' <<<"$J")" 'AT Translated Set 2 keyboard'
is 'ydotoold is listed on an event node' \
  "$(jq -r '.[]|select(.name|test("ydotoold"))|.path' <<<"$J")" /dev/input/event13
is 'EV types come from the EV= bitmask' \
  "$(jq -r '.[]|select(.path=="/dev/input/event3")|.ev|join(",")' <<<"$J")" 'EV_SYN,EV_KEY,EV_MSC,EV_LED,EV_REP'
is 'bus/vendor/product are kept' \
  "$(jq -r '.[]|select(.path=="/dev/input/event13")|"\(.bus) \(.vendor):\(.product)"' <<<"$J")" '0006 2333:6666'

# 2. holders: /proc/*/fd symlinks name who has each node open, with its unit.
is 'the keyboard has two openers' \
  "$(jq '.[]|select(.path=="/dev/input/event3")|.openers|length' <<<"$J")" 2
is 'the unit comes from the cgroup' \
  "$(jq -r '.[]|select(.path=="/dev/input/event3")|.openers[]|select(.pid==2138)|.unit' <<<"$J")" \
  'org.gnome.Shell@wayland.service'
is 'multiplexers are not a grab guess' \
  "$(jq '.[]|select(.path=="/dev/input/event3")|.grabbed_guess' <<<"$J")" false
is 'the sidecar on the AVRCP node is a grab guess' \
  "$(jq '.[]|select(.path=="/dev/input/event20")|.grabbed_guess' <<<"$J")" true

# 3. grabs: only nodes somebody holds, the sidecar flagged.
G=$(fx grabs --json)
is 'grabs is an array'  "$(jq -r 'type' <<<"$G")" array
is 'grabs lists the three held nodes' "$(jq 'length' <<<"$G")" 3
is 'the sidecar is flagged' \
  "$(jq -r '.[]|select(.sidecar)|.path' <<<"$G")" /dev/input/event20
is 'the sidecar opener is named' \
  "$(jq -r '.[]|select(.sidecar)|.openers[0].unit' <<<"$G")" dark-eye-ptt.service
is 'text grabs marks SIDECAR' "$(fx grabs | grep -c SIDECAR)" 1

# 4. inject --dry-run: the event list, no device, no ledger.
out=$(fx inject key KEY_MACRO1 --dry-run)
grep -q 'EV_KEY KEY_MACRO1 1' <<<"$out" && ok 'dry run prints the press' || nok 'dry run prints the press' "$out"
grep -q 'EV_KEY KEY_MACRO1 0' <<<"$out" && ok 'dry run prints the release' || nok 'dry run prints the release' "$out"
is 'dry run --json carries the ledger strings' \
  "$(fx inject key KEY_MACRO1 --dry-run --json | jq -r '"\(.target) \(.before) \(.after)"')" \
  'key:KEY_MACRO1 up down,up'
is 'rel dry run'  "$(fx inject rel REL_WHEEL 1 --dry-run --json | jq -r .after)" '+1'
out=$(fx inject key KEY_MACRO1 --device-only)
case "$out" in would:*) ok 'no --apply is a dry run';; *) nok 'no --apply is a dry run' "$out";; esac
[ -e "$WORK/l.jsonl" ] && nok 'dry runs write no ledger entry' 'ledger exists' \
                       || ok 'dry runs write no ledger entry'

# 5. argument and option validation.
fx inject key NOPE_KEY --dry-run >/dev/null 2>&1; is 'an unknown key name exits 2' "$?" 2
fx inject                        >/dev/null 2>&1; is 'inject without a kind exits 2' "$?" 2
fx inject rel REL_X              >/dev/null 2>&1; is 'rel without a value exits 2' "$?" 2
fx caps                          >/dev/null 2>&1; is 'caps without a device exits 2' "$?" 2
fx nosuchverb                    >/dev/null 2>&1; is 'an unknown verb exits 2' "$?" 2
fx --nosuchflag                  >/dev/null 2>&1; is 'an unknown option exits 2' "$?" 2
fx -h >/dev/null 2>&1; is '-h exits 0' "$?" 0
grep -q '^  pc input ' <<<"$("$BIN/pc" help)" && ok 'pc help lists pc input' || nok 'pc help lists pc input' 'missing'

# 6. live, night-safe: one uinput round trip on a key nothing binds, with the node grabbed by
#    our own reader, so the event never reaches the session. Temp ledger; no residue.
live() { PC_LEDGER="$WORK/live.jsonl" "$BIN/pc-input" "$@"; }
virtuals() { cat /sys/devices/virtual/input/input*/name 2>/dev/null | grep -c '^pc-input-virtual$'; }
is 'no virtual device before' "$(virtuals)" 0
if [ -w /dev/uinput ] && sudo -n true 2>/dev/null; then
  out=$(live inject key KEY_MACRO1 --apply --device-only)
  grep -q 'verified' <<<"$out" && ok 'the injected key is read back' || nok 'the injected key is read back' "$out"
  grep -q '^rollback: pc undo ' <<<"$(tail -1 <<<"$out")" \
    && ok 'the rollback line is last' || nok 'the rollback line is last' "$out"
  is 'two ledger lines' "$(wc -l <"$WORK/live.jsonl")" 2
  is 'the ledger entry is verified' "$(jq -r 'select(.verified!=null).verified' "$WORK/live.jsonl")" true
  is 'the ledger records the inverse event' \
    "$(jq -r 'select(.rollback)|.rollback|test("inject key KEY_MACRO1 0 --apply --device-only")' "$WORK/live.jsonl")" true
  J2=$(live inject key KEY_MACRO1 --apply --device-only --json | head -1)
  is 'json says device-only'  "$(jq -r .device_only <<<"$J2")" true
  is 'json read back 2 events' "$(jq '.observed|length' <<<"$J2")" 2
  is 'json names the device'   "$(jq -r .device <<<"$J2")" pc-input-virtual
  is 'a relative step is read back too' \
    "$(live inject rel REL_WHEEL 1 --apply --device-only --json | head -1 | jq -r .verified)" true
  # The inverse of a key injection is its release; the input core drops a release for a key it
  # does not hold, so `pc undo` verifies it by that silence.
  live inject key KEY_MACRO1 --apply --device-only >/dev/null
  PC_LEDGER="$WORK/live.jsonl" "$BIN/pc-undo" --last --apply >/dev/null 2>&1
  is 'pc undo replays the release and verifies' \
    "$(PC_LEDGER=$WORK/live.jsonl "$BIN/pc-undo" list --json | jq -r '.[0]|"\(.after) \(.verified)"')" \
    'up true' 
else
  ok 'live uinput round trip skipped (no /dev/uinput or no sudo -n)'
fi
is 'no virtual device left behind' "$(virtuals)" 0

# 7. live reads: the real tree still parses and a 1 s watch on the keyboard ends by itself.
if sudo -n true 2>/dev/null; then
  is 'live devices lists ydotoold' \
    "$("$BIN/pc-input" devices --json | jq -r '[.[]|select(.name|test("ydotoold"))]|length')" 1
  is 'live grabs is an array' "$("$BIN/pc-input" grabs --json | jq -r type)" array
  "$BIN/pc-input" watch /dev/input/event3 --seconds 1 --json >/dev/null 2>&1
  is 'a 1 s watch exits 0' "$?" 0
else
  ok 'live reads skipped (no sudo -n)'
fi

[ $bad = 0 ] && echo 'PASS pc-input' || echo 'FAIL pc-input'
exit $bad
