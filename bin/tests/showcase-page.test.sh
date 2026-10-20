#!/usr/bin/env bash
# showcase-page picks the newest non-scratch film and the newest play.mp4 drop, links media in place and the cpp-report page, dates every number; --check verifies a built page.
# Fixture tree in a mktemp dir only: every root is passed as a flag, so no real ~/drop or project is read or written.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
t() { printf '%-76s' "showcase-page: $1"; }
ok() { echo OK; }
no() { echo "FAIL — $1"; fail=1; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
NOW=1760954400   # fixture "now"; files are touched relative to it
mk() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" >"$1"; touch -d "@$(( NOW - $3 ))" "$1"; }
film() {  # film <proj> <header> <draft> <age_s>
  mk "$SB/motion/$1/build.sh" $'#!/usr/bin/env bash\n# build.sh ('"$2"'): fixture' "$4"
  mk "$SB/motion/$1/out/build.json" "{\"name\":\"$1\",\"draft\":$3,\"seconds\":20,\"fps\":24,\"size\":\"1920x1080\",\"cpu_s\":1000.0,\"steps_cpu\":{\"plate0\":400.0,\"composite\":300.0,\"hdr10\":200.0,\"beats\":1.5},\"aspects\":{\"16x9\":{\"vmaf\":96.5,\"review\":\"PASS\",\"mb\":11.1}},\"review\":\"PASS\"}" "$4"
  mk "$SB/motion/$1/out/$1-16x9.mp4" "video-$1" "$4"
  mk "$SB/motion/$1/out/$1-16x9.sheet.jpg" "sheet-$1" "$4"
  mk "$SB/motion/$1/out/$1-16x9.report.html" "report-$1" "$4"
  mk "$SB/motion/$1/out/$1-16x9.review.json" '{}' "$4"
}
film hero-film film false 7200
film demo film false 600            # scratch name: skipped
film draft-film film true 600       # draft: skipped
film promo trailer false 600        # not the film template: skipped
mk "$SB/drop/T100/hero.mp4" "video-hero-film" 7000
mk "$SB/drop/T100/hero-film-16x9.sheet.jpg" "sheet-hero-film" 7000
mk "$SB/drop/T100/hero-film-16x9.report.html" "report-hero-film" 7000
mk "$SB/drop/T099/play.mp4" "old-play" 90000
mk "$SB/drop/T101/play.mp4" "new-play" 3600
mk "$SB/drop/T101/contact-sheet.jpg" "sheet-play" 3600
mk "$SB/games/arena-v2/ci/summary.json" '{"date":"2025-10-20T08:00:00+00:00","ok":true,"seconds":79,"stages":{"configure":{"status":"pass","seconds":1},"perf":{"status":"pass","seconds":2,"gpu_ms_p50":1.2647},"tidy":{"status":"fail","seconds":42}}}' 3600
mk "$SB/perf-cpp.csv" $'date,project,gpu_ms_p50,gpu_ms_p99,cpu_ms_p50,post_ms_p50,gpu_ms_p50_shadow,gpu_ms_p50_scene\n2025-10-19T10:00:00+00:00,cpp,9.9999,9.9,9.9,9.9,9.9,9.9\n2025-10-20T09:00:00+00:00,cpp,1.1190,3.7844,0.4365,0.4449,0.0668,0.6018\n' 0
mk "$SB/FOLLOWUPS.md" $'# seeds\n- T100 hero film red on CPU 1,000 vs 900.\n- ~~T100 old flaw~~ (done T200)\n- T555 unrelated line.\n- T687: first nightly row in perf-cpp.csv.\n- T300 arena v2 FXAA over budget.\n' 60

run() { "$BIN/showcase-page" --out "$SB/drop/T745" --drop "$SB/drop" --motion "$SB/motion" --games "$SB/games" \
  --perf "$SB/perf-cpp.csv" --followups "$SB/FOLLOWUPS.md" --now "$NOW" "$@"; }

t "selftest: fixture roots only"
[[ $SB == /tmp/* || $SB == "${TMPDIR:-/tmp}"/* ]] && ok || no "sandbox $SB not a temp dir"

t "usage without --out exits 2"
"$BIN/showcase-page" >/dev/null 2>&1; [[ $? == 2 ]] && ok || no "rc not 2"

t "writes index.html, rc 0"
msg=$(run 2>&1); rc=$?; P="$SB/drop/T745/index.html"
[[ $rc == 0 && -s $P ]] && ok || no "rc=$rc $msg"
H=$(cat "$P" 2>/dev/null)
has() { grep -qF -- "$1" <<<"$H"; }

t "newest non-scratch film chosen (not demo/draft/trailer)"
has 'Motion video · hero-film · T100' && ! has 'draft-film' && ! has 'promo' && ! has '>demo' && ok || no "wrong film"

t "film media linked in place by content, no copies"
has 'src="../T100/hero.mp4"' && has 'src="../T100/hero-film-16x9.sheet.jpg"' && has 'href="../T100/hero-film-16x9.report.html"' \
  && [[ -z $(find "$SB/drop/T745" -name '*.mp4' -o -name '*.jpg') ]] && ok || no "links or copies wrong"

t "cpu_s + top 3 steps_cpu in order, 4th left out"
grep -o 'steps_cpu #[0-9] [a-z0-9]*' <<<"$H" | tr '\n' ' ' | grep -qx 'steps_cpu #1 plate0 steps_cpu #2 composite steps_cpu #3 hdr10 ' \
  && has '1,000.0' && has '400.0 (40 %)' && ! has 'beats' && ok || no "steps wrong"

t "review + VMAF shown"
has '<td>PASS</td>' && has '96.5 / 11.1 MB · PASS' && ok || no "review missing"

t "newest play.mp4 drop chosen"
has 'src="../T101/play.mp4"' && has 'src="../T101/contact-sheet.jpg"' && ! has 'T099' && ok || no "wrong game drop"

t "cpp-ci stages with status, gpu p50 on perf"
has '2/3 pass, 79 s' && has 'stage tidy</th><td>fail · 42 s' && has 'pass · 2 s · gpu p50 1.2647 ms' && ok || no "stages wrong"

t "cpp-report.html written beside the page and linked from the game section"
R="$SB/drop/T745/cpp-report.html"
has 'href="cpp-report.html"' && [[ -s $R ]] && grep -q 'cpp-ci · arena-v2' "$R" && grep -q '<td>tidy</td><td><span class="b fail">fail' "$R" \
  && grep -q 'data:image/jpeg;base64' "$R" && ok || no "report missing or wrong"

t "last perf-cpp.csv row per pass, not the older row"
has '1.1190 ms' && has 'nightly pass shadow p50</th><td>0.0668 ms' && has 'nightly pass post p50' && ! has '9.9999' && ok || no "perf row wrong"

t "every number has an age; ages from summary/csv dates, not mtimes"
n_rows=$(grep -o '<tr><th>[^M]' <<<"$H" | wc -l); n_age=$(grep -o '<td class=age>[0-9]* \(min\|h\|d\)</td>' <<<"$H" | wc -l)
[[ $n_rows -gt 10 && $n_rows == "$n_age" ]] && has '<td class=age>2 h</td>' && has '<td class=age>1 h</td>' \
  && ! has '<td class=age>0 min</td>' && ok || no "rows=$n_rows ages=$n_age"

t "open follow-ups per section; closed + unrelated left out"
has 'T100 hero film red on CPU' && has 'T687: first nightly row' && has 'T300 arena v2 FXAA' \
  && ! has 'old flaw' && ! has 'T555' && ok || no "follow-ups wrong"

t "empty roots: page still written with 'not found' notes"
"$BIN/showcase-page" --out "$SB/e/out" --drop "$SB/e" --motion "$SB/e/m" --games "$SB/e/g" --perf "$SB/e/none.csv" \
  --followups "$SB/e/none.md" --now "$NOW" >/dev/null 2>&1 && grep -q 'no non-scratch film' "$SB/e/out/index.html" \
  && grep -q 'no cpp-ci summary' "$SB/e/out/index.html" && ok || no "empty case"

mk "$SB/drop/T100/layout.txt" $'PASS layout 16x9: 3 shots\n' 7000
chk() { "$BIN/showcase-page" --check --drop "$SB/drop/T745" --now "$NOW" "$@"; }

t "--check complete drop: rc 0, one line each, last 'showcase: N/N ok'"
out=$(chk); rc=$?
[[ $rc == 0 ]] && ! grep -q '^FAIL' <<<"$out" && tail -1 <<<"$out" | grep -qx 'showcase: 11/11 ok' \
  && grep -qx 'ok film preview: ../T100/hero.mp4 + ../T100/hero-film-16x9.sheet.jpg' <<<"$out" \
  && grep -qx 'ok film layout: ../T100/layout.txt FAIL 0' <<<"$out" && grep -qx 'ok game report: cpp-report.html' <<<"$out" && ok || no "rc=$rc $out"

t "--check --json gives the same counts"
chk --json | python3 -c 'import json,sys; j=json.load(sys.stdin); sys.exit(not (j["ok"]==j["total"]==11 and all(c["ok"] for c in j["checks"])))' \
  && ok || no "json wrong"

t "--check missing play.mp4: rc 1 naming it"
mv "$SB/drop/T101/play.mp4" "$SB/play.bak"
out=$(chk); rc=$?; mv "$SB/play.bak" "$SB/drop/T101/play.mp4"; touch -d "@$(( NOW - 3600 ))" "$SB/drop/T101/play.mp4"
[[ $rc == 1 ]] && grep -qx 'FAIL ../T101/play.mp4 missing' <<<"$out" && tail -1 <<<"$out" | grep -qx 'showcase: 10/11 ok' && ok || no "rc=$rc $out"

t "--check stale film (--max-age 1h): rc 1 naming it"
out=$(chk --max-age 1h); rc=$?
[[ $rc == 1 ]] && grep -q '^FAIL ../T100/hero.mp4 stale' <<<"$out" && ! grep -q '^FAIL ../T101/play.mp4' <<<"$out" && ok || no "rc=$rc $out"

t "--check layout FAIL lines and empty media fail"
printf 'FAIL title t0 over subject\n' >>"$SB/drop/T100/layout.txt"; : >"$SB/drop/T101/contact-sheet.jpg"
out=$(chk); rc=$?
[[ $rc == 1 ]] && grep -qx 'FAIL film layout: ../T100/layout.txt FAIL 1' <<<"$out" \
  && grep -qx 'FAIL ../T101/contact-sheet.jpg empty' <<<"$out" && ok || no "rc=$rc $out"

t "--check missing cpp-report.html: rc 1 naming it"
mv "$R" "$SB/rep.bak"; out=$(chk); rc=$?; mv "$SB/rep.bak" "$R"
[[ $rc == 1 ]] && grep -qx 'FAIL cpp-report.html missing' <<<"$out" && ok || no "rc=$rc $out"

t "--check without index.html: rc 1"
out=$("$BIN/showcase-page" --check --drop "$SB/e/none" --now "$NOW"); rc=$?
[[ $rc == 1 ]] && grep -q '^FAIL .*index.html missing' <<<"$out" && ok || no "rc=$rc $out"

t "--check game stack unlinked: rc 1 naming play.mp4"
out=$("$BIN/showcase-page" --check --drop "$SB/e/out" --now "$NOW"); rc=$?
[[ $rc == 1 ]] && grep -qx 'FAIL game preview: no play.mp4 or contact sheet linked' <<<"$out" \
  && grep -qx 'FAIL game report: no cpp-report.html linked' <<<"$out" && ok || no "rc=$rc $out"

t "bad --max-age exits 2"
chk --max-age 24 >/dev/null 2>&1; [[ $? == 2 ]] && ok || no "rc not 2"

exit $fail
