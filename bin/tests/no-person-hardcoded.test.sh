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
. "$HOME/agents/bin/tests/lib/assert.sh"

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
[ -n "$files" ] && truthy "tracked files listed ($(printf '%s\n' "$files" | wc -l) audited)" 1 \
  || { truthy "tracked files listed" 0; exit 1; }

hits() { # hits <label> <ere> [file list]
  local out list="${3:-$files}"
  out="$(cd "$DIR" && printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 grep -nIE --devices=skip "$2" 2>/dev/null)"
  if [ -z "$out" ]; then truthy "no $1" 1; else truthy "no $1" 0; printf '%s\n' "$out" | cut -c1-160 | head -8; fi
}

# Intentional samples, one `file:line` each with its reason.
ALLOW_HOME='
discord-bot/tests/test_bot.py:45 redaction sample the bot must scrub from replies
discord-bot/tests/test_bot.py:213 redaction sample the bot must scrub from replies
discord-bot/tests/test_bot.py:215 asserts the redaction sample is gone
discord-bot/tests/test_bot.py:256 asserts the redaction sample is gone
bin/tests/auditlib.test.py:53 fake error text for the audit error classifier
'
HOME_RE='/home/[A-Za-z0-9._-]+'

home_hits() { # home_hits <dir> <file list>: /home/<user> literals, minus $VAR/home fixtures and ALLOW_HOME
  local allow
  allow="$(printf '%s\n' "$ALLOW_HOME" | awk 'NF {print $1 ":"}')"
  (cd "$1" && printf '%s\n' "$2" | tr '\n' '\0' | xargs -0 grep -nIE --devices=skip "$HOME_RE" 2>/dev/null) \
    | grep -vF -f <(printf '%s\n' "$allow") \
    | sed -E 's#\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/home/[A-Za-z0-9._-]*##g' | grep -E "$HOME_RE"
}

sbx="$(mktemp -d)"; trap 'rm -rf "$sbx"' EXIT
printf '%s\n' 'mkdir -p "$SBX/home/agents" "${WORK}/home/x"' >"$sbx/fixture.sh"
u=realuser
printf '%s\n' 'cd "$SBX/home/a" && cat /home/'"$u/notes" >"$sbx/mixed.sh"
printf '%s\n' "LOG=/home/$u/agents/x.log" >"$sbx/real.sh"
truthy "selftest: \$VAR/home fixture prefixes are ignored" "$([ -z "$(home_hits "$sbx" fixture.sh)" ] && echo 1 || echo 0)"
truthy "selftest: a real /home/<user> literal still fails" "$([ "$(home_hits "$sbx" "$(printf 'real.sh\nmixed.sh')" | wc -l)" = 2 ] && echo 1 || echo 0)"

code="$(printf '%s\n' "$files" | grep -vE "$SKIPSHAPE")"
out="$(home_hits "$DIR" "$code")"
if [ -z "$out" ]; then truthy "no absolute home path" 1; else truthy "no absolute home path" 0; printf '%s\n' "$out" | cut -c1-160 | head -8; fi
hits "hardcoded uid"           '/run/user/[0-9]+|user-[0-9]+\.slice|user@[0-9]+\.service' "$code"
hits "Linux user name"         "(^|[^A-Za-z0-9_-])$(id -un)([^A-Za-z0-9_-]|$)"
[ -n "${HARNESS_HOST:-}" ]          && hits "host name"    "(^|[^A-Za-z0-9_-])$HARNESS_HOST([^A-Za-z0-9_-]|$)"
[ -n "${HARNESS_LAN_IP:-}" ]        && hits "LAN IP"       "$(printf '%s' "$HARNESS_LAN_IP" | sed 's/\./\\./g')"
[ -n "${HARNESS_TAILNET_FQDN:-}" ]  && hits "tailnet name" "$(printf '%s' "${HARNESS_TAILNET_FQDN#*.}" | sed 's/\./\\./g')"
[ -n "${HARNESS_OWNER_NAME:-}" ]    && hits "owner name"   "$HARNESS_OWNER_NAME"
ts="$(tailscale ip -4 2>/dev/null | head -1)"
[ -n "$ts" ] && hits "tailnet IP" "$(printf '%s' "$ts" | sed 's/\./\\./g')"

[ "$bad" = 0 ] && echo "all no-person-hardcoded cases pass"
exit $bad
