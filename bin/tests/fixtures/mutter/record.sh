#!/usr/bin/env bash
# Re-records the pc-mutter fixtures from the live session bus. Run it by hand when gnome-shell
# changes. Every call here is a read. `state-single.json` is whatever is live; `state-mirrored.json`
# is derived from it (both connectors driven at 1920x1080 by one logical monitor) so the tests
# always have the mirrored case the owner configured on 2026-09-06 — see ~/agents/KB/quirks.md.
set -eu
d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; r="$d/resp"; mkdir -p "$r"
P="$HOME/agents/bin/pc-dbus"
"$P" call org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig GetCurrentState --json >"$r/state-single.json"
"$P" call org.gnome.Mutter.IdleMonitor /org/gnome/Mutter/IdleMonitor/Core GetIdletime --json >"$r/idle.json"
"$P" introspect org.gnome.Shell /org/gnome/Shell --json >"$r/shell.json"
"$P" call org.gnome.Shell /org/gnome/Shell ListExtensions --json >"$r/exts.json"
"$P" call org.a11y.Bus /org/a11y/bus GetAddress --json >"$r/a11y.json"
xrandr >"$r/xrandr-single.txt"
python3 "$d/mirror.py" "$r/state-single.json" "$r/state-mirrored.json" "$r/xrandr-mirrored.txt"
