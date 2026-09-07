#!/usr/bin/env bash
# GH17: no repo-tracked file that an install actually uses may hardcode this machine's person,
# home path, uid, hostname or IP. Those values come from config.env; KB/machine.md is generated.
#
# The tracked set is git's own (`tracked-files.sh` = `git ls-files` once the repo exists, the same
# .gitignore applied by a dry-run matcher before that). Recorded history is exempt — see SKIP below.
set -uo pipefail
# shellcheck source=/dev/null
. "$HOME/agents/bin/env.sh"
DIR="$HARNESS_HOME"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bad=0
ok() { if [ "$1" = 1 ]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad+1)); fi; }

# Evidence and history keep the literals they recorded on purpose:
#   bench/            frozen benchmark arms, recorded trajectories, and the safety selftest that
#                     must name the real remote it proves the guard refuses (AGENTS.md §5.6)
SKIP='^bench/'
# Test fixtures are command output recorded on this machine and replayed byte for byte, so they
# carry an absolute home and a uid by nature. GH17 scrubbed the identities out of them
# (`agentuser`, `example-host`, TEST-NET addresses), and the identity cases below still cover
# them — only the two shape cases skip them.
SKIPSHAPE='^bin/tests/fixtures/'

files="$(bash "$HERE/tracked-files.sh" "$DIR" | grep -vE "$SKIP")"
[ -n "$files" ] && ok 1 "tracked files listed ($(printf '%s\n' "$files" | wc -l) audited)" \
  || { ok 0 "tracked files listed"; exit 1; }

hits() { # hits <label> <ere> [file list]
  local out list="${3:-$files}"
  out="$(cd "$DIR" && printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 grep -nIE "$2" 2>/dev/null)"
  if [ -z "$out" ]; then ok 1 "no $1"; else ok 0 "no $1"; printf '%s\n' "$out" | cut -c1-160 | head -8; fi
}

code="$(printf '%s\n' "$files" | grep -vE "$SKIPSHAPE")"
hits "absolute home path"      '/home/[A-Za-z0-9._-]+' "$code"
hits "hardcoded uid"           '/run/user/[0-9]+|user-[0-9]+\.slice|user@[0-9]+\.service' "$code"
hits "Linux user name"         "(^|[^A-Za-z0-9_-])$(id -un)([^A-Za-z0-9_-]|$)"
[ -n "${HARNESS_HOST:-}" ]          && hits "host name"    "(^|[^A-Za-z0-9_-])$HARNESS_HOST([^A-Za-z0-9_-]|$)"
[ -n "${HARNESS_LAN_IP:-}" ]        && hits "LAN IP"       "$(printf '%s' "$HARNESS_LAN_IP" | sed 's/\./\\./g')"
[ -n "${HARNESS_TAILNET_FQDN:-}" ]  && hits "tailnet name" "$(printf '%s' "${HARNESS_TAILNET_FQDN#*.}" | sed 's/\./\\./g')"
[ -n "${HARNESS_OWNER_NAME:-}" ]    && hits "owner name"   "$HARNESS_OWNER_NAME"
ts="$(tailscale ip -4 2>/dev/null | head -1)"
[ -n "$ts" ] && hits "tailnet IP" "$(printf '%s' "$ts" | sed 's/\./\\./g')"

[ "$bad" = 0 ] && echo "all no-person-hardcoded cases pass" || echo "$bad FAILURES"
exit $([ "$bad" = 0 ] && echo 0 || echo 1)
