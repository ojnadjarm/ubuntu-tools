#!/usr/bin/env bash
# concept-img against a mock OpenRouter on localhost: writes the PNG and logs cost/total, refuses at an optional --cap without a POST, runs without one, never logs the key.
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
echo 'sk-mock-SECRET' >"$WORK/key"
[[ $CONCEPT_IMG_API =~ ^http://127.0.0.1:[0-9]+$ ]] && ok 'sandbox: API is the localhost mock' || { nok sandbox "$CONCEPT_IMG_API"; exit 1; }

"$BIN/concept-img" --model m/x --prompt 'a wizard' --out "$WORK/a.png" --log "$WORK/s.tsv" --start 0.9 --cap 0.5 --resolution 2K --aspect 3:4 >/dev/null
is 'call: exit 0' $? 0
is 'call: PNG written' "$(head -c 4 "$WORK/a.png" | tail -c 3)" PNG
is 'call: request fields' "$(jq -c '[.model,.prompt,.resolution,.aspect_ratio]' "$WORK/posts")" '["m/x","a wizard","2K","3:4"]'
is 'log: cost and running total' "$(tail -1 "$WORK/s.tsv" | cut -f2,6,8)" "$(printf 'm/x\t0.1200\t0.2200')"

"$BIN/concept-img" --model m/x --prompt 'again' --out "$WORK/b.png" --log "$WORK/s.tsv" --start 0.9 --cap 0.5 2>/dev/null
is 'cap: exit 3 when spent + reserve > cap' $? 3
is 'cap: no POST sent' "$(wc -l <"$WORK/posts")" 1
ev 'cap: no image written' '[ ! -e "$WORK/b.png" ]'
ev 'secret: key never in the log' '! grep -q SECRET "$WORK/s.tsv"'

printf 'h\ttotal\nx\t0.4000\n' >"$WORK/lag.tsv"
"$BIN/concept-img" --model m/x --prompt 'lag' --out "$WORK/d.png" --log "$WORK/lag.tsv" --start 5 --cap 0.6 2>/dev/null
is 'cap: a lagging key falls back to the logged total' $? 3

"$BIN/concept-img" --model m/x --prompt 'nocap' --out "$WORK/e.png" --log "$WORK/lag.tsv" --start 5 >/dev/null
is 'no --cap: the call runs' $? 0

"$BIN/concept-img" --model m/x --out "$WORK/c.png" --log "$WORK/s.tsv" --start 0 --cap 1 2>/dev/null
is 'usage: no prompt exits 2' $? 2
exit $bad
