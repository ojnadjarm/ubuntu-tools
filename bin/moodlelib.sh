#!/usr/bin/env bash
# moodlelib.sh — Moodle env discovery shared by moodle-envs, moodle-keep, moodle-login-check and pc-status.
# Source it, never execute it.
#
# API — one line per function:
#   moodle_envs_root         the envs root: $MOODLE_ENVS_DIR, else ~/moodle-envs
#   moodle_src <envdir>      absolute code dir mounted at /var/www/html by <envdir>/docker-compose.yml; 1 when none
#   moodle_project <envdir>  compose project name: the file's `name:`, else the dir name
#   moodle_wwwroot <config>  first static http(s) $CFG->wwwroot in <config>; skips 'http://' . $_SERVER lines

moodle_envs_root() { echo "${MOODLE_ENVS_DIR:-$HOME/moodle-envs}"; }

moodle_src() {
  local d="${1%/}" src
  src="$(sed -n 's#^[[:space:]]*-[[:space:]]*"\{0,1\}\([^:"]*\):/var/www/html"\{0,1\}[[:space:]]*$#\1#p' "$d/docker-compose.yml" 2>/dev/null | head -1)"
  [ -n "$src" ] || return 1
  case "$src" in /*) echo "$src" ;; *) echo "$d/${src#./}" ;; esac
}

moodle_project() {
  local p
  p="$(sed -n 's/^name:[[:space:]]*//p' "${1%/}/docker-compose.yml" 2>/dev/null | head -1)"
  echo "${p:-$(basename "$1")}"
}

moodle_wwwroot() {
  sed -n "s|.*\$CFG->wwwroot[[:space:]]*=[[:space:]]*'\(https\{0,1\}://[^']\{1,\}\)'.*|\1|p" "$1" 2>/dev/null | head -1
}
