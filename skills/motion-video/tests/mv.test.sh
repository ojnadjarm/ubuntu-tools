#!/usr/bin/env bash
# mv.test.sh: exercise the 8 mv-* CLIs on synthetic lavfi clips; fixtures are created here and deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-test.XXXXXX")
export CREATIVE_CI_LOG=$FX/creative-ci.jsonl
mkdir -p "$FX/bin"
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
probe() { ffprobe -v error -select_streams "$3" -show_entries "stream=$2" -of csv=p=0 "$1" | head -1; }
dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
near() { awk -v a="$1" -v b="$2" -v e="$3" 'BEGIN{d=a-b; if (d<0) d=-d; exit !(d<=e)}' && echo 1 || echo 0; }
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }

ff -f lavfi -i testsrc2=s=320x240:r=30:d=2 -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$FX/clip.mp4"
ff -f lavfi -i sine=f=440:d=2:sample_rate=48000 "$FX/sine.wav"
ff -f lavfi -i sine=f=880:d=0.2:sample_rate=48000 "$FX/blip.wav"
ff -f lavfi -i testsrc2=s=320x240:r=30:d=1 -f lavfi -i color=black:s=320x240:r=30:d=1.2 \
  -f lavfi -i testsrc2=s=320x240:r=30:d=0.8 -filter_complex '[0:v][1:v][2:v]concat=n=3:v=1[v]' -map '[v]' \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$FX/black.mp4"
mkdir -p "$FX/seq" && ff -f lavfi -i testsrc2=s=320x240:r=24:d=1 "$FX/seq/f_%03d.png"
ok "$( [[ -s $FX/clip.mp4 && -s $FX/sine.wav && -s $FX/black.mp4 && -s $FX/seq/f_024.png ]] && echo 1 || echo 0)" "fixtures generated"

# mv-mix
"$BIN/mv-mix" --out "$FX/mix.wav" --duration 2 --vo "$FX/sine.wav" --vo-at 0.3 --music "$FX/blip.wav" \
  --sfx "$FX/blip.wav@1@-3" >/dev/null
ok "$(near "$(dur "$FX/mix.wav")" 2 0.05)" "mv-mix duration 2 s +-0.05"
ok "$(is "$(probe "$FX/mix.wav" sample_rate,channels a:0)" 48000,2)" "mv-mix 48 kHz stereo"
ok "$(is "$(rc "$BIN/mv-mix" --out "$FX/x.wav" --duration 2)" 2)" "mv-mix without inputs -> rc 2"
cat >"$FX/marks.json" <<'J'
{"clips": {"vo": {"marks": {"intro": 0.2, "hit": 0.5}, "words": []}, "b": {"marks": {"outro": 1.0}, "words": []}}}
J
ff -f lavfi -i anullsrc=r=48000:cl=stereo -t 2 "$FX/silent.wav"
onset() { ffmpeg -hide_banner -nostats -i "$1" -af silencedetect=n=-50dB:d=0.1 -f null - 2>&1 | awk '/silence_end/{print $5; exit}'; }
"$BIN/mv-mix" --out "$FX/cue.wav" --duration 2 --vo "$FX/silent.wav" --vo-at 0.3 --cues "$FX/marks.json" \
  --sfx "$FX/blip.wav@cue:hit+20@-3" >/dev/null
ok "$(near "$(onset "$FX/cue.wav")" 0.82 0.010)" "mv-mix --sfx @cue:hit+20 starts at mark 0.5 + vo-at 0.3 + 20 ms +-10 ms"
"$BIN/mv-mix" --out "$FX/cue.wav" --duration 2 --vo "$FX/silent.wav" --vo-at 0.3 --cues "$FX/marks.json" \
  --sfx "$FX/blip.wav@cue:outro-100" >/dev/null
ok "$(near "$(onset "$FX/cue.wav")" 1.2 0.010)" "mv-mix --sfx @cue:outro-100 (second clip, negative ms) +-10 ms"
"$BIN/mv-mix" --out "$FX/cue.wav" --duration 2 --sfx "$FX/blip.wav@0.7@-3" >/dev/null
ok "$(near "$(onset "$FX/cue.wav")" 0.7 0.010)" "mv-mix --sfx seconds form unchanged: onset 0.7 +-10 ms"
"$BIN/mv-mix" --out "$FX/x.wav" --duration 2 --cues "$FX/marks.json" --sfx "$FX/blip.wav@cue:nope" >/dev/null 2>"$FX/cue.err"; r=$?
ok "$( [[ $r == 2 ]] && grep -q "unknown cue 'nope'; known: hit intro outro" "$FX/cue.err" && echo 1 || echo 0)" \
  "mv-mix unknown cue -> rc 2 naming the known cues"
ok "$(is "$(rc "$BIN/mv-mix" --out "$FX/x.wav" --duration 2 --sfx "$FX/blip.wav@cue:hit")" 2)" "mv-mix cue: without --cues -> rc 2"

# mv-captions
cat >"$FX/cues.json" <<'J'
{"clips": {"c1": {"words": [
 {"w": "One", "s": 0.0, "e": 0.2}, {"w": "two", "s": 0.25, "e": 0.4}, {"w": "three.", "s": 0.45, "e": 0.7},
 {"w": "Four", "s": 0.8, "e": 0.95}, {"w": "five", "s": 1.0, "e": 1.1}, {"w": "six", "s": 1.15, "e": 1.3},
 {"w": "seven", "s": 1.9, "e": 2.0}]}}}
J
"$BIN/mv-captions" "$FX/cues.json" c1 "$FX/caps" --size 320x240 >/dev/null
ok "$(is "$(grep -c -- '-->' "$FX/caps.srt")" 3)" "mv-captions .srt has 3 cues (sentence + pause breaks)"
ok "$(is "$(grep -c '^Dialogue:' "$FX/caps.ass")" 7)" "mv-captions .ass has 7 word events"
ok "$(is "$(sed -n 2p "$FX/caps.srt")" '00:00:00,000 --> 00:00:00,800')" "mv-captions first cue timing"

# mv-lut
"$BIN/mv-lut" film "$FX/film.cube" >/dev/null
ok "$(awk 'NR==2 && $0=="LUT_3D_SIZE 33"{h=1} NR>2{if (NF!=3) b=1; for (i=1;i<=3;i++) if ($i<0||$i>1) b=1; c++}
  END{print (h && !b && c==35937) ? 1 : 0}' "$FX/film.cube")" "mv-lut .cube: 33^3 rows of 3 values in [0,1]"
ok "$(is "$(rc "$BIN/mv-lut" nope "$FX/x.cube")" 1)" "mv-lut unknown look -> rc 1"

# mv-encode
"$BIN/mv-encode" "$FX/clip.mp4" "$FX/master.mp4" --audio "$FX/mix.wav" --lut "$FX/film.cube" --subs "$FX/caps.srt" >/dev/null
ok "$(is "$(probe "$FX/master.mp4" codec_name,pix_fmt,r_frame_rate v:0)" h264,yuv420p,30/1)" "mv-encode h264-master h264 30 fps yuv420p"
ok "$(is "$(probe "$FX/master.mp4" codec_name a:0)" aac)" "mv-encode audio aac"
ok "$(is "$(probe "$FX/master.mp4" codec_name s:0)" mov_text)" "mv-encode --subs mov_text"
ok "$(near "$(probe "$FX/master.mp4" duration v:0)" 2 0.05)" "mv-encode video stays 2 s with --audio"
"$BIN/mv-encode" "$FX/clip.mp4" "$FX/hevc.mp4" --preset hevc-10 >/dev/null
ok "$(is "$(probe "$FX/hevc.mp4" codec_name,codec_tag_string,pix_fmt v:0)" hevc,hvc1,yuv420p10le)" "mv-encode hevc-10 hvc1 10-bit"
"$BIN/mv-encode" "$FX/clip.mp4" "$FX/av1.mp4" --preset av1 >/dev/null 2>&1
ok "$(is "$(probe "$FX/av1.mp4" codec_name,r_frame_rate v:0)" av1,30/1)" "mv-encode av1 30 fps"
"$BIN/mv-encode" "$FX/clip.mp4" "$FX/alpha.webm" --preset vp9-alpha >/dev/null
ok "$(is "$(probe "$FX/alpha.webm" codec_name v:0)" vp9)" "mv-encode vp9-alpha webm"
"$BIN/mv-encode" "$FX/seq/f_%03d.png" "$FX/seq.mp4" --preset h264-web --fps 24 >/dev/null
ok "$(is "$(probe "$FX/seq.mp4" codec_name,r_frame_rate,nb_frames v:0)" h264,24/1,24)" "mv-encode image sequence 24 fps 24 frames"
ok "$(is "$(rc "$BIN/mv-encode" "$FX/clip.mp4" "$FX/x.mp4" --preset nope)" 2)" "mv-encode unknown preset -> rc 2"
ok "$(is "$(rc "$BIN/mv-encode" "$FX/seq/f_%03d.png" "$FX/x.mp4")" 2)" "mv-encode sequence without --fps -> rc 2"

# mv-review
"$BIN/mv-review" "$FX/master.mp4" --out "$FX/rev" >"$FX/rev.log" 2>&1; r=$?
ok "$( [[ $r == 0 ]] && grep -q PASS "$FX/rev.log" && echo 1 || echo 0)" "mv-review clean clip -> PASS rc 0"
ok "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(int(d["pass"] and d["fps"] == 30 and d["width"] == 320))' \
  "$FX/rev/master.review.json")" "mv-review json pass, 30 fps, 320 px"
ok "$( [[ -s $FX/rev/master.sheet.jpg ]] && echo 1 || echo 0)" "mv-review contact sheet written"
"$BIN/mv-encode" "$FX/black.mp4" "$FX/blackav.mp4" --audio "$FX/mix.wav" >/dev/null
"$BIN/mv-review" "$FX/blackav.mp4" --out "$FX/rev" >"$FX/rev.log" 2>&1; r=$?
ok "$( [[ $r == 1 ]] && grep -q 'FAIL black 1x' "$FX/rev.log" && echo 1 || echo 0)" "mv-review 1 s black -> FAIL rc 1"
ok "$(is "$(rc "$BIN/mv-review" "$FX/clip.mp4" --out "$FX/rev")" 1)" "mv-review no audio -> rc 1"

# BT.709 colour: SMPTE bars PNG -> encode -> decode as 709 -> mean error per channel <= 2/255, all tags bt709
tags=color_range,color_space,color_transfer,color_primaries
mkdir -p "$FX/bars" && ff -f lavfi -i smptehdbars=s=640x360:r=24:d=0.25 "$FX/bars/b_%02d.png"
"$BIN/mv-encode" "$FX/bars/b_%02d.png" "$FX/bars.mp4" --fps 24 >/dev/null
ok "$(is "$(probe "$FX/bars.mp4" $tags v:0)" tv,bt709,bt709,bt709)" "mv-encode PNG master tagged bt709 tv"
ok "$(python3 -I - "$FX/bars/b_01.png" "$FX/bars.mp4" <<'P'
import subprocess, sys
def rgb(p, vf):
    return subprocess.run(['ffmpeg', '-v', 'error', '-i', p, '-frames:v', '1', '-vf', vf, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                          capture_output=True, check=True).stdout
a, b = rgb(sys.argv[1], 'format=rgb24'), rgb(sys.argv[2], 'scale=in_color_matrix=bt709:in_range=tv,format=rgb24')
err = [sum(abs(x - y) for x, y in zip(a[c::3], b[c::3])) / (len(a) // 3) for c in range(3)]
print(int(len(a) == len(b) and max(err) <= 2))
P
)" "mv-encode bars decoded as 709: mean RGB error <= 2/255"
ok "$(is "$(probe "$FX/hevc.mp4" $tags v:0)" tv,bt709,bt709,bt709)" "mv-encode hevc-10 from video tagged bt709 tv"
if [[ -e /dev/dri/renderD128 ]]; then
  "$BIN/mv-encode" "$FX/bars/b_%02d.png" "$FX/bars-hw.mp4" --fps 24 --preset h264-hw >/dev/null
  ok "$(is "$(probe "$FX/bars-hw.mp4" $tags v:0)" tv,bt709,bt709,bt709)" "mv-encode h264-hw (VA-API) tagged bt709 tv"
fi
ok "$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["color"]; print(int(set(c.values()) == {"bt709", "tv"}))' \
  "$FX/rev/master.review.json")" "mv-review json color bt709"
ff -i "$FX/clip.mp4" -i "$FX/mix.wav" -map 0:v -map 1:a -c:v copy -c:a aac "$FX/untagged.mp4"
"$BIN/mv-review" "$FX/untagged.mp4" --out "$FX/rev" >"$FX/rev.log" 2>&1; r=$?
ok "$( [[ $r == 1 ]] && grep -q 'FAIL colour untagged' "$FX/rev.log" && echo 1 || echo 0)" "mv-review untagged colour -> FAIL rc 1"
ff -i "$FX/clip.mp4" -i "$FX/mix.wav" -map 0:v -map 1:a -c:a aac -c:v libx264 -preset ultrafast \
  -vf setparams=colorspace=bt709:color_primaries=bt709:color_trc=iec61966-2-1 "$FX/mixed.mp4"
"$BIN/mv-review" "$FX/mixed.mp4" --out "$FX/rev" >"$FX/rev.log" 2>&1; r=$?
ok "$( [[ $r == 1 ]] && grep -q 'FAIL colour mixed' "$FX/rev.log" && echo 1 || echo 0)" "mv-review mixed colour tags -> FAIL rc 1"

# mv-new
"$BIN/mv-new" "$FX/proj" --kind promo >/dev/null
ok "$( [[ -f $FX/proj/package.json && -d $FX/proj/src && -f $FX/proj/brand.json && -x $FX/proj/build.sh && ! -e $FX/proj/node_modules ]] \
  && echo 1 || echo 0)" "mv-new promo tree"
ok "$(grep -q '^KIND=promo NAME=${NAME:-proj} COMP=${COMP:-Main}' "$FX/proj/build.sh" && ! grep -q __ "$FX/proj/build.sh" && echo 1 || echo 0)" \
  "mv-new build.sh placeholders filled"
"$BIN/mv-new" "$FX/mc" --kind explainer >/dev/null
ok "$( [[ -f $FX/mc/vite.config.ts ]] && grep -q 'COMP=${COMP:-main}' "$FX/mc/build.sh" && echo 1 || echo 0)" "mv-new explainer tree"
ok "$(is "$(rc "$BIN/mv-new" "$FX/proj" --kind promo)" 2)" "mv-new existing dir -> rc 2"
ok "$(is "$(rc "$BIN/mv-new" "$FX/y" --kind nope)" 2)" "mv-new unknown kind -> rc 2"

# build.sh (mv-render stubbed: aspect "bad" gets the black clip, others the clean one)
mkdir -p "$FX/bbin" && for s in mv-mix mv-encode mv-review; do ln -s "$BIN/$s" "$FX/bbin/$s"; done
cat >"$FX/bbin/mv-render" <<S
#!/usr/bin/env bash
[[ \$4 == *raw-bad.mp4 ]] && cp "$FX/black.mp4" "\$4" || cp "$FX/clip.mp4" "\$4"
S
chmod +x "$FX/bbin/mv-render"
if [[ $(PATH=$FX/bbin:$PATH command -v mv-render) == "$FX/bbin/mv-render" ]]; then
  ok 1 "build.sh sandbox selftest: mv-render is the stub"
  bld() { (cd "$FX/proj" && rm -rf out && PATH=$FX/bbin:$PATH MUSIC=$FX/sine.wav ASPECTS=$1 ./build.sh >"$FX/build.log" 2>&1); echo $?; }
  if ! busy=$(quiet-gate --max-per-cpu 1); then
    echo "SKIP build.sh x3: ${busy#quiet-gate: busy, } (build.sh refuses, rc 3)"
  else
    ok "$(is "$(bld "good:320:240 bad:320:240")" 1)" "build.sh black aspect -> rc 1"
    ok "$(grep -q 'build: FAIL bad: black 1x' "$FX/build.log" && jq -e '.good.review == "PASS" and .bad.review == "FAIL"
      and .bad.reasons == ["black 1x"] and (.good | has("render_s") and has("mix_s") and has("encode_s"))' \
      "$FX/proj/out/build.json" >/dev/null && echo 1 || echo 0)" "build.sh runs every aspect, names the FAIL, writes build.json"
    ok "$(is "$(bld "good:320:240")" 0)" "build.sh clean aspect -> rc 0"
    ok "$(jq -se 'length == 2 and .[0].tool == "mv-build" and .[0].project == "proj" and .[0].ok == false and .[0].failed == ["bad:black 1x"]
      and .[1].ok == true and .[1].failed == [] and (.[1].summary | endswith("-mv-build-proj.json"))' "$CREATIVE_CI_LOG" >/dev/null \
      && ! awk 'length > 300' "$CREATIVE_CI_LOG" | grep -q . && echo 1 || echo 0)" "build.sh logs one creative-ci line per run (red, green)"
  fi
else
  ok 0 "build.sh sandbox selftest: mv-render is the stub (skipped build)"
fi

# mv-render
"$BIN/mv-render" new remotion "$FX/rem" >/dev/null
ok "$( [[ -f $FX/rem/remotion.config.ts ]] && echo 1 || echo 0)" "mv-render new remotion"
mkdir -p "$FX/rem/node_modules" "$FX/rem/out"
"$BIN/mv-render" clean "$FX/rem" >/dev/null
ok "$( [[ ! -e $FX/rem/node_modules && -d $FX/rem/out && -f $FX/rem/package.json ]] && echo 1 || echo 0)" "mv-render clean keeps out/"
"$BIN/mv-render" clean --all "$FX/rem" >/dev/null
ok "$( [[ ! -e $FX/rem/out && -f $FX/rem/package.json ]] && echo 1 || echo 0)" "mv-render clean --all"
ok "$( [[ ! -e $FX/rem/node_modules && ! -e $FX/rem/out && -f $FX/rem/package.json ]] && echo 1 || echo 0)" "mv-render clean"
ok "$(is "$(rc "$BIN/mv-render" bogus)" 2)" "mv-render unknown command -> rc 2"

# mv-assets (curl stubbed: no network)
ff -f lavfi -i sine=d=0.1 "$FX/a.ogg" && (cd "$FX" && zip -q pack.zip a.ogg)
cat >"$FX/bin/curl" <<S
#!/usr/bin/env bash
echo "\${@: -3:1}" >>"$FX/curl.log"
[[ \${@: -3:1} == *.zip ]] && cp "$FX/pack.zip" "\${@: -1}" || cp "$FX/a.ogg" "\${@: -1}"
S
chmod +x "$FX/bin/curl"
printf '#!/usr/bin/env bash\necho "$2" >>"%s/curl.log"; mkdir -p "$3/polyhaven/$2" && touch "$3/polyhaven/$2/$2.gltf"\n' "$FX" >"$FX/bin/cc0-fetch"
if [[ $(PATH=$FX/bin:$PATH command -v curl) == "$FX/bin/curl" ]]; then
  ok 1 "mv-assets sandbox selftest: curl is the stub"
  CC0_FETCH=$FX/bin/cc0-fetch PATH=$FX/bin:$PATH MV_LIBRARY=$FX/lib "$BIN/mv-assets" fetch >/dev/null
  rows=$(grep -vc '^#' "$HERE/../assets.tsv")
  ok "$(is "$(wc -l <"$FX/curl.log")" "$rows")" "mv-assets fetch: one stubbed download per assets.tsv row"
  ok "$(is "$(wc -l <"$FX/lib/LICENSES.tsv")" "$rows")" "mv-assets LICENSES.tsv rows"
  ok "$(is "$(MV_LIBRARY=$FX/lib "$BIN/mv-assets" list | wc -l)" "$rows")" "mv-assets list"
  CC0_FETCH=$FX/bin/cc0-fetch PATH=$FX/bin:$PATH MV_LIBRARY=$FX/lib "$BIN/mv-assets" fetch >/dev/null
  ok "$(is "$(wc -l <"$FX/curl.log")" "$rows")" "mv-assets fetch is idempotent"
else
  ok 0 "mv-assets sandbox selftest: curl is the stub (skipped fetch)"
fi

echo "mv.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
