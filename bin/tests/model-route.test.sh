#!/usr/bin/env bash
# model-route (T1728): one case per table row, no class, the Fable downgrade, --owner-said, caps, usage. Pure CLI, no fixture.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
. "$HOME/agents/bin/tests/lib/assert.sh"
mr() { "$BIN/model-route" "$@" 2>&1; }
js() { "$BIN/model-route" --json "${@:2}" | jq -r "$1"; }

is 'row fix' "$(mr --class fix)" 'fix: opus high (itself)'
is 'row touchup' "$(mr --class touchup)" 'touchup: opus high (itself)'
is 'row build' "$(mr --class build)" 'build: opus high (itself)'
is 'row review' "$(mr --class review)" 'review: opus high (itself)'
is 'row plan' "$(mr --class plan)" 'plan: claude-fable-5-2 high (lead)'
is 'row art' "$(mr --class art)" 'art: claude-fable-5-2 medium (itself)'
is 'no class is build' "$(mr)" 'build: opus high (itself)'

is 'downgrade: Fable on fix gives opus high' "$(js '.model + " " + .effort + " " + (.downgraded|tostring)' --class fix --model claude-fable-5-2)" 'opus high true'
is 'downgrade: any fable id, touchup' "$(js .model --class touchup --model claude-fable-9 --effort medium)" opus
out=$(mr --class fix --model claude-fable-5-2)
is 'downgrade: plain output is 2 lines' "$(printf '%s\n' "$out" | wc -l)" 2
ev 'downgrade: the note names the ask and --owner-said' 'printf "%s" "$out" | sed -n 2p | grep -q "claude-fable-5-2 asked for fix, an Opus class: downgraded to opus high.*--owner-said"'
is 'downgrade: requested kept in json' "$(js .requested.model --class fix --model claude-fable-5-2)" claude-fable-5-2

is 'owner-said wins: model and effort' "$(js '.model + " " + .effort + " " + (.downgraded|tostring)' --class fix --model claude-fable-5-2 --effort medium --owner-said 'use fable')" 'claude-fable-5-2 medium false'
ev 'owner-said: the note carries the quote' 'js .note --class fix --model claude-fable-5-2 --owner-said "use fable" | grep -q "\"use fable\""'
is 'empty owner-said does not win' "$(js .model --class fix --model claude-fable-5-2 --owner-said '')" opus

is 'Fable on a Fable row keeps the asked effort' "$(js '.model + " " + .effort' --class plan --model claude-fable-5-2 --effort medium)" 'claude-fable-5-2 medium'
is 'asking Opus on a Fable row gives Opus' "$(mr --class plan --model opus)" 'plan: opus high (lead)'
is 'asking Opus on art: no note' "$(js '.model + " " + .note' --class art --model opus)" 'opus '
is 'Opus on art runs at high' "$(mr --class art --model opus)" 'art: opus high (itself)'
is 'Opus on art keeps an asked effort' "$(mr --class art --model opus --effort medium)" 'art: opus medium (itself)'
is 'owner-said Fable on fix runs at high' "$(js '.model + " " + .effort' --class fix --model claude-fable-5-2 --owner-said x)" 'claude-fable-5-2 high'

is 'effort cap: max becomes high' "$(js .effort --class art --effort max)" high
ev 'effort cap: with a note' 'js .note --class plan --model claude-fable-5-2 --effort xhigh | grep -q "effort xhigh capped at high"'

mr --class nonsense >/dev/null; is 'unknown class exits 2' "$?" 2
ev 'unknown class names the classes' '{ mr --class nonsense; true; } | grep -q "fix touchup build review plan art"'
mr --bogus >/dev/null; is 'bad option exits 2' "$?" 2
mr --class fix --effort turbo >/dev/null; is 'unknown effort exits 2' "$?" 2
mr --class >/dev/null; is 'option without a value exits 2' "$?" 2
mr --help | grep -q '^usage: model-route --class'; is '--help prints usage' "$?" 0

tab=$(mr --table)
for c in fix touchup build review plan art; do ev "--table names $c" 'printf "%s\n" "$tab" | grep -q "^$c "'; done
is '--table: head line' "$(printf '%s\n' "$tab" | head -1 | cut -c1-40)" 'Model routing (owner 2026-11-17, T1728):'
is '--table: 5 rules' "$(printf '%s\n' "$tab" | grep -c '^[1-5]\. ')" 5
is '--classes' "$(mr --classes | paste -sd' ')" 'fix touchup build review plan art'
exit $bad
