#!/usr/bin/env bash
# concept-img against a mock OpenRouter on localhost: writes the PNG and logs cost/total, refuses at --cap without a POST,
# never logs the key; T1632: refuses without a grant or key (exit 4), logs the quote, default job and month caps, one 80 % notify.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
WORK=$(mktemp -d)
. "$HOME/agents/bin/tests/lib/assert.sh"

cat >"$WORK/mock.py" <<'PY'
import base64, http.server, json, sys
work = sys.argv[1]
state = {"usage": 1.0}
png = base64.b64encode(b"\x89PNG\r\n\x1a\nmock").decode()
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, obj):
        b = json.dumps(obj).encode(); self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        self.reply({"data": {"usage": state["usage"]}})
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        open(f"{work}/posts", "a").write(json.dumps(body) + "\n")
        state["usage"] += 0.12
        self.reply({"data": [{"b64_json": png}], "usage": {"cost": 0.12}})
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(f"{work}/port", "w").write(str(s.server_port))
s.serve_forever()
PY
python3 -I "$WORK/mock.py" "$WORK" & MOCK=$!
trap 'kill $MOCK; rm -rf "$WORK"' EXIT
wait-for --label concept-img-mock --every 0.2 --job $MOCK --until "test -s '$WORK/port'" >/dev/null
export NO_PROXY=127.0.0.1 no_proxy=127.0.0.1 CONCEPT_IMG_API="http://127.0.0.1:$(cat "$WORK/port")" OPENROUTER_KEY_FILE="$WORK/key"
export HARNESS_CONFIG=/dev/null CONCEPT_IMG_LEDGER="$WORK/ledger.tsv" CONCEPT_IMG_NOTIFY="$WORK/notify"
unset CONCEPT_IMG_JOB_CAP CONCEPT_IMG_MONTH_CAP
printf '#!/bin/sh\necho "$1" >>"%s/notified"\n' "$WORK" >"$WORK/notify"; chmod +x "$WORK/notify"
ASK='hazme una imagen con IA de un mago'
posts() { wc -l <"$WORK/posts"; }
echo 'sk-mock-SECRET' >"$WORK/key"
[[ $CONCEPT_IMG_API =~ ^http://127.0.0.1:[0-9]+$ ]] && ok 'sandbox: API is the localhost mock' || { nok sandbox "$CONCEPT_IMG_API"; exit 1; }

"$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'a wizard' --out "$WORK/a.png" --log "$WORK/s.tsv" --start 0.9 --cap 0.5 --resolution 2K --aspect 3:4 >/dev/null
is 'call: exit 0' $? 0
is 'call: PNG written' "$(head -c 4 "$WORK/a.png" | tail -c 3)" PNG
is 'call: request fields' "$(jq -c '[.model,.prompt,.resolution,.aspect_ratio]' "$WORK/posts")" '["m/x","a wizard","2K","3:4"]'
is 'log: cost and running total' "$(tail -1 "$WORK/s.tsv" | cut -f2,6,8)" "$(printf 'm/x\t0.1200\t0.2200')"

"$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'again' --out "$WORK/b.png" --log "$WORK/s.tsv" --start 0.9 --cap 0.5 2>/dev/null
is 'cap: exit 3 when spent + reserve > cap' $? 3
is 'cap: no POST sent' "$(wc -l <"$WORK/posts")" 1
ev 'cap: no image written' '[ ! -e "$WORK/b.png" ]'
ev 'secret: key never in the log' '! grep -q SECRET "$WORK/s.tsv"'

printf 'h\ttotal\nx\t0.4000\n' >"$WORK/lag.tsv"
"$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'lag' --out "$WORK/d.png" --log "$WORK/lag.tsv" --start 5 --cap 0.6 2>/dev/null
is 'cap: a lagging key falls back to the logged total' $? 3

"$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'nocap' --out "$WORK/e.png" --log "$WORK/lag.tsv" --start 5 >/dev/null
is 'no --cap: the call runs' $? 0

"$BIN/concept-img" --model m/x --out "$WORK/c.png" --log "$WORK/s.tsv" --start 0 --cap 1 2>/dev/null
is 'usage: no prompt exits 2' $? 2

# T1632: the image model is opt-in
n=$(posts)
"$BIN/concept-img" --model m/x --prompt 'a portrait of him' --out "$WORK/g.png" --log "$WORK/g.tsv" 2>"$WORK/err"
is 'grant: no --asked exits 4' $? 4
is 'grant: one clear line' "$(cat "$WORK/err")" "concept-img: make it yourself by code; the image model needs the requester's own words asking for an AI image"
"$BIN/concept-img" --asked 'dibuja una representación de ti' --model m/x --prompt 'p' --out "$WORK/g.png" --log "$WORK/g.tsv" 2>/dev/null
is 'grant: a quote that asks for no AI image exits 4' $? 4
: >"$WORK/nokey"
OPENROUTER_KEY_FILE="$WORK/nokey" "$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'p' --out "$WORK/g.png" --log "$WORK/g.tsv" 2>/dev/null
is 'grant: an environment without a key exits 4' $? 4
is 'grant: refusals send no POST' "$(posts)" "$n"
ev 'grant: refusals write no image' '[ ! -e "$WORK/g.png" ]'

"$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'p' --out "$WORK/g.png" --log "$WORK/g.tsv" >/dev/null
is 'grant: with the quote, exit 0 without --start' $? 0
is 'grant: quote logged in the spend TSV' "$(tail -1 "$WORK/g.tsv" | cut -f8,9)" "$(printf '0.1200\t%s' "$ASK")"
is 'grant: cost and quote in the month ledger' "$(tail -1 "$WORK/ledger.tsv" | cut -f2,4)" "$(printf '0.1200\t%s' "$ASK")"

printf 'h\ttotal\nx\t1.8000\n' >"$WORK/job.tsv"; n=$(posts)
"$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'p' --out "$WORK/j.png" --log "$WORK/job.tsv" 2>/dev/null
is 'job cap: default $2 stops at 1.80 + 0.30 reserve' $? 3
is 'job cap: no POST sent' "$(posts)" "$n"
CONCEPT_IMG_JOB_CAP=5 "$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'p' --out "$WORK/j.png" --log "$WORK/job.tsv" >/dev/null
is 'job cap: CONCEPT_IMG_JOB_CAP raises it' $? 0

printf '%s\t9.8000\tx\tq\n' "$(date -d '-40 days' +%Y-%m-%dT%H:%M:%S)" >"$WORK/m.tsv"; n=$(posts)
CONCEPT_IMG_LEDGER="$WORK/m.tsv" "$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'p' --out "$WORK/m1.png" --log "$WORK/m1.tsv" >/dev/null
is 'month cap: an older month does not count' $? 0
printf '%s\t9.6000\tx\tq\n' "$(date +%Y-%m-%dT%H:%M:%S)" >>"$WORK/m.tsv"
CONCEPT_IMG_LEDGER="$WORK/m.tsv" "$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'p' --out "$WORK/m2.png" --log "$WORK/m2.tsv" 2>/dev/null
is 'month cap: default $10 across logs stops at 9.72 + 0.30' $? 3
is 'month cap: no POST sent' "$(posts)" "$((n + 1))"

printf '%s\t7.9000\tx\tq\n' "$(date +%Y-%m-%dT%H:%M:%S)" >"$WORK/n.tsv"; rm -f "$WORK/notified"
for i in 1 2; do CONCEPT_IMG_LEDGER="$WORK/n.tsv" "$BIN/concept-img" --asked "$ASK" --model m/x --prompt 'p' --out "$WORK/n$i.png" --log "$WORK/n$i.tsv" >/dev/null; done
is 'notify: one line when the month crosses 80 %' "$(cat "$WORK/notified" 2>/dev/null)" 'concept-img: $8.02 of the $10.00 monthly image cap spent (80 %)'
ev 'secret: key never in the ledger' '! grep -q SECRET "$WORK/ledger.tsv"'
exit $bad
