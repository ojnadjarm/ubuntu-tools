#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../_lib/task.sh"
orig=$(st_get orig.profile); : "${orig:=performance}"
[ "$(powerprofilesctl get)" = "$orig" ] || powerprofilesctl set "$orig"
# The restore goes behind pc's back, so drop the profile cache entries it would otherwise
# serve to the next trial for up to 60 s (pclib `cached`: ppd, power_profile).
rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pc-status/ppd" \
      "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pc-status/power_profile"
rm -rf "$STATE"
[ "$(powerprofilesctl get)" = "$orig" ] || { echo "teardown: profile still $(powerprofilesctl get)" >&2; exit 1; }
exit 0
