#!/usr/bin/env bash
# drop-link fixture suite: a temp drop folder served by a loopback http.server; the real ~/drop and :8470 are never touched.
set -uo pipefail
BIN=$(dirname "$(readlink -f "$0")")/..
T=$(mktemp -d); trap 'kill $srv 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/drop" "$T/src/site"
echo hi > "$T/src/a b.txt"; echo '<p>x</p>' > "$T/src/site/index.html"; echo '<p>y</p>' > "$T/src/page.html"
port=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
python3 -m http.server "$port" --bind 127.0.0.1 -d "$T/drop" >/dev/null 2>&1 & srv=$!
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$port/" && break; sleep 0.1; done
export DROP_DIR=$T/drop DROP_URL=http://127.0.0.1:$port
pass=0 fail=0
ok() { if eval "$2"; then echo "ok   $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }

[ "$(readlink -f "$T/drop")" != "$(readlink -f "$HOME/drop")" ] || { echo "selftest: fixture drop is the real ~/drop"; exit 1; }
out=$("$BIN/drop-link" "$T/src/a b.txt" t99); rc=$?
ok "file: exit 0 and URL-encoded link" '[ $rc = 0 ] && [ "$out" = "$DROP_URL/t99/a%20b.txt" ]'
ok "file: hard link, same inode" '[ "$(stat -c %i "$T/src/a b.txt")" = "$(stat -c %i "$T/drop/t99/a b.txt")" ]'
out=$("$BIN/drop-link" "$T/src/site" t99); rc=$?
ok "folder: trailing-slash link answers" '[ $rc = 0 ] && [ "$out" = "$DROP_URL/t99/site/" ]'
out=$("$BIN/drop-link" "$T/drop/t99/site/index.html"); rc=$?
ok "index.html already in drop: folder link, no copy" '[ $rc = 0 ] && [ "$out" = "$DROP_URL/t99/site/" ]'
err=$("$BIN/drop-link" "$T/src/page.html" t99 2>&1 >/dev/null)
ok "other .html: download warning" '[[ "$err" == *"served as a download"* ]]'
"$BIN/drop-link" "$T/src/a b.txt" "../x" >/dev/null 2>&1; rc=$?
ok "sub with .. is refused (exit 2)" '[ $rc = 2 ] && [ ! -e "$T/x" ]'
DROP_URL=http://127.0.0.1:9 "$BIN/drop-link" "$T/src/a b.txt" t99 >/dev/null 2>&1; rc=$?
ok "dead server: exit 1" '[ $rc = 1 ]'
echo "$pass passed, $fail failed"; [ $fail = 0 ]
