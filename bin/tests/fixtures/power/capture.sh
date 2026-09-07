#!/usr/bin/env bash
# Re-captures tests/fixtures/{power,thermal}/sys from this machine's live tree (readable files
# only; root-only RAPL counters are read through sudo and stored user-readable).
# Usage: capture.sh [power|thermal]   — sys2/ (the second RAPL/rc6 sample) is edited by hand.
set -uo pipefail
FIX="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
what=${1:-both}

grab() {  # grab <dest-root> <sysfs-dir>… — every regular file one level down
  local dest=$1 d f; shift
  for d in "$@"; do
    [ -d "$d" ] || continue
    mkdir -p "$dest/${d#/}"
    for f in "$d"/*; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      { sudo -n cat "$f" 2>/dev/null || true; } >"$dest/${f#/}"
    done
  done
}

if [ "$what" = power ] || [ "$what" = both ]; then
  rm -rf "$FIX/power/sys"
  grab "$FIX/power" /sys/class/powercap/intel-rapl:0 /sys/class/powercap/intel-rapl:0:0 \
       /sys/class/powercap/intel-rapl:0:1 /sys/class/powercap/intel-rapl:1 \
       /sys/class/drm/card1/gt/gt0 /sys/class/power_supply/BAT0 /sys/class/power_supply/AC0 \
       /sys/devices/system/cpu/intel_pstate /sys/devices/system/cpu/cpu0/cpufreq \
       /sys/devices/platform/asus-nb-wmi /sys/firmware/acpi
  mkdir -p "$FIX/power/sys/class/drm/card1/device/power"
  printf '%s\n' "$(cat /sys/class/drm/card1/device/power/runtime_status)" \
    >"$FIX/power/sys/class/drm/card1/device/power/runtime_status"
fi

if [ "$what" = thermal ] || [ "$what" = both ]; then
  rm -rf "$FIX/thermal/sys"
  grab "$FIX/thermal" /sys/class/thermal/thermal_zone* /sys/class/hwmon/hwmon* \
       /sys/class/drm/card1/gt/gt0 /sys/class/powercap/intel-rapl:0 \
       /sys/devices/platform/asus-nb-wmi
fi
