#!/usr/bin/env bash
# T1754-B P044/D481 bin/outbox-post: one Discord reply into a fixture PO's outbox (tmp + rename), refused when it holds a
# home path, host or tailnet name, secret or the owner's name. Fixture only: HARNESS_HOME and the identity are temp values,
# no liaison, no Discord.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$BIN/tests/lib/assert.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export HARNESS_HOME="$W/agents" HARNESS_CONFIG=/nonexistent HARNESS_OWNER_NAME='Ann Example Smithers' \
       HARNESS_OWNER_EMAIL=ann@example.org HARNESS_HOST=boxy HARNESS_TAILNET_FQDN=boxy.tail1234.ts.net
P="$HARNESS_HOME/po-fx"; O="$P/outbox/discord"
mkdir -p "$P/inbox"; : >"$P/BRIEF.md"
post() { "$BIN/outbox-post" "$@"; }

case "$HARNESS_HOME" in "$W"/*) ok 'selftest: HARNESS_HOME is the fixture';; *) nok 'selftest' "$HARNESS_HOME";; esac

f=$(post fx 123 'Listo: el mapa nuevo está en el hilo.'); is 'plain reply: exit 0' "$?" 0
case "$f" in "$O"/*T*Z-123.md) ok 'named <utc>-<thread>.md in outbox/discord';; *) nok 'name' "$f";; esac
is 'file: thread line, then the text' "$(cat "$f")" "$(printf 'thread: 123\nListo: el mapa nuevo está en el hilo.')"
is 'no tmp file left' "$(ls -A "$O" | grep -c '\.tmp$')" 0

touch "$W/shot.png"
f=$(cd "$W" && post fx 123 --image shot.png --image "$W/shot.png" 'two shots'); is 'images: exit 0' "$?" 0
is 'images: one absolute image line each, before the text' "$(cat "$f")" \
   "$(printf 'thread: 123\nimage: %s\nimage: %s\ntwo shots' "$W/shot.png" "$W/shot.png")"
ev 'a second reply to the thread: a second file, not an overwrite' '[ "$(ls "$O"/*-123*.md | wc -l)" = 2 ]'
f=$(printf 'from\nstdin\n' | post fx 7 -); is 'stdin text kept' "$(tail -n +2 "$f")" "$(printf 'from\nstdin')"

n0=$(ls -A "$O" | wc -l)
held() {   # held <name> <want line> <text>
  local o r; o=$(post fx 123 "$3" 2>&1); r=$?
  is "refused: $1" "$r $o" "3 $2"
}
held 'home path ~/' 'outbox-post: refused (home path): name the file without its folder; nothing was written' 'mira ~/drop/T1/x.png'
held 'home path /home' 'outbox-post: refused (home path): name the file without its folder; nothing was written' 'en /home/someone/x'
held 'host name' 'outbox-post: refused (host or tailnet name): say "the server" instead; nothing was written' 'corre en boxy'
held 'tailnet name' 'outbox-post: refused (host or tailnet name): say "the server" instead; nothing was written' 'https://x.tail1234.ts.net/a'
held 'owner full name (D481)' 'outbox-post: refused (owner name): write it without his name or e-mail; nothing was written' 'firmado: ann example smithers'
held 'owner family name (D481)' 'outbox-post: refused (owner name): write it without his name or e-mail; nothing was written' 'según SMITHERS'
held 'owner e-mail (D481)' 'outbox-post: refused (owner name): write it without his name or e-mail; nothing was written' 'escribe a ann@example.org'
held 'secret' 'outbox-post: refused (secret): drop the token or key; nothing was written' 'key ghp_abcdefghijklmnopqrstuvwxyz0123'
is 'refused: nothing written' "$(ls -A "$O" | wc -l)" "$n0"
post fx 123 'Ann lo revisa' >/dev/null; is 'a first name alone passes' "$?" 0

post fx abc 'x' >/dev/null 2>&1; is 'thread not a number: exit 2' "$?" 2
post fx 123 '' >/dev/null 2>&1; is 'empty text: exit 2' "$?" 2
post nope 123 'x' >/dev/null 2>&1; is 'unknown PO: exit 2' "$?" 2
exit $bad
