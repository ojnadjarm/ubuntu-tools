#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # ev evals its single-quoted checks
# T435: `install.sh --links` puts every bin/ command (not pc-*, *.sh, *.py) on ~/.local/bin, idempotently;
# the live bin/ has no unlinked command. Fixture HOME + a copied install.sh; the live check only reads.
set -uo pipefail
REAL="$HOME/agents"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FH="$W/home"; H="$FH/agents"
mkdir -p "$H/bin/sub" "$FH/.local/bin"
cp "$REAL/install.sh" "$H/"; cp "$REAL/bin/env.sh" "$H/bin/"
for n in foo bar pc-baz lib.sh mod.py; do printf '#!/bin/sh\n' >"$H/bin/$n"; chmod +x "$H/bin/$n"; done
printf 'x\n' >"$H/bin/notexec"

. "$HOME/agents/bin/tests/lib/assert.sh"

# unlinked BIN LOCAL — the bin/ commands LOCAL does not link to BIN, one per line.
unlinked() {
  local f n
  for f in "$1"/*; do
    [ -f "$f" ] && [ -x "$f" ] || continue
    n="${f##*/}"
    case "$n" in pc-*|*.sh|*.py) continue;; esac
    [ "$(readlink -f "$2/$n" 2>/dev/null)" = "$(readlink -f "$f")" ] || echo "$n"
  done
}
run() { env -i HOME="$FH" PATH="$FH/.local/bin:/usr/bin:/bin" HARNESS_CONFIG="$W/none.env" bash "$H/install.sh" --links; }

ln -s "$H/bin/bar" "$FH/.local/bin/bar"
ev "fixture: unlinked detects foo only" '[ "$(unlinked "$H/bin" "$FH/.local/bin")" = foo ]'
o1=$(run); r1=$?
ev "first run exits 0" '[ "$r1" = 0 ]'
ev "first run links 1 command" 'grep -qx "install.sh: 1 change(s) applied" <<<"$o1"'
ev "fixture: 0 unlinked after --links" '[ -z "$(unlinked "$H/bin" "$FH/.local/bin")" ]'
ev "pc-*, libs, non-exec and dirs not linked" '[ "$(ls "$FH/.local/bin" | sort | tr "\n" " ")" = "bar foo " ]'
ev "--links skips steps 1, 2, 4+" '! grep -qE "^(1|2|4)\. " <<<"$o1" && [ ! -e "$W/none.env" ]'
o2=$(run)
ev "second run: no changes" 'grep -qx "install.sh: no changes" <<<"$o2"'

live=$(unlinked "$REAL/bin" "$HOME/.local/bin")
ev "live: every command linked (missing: ${live//$'\n'/ })" '[ -z "$live" ]'

exit $bad
