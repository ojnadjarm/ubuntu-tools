#!/usr/bin/env bash
# PT16: pc explain (KB ranking, --json, --files, no-match exit 1) and pc help --md -> pc-cli.md.
# Runs against the live KB (small, read-only, no fixture needed — the same corpus every agent reads).
set -uo pipefail
BIN="$HOME/agents/bin"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
is()  { [ "$2" = "$3" ] && ok "$1" || nok "$1" "expected '$3', got '$2'"; }
in_top3() { # in_top3 <query> <needle-in-path>
  "$BIN/pc-explain" "$1" --files | head -3 | grep -q "$2"
}

# 1. speed budget.
T0=$EPOCHREALTIME
"$BIN/pc-explain" render.sock >/dev/null
T1=$EPOCHREALTIME
ms=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%d", (b-a)*1000}')
[ "$ms" -le 300 ] && ok "render.sock answers in <= 0.3 s ($ms ms)" || nok "render.sock answers in <= 0.3 s" "${ms}ms"

# 2. the agents' actual questions each resolve to a relevant file in the top 3.
in_top3 render.sock toolbox.md          && ok 'render.sock -> toolbox.md in top 3' || nok 'render.sock -> toolbox.md in top 3' "$( "$BIN/pc-explain" render.sock --files)"
in_top3 x-offset toolbox.md             && ok 'x-offset -> toolbox.md in top 3'    || nok 'x-offset -> toolbox.md in top 3'    "$( "$BIN/pc-explain" x-offset --files)"
in_top3 keyring README-pc-control.md    && ok 'keyring -> README-pc-control.md in top 3' || nok 'keyring -> README-pc-control.md in top 3' "$( "$BIN/pc-explain" keyring --files)"
in_top3 "tv off" 'RUNBOOK.md\|quirks.md\|toolbox.md' && ok '"tv off" -> the TV-off topic in top 3' || nok '"tv off" -> the TV-off topic in top 3' "$( "$BIN/pc-explain" "tv off" --files)"
in_top3 window-calls README-pc-control.md && ok 'window-calls -> README-pc-control.md in top 3' || nok 'window-calls -> README-pc-control.md in top 3' "$( "$BIN/pc-explain" window-calls --files)"
in_top3 "pc status cache" 'toolbox.md\|README-pc-control.md' && ok '"pc status cache" -> toolbox/README in top 3' || nok '"pc status cache" -> toolbox/README in top 3' "$( "$BIN/pc-explain" "pc status cache" --files)"
in_top3 8642 'RUNBOOK.md\|toolbox.md\|PLAN-LOWRES.md' && ok '8642 -> the bridge port docs in top 3' || nok '8642 -> the bridge port docs in top 3' "$( "$BIN/pc-explain" 8642 --files)"
in_top3 DARK_EYE_RENDER_SOCK toolbox.md  && ok 'DARK_EYE_RENDER_SOCK -> toolbox.md in top 3' || nok 'DARK_EYE_RENDER_SOCK -> toolbox.md in top 3' "$( "$BIN/pc-explain" DARK_EYE_RENDER_SOCK --files)"
in_top3 body-sandbox 'toolbox.md\|RUNBOOK.md\|quirks.md' && ok 'body-sandbox -> its own doc in top 3' || nok 'body-sandbox -> its own doc in top 3' "$( "$BIN/pc-explain" body-sandbox --files)"

# 3. --json shape.
J=$("$BIN/pc-explain" keyring --json)
is '--json is an array'         "$(jq -r 'type' <<<"$J")" array
is '--json has file/line/text'  "$(jq -r '.[0]|has("file") and has("line") and has("text")' <<<"$J")" true
is '--json top hit is README'   "$(jq -r '.[0].file|test("README-pc-control")' <<<"$J")" true

# 4. no match: exit 1, closest headings on stderr, nothing on stdout.
out=$("$BIN/pc-explain" zzz-nothing-matches-this-zzz 2>/tmp/pc-explain-test-err); rc=$?
is 'no match exits 1'        "$rc" 1
is 'no match prints nothing on stdout' "$out" ""
is 'no match lists <=3 headings'       "$([ "$(wc -l </tmp/pc-explain-test-err)" -le 4 ] && echo yes)" yes
rm -f /tmp/pc-explain-test-err

# 5. usage.
is '-h exits 0 and prints usage' "$("$BIN/pc-explain" -h >/dev/null; echo $?)" 0

# 6. pc help --md matches the generated KB/pc-cli.md exactly.
if diff -q <("$BIN/pc" help --md) "$HOME/agents/KB/pc-cli.md" >/dev/null; then
  ok 'pc help --md matches KB/pc-cli.md'
else
  nok 'pc help --md matches KB/pc-cli.md' 'diff — regenerate with pc help --md > ~/agents/KB/pc-cli.md'
fi

# 7. every pc-<sub> script has a row, one command per script (a11y-click's digit breaks the
# naive `[a-z-]+` grep, a known limitation of that check, not of the table).
missing=$(comm -23 <(ls "$BIN"/pc-* | sed 's#.*/pc-##' | sort) <(grep -oE '`pc [a-z0-9-]+`' "$HOME/agents/KB/pc-cli.md" | sed -e 's/`pc //' -e 's/`//' | sort -u))
is 'every pc-<sub> script has a pc-cli.md row' "$missing" ""

exit $bad
