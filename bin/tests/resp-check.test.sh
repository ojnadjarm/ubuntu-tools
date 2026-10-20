#!/usr/bin/env bash
# resp-check fixture suite: local file:// pages in a temp dir (fluid, 1500 px fixed, left-aligned, noise), no network.
set -uo pipefail
BIN=$(dirname "$(readlink -f "$0")")/..
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok() { if eval "$2"; then echo "ok   $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
rows() { awk '$1 ~ /^[0-9]+$/ && $7 == "'"$2"'" {printf "%s ", $1}' <<<"$1"; }

case $T in "${TMPDIR:-/tmp}"/*) ;; *) echo "selftest: fixture dir $T is not a temp dir"; exit 1;; esac
head='<!doctype html><meta name=viewport content="width=device-width"><style>body{margin:0}'
echo "$head main{max-width:900px;margin:0 auto;padding:0 16px}</style><main><h1>Fluid</h1><p>Text that wraps.</p><div style=\"background:#eee;height:200px\"></div></main>" >"$T/fluid.html"
echo "$head main{width:1500px;margin:0 auto}</style><main><h1>Fixed</h1><p>Wide fixed page.</p></main>" >"$T/fixed.html"
echo "$head main{max-width:600px;padding:0 16px}</style><main><h1>Left</h1><p>Left-aligned column.</p></main>" >"$T/left.html"
echo "$head</style><canvas id=c style=\"width:100%;height:100vh;display:block\"></canvas><script>const c=document.getElementById('c');c.width=innerWidth;c.height=innerHeight;
const x=c.getContext('2d'),d=x.createImageData(c.width,c.height);for(let i=0;i<d.data.length;i++)d.data[i]=i%4==3?255:Math.random()*256;x.putImageData(d,0,0)</script>" >"$T/noise.html"

"$BIN/resp-check" --help >/dev/null; rc=$?
ok "--help exits 0" '[ $rc = 0 ]'
"$BIN/resp-check" >/dev/null 2>&1; rc=$?
ok "no url exits 2" '[ $rc = 2 ]'
"$BIN/resp-check" "$T/missing.html" >/dev/null 2>&1; rc=$?
ok "missing file exits 2" '[ $rc = 2 ]'
"$BIN/resp-check" "$T/fluid.html" --widths 400,abc >/dev/null 2>&1; rc=$?
ok "bad --widths exits 2" '[ $rc = 2 ]'

# The four browser runs go one after another: in parallel they cost ~25 % more CPU (T905).
"$BIN/resp-check" "$T/fluid.html" >"$T/fluid.out"; echo $? >"$T/fluid.rc"
"$BIN/resp-check" "$T/fixed.html" >"$T/fixed.out"; echo $? >"$T/fixed.rc"
"$BIN/resp-check" "$T/left.html" --widths 400,1920 >"$T/left.out"; echo $? >"$T/left.rc"
"$BIN/resp-check" "$T/noise.html" --sheet "$T/sheet.jpg" >"$T/noise.out"; echo $? >"$T/noise.rc"
res() { out=$(cat "$T/$1.out"); rc=$(cat "$T/$1.rc"); }

res fluid
ok "fluid page: rc 0, PASS at 400 768 1366 1920 2560" '[ $rc = 0 ] && [ "$(rows "$out" PASS)" = "400 768 1366 1920 2560 " ]'
ok "fluid page: symmetric 16/16 margins at 400" 'grep -qE "^400 +400 +400 +no +16 +16 +PASS" <<<"$out"'
res fixed
ok "1500 px page: rc 1, FAIL at 400 768 1366 only" '[ $rc = 1 ] && [ "$(rows "$out" FAIL)" = "400 768 1366 " ]'
ok "1500 px page: h-scroll named with scrollW 1500" 'grep -qE "^400 +400 +1500 +yes .*FAIL h-scroll" <<<"$out"'
res left
ok "left-aligned column: margins FAIL at 1920, PASS at 400" '[ $rc = 1 ] && [ "$(rows "$out" FAIL)" = "1920 " ] && grep -q "FAIL margins" <<<"$out"'

res noise
size=$(stat -c %s "$T/sheet.jpg" 2>/dev/null || echo 0)
ok "noise page --sheet: JPEG written, <= 200 KB ($size bytes)" '[ $rc = 0 ] && [ "$size" -gt 0 ] && [ "$size" -le 204800 ] && file "$T/sheet.jpg" | grep -q "JPEG image"'
ok "sheet line names the file and size" 'grep -qx "sheet $T/sheet.jpg $size bytes" <<<"$out"'
ok "browser runs headless with --mute-audio" 'grep -q "headless: true, args: \[.--mute-audio.\]" "$BIN/resp-check"'

echo "resp-check: $pass ok, $fail failed"
[ "$fail" = 0 ]
