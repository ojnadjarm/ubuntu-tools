#!/usr/bin/env bash
# T257: `pc status --facts --apply` rewrites only its marked region of KB/machine.md; hand sections
# (the "System changes" table) survive, and a file without markers gains them and loses no hand section.
# Sandboxed (FLEET §5.6): writes only to $WORK via PC_FACTS_FILE; the selftest proves the real file is untouched.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCS="$HERE/../pc-status"
REAL="$HOME/agents/KB/machine.md"
. "$HOME/agents/bin/tests/lib/assert.sh"
B='<!-- pc-status-facts:begin -->'; E='<!-- pc-status-facts:end -->'

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
real_sum=$(sha256sum "$REAL" 2>/dev/null)
# Splice cases read one stubbed fixture machine (silent system tools, a private probe cache); only 5b's
# second run reads the live machine for the serve row and the Moodle lines.
mkdir -p "$WORK/sbin" "$WORK/run/pc-status"
for c in docker tailscale sensors systemctl loginctl tmux ip resolvectl journalctl curl ping sudo nmcli iwgetid \
  upower powerprofilesctl playerctl gdbus busctl claude smartctl; do printf '#!/bin/sh\nexit 0\n' >"$WORK/sbin/$c"; done
chmod +x "$WORK/sbin"/*
facts() { env PATH="$WORK/sbin:$PATH" XDG_RUNTIME_DIR="$WORK/run" "$PCS" --facts "$@"; }
apply() { PC_FACTS_FILE="$1" facts --apply >/dev/null; }
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
PC_FACTS_FILE="$WORK/none.md" facts >"$WORK/facts.out"
{ sed "/^$B\$/d;/^$E\$/d" "$WORK/facts.out"; printf '\n## Hand notes\nkeep me\n\n%s\n' "$TABLE"; } >"$h"
apply "$h"
[ "$(grep -cxF "$B" "$h")$(grep -cxF "$E" "$h")" = 11 ] && ok "fallback adds one marker pair" || nok "fallback markers" "missing"
grep -qx 'keep me' "$h" && [ "$(rows "$h")" = 3 ] && ok "fallback keeps hand sections (3/3 rows)" || nok "fallback loses nothing" "$(rows "$h") rows"
[ "$(grep -c '^## Identity' "$h")" = 1 ] && ok "fallback does not duplicate generated sections" || nok "dup sections" "$(grep -c '^## Identity' "$h")"
apply "$h"; [ "$(rows "$h")" = 3 ] && grep -qx 'keep me' "$h" && ok "fallback file stable on rerun" || nok "fallback rerun" "changed"

# --- 4. missing file is created with markers ---------------------------------
n="$WORK/new.md"; apply "$n"; [ "$(grep -cxF "$E" "$n")" = 1 ] && ok "missing file created" || nok "missing file" "no markers"

# --- 5. plain --facts still prints to stdout, writes nothing -----------------
out=$(head -1 "$WORK/facts.out")
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
apply "$m"; PC_FACTS_FILE="$m" "$PCS" --facts --apply >/dev/null
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
# T398: a stopped env shows the code dir its compose file mounts, not a guessed <env>/www.
envs="$WORK/envs"; mkdir -p "$envs/9.9" "$envs/9.8" "$envs/9.7" "$envs/svc"
printf 'services:\n  app:\n    volumes:\n      - ./www:/var/www/html\n' >"$envs/9.9/docker-compose.yml"
printf 'services:\n  api:\n    volumes:\n      - ./data:/srv/data\n' >"$envs/svc/docker-compose.yml"
cp "$envs/9.9/docker-compose.yml" "$envs/9.8/"
printf 'services:\n  app:\n    volumes:\n      - /srv/x/moodle:/var/www/html\n' >"$envs/9.7/docker-compose.yml"
blk=$(MOODLE_ENVS_DIR="$envs" facts)
grep -q '^- Moodle 9\.9: ' <<<"$blk" && ok "mounted stack listed as Moodle env" || nok "Moodle env listed" "9.9 missing"
grep -q '^- Moodle svc: ' <<<"$blk" && nok "non-Moodle stack skipped" "svc listed" || ok "non-Moodle stack skipped"
line=$(grep '^- Moodle envs: ' <<<"$blk")
[ "$line" = '- Moodle envs: `~/moodle-envs/9.7`, `~/moodle-envs/9.8`, `~/moodle-envs/9.9`' ] && ok "Paths line lists only Moodle envs, ', ' separated" || nok "Paths Moodle envs line" "$line"
line=$(grep '^- Moodle 9\.7: ' <<<"$blk")
case "$line" in *'code `/srv/x/moodle`'*) ok "a stopped env shows its mounted code dir";; *) nok "a stopped env shows its mounted code dir" "$line";; esac

# --- 5d. T463: pc_unit_loops lists a looping timer unit, not a recovered or never-failed one
fk="$WORK/fake"; mkdir -p "$fk"
cat >"$fk/systemctl" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *list-timers*) echo '[{"activates":"loop.service"}]';;
  *show*) cat "$FAKE_SHOW";;
esac
SH
cat >"$fk/journalctl" <<'SH'
#!/usr/bin/env bash
case "$*" in *"-o json"*) cat "$FAKE_FAILS";; *) echo 'Moodle upgrade pending';; esac
SH
chmod +x "$fk/systemctl" "$fk/journalctl"
T0=1792396000
for i in $(seq 0 11); do printf '{"USER_UNIT":"loop.service","__REALTIME_TIMESTAMP":"%s000000"}\n' $((T0 + i * 60)); done >"$WORK/fails.json"
: >"$WORK/nofails.json"
loops() { # <fails file> <Result> <exit epoch>
  printf 'Result=%s\nExecMainExitTimestamp=@%s\n' "$2" "$3" >"$WORK/show"
  PATH="$fk:$PATH" PC_FIXTURE= FAKE_FAILS="$1" FAKE_SHOW="$WORK/show" bash -c 'source "$1"; pc_unit_loops' _ "$HERE/../pclib.sh"
}
[ "$(PATH="$fk:$PATH" command -v journalctl)" = "$fk/journalctl" ] && ok "selftest: unit-loop probe reads fake journalctl/systemctl" || nok selftest "real journalctl on PATH"
tl=$((T0 + 11 * 60))
out=$(loops "$WORK/fails.json" exit-code "$tl"); rc=$?
[ $rc = 1 ] && [ "$out" = 'loop.service 12 fails/h: Moodle upgrade pending' ] && ok "looping unit listed as FAIL" || nok "looping unit" "rc=$rc $out"
out=$(loops "$WORK/fails.json" success $((tl + 60))); rc=$?
[ $rc = 0 ] && [ -z "$out" ] && ok "recovered unit (success after last fail) not listed" || nok "recovered unit" "rc=$rc $out"
out=$(loops "$WORK/fails.json" success $((tl - 60))); rc=$?
[ $rc = 1 ] && ok "success older than the last fail still listed" || nok "stale success" "rc=$rc $out"
out=$(loops "$WORK/nofails.json" success "$tl"); rc=$?
[ $rc = 0 ] && [ -z "$out" ] && ok "never-failed unit not listed" || nok "never-failed unit" "rc=$rc $out"

# --- 6. the real KB file was not touched -------------------------------------
[ "$(sha256sum "$REAL" 2>/dev/null)" = "$real_sum" ] && ok "real machine.md untouched" || nok "real machine.md untouched" "checksum changed"
exit $bad
