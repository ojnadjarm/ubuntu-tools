#!/usr/bin/env bash
# T1515 bin/chat tests, one file per section: chat-<section>.test.sh (fixture lib/chat-fixture.sh). Thin runner.
# Run: bash chat.test.sh <section>... (e.g. ask hop drain) | all   (no args: usage only; the suite runs each file itself)
set -uo pipefail
D=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
. "$D/lib/assert.sh"

[ $# -gt 0 ] || { sed -n 3p "$0"; exit 0; }
[ "$1" = all ] && set -- $(for f in "$D"/chat-*.test.sh; do f=${f##*/chat-}; echo "${f%.test.sh}"; done)
for s in "$@"; do
  [ -f "$D/chat-$s.test.sh" ] || { nok "section $s" 'unknown section'; exit 2; }
done
for s in "$@"; do bash "$D/chat-$s.test.sh" || bad=1; done
exit $bad
