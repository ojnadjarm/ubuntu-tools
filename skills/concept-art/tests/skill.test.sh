#!/usr/bin/env bash
# T2016: the concept-art skill has valid front matter, names both routes, and the commands it names are on PATH.
set -uo pipefail
F="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/SKILL.md"
. "$HOME/agents/bin/tests/lib/assert.sh"

eq "front matter opens" "---" "$(sed -n 1p "$F")"
ev "front matter has name concept-art" 'sed -n "2,/^---$/p" "$F" | grep -qx "name: concept-art"'
ev "front matter has a description" 'sed -n "2,/^---$/p" "$F" | grep -q "^description: ."'
ev "names route 1 concept-img" 'grep -q "concept-img --asked" "$F"'
ev "names route 2 genai ask" 'grep -q "genai ask --ticket" "$F"'
ev "under 60 lines" '[ "$(wc -l <"$F")" -lt 60 ]'
for c in concept-img genai secret drop-link; do
  ev "$c on PATH" 'command -v "$c" >/dev/null'
done

exit $bad
