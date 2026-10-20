#!/usr/bin/env bash
# T472: `pc spotify` and spotify_api.py on stubs — fake playerctl/pactl/sleep on PATH, a fake $HOME, a patched urlopen
# inside bwrap --unshare-net; no live player, sink or Web API is touched (selftest proves the stubs resolve first).
set -uo pipefail
SELF=$(readlink -f "$0"); BIN=$(cd "$(dirname "$SELF")/.." && pwd)
if [ -z "${SP_SANDBOXED:-}" ] && bwrap --dev-bind / / --unshare-net true 2>/dev/null; then
  exec bwrap --dev-bind / / --unshare-net --setenv SP_SANDBOXED 1 -- bash "$SELF"
fi
PC="$BIN/pc-spotify" API="$BIN/spotify_api.py"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
STUB="$WORK/stub" FH="$WORK/home" LOG="$WORK/calls.log"
mkdir -p "$STUB" "$FH/agents/secrets"; : >"$LOG"
. "$HOME/agents/bin/tests/lib/assert.sh"
has() { grep -qF -- "$2" <<<"$3" && ok "$1" || nok "$1" "no '$2' in: $3"; }
sp()  { PATH="$STUB:$PATH" HOME="$FH" HARNESS_CONFIG=/dev/null SP_LOG="$LOG" "$PC" "$@"; }

cat >"$STUB/playerctl" <<'EOF'
#!/bin/bash
echo "playerctl $*" >>"$SP_LOG"
[ "$1" = -l ] && { [ -n "${SP_DOWN:-}" ] || echo spotify; exit 0; }
shift 2
case "$1 ${2:-}" in
  "status ") echo Playing;;
  "metadata xesam:artist") echo 'Fake Artist';;
  "metadata xesam:title") echo 'Fake Title';;
  "metadata xesam:album") echo 'Fake Album';;
  "metadata xesam:url") echo 'https://open.spotify.com/track/FAKE';;
  "metadata mpris:length") echo 210000000;;
  "position ") echo 75.3;;
  "volume ") echo 0.42;;
esac
exit 0
EOF
cat >"$STUB/pactl" <<'EOF'
#!/bin/bash
echo "pactl $*" >>"$SP_LOG"
case "$*" in
  'list sink-inputs') printf 'Sink Input #42\n\tSink: 5\n\tProperties:\n\t\tapplication.name = "Spotify"\n';;
  'list sinks short') printf '5\talsa_output.pci-0000.analog-stereo\tPipeWire\n7\tbluez_output.00_00_5E_00_53_01.1\tPipeWire\n';;
  get-default-sink) echo alsa_output.pci-0000.analog-stereo;;
esac
exit 0
EOF
printf '#!/bin/sh\nexit 0\n' >"$STUB/sleep"
chmod +x "$STUB"/*

# 0. selftest: the stubs win on PATH, the fake HOME has no Web API secrets, the sandbox has no route out.
for c in playerctl pactl sleep; do
  is "selftest: $c resolves to the stub" "$(PATH="$STUB:$PATH" command -v $c)" "$STUB/$c"
done
[ -e "$FH/agents/secrets/spotify.env" ] && nok 'selftest: fake HOME has no spotify.env' present || ok 'selftest: fake HOME has no spotify.env'
if [ -n "${SP_SANDBOXED:-}" ]; then
  python3 -c 'import socket; socket.create_connection(("1.1.1.1", 443), 2)' 2>/dev/null \
    && nok 'selftest: sandbox has no network' reachable || ok 'selftest: sandbox has no network'
fi

# 1. --help and argument errors.
out=$(sp --help); is '--help exits 0' "$?" 0; has '--help lists the verbs' 'status [--json]' "$out"
sp nosuchverb >/dev/null 2>&1; is 'an unknown verb exits 2' "$?" 2
sp vol 101 >/dev/null 2>&1; is 'vol 101 exits 2' "$?" 2
sp vol abc >/dev/null 2>&1; is 'vol abc exits 2' "$?" 2
sp seek xyz >/dev/null 2>&1; is 'seek xyz exits 2' "$?" 2
sp open https://example.com/x >/dev/null 2>&1; is 'open of a non-Spotify URL exits 2' "$?" 2
sp output nosuchsink >/dev/null 2>&1; is 'output to an unknown sink exits 2' "$?" 2
sp search >/dev/null 2>&1; is 'search with no query exits 2' "$?" 2

# 2. the app is not on the bus: every player verb refuses with 1.
out=$(SP_DOWN=1 sp play 2>&1); is 'play with no app exits 1' "$?" 1; has 'play says not running' 'not running' "$out"
SP_DOWN=1 sp status >/dev/null 2>&1; is 'status with no app exits 1' "$?" 1

# 3. happy path on the stubbed player.
out=$(sp status)
has 'status prints the state' 'state: Playing' "$out"
has 'status prints position / length as m:ss' 'position: 1:15 / 3:30' "$out"
has 'status prints volume as a percentage' 'volume: 42' "$out"
has 'status names the stream sink by alias' 'output: speakers (alsa_output.pci-0000.analog-stereo)' "$out"
j=$(sp status --json)
is 'status --json types and values' "$(jq -r '[.state,.artist,.position==75.3,.length==210,.volume,.output]|map(tostring)|join(",")' <<<"$j")" \
  'Playing,Fake Artist,true,true,42,speakers'
: >"$LOG"; is 'vol 55 prints the new volume' "$(sp vol 55)" 'volume: 55'
has 'vol 55 sets 0.55 on the player' 'playerctl -p spotify volume 0.55' "$(cat "$LOG")"
: >"$LOG"; sp toggle; has 'toggle sends play-pause' 'playerctl -p spotify play-pause' "$(cat "$LOG")"
: >"$LOG"; sp seek +10 >/dev/null; has 'seek +10 is relative' 'playerctl -p spotify position 10+' "$(cat "$LOG")"
: >"$LOG"; sp next; has 'next sends next' 'playerctl -p spotify next' "$(cat "$LOG")"
is 'output with no argument prints the current sink' "$(sp output)" 'output: speakers (alsa_output.pci-0000.analog-stereo)'
: >"$LOG"; sp output earbuds >/dev/null
has 'output earbuds moves stream 42 to the bluez sink' 'pactl move-sink-input 42 bluez_output.00_00_5E_00_53_01.1' "$(cat "$LOG")"

# 4. the Web API without credentials prints the setup steps and exits 2.
out=$(sp search 'x' 2>&1); is 'search with no credentials exits 2' "$?" 2
has 'search with no credentials explains the setup' 'developer.spotify.com/dashboard' "$out"

# 5. spotify_api.py with a patched urlopen (no socket is ever opened).
api() {  # api <http-status> <args...> — runs spotify_api.py under the fake HOME; requests go to $WORK/req.jsonl
  local code=$1; shift
  HOME="$FH" WORK="$WORK" CODE="$code" python3 - "$API" "$@" <<'PY'
import io, json, os, runpy, sys, urllib.error, urllib.request
work, code = os.environ["WORK"], int(os.environ["CODE"])
R = {"me/player/devices": {"devices": [{"id": "ph", "type": "Smartphone", "name": "Phone"},
                                       {"id": "pc", "type": "Computer", "name": "Laptop"}]},
     "search": {"tracks": {"items": [{"artists": [{"name": "A"}], "name": "T", "uri": "spotify:track:1"}]},
                "albums": {"items": []}, "playlists": {"items": [None, {"name": "P", "uri": "spotify:playlist:2"}]}},
     "me/playlists": {"items": [{"name": "Mine", "tracks": {"total": 3}, "uri": "spotify:playlist:9"}]},
     "api/token": {"access_token": "NEW", "expires_in": 3600}}
class Resp(io.BytesIO):
    def __enter__(self): return self
    def __exit__(self, *a): pass
def fake(req, timeout=None):
    url = req.full_url
    with open(os.path.join(work, "req.jsonl"), "a") as f:
        f.write(json.dumps({"method": req.get_method(), "url": url,
                            "body": (req.data or b"").decode()}) + "\n")
    if code != 200 and "api.spotify.com" in url:
        raise urllib.error.HTTPError(url, code, "x", {}, None)
    path = url.split("/v1/")[-1].split("?")[0] if "/v1/" in url else "api/token"
    return Resp(json.dumps(R.get(path, {})).encode() if path in R else b"")
urllib.request.urlopen = fake
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
PY
}
S="$FH/agents/secrets"
printf 'SPOTIFY_CLIENT_ID=cid\nSPOTIFY_CLIENT_SECRET="sec"\n' >"$S/spotify.env"
out=$(api 200 search q 2>&1); is 'api: no token exits 2' "$?" 2; has 'api: no token says run auth' 'pc spotify auth' "$out"
echo '{"access_token":"OLD","refresh_token":"R","expires_at":9999999999}' >"$S/spotify-token.json"
api 200 bogus >/dev/null 2>&1; is 'api: unknown command exits 2' "$?" 2
out=$(api 200 search q); is 'api search exits 0' "$?" 0
has 'api search prints the track' 'track: A — T  spotify:track:1' "$out"
has 'api search skips null playlists' 'playlist: P  spotify:playlist:2' "$out"
is 'api library prints playlists' "$(api 200 library)" 'playlist: Mine (3 tracks)  spotify:playlist:9'
: >"$WORK/req.jsonl"; out=$(api 200 play spotify:album:7)
is 'api play picks the Computer device' "$out" 'play: spotify:album:7 on Laptop'
is 'api play PUTs an album as context_uri' \
  "$(jq -sr '.[-1]|.method + " " + (.url|test("device_id=pc")|tostring) + " " + .body' "$WORK/req.jsonl")" \
  'PUT true {"context_uri": "spotify:album:7"}'
out=$(api 401 library 2>&1); is 'api: an HTTP error exits 1' "$?" 1; has 'api: an HTTP error names the code' 'Web API 401' "$out"
echo '{"access_token":"OLD","refresh_token":"R","expires_at":1}' >"$S/spotify-token.json"; chmod 600 "$S/spotify-token.json"
api 200 library >/dev/null
is 'api: an expired token is refreshed and kept 0600' \
  "$(jq -r '.access_token + " " + .refresh_token' "$S/spotify-token.json") $(stat -c %a "$S/spotify-token.json")" 'NEW R 600'

[ $bad -eq 0 ] && echo PASS || echo FAIL
exit $bad
