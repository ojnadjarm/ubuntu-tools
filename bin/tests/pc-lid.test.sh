#!/usr/bin/env bash
# T44: `pc lid` — watcher logic on fake bus events, and the verb against fake busctl/systemctl (no real bus, no real unit).
set -uo pipefail
BIN="$HOME/agents/bin"
L="$BIN/pc-lid"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

## --- watcher logic: fixture events through a fake bus ----------------------
PYTHONPATH="$BIN" python3 - "$W" <<'PY' || bad=1
import sys
from pc_lid import Lid, DARK, LIT

class FakeBus:
    def __init__(s): s.closed, s.ext, s.mode, s.sets = False, False, 0, []
    def lid_closed(s): return s.closed
    def external(s): return s.ext
    def psm(s): return s.mode
    def set_psm(s, v): s.mode = v; s.sets.append(v)

fails = 0
def check(name, got, want):
    global fails
    print(('ok   ' if got == want else 'FAIL ') + name + ('' if got == want else f': expected {want!r}, got {got!r}'))
    fails += got != want

t = [0.0]
notes = []
def mk():
    b = FakeBus()
    return b, Lid(b, state_path=sys.argv[1] + '/state.json', notify=notes.append, clock=lambda: t[0])

b, lid = mk()
check('lid open at start: nothing set', (lid.evaluate(), b.sets), (None, []))
b.closed = True
check('lid closes, no external: set 3', (lid.evaluate(), b.mode), (DARK, DARK))
check('own PropertiesChanged echo: no action', (lid.evaluate(), b.sets), (None, [DARK]))
b.mode = 0; t[0] = 1
check('gsd resets to 0 while closed: reassert 3', (lid.evaluate(), b.mode, lid.reasserts), (DARK, DARK, 1))
b.closed = False
check('lid opens: set 0', (lid.evaluate(), b.mode, lid.we_set), (LIT, LIT, False))
check('lid open, psm 0: nothing', (lid.evaluate(), b.sets[-1]), (None, LIT))

b, lid = mk()
b.closed, b.ext = True, True
check('lid closed with the TV connected: PowerSaveMode untouched', (lid.evaluate(), b.sets), (None, []))
b.ext = False
check('TV unplugged while closed: set 3', lid.evaluate(), DARK)
b.ext = True
check('TV plugged in again while closed: set 0 (we set it)', lid.evaluate(), LIT)

b, lid = mk()
b.closed, b.ext, b.mode = True, True, 3
check('someone else set 3 with the lid closed and TV on: left alone', (lid.evaluate(), b.sets), (None, []))
b, lid = mk()
b.mode = 3
check('restart with lid open and psm 3 left over: set 0', lid.evaluate(), LIT)

b, lid = mk(); notes.clear(); t[0] = 100
b.closed = True
for i in range(8):
    lid.evaluate(); b.mode = 0; t[0] += 0.5
check('flood: stops after 5 sets in 10 s', b.sets.count(DARK), 5)
check('flood: notifies the owner once', len(notes), 1)
b.closed = False; lid.evaluate(); b.closed = True; t[0] += 20
check('lid cycle clears the flood stop', lid.evaluate(), DARK)
import json
check('state file carries reasserts', 'reasserts' in json.load(open(sys.argv[1] + '/state.json')), True)
sys.exit(1 if fails else 0)
PY

## --- the real watcher on a private bus with fake UPower + DisplayConfig -----
# Selftest first: the private bus must not be the session bus, so the real mutter is unreachable.
T="$W/rt"; mkdir -m 700 -p "$T"
env -u DBUS_SYSTEM_BUS_ADDRESS XDG_RUNTIME_DIR="$T" REAL="$DBUS_SESSION_BUS_ADDRESS" dbus-run-session -- bash -c '
  [ -n "$DBUS_SESSION_BUS_ADDRESS" ] && [ "$DBUS_SESSION_BUS_ADDRESS" != "$REAL" ] || { echo "FAIL fake bus selftest: not isolated"; exit 1; }
  echo "ok   fake bus selftest: private bus, not the session bus"
  DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS python3 "$0/tests/fixtures/pc-lid-fakebus.py" "$0"' "$BIN" || bad=1

## --- the verb against fake busctl/systemctl --------------------------------
F="$W/fx"; mkdir -p "$F/bin" "$F/sys/class/drm/card1-eDP-1" "$W/units"
echo Off >"$F/sys/class/drm/card1-eDP-1/dpms"
cat >"$F/bin/busctl" <<'SH'
#!/usr/bin/env bash
echo "busctl $*" >>"$(dirname "$0")/../calls"
case "$*" in
  *LidIsClosed*) echo 'b true';; *HasExternalMonitor*) echo 'b false';;
  *get-property*PowerSaveMode*) echo 'i 3';;
esac
SH
cat >"$F/bin/systemctl" <<'SH'
#!/usr/bin/env bash
d="$(dirname "$0")/.."; echo "systemctl $*" >>"$d/calls"
case "$*" in
  *enable\ --now*) touch "$d/enabled";; *disable*) rm -f "$d/enabled";;
  *is-enabled*) [ -f "$d/enabled" ] && echo enabled || echo disabled;;
  *is-active*) [ -f "$d/enabled" ] && echo active || echo inactive;;
esac
SH
chmod +x "$F/bin/"*
export PC_FIXTURE="$F" PC_LID_UNIT_DIR="$W/units" PC_LID_STATE="$W/state.json" PC_LEDGER="$W/changes.jsonl"
echo '{"reasserts":2}' >"$W/state.json"

is 'status line' "$("$L")" 'lid=closed psm=3 edp=Off ext=no unit=inactive reasserts=2'
is 'status --json' "$("$L" --json | jq -c '[.lid,.psm,.edp,.ext,.policy]')" '["closed",3,"Off","no","none"]'
is 'policy with no unit is none' "$("$L" policy)" none
is 'without --apply: would line' "$("$L" policy panel-off)" 'would: pc-lid.service none → panel-off'
[ ! -e "$W/units/pc-lid.service" ] && ok 'without --apply: no unit file written' || nok 'without --apply: no unit file written' present
out=$("$L" policy panel-off --apply); id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
[ -n "$id" ] && ok 'panel-off --apply prints rollback' || nok 'panel-off --apply prints rollback' "$out"
grep -q '^ExecStart=/usr/bin/python3 %h/agents/bin/pc_lid.py$' "$W/units/pc-lid.service" && ok 'unit file written' || nok 'unit file written' missing
grep -q 'systemctl --user enable --now pc-lid.service' "$F/calls" && ok 'unit enabled --now' || nok 'unit enabled --now' "$(cat "$F/calls")"
is 'ledger verified the install' "$(jq -rs 'map(select(has("verified")))[-1].verified' "$W/changes.jsonl")" true
"$BIN/pc-undo" "$id" --apply >/dev/null 2>&1
is 'pc undo <id> removes the unit' "$("$L" policy)" none
[ ! -e "$W/units/pc-lid.service" ] && ok 'undo deleted the unit file' || nok 'undo deleted the unit file' present
grep -q 'busctl --user set-property .* PowerSaveMode i 0' "$F/calls" && ok 'undo sets PowerSaveMode 0' || nok 'undo sets PowerSaveMode 0' "$(cat "$F/calls")"
"$L" policy bogus >/dev/null 2>&1; is 'unknown policy exits 2' "$?" 2
"$BIN/pc-dbus" set org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig PowerSaveMode 3 --apply >/dev/null 2>&1
is 'pc dbus set PowerSaveMode is refused (guard; pc lid is the only writer)' "$?" 3

exit $bad
