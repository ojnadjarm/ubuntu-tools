#!/usr/bin/env bash
# T2017: no tracked file of the repo names a protected project, in its content or its path.
# Usage: no-protected-name.test.sh [repo-dir]   (default: the repo this script lives in)
# Names are the words of PROTECTED_PROJECTS in the config file, read at run time, never written here.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${1:-$(git -C "$HERE" rev-parse --show-toplevel)}"
CONF="${HARNESS_CONFIG:-$HOME/.config/pc-harness/config.env}"
. "$HERE/lib/assert.sh"

# names <file>: the words of PROTECTED_PROJECTS in that file only.
names() {
  [ -r "$1" ] || return 0
  env -i HOME="$HOME" PATH="$PATH" bash -c 'set -f; . "$1" >/dev/null 2>&1; for n in ${PROTECTED_PROJECTS:-}; do echo "$n"; done' _ "$1"
}

# scan <repo> <name>...: tracked files whose content (binary too) or path holds a name, any case.
scan() {
  local r=$1 n; shift
  for n in "$@"; do git -C "$r" grep -il -F -e "$n"; git -C "$r" ls-files | grep -i -F -e "$n"; done | sort -u
}

mapfile -t N < <(names "$CONF")
[ "${#N[@]}" -gt 0 ] || { echo "SKIP no-protected-name: PROTECTED_PROJECTS is not set in $CONF"; exit 0; }
[ -z "${NPN_SELFTEST:-}" ] || { echo "FAIL selftest: names read from an empty config"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf 'PROTECTED_PROJECTS="acme"\n' > "$T/one.env"; : > "$T/empty.env"
fx="$T/fx"; git init -q "$fx"
g() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$fx" -c user.name=t -c user.email=t "$@"; }
is 'selftest: the fixture config names acme' "$(names "$T/one.env")" acme
is 'selftest: a caller PROTECTED_PROJECTS is not read' "$(PROTECTED_PROJECTS=acme names "$T/empty.env")" ''
echo clean > "$fx/a.txt"; g add a.txt; g commit -qm init
is 'selftest: a clean commit passes' "$(scan "$fx" acme)" ''
echo acme > "$fx/notes-acme.txt"
is 'selftest: an untracked file is not scanned' "$(scan "$fx" acme)" ''
echo 'see ACME-services' > "$fx/b.txt"; g add b.txt
is 'selftest: a tracked line is caught' "$(scan "$fx" acme)" b.txt
echo clean > "$fx/x-acme-y.md"; g add x-acme-y.md
is 'selftest: a tracked file name is caught' "$(scan "$fx" acme)" $'b.txt\nx-acme-y.md'
out="$(NPN_SELFTEST=1 HARNESS_CONFIG="$T/empty.env" bash "${BASH_SOURCE[0]}" "$fx")"; rc=$?
is 'selftest: an empty config skips with rc 0' "$rc:$out" "0:SKIP no-protected-name: PROTECTED_PROJECTS is not set in $T/empty.env"

hits="$(scan "$REPO" "${N[@]}")"
if [ -z "$hits" ]; then ok "no protected name in $(basename "$REPO")"
else nok "no protected name in $(basename "$REPO")" "$(printf '%s\n' "$hits" | wc -l) files"; printf '%s\n' "$hits"; fi
exit $bad
