#!/usr/bin/env bash
# sites: publish into a temp root and run the Pages check against a loopback caddy using the real Caddyfile (fixture only).
set -euo pipefail
T=$(mktemp -d); trap 'kill $CPID 2>/dev/null; rm -rf "$T"' EXIT
PORT=18072
mkdir -p "$T/repo/dist/assets" "$T/repo/dist/sub" "$T/root"
echo '<h1>home</h1>' > "$T/repo/dist/index.html"; echo '<h1>sub</h1>' > "$T/repo/dist/sub/index.html"
echo '<h1>site 404</h1>' > "$T/repo/dist/404.html"; head -c 4000 /dev/zero | tr '\0' 'a' | sed 's/^/var x="/;s/$/";/' > "$T/repo/dist/assets/app.js"
printf x > "$T/repo/dist/cues.json"; printf 'x' > "$T/repo/dist/assets/a.opus"; printf 'x' > "$T/repo/dist/assets/f.woff2"
sed -e "s|:8072|:$PORT|" -e "s|bind .*|bind 127.0.0.1|" -e "s|/srv/sites|$T/root|" ~/.config/sites/Caddyfile > "$T/Caddyfile"
caddy run --config "$T/Caddyfile" --adapter caddyfile >"$T/caddy.log" 2>&1 & CPID=$!
BIN=$(mktemp -p "$T" sites.XXX); sed "s|\[ailearning\]=\"\$HOME/projects/personal/ailearning\"|[ailearning]=\"$T/repo\"|; s|\[portfolio\]=\"\$HOME/projects/personal/portfolio\"|[portfolio]=\"$T/pf\"|" ~/agents/bin/sites > "$BIN"
export SITES_ROOT="$T/root" SITES_STATE="$T/state" SITES_URL="http://127.0.0.1:$PORT"
bash "$BIN" publish ailearning --no-build >/dev/null
echo '<h1>v2</h1>' > "$T/repo/dist/index.html"; bash "$BIN" publish ailearning --no-build >/dev/null
for _ in $(seq 50); do curl -s -o /dev/null "$SITES_URL/" && break; sleep 0.1; done
grep -q v2 <(curl -s "$SITES_URL/ailearning/") && echo "ok swap" || { echo "FAIL swap"; exit 1; }
[[ -z "$(ls -A "$T/state/stage")" ]] && echo "ok stage empty" || { echo "FAIL stage left"; exit 1; }
[[ "$(curl -s -o /dev/null -w '%{http_code}' "$SITES_URL/ailearning/sub")" == 301 ]] && echo "ok subdir 301" || { echo "FAIL subdir"; exit 1; }
echo '{"commit":"aaa1111","built":"2026-10-18 01:00:00"}' > "$T/repo/dist/build.json"
[[ "$(bash "$BIN" publish ailearning --no-build)" == verified\ ailearning* ]] && echo "ok publish verifies" || { echo "FAIL publish verify"; exit 1; }
echo '{"commit":"aaa1111","built":"2026-10-18 01:00:09"}' > "$T/repo/dist/build.json"
bash "$BIN" verify ailearning >/dev/null 2>&1 && { echo "FAIL stale build passed verify"; exit 1; } || echo "ok stale build fails verify"
bash "$BIN" publish ailearning --no-build >/dev/null && bash "$BIN" verify ailearning >/dev/null && echo "ok fresh build passes verify" || { echo "FAIL fresh verify"; exit 1; }
[[ "$(curl -sI "$SITES_URL/ailearning/cues.json" | tr -d "\r" | grep -i "^cache-control" | cut -d" " -f2-)" == "max-age=600" ]] && echo "ok other files max-age=600" || { echo "FAIL other cache-control"; exit 1; }
mkdir -p "$T/pf/dist/assets" && git -C "$T/pf" init -q && git -C "$T/pf" -c user.name=t -c user.email=t@t commit -q --allow-empty -m fixture
node --input-type=module -e "
const { stampPlugin } = await import('$HOME/projects/personal/portfolio/scripts/stamp.mjs');
const p = stampPlugin(); let f; p.configResolved({ root: '$T/pf' }); p.generateBundle.call({ emitFile: (a) => { f = a; } });
const j = JSON.parse(f.source); if (f.fileName !== 'build.json' || j.commit !== '$(git -C "$T/pf" rev-parse --short HEAD)' || !/^\\d{4}-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d$/.test(j.built)) process.exit(1);
process.stdout.write(f.source);" > "$T/pf/dist/build.json" && echo "ok portfolio plugin emits build.json" || { echo "FAIL portfolio plugin"; exit 1; }
echo '<h1>pf</h1>' > "$T/pf/dist/index.html"
[[ "$(bash "$BIN" publish portfolio --no-build)" == verified\ portfolio* ]] && echo "ok portfolio publish verifies" || { echo "FAIL portfolio publish verify"; exit 1; }
echo '{"commit":"stale00","built":"2026-01-01 00:00:00"}' > "$T/pf/dist/build.json"
bash "$BIN" verify portfolio >/dev/null 2>&1 && { echo "FAIL stale portfolio passed verify"; exit 1; } || echo "ok stale portfolio fails verify"
bash "$BIN" check
