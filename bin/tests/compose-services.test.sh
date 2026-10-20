#!/usr/bin/env bash
# T517: compose-services lists the services `up -d` starts — a profile-only service is left out;
# the config_files label wins over the ~/moodle-envs `name:` match; an unknown project exits 1.
# Sandboxed (FLEET §5.6): a stub docker answers `ps` from a fixture and passes only `compose ... config`
# (pure file parsing, no daemon) to the real CLI; HOME is a fixture, so no real stack is read.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CS="$HERE/../compose-services"
REAL_DOCKER=$(command -v docker)
. "$HOME/agents/bin/tests/lib/assert.sh"
eq()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "want '$3', got '$2'"; }

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/home/moodle-envs/fx" "$W/elsewhere"
cat >"$W/home/moodle-envs/fx/docker-compose.yml" <<'Y'
name: fxenv
services:
  app:
    image: busybox
  db:
    image: busybox
  tool:
    image: busybox
    profiles: [tools]
Y
cat >"$W/elsewhere/docker-compose.yml" <<'Y'
name: fxlabel
services:
  web:
    image: busybox
Y
cat >"$W/bin/docker" <<S
#!/bin/sh
echo "\$*" >>"$W/calls"
case "\$1" in
  ps) case "\$*" in *project=fxlabel*) echo "$W/elsewhere/docker-compose.yml";; esac; exit 0;;
  compose) case "\$*" in *" config --services") exec "$REAL_DOCKER" "\$@";; esac;;
esac
echo "stub refused: \$*" >&2; exit 99
S
chmod +x "$W/bin/docker"
run() { env -u COMPOSE_PROFILES PATH="$W/bin:$PATH" HOME="$W/home" "$CS" "$@"; }

# --- 0. selftest: the stub refuses anything but ps and compose config -------
env PATH="$W/bin:$PATH" docker compose -p fxenv up -d >/dev/null 2>&1; rc=$?
eq "selftest: stub refuses compose up" "$rc" 99
rm -f "$W/calls"

# --- 1. a service behind an inactive profile is not expected ---------------
eq "name: match lists app+db, not the profile-only tool" "$(run fxenv | tr '\n' ' ')" "app db "
eq "an active profile adds it back" \
  "$(env COMPOSE_PROFILES=tools PATH="$W/bin:$PATH" HOME="$W/home" "$CS" fxenv | tr '\n' ' ')" "app db tool "

# --- 2. the container label wins over the ~/moodle-envs scan ----------------
eq "config_files label is read" "$(run fxlabel)" web

# --- 3. unknown project ------------------------------------------------------
out=$(run nosuch); rc=$?
eq "unknown project prints nothing" "$out" ""
eq "unknown project exits 1" "$rc" 1

# --- 4. only read-only verbs reached the stub --------------------------------
eq "only ps and compose config were called" "$(grep -cv '^ps \|config --services$' "$W/calls")" 0

exit $bad
