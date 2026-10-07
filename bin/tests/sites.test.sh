#!/usr/bin/env bash
# sites: publish into a temp root and run the Pages check against a loopback caddy using the real Caddyfile (fixture only).
set -euo pipefail
T=$(mktemp -d); trap 'kill $CPID 2>/dev/null; rm -rf "$T"' EXIT
PORT=18072
mkdir -p "$T/repo/dist/assets" "$T/repo/dist/sub" "$T/root"
echo '<h1>home</h1>' > "$T/repo/dist/index.html"; echo '<h1>sub</h1>' > "$T/repo/dist/sub/index.html"
echo '<h1>site 404</h1>' > "$T/repo/dist/404.html"; head -c 4000 /dev/zero | tr '\0' 'a' | sed 's/^/var x="/;s/$/";/' > "$T/repo/dist/assets/app.js"
printf 'x' > "$T/repo/dist/assets/a.opus"; printf 'x' > "$T/repo/dist/assets/f.woff2"
sed -e "s|:8072|:$PORT|" -e "s|bind .*|bind 127.0.0.1|" -e "s|/srv/sites|$T/root|" ~/.config/sites/Caddyfile > "$T/Caddyfile"
caddy run --config "$T/Caddyfile" --adapter caddyfile >"$T/caddy.log" 2>&1 & CPID=$!
BIN=$(mktemp -p "$T" sites.XXX); sed "s|\[ailearning\]=\"\$HOME/projects/personal/ailearning\"|[ailearning]=\"$T/repo\"|; /\[portfolio\]=/d" ~/agents/bin/sites > "$BIN"
export SITES_ROOT="$T/root" SITES_STATE="$T/state" SITES_URL="http://127.0.0.1:$PORT"
bash "$BIN" publish ailearning --no-build >/dev/null
echo '<h1>v2</h1>' > "$T/repo/dist/index.html"; bash "$BIN" publish ailearning --no-build >/dev/null
for _ in $(seq 50); do curl -s -o /dev/null "$SITES_URL/" && break; sleep 0.1; done
grep -q v2 <(curl -s "$SITES_URL/ailearning/") && echo "ok swap" || { echo "FAIL swap"; exit 1; }
[[ -z "$(ls -A "$T/state/stage")" ]] && echo "ok stage empty" || { echo "FAIL stage left"; exit 1; }
[[ "$(curl -s -o /dev/null -w '%{http_code}' "$SITES_URL/ailearning/sub")" == 301 ]] && echo "ok subdir 301" || { echo "FAIL subdir"; exit 1; }
bash "$BIN" check
