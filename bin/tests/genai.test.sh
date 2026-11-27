#!/usr/bin/env bash
# genai against a fake agy on a temp PATH and a temp HOME: ask writes n PNGs + the md + one TSV line, two asks run one
# after the other, a 429 is exit 3 with the reset time, a missing agy is exit 5 with the owner's two steps; doctor codes.
# One agy call per image, a denied call with no image is retried once, quota text in a JSON answer or mid-run is exit 3.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

mkdir -p "$WORK/home" "$WORK/fakebin"
cat >"$WORK/fakebin/agy" <<'SH'
#!/usr/bin/env bash
# fake agy: --version; -p writes the asked number of PNGs into its cwd, or fails as FAKE_AGY says (429, auth).
[ "${1:-}" = --version ] && { echo 'agy 9.9.9-fake'; exit 0; }
echo "$*" >>"$FAKE_LOG/args"
case "${FAKE_AGY:-ok}" in
  429) echo 'Error 429 RESOURCE_EXHAUSTED: quota exceeded. Quota resets at 2026-11-28T08:00:00Z' >&2; exit 1 ;;
  auth) echo 'Not signed in: run agy to log in' >&2; exit 1 ;;
  quota-json) echo '{"response":"Error (HTTP 429): \"You have exhausted your capacity on this model. Your quota will reset after 3h44m45s.\"","model":"m"}'; exit 0 ;;
  quota-second) [ -f "$FAKE_LOG/made" ] && { echo '{"response":"(HTTP 429): \"You have exhausted your capacity on this model. Your quota will reset after 0h10m0s.\""}'; exit 0; } ;;
  deny-first) [ -f "$FAKE_LOG/denied" ] || { touch "$FAKE_LOG/denied"; echo '{"response":"","denied_actions":[{"action":"command","display_name":"RunWorkflow"}]}'; exit 0; } ;;
esac
if [ "${FAKE_AGY:-}" = multi-denied ] && ! printf '%s' "$*" | grep -qE 'exactly 1 '; then
  echo '{"response":"","denied_actions":[{"action":"command","display_name":"RunWorkflow"}]}'; exit 0
fi
touch "$FAKE_LOG/made"
echo "start $(date +%s%N)" >>"$FAKE_LOG/order"
sleep 0.4
n=$(printf '%s' "$*" | grep -oE 'exactly [0-9]+' | grep -oE '[0-9]+' || echo 1)
for i in $(seq 1 "$n"); do printf '\x89PNG\r\n\x1a\nfake%s' "$i" >"concept-$i.png"; done
echo "end $(date +%s%N)" >>"$FAKE_LOG/order"
echo '{"result":"done"}'
SH
chmod +x "$WORK/fakebin/agy"
export HOME="$WORK/home" PATH="$WORK/fakebin:$PATH" FAKE_LOG="$WORK" GENAI_AGY="$WORK/fakebin/agy" CHAT_SEAT=w1
unset DROP_DIR GENAI_LOG
DROP="$WORK/home/drop/T9001/concept"
TSV="$WORK/home/agents/log/genai.tsv"
[[ $(readlink -f ~) == "$WORK/home" ]] && ok 'sandbox: HOME is a temp dir' || { nok sandbox "$HOME"; exit 1; }

out=$("$BIN/genai" ask --ticket T9001 --need 'a lighthouse keeper robot, front view, for the T9001 title card' --n 3)
is 'ask: exit 0' $? 0
is 'ask: 3 PNGs written' "$(ls "$DROP"/*-[123].png 2>/dev/null | wc -l)" 3
is 'ask: each file is a PNG' "$(for f in "$DROP"/*.png; do head -c 4 "$f" | tail -c 3; echo; done | sort -u)" PNG
md=$(ls "$DROP"/*.md 2>/dev/null)
is 'ask: one md' "$(echo "$md" | grep -c .)" 1
is 'md: first line' "$(head -1 "$md")" 'CONCEPT, not an asset'
ev 'md: need, prompt, backend, model, date' 'grep -q "lighthouse keeper" "$md" && grep -q "^- Prompt sent:" "$md" && grep -q "^- Backend: agy" "$md" && grep -q "^- Model:" "$md" && grep -q "^- Date:" "$md"'
is 'ask: prints the 3 PNGs and the md' "$(echo "$out" | grep -c "^$DROP/")" 4
is 'tsv: one line' "$(wc -l <"$TSV")" 1
is 'tsv: ticket seat n backend exit' "$(cut -f2-6 "$TSV")" "$(printf 'T9001\tw1\t3\tagy\t0')"
ev 'tsv: seconds is a number' '[[ $(cut -f7 "$TSV") =~ ^[0-9]+(\.[0-9]+)?$ ]]'
ev 'agy: called headless with -p' 'grep -q -- "-p " "$WORK/args"'

rm -f "$WORK/order"
"$BIN/genai" ask --ticket T9001 --need 'two at once A' >/dev/null & A=$!
"$BIN/genai" ask --ticket T9001 --need 'two at once B' >/dev/null & B=$!
wait $A; ra=$?; wait $B; rb=$?
is 'lock: both asks exit 0' "$ra$rb" 00
is 'lock: one after the other' "$(cut -d' ' -f1 "$WORK/order" | tr '\n' ' ')" 'start end start end '
is 'lock: two md files more' "$(ls "$DROP"/*.md | wc -l)" 3

FAKE_AGY=429 "$BIN/genai" ask --ticket T9001 --need 'x' 2>"$WORK/err" >/dev/null
is '429: exit 3' $? 3
ev '429: prints the reset time' 'grep -q "2026-11-28T08:00:00Z" "$WORK/err"'
is '429: tsv line with exit 3' "$(tail -1 "$TSV" | cut -f6)" 3

GENAI_AGY="$WORK/none/agy" "$BIN/genai" ask --ticket T9001 --need 'x' 2>"$WORK/err" >/dev/null
is 'missing agy: exit 5' $? 5
ev 'missing agy: install step' 'grep -qF "curl -fsSL https://antigravity.google/cli/install.sh | bash" "$WORK/err"'
ev 'missing agy: sign-in step' 'grep -q "run agy and sign in" "$WORK/err"'

FAKE_AGY=auth "$BIN/genai" ask --ticket T9001 --need 'x' 2>"$WORK/err" >/dev/null
is 'not signed in: exit 5' $? 5
ev 'not signed in: sign-in step' 'grep -q "run agy and sign in" "$WORK/err"'

"$BIN/genai" ask --need 'no ticket' 2>/dev/null; is 'usage: no ticket is exit 2' $? 2
"$BIN/genai" ask --ticket T9001 --need x --n 5 2>/dev/null; is 'usage: --n 5 is exit 2' $? 2
"$BIN/genai" ask --ticket T9001 --need x --ref "$WORK/nope.png" 2>/dev/null; is 'usage: missing --ref is exit 2' $? 2

printf '\x89PNG\r\n\x1a\nref' >"$WORK/ref.png"
"$BIN/genai" ask --ticket T9001 --need 'with a ref' --ref "$WORK/ref.png" >/dev/null
is 'ref: exit 0' $? 0
ev 'ref: the ref path reaches agy' 'tail -1 "$WORK/args" | grep -q "$WORK/ref.png"'

FAKE_AGY=quota-json "$BIN/genai" ask --ticket T9001 --need 'x' 2>"$WORK/err" >/dev/null
is 'quota in a JSON answer on exit 0: exit 3' $? 3
ev 'quota in a JSON answer: prints the reset after time' 'grep -q "resets after 3h44m45s" "$WORK/err"'
ev 'quota in a JSON answer: prints the clock time' "grep -q \"at $(date -d '+3 hours 44 minutes 45 seconds' +%Y-%m-%d)\" \"\$WORK/err\""

: >"$WORK/args"
out=$(FAKE_AGY=multi-denied "$BIN/genai" ask --ticket T9002 --need 'two robots' --n 2); rc=$?
is 'n=2: exit 0 though agy denies a multi-image ask' $rc 0
is 'n=2: two PNGs' "$(ls "$WORK/home/drop/T9002/concept/"*.png 2>/dev/null | wc -l)" 2
is 'n=2: two agy calls, one image each' "$(grep -c 'exactly 1 ' "$WORK/args")" 2

rm -f "$WORK/denied"; : >"$WORK/args"
FAKE_AGY=deny-first "$BIN/genai" ask --ticket T9003 --need 'x' >/dev/null
is 'denied_actions with no image: retried, exit 0' $? 0
is 'denied_actions with no image: two calls' "$(wc -l <"$WORK/args")" 2

rm -f "$WORK/made"
out=$(FAKE_AGY=quota-second "$BIN/genai" ask --ticket T9004 --need 'x' --n 3 2>"$WORK/err"); rc=$?
is 'quota mid-run: exit 3' $rc 3
is 'quota mid-run: keeps the one made' "$(ls "$WORK/home/drop/T9004/concept/"*.png 2>/dev/null | wc -l)" 1
is 'quota mid-run: prints the PNG and the md' "$(echo "$out" | grep -c "^$WORK/home/drop/T9004/concept/")" 2
ev 'quota mid-run: md lists what was made' 'grep -q "^- Made: 1 of 3" "$WORK/home/drop/T9004/concept/"*.md'

out=$("$BIN/genai" doctor)
ev 'doctor: last ask on quota prints the reset time from the log' 'echo "$out" | grep -q "^quota: .*resets at [0-9-]* [0-9:]*"'

out=$("$BIN/genai" doctor); rc=$?
is 'doctor: exit 0 when an ask can run' $rc 0
ev 'doctor: installed line has path and version' 'echo "$out" | grep -q "installed.*$WORK/fakebin/agy.*9.9.9-fake"'
ev 'doctor: last ask line' 'echo "$out" | grep -q "^last ask"'
GENAI_AGY="$WORK/none/agy" "$BIN/genai" doctor >/dev/null 2>&1; is 'doctor: missing agy is exit 5' $? 5
FAKE_AGY=auth "$BIN/genai" doctor >/dev/null 2>&1; is 'doctor: not signed in is exit 5' $? 5
FAKE_AGY=429 "$BIN/genai" doctor >/dev/null 2>&1; is 'doctor: quota out is exit 3' $? 3
exit $bad
