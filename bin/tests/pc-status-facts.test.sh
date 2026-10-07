#!/usr/bin/env bash
# T257: `pc status --facts --apply` rewrites only its marked region of KB/machine.md; hand sections
# (the "System changes" table) survive, and a file without markers gains them and loses no hand section.
# Sandboxed (FLEET §5.6): writes only to $WORK via PC_FACTS_FILE; the selftest proves the real file is untouched.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCS="$HERE/../pc-status"
REAL="$HOME/agents/KB/machine.md"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }
B='<!-- pc-status-facts:begin -->'; E='<!-- pc-status-facts:end -->'

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
real_sum=$(sha256sum "$REAL" 2>/dev/null)
apply() { PC_FACTS_FILE="$1" "$PCS" --facts --apply >/dev/null; }
rows() { sed -n '/^## System changes/,$p' "$1" | grep -c '^| [^-F]'; }
hand() { sed -n "/^$E\$/,\$p" "$1"; }

TABLE='## System changes (hand)

| File or setting | Value | Why | Ticket | Class |
|---|---|---|---|---|
| `/etc/a` | 1 | x | T1 | P |
| `/etc/b` | 2 | y | T2 | P |
| `/etc/c` | 3 | z | T3 | H |'

# --- 0. selftest: the target is a fixture, never the real KB file ------------
f="$WORK/marked.md"
case "$f" in "$WORK"/*) [ "$f" != "$REAL" ] && ok "selftest: target under \$WORK" ;; *) nok selftest "$f";; esac

# --- 1. marked file: two runs keep the hand part byte-identical --------------
printf '%s\nold generated text\n%s\n\n%s\n' "$B" "$E" "$TABLE" >"$f"
before=$(hand "$f")
apply "$f"; apply "$f"
[ "$(hand "$f")" = "$before" ] && ok "two runs keep the hand part byte-identical" || nok "hand part kept" "$(diff <(echo "$before") <(hand "$f"))"
[ "$(rows "$f")" = 3 ] && ok "table rows 3/3 after two runs" || nok "table rows" "$(rows "$f")"
grep -q 'old generated text' "$f" && nok "region regenerated" "stale text still there" || ok "region regenerated"
[ "$(grep -cxF "$B" "$f")$(grep -cxF "$E" "$f")" = 11 ] && ok "exactly one marker pair" || nok "marker pair" "$(grep -cxF "$B" "$f")/$(grep -cxF "$E" "$f")"

# --- 2. text before the begin marker survives too ----------------------------
g="$WORK/pre.md"; printf 'hand preface\n%s\nx\n%s\ntail\n' "$B" "$E" >"$g"; apply "$g"
{ [ "$(head -1 "$g")" = 'hand preface' ] && [ "$(tail -1 "$g")" = tail ]; } && ok "text outside both markers kept" || nok "outside text" "$(cat "$g")"

# --- 3. no markers (old generated file + hand table): adds markers, loses nothing
h="$WORK/legacy.md"
{ "$PCS" --facts | sed "/^$B\$/d;/^$E\$/d"; printf '\n## Hand notes\nkeep me\n\n%s\n' "$TABLE"; } >"$h"
apply "$h"
[ "$(grep -cxF "$B" "$h")$(grep -cxF "$E" "$h")" = 11 ] && ok "fallback adds one marker pair" || nok "fallback markers" "missing"
grep -qx 'keep me' "$h" && [ "$(rows "$h")" = 3 ] && ok "fallback keeps hand sections (3/3 rows)" || nok "fallback loses nothing" "$(rows "$h") rows"
[ "$(grep -c '^## Identity' "$h")" = 1 ] && ok "fallback does not duplicate generated sections" || nok "dup sections" "$(grep -c '^## Identity' "$h")"
apply "$h"; [ "$(rows "$h")" = 3 ] && grep -qx 'keep me' "$h" && ok "fallback file stable on rerun" || nok "fallback rerun" "changed"

# --- 4. missing file is created with markers ---------------------------------
n="$WORK/new.md"; apply "$n"; [ "$(grep -cxF "$E" "$n")" = 1 ] && ok "missing file created" || nok "missing file" "no markers"

# --- 5. plain --facts still prints to stdout, writes nothing -----------------
out=$(PC_FACTS_FILE="$WORK/none.md" "$PCS" --facts | head -1)
{ [ "$out" = "$B" ] && [ ! -e "$WORK/none.md" ]; } && ok "--facts without --apply only prints" || nok "--facts stdout" "$out"

# --- 5b. T260: the hand lines moved out of the block survive; serve row and Moodle lines are generated
m="$WORK/moved.md"
MOVED='## Ports, names and URLs (hand)
- Tailscale name renamed from `old-host` on 2026-09-22.
| 8045 | Moodle 4.5 vass (docker) | tailscale0 only |
| 8070 | drop file server | tailscale0, 192.168.1.0/24 |
| 8072 | local sites | tailscale0 only |
- tailscale serve backends: 8070 drop; guide `https-drop-tailscale-serve`.
- Moodle 4.5 (vass): code is the owner checkout (no git writes).
- Status page :19998 routes: `/classic` the old dashboard.'
printf '%s\nold\n%s\n\n%s\n\n%s\n' "$B" "$E" "$MOVED" "$TABLE" >"$m"
apply "$m"; apply "$m"
n_kept=$(grep -cxF -f <(printf '%s\n' "$MOVED") "$m")
[ "$n_kept" = 8 ] && ok "moved hand lines 8/8 kept after two runs" || nok "moved hand lines" "$n_kept/8"
[ "$(rows "$m")" = 3 ] && ok "table rows 3/3 next to the moved lines" || nok "rows with moved lines" "$(rows "$m")"
blk=$(sed -n "/^$B\$/,/^$E\$/p" "$m")
if [ -n "$(tailscale serve status --json 2>/dev/null | jq -r '.Web // {} | keys[]' 2>/dev/null)" ]; then
  grep -qE '^\| [0-9, ]+ \| tailscale serve \(tailscaled\) https [0-9]+→[0-9]+' <<<"$blk" && ok "serve row generated live" || nok "serve row" "missing"
else ok "serve row skipped (no tailscale serve here)"; fi
grep -q 'renamed from\|/classic\|no git writes' <<<"$blk" && nok "block free of hand lines" "found one" || ok "block free of hand lines"
grep -q '^- Moodle .*: http.* · code `' <<<"$blk" && ok "Moodle lines generated" || ok "Moodle lines skipped (no env)"

# --- 5c. T271: only stacks with a /var/www/html mount (moodle-keep's rule) are Moodle envs
envs="$WORK/envs"; mkdir -p "$envs/9.9" "$envs/svc"
printf 'services:\n  app:\n    volumes:\n      - ./www:/var/www/html\n' >"$envs/9.9/docker-compose.yml"
printf 'services:\n  api:\n    volumes:\n      - ./data:/srv/data\n' >"$envs/svc/docker-compose.yml"
blk=$(MOODLE_ENVS_DIR="$envs" "$PCS" --facts)
grep -q '^- Moodle 9\.9: ' <<<"$blk" && ok "mounted stack listed as Moodle env" || nok "Moodle env listed" "9.9 missing"
grep -q '^- Moodle svc: ' <<<"$blk" && nok "non-Moodle stack skipped" "svc listed" || ok "non-Moodle stack skipped"
mkdir -p "$envs/9.8"; cp "$envs/9.9/docker-compose.yml" "$envs/9.8/"
line=$(MOODLE_ENVS_DIR="$envs" "$PCS" --facts | grep '^- Moodle envs: ')
[ "$line" = '- Moodle envs: `~/moodle-envs/9.8`, `~/moodle-envs/9.9`' ] && ok "Paths line lists only Moodle envs, ', ' separated" || nok "Paths Moodle envs line" "$line"

# --- 6. the real KB file was not touched -------------------------------------
[ "$(sha256sum "$REAL" 2>/dev/null)" = "$real_sum" ] && ok "real machine.md untouched" || nok "real machine.md untouched" "checksum changed"
exit $bad
