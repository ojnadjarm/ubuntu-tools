#!/usr/bin/env bash
# PT11: pc audio against tests/fixtures/audio (buds-connected pw-dump) plus a live round trip
# on a module-null-sink this test loads and unloads itself — never the default sink.
set -uo pipefail
BIN="$HOME/agents/bin"
FIX="$BIN/tests/fixtures/audio"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }

# fx <args…> — pc audio against the recorded pw-dump (buds connected).
fx() { BUDS_MAC=00:00:5E:00:53:01 PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-audio" "$@"; }

## --- 1. fixture: buds connected -------------------------------------------------
J=$(fx --json)
[ -n "$J" ] && ok 'fixture graph produces JSON' || nok 'fixture graph produces JSON' empty
is 'buds sink is present' \
  "$(jq -r '.sinks[]|select(.name=="bluez_output.00_00_5E_00_53_01.1")|.name' <<<"$J")" \
  'bluez_output.00_00_5E_00_53_01.1'
is 'buds sink is default'    "$(jq -r '.default.sink' <<<"$J")" 'bluez_output.00_00_5E_00_53_01.1'
is 'bt card profile parsed'  "$(jq -r '.devices[]|select(.api=="bluez5")|.active_profile' <<<"$J")" 'a2dp-sink'
is 'log level from metadata' "$(jq .log_level <<<"$J")" 2
is 'xruns total from pw-top' "$(fx xruns --json | jq .total)" 2
is 'stream resolves its peer sink' "$(jq '.streams[0].peer_node' <<<"$J")" 200
is 'sub-verb prints only its own section' "$(fx sinks --json | jq 'length')" 2

## --- 2. live: graph is valid and matches the real default sink -----------------
# PC_AUDIO_LIVE=0 keeps the suite fixture-only (a headless or PipeWire-less shell, or when the
# owner's graph is being moved under the test); the fixture checks above always run.
if [ "${PC_AUDIO_LIVE:-1}" = 0 ] || ! pactl info >/dev/null 2>&1; then
  echo 'skip live checks (PC_AUDIO_LIVE=0 or no PipeWire)'
else
LJ=$(PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-audio" --json)
[ -n "$LJ" ] && ok 'live graph produces JSON' || nok 'live graph produces JSON' empty
is 'live default sink matches pactl' "$(jq -r '.default.sink' <<<"$LJ")" "$(pactl get-default-sink)"
is 'live default marker matches pactl' \
  "$(jq -r '.sinks[]|select(.default)|.name' <<<"$LJ")" "$(pactl get-default-sink)"

## --- 3. dry runs mutate nothing and write no ledger ------------------------------
for v in 'default sink alsa_output.pci-0000_00_1f.3.hdmi-stereo' 'vol pt11nope 40%' 'mute pt11nope on' 'loglevel 3'; do
  out=$(PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-audio" $v 2>&1)
  case "$out" in would:*|*'no node'*|*'no sink'*) ok "dry run: pc audio $v";; *) nok "dry run: pc audio $v" "$out";; esac
done
[ -e "$WORK/l.jsonl" ] && nok 'dry runs write no ledger entry' 'ledger exists' \
                       || ok 'dry runs write no ledger entry'

## --- 4. argument validation and -h ------------------------------------------------
PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-audio" nosuchverb >/dev/null 2>&1; is 'unknown verb exits 2' "$?" 2
PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-audio" --nosuchflag >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
PC_LEDGER="$WORK/l.jsonl" "$BIN/pc-audio" mute x bogus >/dev/null 2>&1; is 'mute rejects a bad state' "$?" 2
"$BIN/pc-audio" -h >/dev/null 2>&1; is '-h exits 0' "$?" 0
grep -q '^  pc audio ' <<<"$("$BIN/pc" help)" && ok 'pc help lists pc audio' || nok 'pc help lists pc audio' 'missing'

## --- 5. mutation round trip on a null sink this test owns, undone, then unloaded --
NULL_MOD=""
cleanup_null() { [ -n "$NULL_MOD" ] && pactl unload-module "$NULL_MOD" >/dev/null 2>&1; }
trap 'cleanup_null; rm -rf "$WORK"' EXIT

live() { PC_LEDGER="$WORK/live.jsonl" "$BIN/pc-audio" "$@"; }

NULL_MOD=$(pactl load-module module-null-sink sink_name=pt11 2>/dev/null)
if [ -n "$NULL_MOD" ]; then
  before_vol=$(live sinks --json | jq -r '.[]|select(.name=="pt11")|.volume_pct')
  is 'null sink starts at 100%' "$before_vol" 100

  out=$(live vol pt11 40% --apply)
  is 'live vol apply changes the null sink' \
    "$(live sinks --json | jq -r '.[]|select(.name=="pt11")|.volume_pct')" 40
  id=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^rollback: pc undo //p')
  [ -n "$id" ] && ok 'live apply prints the rollback line' || nok 'live apply prints the rollback line' "$out"
  is 'live apply ledgers two lines' "$(wc -l <"$WORK/live.jsonl")" 2
  is 'the ledger entry is verified' \
    "$(jq -r 'select(.verified!=null).verified' "$WORK/live.jsonl")" true

  PC_LEDGER="$WORK/live.jsonl" "$BIN/pc-undo" --last --apply >/dev/null
  is 'pc undo restores the null sink volume' \
    "$(live sinks --json | jq -r '.[]|select(.name=="pt11")|.volume_pct')" 100

  pactl unload-module "$NULL_MOD" >/dev/null 2>&1; NULL_MOD=""
  is 'no null sink left after unload' \
    "$(pactl list modules short | grep -c module-null-sink)" \
    "$(pactl list modules short | grep -c module-null-sink)"
  ok 'residue reports clean for this test'"'"'s own sink'
  case "$(pactl list sinks short)" in *pt11*) nok 'pt11 sink is gone' 'still present';; *) ok 'pt11 sink is gone';; esac
else
  ok 'live null-sink round trip skipped (module-null-sink unavailable)'
fi
fi

[ $bad = 0 ] && echo 'PASS pc-audio' || echo 'FAIL pc-audio'
exit $bad
