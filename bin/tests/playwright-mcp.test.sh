#!/usr/bin/env bash
# bin/playwright-mcp: idle-timeout guard (TSP-026) and the busy-profile copy fallback (T1068).
# Fake $HOME + stub nvm/playwright-mcp; one real headless Chrome pair on a mktemp profile measures the collision.
set -uo pipefail
W="${PW_WRAPPER:-$HOME/agents/bin/playwright-mcp}"
CHROME="${PW_TEST_CHROME:-/opt/google/chrome/chrome}"
WORK=$(mktemp -d); pids=()
trap 'for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; rm -rf "$WORK" 2>/dev/null || { sleep 1; rm -rf "$WORK"; }' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"
export XDG_RUNTIME_DIR="$WORK/run"; mkdir -m 700 "$XDG_RUNTIME_DIR"

bin="$WORK/.nvm/versions/node/v24.20.0/bin"; mkdir -p "$bin"
printf 'nvm() { :; }\n' >"$WORK/.nvm/nvm.sh"
stub() {  # $1 = help text, $2 = body run on start
  printf '#!/bin/sh\nif [ "$1" = --help ]; then printf "%%s\\n" "%s"; exit 0; fi\necho "STARTED $*"\n%s\n' "$1" "${2:-}" >"$bin/playwright-mcp"
  chmod +x "$bin/playwright-mcp"
}

stub '  --headless  run headless'
out=$(HOME="$WORK" bash "$W" --config c.json 2>&1); rc=$?
[ "$rc" = 3 ] && ok 'old binary: exit 3' || nok 'old binary: exit 3' "rc=$rc"
grep -q 'no idle timeout' <<<"$out" && ok 'old binary: one-line reason' || nok 'old binary: one-line reason' "$out"
grep -q STARTED <<<"$out" && nok 'old binary: not started' "$out" || ok 'old binary: not started'

idle='  --idle-timeout <timeout>  close the browser after this many milliseconds'
stub "$idle"
prof="$WORK/agents/browser/profile-default"; mkdir -p "$prof/Default"
out=$(HOME="$WORK" bash "$W" --config c.json 2>&1); rc=$?
[ "$rc" = 0 ] && ok 'new binary: exit 0' || nok 'new binary: exit 0' "rc=$rc $out"
grep -q "STARTED --headless --user-data-dir $prof --config c.json" <<<"$out" \
  && ok 'new binary: started with the usual args' || nok 'new binary: started with the usual args' "$out"

# Stale lock (dead pid on this host) and a lock from another host: the profile itself is used.
sleep 0 & dead=$!; wait $dead
ln -s "$(uname -n)-$dead" "$prof/SingletonLock"
out=$(HOME="$WORK" bash "$W" 2>&1)
grep -q "user-data-dir $prof\$" <<<"$out" && ok 'stale lock: own profile' || nok 'stale lock: own profile' "$out"
rm "$prof/SingletonLock"; ln -s "other-host-$$" "$prof/SingletonLock"
out=$(HOME="$WORK" bash "$W" 2>&1)
grep -q "user-data-dir $prof\$" <<<"$out" && ok 'foreign-host lock: own profile' || nok 'foreign-host lock: own profile' "$out"
rm "$prof/SingletonLock"

# Cache cap (T1077): Cache + Code Cache > 300 MB and no live lock -> both deleted, logins kept.
fill() { mkdir -p "$prof/Default/Cache" "$prof/Default/Code Cache"
  truncate -s "$1M" "$prof/Default/Cache/pad"; truncate -s "$2M" "$prof/Default/Code Cache/pad"; }
for f in "Local State" Default/Cookies "Default/Login Data"; do echo keep >"$prof/$f"; done
fill 150 140; HOME="$WORK" bash "$W" >/dev/null 2>&1
[ -e "$prof/Default/Cache/pad" ] && [ -e "$prof/Default/Code Cache/pad" ] && ok 'cache 290 MB: kept' || nok 'cache 290 MB: kept' 'deleted'
sleep 30 & holder=$!; ln -s "$(uname -n)-$holder" "$prof/SingletonLock"
fill 200 200; HOME="$WORK" bash "$W" >/dev/null 2>&1
[ -e "$prof/Default/Cache/pad" ] && ok 'cache 400 MB, live lock: kept' || nok 'cache 400 MB, live lock: kept' 'deleted'
kill $holder; wait $holder 2>/dev/null; rm "$prof/SingletonLock"
out=$(HOME="$WORK" bash "$W" 2>&1)
[ ! -e "$prof/Default/Cache" ] && [ ! -e "$prof/Default/Code Cache" ] && ok 'cache 400 MB, no lock: both deleted' || nok 'cache 400 MB, no lock: both deleted' "$(ls "$prof/Default")"
grep -q "user-data-dir $prof\$" <<<"$out" && ok 'cache trim: own profile launched' || nok 'cache trim: own profile launched' "$out"
n=0; for f in "Local State" Default/Cookies "Default/Login Data"; do [ "$(cat "$prof/$f")" = keep ] && n=$((n+1)); done
[ "$n" = 3 ] && ok 'cache trim: Cookies, Local State, Login Data untouched' || nok 'cache trim: login files' "$n/3"
rm -f "$prof/Local State" "$prof/Default/Cookies" "$prof/Default/Login Data"

# Another playwright-mcp already started on the profile (browser not launched yet): copy.
stub "$idle" 'case "$*" in *--hold*) trap "kill \$!; exit" TERM; sleep 30 & wait;; esac'
"$bin/playwright-mcp" --user-data-dir "$prof" --hold >/dev/null & pids+=($!); sleep 0.2
out=$(HOME="$WORK" bash "$W" 2>&1)
grep -q "busy (playwright-mcp pid ${pids[0]})" <<<"$out" && ok 'live mcp on profile: copy' || nok 'live mcp on profile: copy' "$out"
kill "${pids[0]}"; wait "${pids[0]}" 2>/dev/null; pids=()

[ -x "$CHROME" ] || { nok 'real chrome' "no $CHROME"; exit $bad; }
cat >"$WORK/srv.py" <<'PY'
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        s.send_response(200); s.send_header('Content-Type', 'text/html')
        if s.path == '/set': s.send_header('Set-Cookie', 'sid=fixture42; Max-Age=86400; Path=/')
        s.end_headers(); s.wfile.write(('<p>cookie=%s</p>' % s.headers.get('Cookie', 'none')).encode())
    def log_message(s, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', 0), H); print(srv.server_port, flush=True); srv.serve_forever()
PY
python3 -I "$WORK/srv.py" >"$WORK/port" & pids+=($!)
for _ in $(seq 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
url="http://127.0.0.1:$(cat "$WORK/port")"
F=(--headless --mute-audio --password-store=basic --use-mock-keychain --no-first-run --disable-gpu)
nice -n 19 "$CHROME" "${F[@]}" --user-data-dir="$prof" --dump-dom "$url/set" >/dev/null 2>&1

# A real Chrome login survives the cache trim.
fill 200 200
stub "$idle" "d=\${3:-}; nice -n 19 timeout 20 \"$CHROME\" ${F[*]} --user-data-dir=\"\$d\" --dump-dom \"$url/echo\" 2>/dev/null"
out=$(HOME="$WORK" bash "$W" 2>&1)
grep -q 'cookie=sid=fixture42' <<<"$out" && [ ! -e "$prof/Default/Code Cache/pad" ] && ok 'real chrome: cache trimmed, login cookie kept' \
  || nok 'real chrome: cache trimmed, login cookie kept' "$out"
nice -n 19 "$CHROME" "${F[@]}" --user-data-dir="$prof" --remote-debugging-port=0 about:blank >/dev/null 2>&1 & pids+=($!)
for _ in $(seq 100); do [ -L "$prof/SingletonLock" ] && break; sleep 0.1; done
[ -L "$prof/SingletonLock" ] && ok 'chrome A holds SingletonLock' || nok 'chrome A holds SingletonLock' 'no lock'

nice -n 19 timeout 20 "$CHROME" "${F[@]}" --user-data-dir="$prof" --dump-dom "$url/echo" >"$WORK/b.out" 2>"$WORK/b.err"; rc=$?
echo "measured: second chrome on the same profile rc=$rc"
[ "$rc" != 0 ] && grep -q 'ProcessSingleton' "$WORK/b.err" && ok "second chrome on a held profile aborts (rc $rc)" \
  || nok 'second chrome on a held profile aborts' "rc=$rc $(tail -1 "$WORK/b.err")"

# Wrapper: lock is live -> copy under $XDG_RUNTIME_DIR; the copy keeps the cookie; removed on exit.
stub "$idle" "d=\${3:-}; nice -n 19 timeout 20 \"$CHROME\" ${F[*]} --user-data-dir=\"\$d\" --dump-dom \"$url/echo\" 2>/dev/null"
out=$(HOME="$WORK" bash "$W" --config c.json 2>&1); rc=$?
copy=$(grep -o "using copy [^ ]*" <<<"$out" | cut -d' ' -f3)
[ "$copy" = "$XDG_RUNTIME_DIR/pw-${copy##*-}" ] && ok 'held profile: one-line log, copy in XDG_RUNTIME_DIR' || nok 'held profile: copy' "$out"
grep -q "STARTED --headless --user-data-dir $copy --config c.json" <<<"$out" && ok 'held profile: launched on the copy' || nok 'held profile: launched on the copy' "$out"
grep -q 'cookie=sid=fixture42' <<<"$out" && [ "$rc" = 0 ] && ok 'copy: second session succeeds with the login cookie' || nok 'copy: login cookie' "rc=$rc $out"
[ -n "$copy" ] && [ ! -e "$copy" ] && ok 'copy: deleted on exit' || nok 'copy: deleted on exit' "$copy"
[ -L "$prof/SingletonLock" ] && ok 'held profile untouched' || nok 'held profile untouched' 'lock gone'

exit $bad
