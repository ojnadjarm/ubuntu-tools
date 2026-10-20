#!/usr/bin/env bash
# cpp-report on a fixture ci dir (summary.json + perf.csv + a 64 px png) in mktemp: page sections, budgets vs previous run, n/a parts, rc 2 on bad input; T949: 0 ms budget, failed compare, no fps, last row from an earlier run; no build.
set -uo pipefail
G=$(cd "$(dirname "$0")/.." && pwd)
R=$G/scripts/cpp-report
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ $T == "${TMPDIR:-/tmp}"/* || $T == /tmp/* ]] && ok "selftest: sandbox in a temp dir" || bad "sandbox $T not a temp dir"

P=$T/proj; C=$P/ci
mkdir -p "$C"
python3 - "$C/golden-frame.png" <<'PY'
import struct, sys, zlib
w = h = 64
c = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
raw = b"".join(b"\0" + bytes(v for x in range(w) for v in (x * 4, y * 4, 128)) for y in range(h))
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + c(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + c(b"IDAT", zlib.compress(raw)) + c(b"IEND", b""))
PY
cat > "$C/summary.json" <<JSON
{"project":"$P","date":"2026-10-19T21:12:27+02:00","ccache_hit_pct":53.8,"load":"0.5 0.4 0.3","seconds":79,"ok":false,
 "stages":{"configure":{"status":"pass","seconds":1,"rc":0,"preset":"release","werror":true},
  "build":{"status":"pass","seconds":2,"rc":0,"warnings":0},
  "sanitize":{"status":"fail","seconds":11,"rc":1,"reports":3,"frames":60},
  "perf":{"status":"pass","seconds":2,"frames":600,"avg_fps":720.7,"load1":0.4,"gpu_ms_p50":1.30,"gpu_ms_p99":2.05,"cpu_ms_p50":0.46,"bound":"gpu",
   "vram_used_mb":115,"vram_budget_mb":2000,"vram_mb_limit":null,"draws":89,"culled":43,"post_ms_p50":0.35,
   "gpu_ms_p50_shadow":0.28,"gpu_ms_p50_scene":0.60,"gpu_ms_p50_post":0.35,"gpu_ms_p50_skin":0.06},
  "tidy":{"status":"fail","seconds":42,"rc":1,"findings":7},
  "golden":{"status":"pass","seconds":1,"frame":60,"flip_mean":0.0123,"flip_max_mean":0.02,"heatmap":null}}}
JSON
h=date,project,frames,avg_fps,load1,gpu_ms_p50,gpu_ms_p99,cpu_ms_p50,bound,status,vram_used_mb,vram_budget_mb,draws,culled,post_ms_p50,gpu_ms_p50_shadow,gpu_ms_p50_scene,gpu_ms_p50_skin
printf '%s\n' "$h" \
	'2026-10-18T10:00:00+02:00,proj,600,700,0.4,1.20,1.90,0.45,gpu,pass,110,2000,80,40,0.30,0.20,0.60,0.06' \
	'2026-10-18T11:00:00+02:00,proj,600,0,0.4,9.99,9.99,9.99,gpu,skip,,,,,,,,' \
	'2026-10-19T21:11:25+02:00,proj,600,720.7,0.4,1.30,2.05,0.46,gpu,pass,115,2000,89,43,0.35,0.28,0.60,0.06' > "$C/perf.csv"
printf '{"post":{"col":"post_ms_p50","ms":0.6},"shadow":{"col":"gpu_ms_p50_shadow","ms":0.10},"frame":{"col":"gpu_ms_p50","ms":1.65}}\n' > "$P/perf-budgets.json"

"$R" "$P" > "$T/out.txt" 2>&1; rc=$?
H=$C/cpp-report.html
[ $rc = 0 ] && [ -s "$H" ] && ok "project dir: rc 0, default OUT ci/cpp-report.html" || bad "project dir rc=$rc $(cat "$T/out.txt")"
has() { grep -qF -- "$1" "$H"; }

has '<meta name=viewport' && has 'grid-template-columns:repeat(auto-fit,minmax(min(100%' && ok "fluid layout: viewport + min(100%,..) grids" || bad "layout markers missing"
! grep -oE '(src|href)="[^"]*"' "$H" | grep -qv '"data:' && ok "self-contained: every src/href is a data: URI" || bad "external link in page"
has 'data:image/png;base64,iVBOR' && has 'mean FLIP 0.0123' && ok "golden frame embedded with FLIP score" || bad "golden frame/FLIP missing"
has '<td>sanitize</td><td><span class="b fail">fail</span></td><td>11 s</td>' && has '53.8 %' && ok "stage table: status, seconds; ccache hit %" || bad "stage table wrong"
has '<b class=bad>3</b>' && has '<b class=bad>7</b>' && ok "sanitizer 3 and tidy 7 counts shown red" || bad "check counts wrong"
sed 's#</tr>#</tr>\n#g' "$H" | grep '<tr><td>shadow</td>' | grep -qE '0\.2800.*280 %.*0\.2000.*\+0\.0800 \(\+40\.0 %\).*over' \
	&& ok "shadow vs budget (280 %, over) and vs previous pass row (+40 %)" || bad "shadow row: $(grep -oE '<tr><td>shadow</td>.{0,300}' "$H" | head -c 300)"
has 'previous: 2026-10-18T10:00:00+02:00' && ! has '9.99' && ok "previous = last earlier pass row (skip row ignored)" || bad "wrong previous row"
has '1.3000 / 2.0500 ms' && has '89 / 43' && has '115 MB of 2,000 MB device budget (5.8 %)' && has 'n/a (--vram-mb off)' \
	&& ok "p50/p99, draws/culled, VRAM vs budget" || bad "frame stats wrong"
has 'n/a (no contact sheet' && ok "no contact sheet: n/a (why)" || bad "sheet n/a missing"

cp "$C/golden-frame.png" "$C/contact-sheet.jpg"
"$R" "$C" --out "$T/o/page.html" >/dev/null 2>&1 && [ "$(grep -o 'data:image/[a-z]*;base64' "$T/o/page.html" | wc -l)" = 2 ] \
	&& ok "ci dir + --out FILE: contact sheet embedded" || bad "--out or sheet"

M=$T/min/ci; mkdir -p "$M"
echo '{"project":"/nowhere/min","stages":{"configure":{"status":"fail","seconds":1,"rc":1}}}' > "$M/summary.json"
"$R" "$M" > /dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q 'n/a (perf stage did not run)' "$M/cpp-report.html" && grep -q 'n/a (sanitize stage did not run)' "$M/cpp-report.html" \
	&& grep -q 'n/a (no golden-frame.png' "$M/cpp-report.html" && ok "configure-only run: page written, parts n/a (why)" || bad "minimal rc=$rc"

sed -i '2,3d' "$C/perf.csv"
"$R" "$C" --out "$T/first.html" >/dev/null 2>&1 && grep -q 'n/a (no earlier pass run)' "$T/first.html" && grep -q 'previous: none' "$T/first.html" \
	&& ok "first perf row: previous n/a, budgets still compared" || bad "first-run case"

CPP_REPORT_GAMEDEV_PERF=$T/none "$R" "$C" --out "$T/np.html" >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q 'n/a (gamedev-perf --compare gave no JSON)' "$T/np.html" && ok "gamedev-perf unusable: n/a, rc 0" || bad "no-gamedev-perf rc=$rc"

# T949: bad input shows why, never a crash or the wrong row
cp "$P/perf-budgets.json" "$T/budgets.keep"
printf '{"shadow":{"col":"gpu_ms_p50_shadow","ms":0}}\n' > "$P/perf-budgets.json"
"$R" "$C" --out "$T/b0.html" >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q 'compare failed rc 2: gamedev-perf: budget shadow.ms=0 must be &gt; 0' "$T/b0.html" && ok "budget ms 0: refused by gamedev-perf, shown with its reason, rc 0" || bad "budget 0 rc=$rc"
cp "$T/budgets.keep" "$P/perf-budgets.json"
printf '#!/bin/sh\necho "Traceback (most recent call last):" >&2\necho "AttributeError: list has no items" >&2\nexit 1\n' > "$T/gp-fail"; chmod +x "$T/gp-fail"
CPP_REPORT_GAMEDEV_PERF=$T/gp-fail "$R" "$C" --out "$T/cf.html" >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q 'compare failed rc 1: AttributeError: list has no items' "$T/cf.html" && ok "compare fails: rc and last stderr line shown" || bad "compare failed rc=$rc"
mkdir -p "$T/f/ci"; jq 'del(.stages.perf.avg_fps)' "$C/summary.json" > "$T/f/ci/summary.json"
"$R" "$T/f/ci" >/dev/null 2>&1 && grep -q 'fps n/a over 600 frames' "$T/f/ci/cpp-report.html" && ! grep -q 'None' "$T/f/ci/cpp-report.html" \
	&& ok "no avg_fps: fps n/a, no None" || bad "avg_fps missing: $(grep -o '.\{20\}over [0-9]* frames' "$T/f/ci/cpp-report.html")"
mkdir -p "$T/d/ci"; cp "$C/summary.json" "$T/d/ci/"
printf '%s\n' "$h" '2026-10-17T10:00:00+02:00,proj,600,700,0.4,1.20,1.90,0.45,gpu,pass,110,2000,80,40,0.30,0.20,0.60,0.06' \
	'2026-10-18T10:00:00+02:00,proj,600,700,0.4,1.20,1.90,0.45,gpu,pass,110,2000,80,40,0.30,0.25,0.60,0.06' > "$T/d/ci/perf.csv"
"$R" "$T/d/ci" >/dev/null 2>&1 && grep -q 'previous: 2026-10-18T10:00:00+02:00' "$T/d/ci/cpp-report.html" \
	&& ok "last perf.csv row from an earlier run: kept as previous" || bad "prev_row dropped a row this run did not write"

"$R" "$T/empty-dir-none" >/dev/null 2>&1; [ $? = 2 ] && ok "missing dir: rc 2" || bad "missing dir rc not 2"
mkdir -p "$T/badj/ci"; echo '{nope' > "$T/badj/ci/summary.json"
"$R" "$T/badj" >/dev/null 2>&1; [ $? = 2 ] && ok "unreadable summary.json: rc 2" || bad "bad json rc not 2"
"$R" "$C" --sheet "$T/nope.jpg" >/dev/null 2>&1; [ $? = 2 ] && ok "missing --sheet: rc 2" || bad "--sheet missing rc not 2"

echo "cpp-report: $fails failed"
[ "$fails" -eq 0 ]
