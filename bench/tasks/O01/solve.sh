#!/usr/bin/env bash
# O01 oracle — false when the HDMI connector reads disconnected (a sensor reading), otherwise
# unknown: a connected panel in standby is invisible (KB/quirks.md EF10). Cited from `eye tv`.
set -euo pipefail
MODE_JSON=$(eye tv)
status=$(cat "${PCBENCH_DRM_ROOT:-/sys/class/drm}"/*-HDMI-A-1/status 2>/dev/null | head -1 || true)
if [ "$status" = "disconnected" ]; then tv=false; else tv=unknown; fi
printf '{"tv_on":"%s","evidence":"eye tv reports %s; HDMI connector reads %s","unknown":%s,"reason":"%s"}\n' \
  "$tv" "$(printf '%s' "$MODE_JSON" | tr -d '\n' | sed 's/"/\\"/g')" "${status:-absent}" \
  "$([ "$tv" = unknown ] && echo true || echo false)" \
  "$([ "$tv" = unknown ] && echo 'no sensor for standby' || echo 'sysfs disconnect')"
