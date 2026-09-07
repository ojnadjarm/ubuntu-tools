#!/usr/bin/env bash
# PT09: `pc mutter`. Sections 1-3 run against the recorded compositor in fixtures/mutter (no bus,
# no window); section 4 is live and read-only. Nothing here opens, moves or focuses a window,
# takes a screenshot, makes a sound or touches the monitor configuration.
set -uo pipefail
BIN="$HOME/agents/bin"
PC="$BIN/pc-mutter"
FIX="$BIN/tests/fixtures/mutter"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
fx()  { PC_FIXTURE="$FIX" XDG_RUNTIME_DIR="$WORK" "$PC" "$@"; }

# 1. shape: the description line pc help prints, -h, and the exit codes.
l=$(sed -n 2p "$PC")
case "$l" in '# pc mutter '*' — '*) ok 'line 2 is the pc help signature';; *) nok 'line 2 is the pc help signature' "$l";; esac
fx -h >/dev/null; is '-h exits 0' "$?" 0
fx --nope >/dev/null 2>&1; is 'unknown option exits 2' "$?" 2
fx nosuchverb >/dev/null 2>&1; is 'unknown verb exits 2' "$?" 2
is 'the script never builds a monitor-config call' \
  "$(grep -c 'ApplyMonitorsConfig\|ApplyConfiguration\|SetBacklight' "$PC")" 0

# 2. the mirrored recording (both connectors driven by one logical monitor, as on 2026-09-06).
o=$(fx outputs --json)
is 'outputs --json lists both connectors' "$(jq -r 'length' <<<"$o")" 2
is 'outputs --json reads the current mode' \
  "$(jq -r '.[] | select(.connector=="HDMI-1") | .mode' <<<"$o")" 1920x1080@60.000
is 'outputs --json reports the mode size' \
  "$(jq -r '.[] | select(.connector=="HDMI-1") | "\(.width)x\(.height)"' <<<"$o")" 1920x1080
is 'outputs --json flags the mirroring' \
  "$(jq -r '.[] | select(.connector=="HDMI-1") | .mirrored_with[0]' <<<"$o")" eDP-1
is 'outputs --json gives the logical position and scale' \
  "$(jq -r '.[] | select(.connector=="eDP-1") | "\(.x),\(.y)@\(.scale)"' <<<"$o")" 0,0@1
is 'outputs --json marks the built-in panel' \
  "$(jq -r '.[] | select(.connector=="eDP-1") | .builtin' <<<"$o")" true
is 'outputs text prints one row per connector' "$(fx outputs | grep -c '^[eH]')" 2

s=$(fx --json)
is 'summary --json agrees with xrandr' "$(jq -r '.screen.match' <<<"$s")" true
is 'summary --json carries both screen sizes' \
  "$(jq -c '[.screen.xrandr, .screen.displayconfig]' <<<"$s")" '[[1920,1080],[1920,1080]]'
is 'summary --json counts the windows' "$(jq -r '.windows | length' <<<"$s")" 2
is 'workspaces --json takes the active index from the focused window' \
  "$(fx workspaces --json | jq -c '[.count,.dynamic,.active]')" '[1,false,0]'
is 'summary text is one line per section' "$(fx | wc -l)" 7
is 'summary text names the mirroring' "$(fx | sed -n 1p | grep -c 'mirroring HDMI-1')" 1

# 3. the single-monitor recording: eDP-1 off, and a deliberate xrandr/DisplayConfig mismatch.
sg() { PC_FIXTURE="$FIX" PC_MUTTER_STATE=single PC_MUTTER_XRANDR="$1" XDG_RUNTIME_DIR="$WORK" "$PC" "${@:2}"; }
is 'a disabled connector reports enabled:false' \
  "$(sg single outputs --json | jq -r '.[] | select(.connector=="eDP-1") | .enabled')" false
is 'a disabled connector has no mode' \
  "$(sg single outputs --json | jq -r '.[] | select(.connector=="eDP-1") | .mode')" null
is 'the single screen matches its xrandr' "$(sg single --json | jq -r .screen.match)" true
is 'a differing xrandr is a MISMATCH' "$(sg mirrored --json | jq -r .screen.match)" false
is 'the summary line says MISMATCH' "$(sg mirrored | sed -n 2p | grep -c MISMATCH)" 1

is 'extensions --json names the states' \
  "$(fx extensions --json | jq -r '.[] | select(.uuid=="window-calls@domandoman.xyz") | .state')" active
is 'extensions --json reports an inactive extension' \
  "$(fx extensions --json | jq -r '.[] | select(.uuid=="tiling-assistant@ubuntu.com") | "\(.state)/\(.state_code)"')" inactive/2
is 'extensions --json carries UserExtensionsEnabled' \
  "$(fx extensions --json | jq -r '.[0].user_extensions_enabled')" true
is 'shell --json reads the three properties' \
  "$(fx shell --json | jq -c '[.version,.mode,.overview]')" '["50.1","ubuntu",false]'
is 'idle --json is numeric' "$(fx idle --json | jq -r '.idle_ms | type')" number

# 4. live, read-only. Skipped when this shell has no session bus (a systemd/cron agent).
if busctl --user list --no-pager >/dev/null 2>&1; then
  is 'live outputs --json has HDMI-1 with a WxH@Hz mode' \
    "$("$PC" outputs --json | jq -r '[.[] | select(.connector=="HDMI-1") | .mode | test("^[0-9]+x[0-9]+@")] | first')" true
  is 'live extensions --json has window-calls active' \
    "$("$PC" extensions --json | jq -r '.[] | select(.uuid=="window-calls@domandoman.xyz") | .state')" active
  is 'live idle --json is a non-negative number' "$("$PC" idle --json | jq -r '.idle_ms >= 0')" true
  is 'live shell --json reports GNOME 50.1' "$("$PC" shell --json | jq -r .version)" 50.1
  is 'live shell --all lists the DisplayConfig methods without calling them' \
    "$("$PC" shell --all --json | jq -r '[.interfaces[] | select(.path=="/org/gnome/Mutter/DisplayConfig")
        | .interfaces[].methods[] | select(. == "GetCurrentState")] | length')" 1
  is 'live windows --json is the pc win list array' "$("$PC" windows --json | jq -r type)" array
  is 'live summary --json parses' "$("$PC" --json | jq -r '[.outputs,.workspaces,.idle,.shell,.extensions] | length')" 5
  m=$("$PC" --json | jq -r .screen.match)
  [ "$m" = true ] && ok 'live xrandr and DisplayConfig agree on the screen size' \
    || nok 'live xrandr and DisplayConfig agree on the screen size' "$("$PC" | sed -n 2p)"
  is 'live summary is inside its 0.4 s budget' \
    "$(awk -v t="$( { /usr/bin/time -f %e "$PC" >/dev/null; } 2>&1 )" 'BEGIN{print (t <= 0.4) ? "yes" : t}')" yes
else
  ok 'live checks skipped (no session bus in this shell)'
fi

[ $bad = 0 ] && echo 'PASS pc-mutter' || echo 'FAIL pc-mutter'
exit $bad
