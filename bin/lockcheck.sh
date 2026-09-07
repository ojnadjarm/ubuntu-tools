#!/bin/bash
# Prints OK if the always-on desktop keys hold their values and the screen is not locked.
. "$(dirname "$0")/env.sh"
fail=0
declare -A SCHEMA
# one `gsettings list-recursively` per schema, read once up front (no per-key fork).
for s in org.gnome.desktop.screensaver org.gnome.desktop.session org.gnome.desktop.lockdown \
         org.gnome.settings-daemon.plugins.power; do
  SCHEMA[$s]=$'\n'"$(gsettings list-recursively "$s" 2>/dev/null)"
done
get() {
  local key=$2 k v
  while read -r _ k v; do [ "$k" = "$key" ] && { printf '%s\n' "$v"; return; }; done <<<"${SCHEMA[$1]}"
}
check() { local got; got=$(get "$1" "$2"); [ "$got" = "$3" ] || { echo "FAIL $1 $2 = $got (expected $3)"; fail=1; }; }
check org.gnome.desktop.screensaver lock-enabled false
check org.gnome.desktop.screensaver idle-activation-enabled false
check org.gnome.desktop.screensaver lock-delay "uint32 0"
check org.gnome.desktop.session idle-delay "uint32 0"
check org.gnome.desktop.lockdown disable-lock-screen true
check org.gnome.settings-daemon.plugins.power idle-dim false
check org.gnome.settings-daemon.plugins.power power-button-action "'nothing'"
check org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'"
check org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type "'nothing'"
active=$(gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.GetActive 2>&1)
[ "$active" = "(false,)" ] || { echo "FAIL screensaver active: $active"; fail=1; }
[ $fail -eq 0 ] && echo OK
exit $fail
