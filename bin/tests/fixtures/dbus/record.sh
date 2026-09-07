#!/usr/bin/env bash
# Re-records the fixtures below from the live session bus. Run it by hand when gnome-shell changes.
set -eu
d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resp"; mkdir -p "$d"
rec() { local k; k=$(printf '%s\0' "$@" | sha1sum | cut -c1-16); busctl "$@" >"$d/$k"; }
rec --user list --no-pager --json=short --acquired
rec --user tree --no-pager --list org.gnome.Shell
rec --user introspect --no-pager org.gnome.Shell /org/gnome/Shell
rec --user introspect --no-pager org.gnome.Shell /org/gnome/Shell/Extensions/Windows
rec --user get-property --json=short org.gnome.Shell /org/gnome/Shell org.gnome.Shell ShellVersion
rec --user get-property --json=short org.gnome.Shell /org/gnome/Shell org.gnome.Shell OverviewActive
rec --user call --json=short org.gnome.Shell /org/gnome/Shell/Extensions/Windows org.gnome.Shell.Extensions.Windows List
