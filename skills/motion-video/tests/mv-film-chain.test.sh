#!/usr/bin/env bash
# mv-film-chain.test.sh: the film template's `build.sh --chain` on a 2 s 160x90 lavfi fixture (3 plates, 2 title spans, -16 LUFS mix): one plate decode makes both h264-web deliveries (ffmpeg shim + -progress), no master unless MV_MASTER=1 (then its own step from the lossless ref), durations +-1 frame, loudness kept, BT.709 tags, steps in build.json, no lossless leftovers.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
export HARNESS_HOME=$FX/harness; unset CREATIVE_CI_LOG
REAL=$(command -v ffmpeg)
mkdir -p "$FX/bin" "$FX/prog"
cat >"$FX/bin/ffmpeg" <<SH
#!/usr/bin/env bash
n=\$(ls "$FX/prog" | wc -l)
printf '%s\x1f' "\$@" >>"$FX/ffmpeg.log"; echo >>"$FX/ffmpeg.log"
exec "$REAL" -progress "$FX/prog/\$n" "\$@"
SH
chmod +x "$FX/bin/ffmpeg"
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
b() { "$@" >/dev/null 2>&1 && echo 1 || echo 0; }
FPS=12 S=2

"$HERE/../scripts/mv-new" "$FX/fx" --kind film >/dev/null
P=$FX/fx O=$P/out
ff() { "$REAL" -v error -y "$@"; }
lufs() { "$REAL" -hide_banner -nostats -i "$1" -map 0:a:0 -af ebur128 -f null - 2>&1 | awk '/I:/{v = $2} END{print v}'; }
fixture() {   # 3 plates of 8 frames, titles for spans [0,5] + [18,23], cuts, -16 LUFS mix
  rm -rf "$O"; mkdir -p "$O/title-16x9" "$O/title-9x16"
  for i in 0 1 2; do
    mkdir -p "$O/shot$i"
    ff -f lavfi -i "testsrc2=s=160x90:r=$FPS" -vf "hue=h=$((i * 120))" -frames:v 8 "$O/shot$i/frame_%04d.png"
  done
  ff -f lavfi -i "color=c=white@0.5:s=160x90:r=$FPS,format=rgba" -frames:v 12 "$O/title-16x9/%04d.png"
  ff -f lavfi -i "color=c=white@0.5:s=90x160:r=$FPS,format=rgba" -frames:v 12 "$O/title-9x16/%04d.png"
  echo '[[0,5],[18,23]]' >"$O/spans.json"
  echo '{"grid":"even","cuts":[0.6667,1.3333],"frames":[8,8,8],"starts":[0,0.6667,1.3333]}' >"$O/cuts.json"
  ff -f lavfi -i "anoisesrc=c=pink:d=$S:a=0.1:r=48000" -ac 2 "$O/raw.wav"
  ff -i "$O/raw.wav" -af "volume=$(awk -v l="$(lufs "$O/raw.wav")" 'BEGIN{print -16 - l}')dB" "$O/mix.wav"
  rm -f "$O/raw.wav" "$FX/ffmpeg.log" "$FX"/prog/*
}
run() {   # env for build.sh --chain
  (cd "$P" && env PATH="$FX/bin:$PATH" SIZE=160x90 FPS=$FPS SECONDS_TOTAL=$S MAX_PER_CPU=999 GATE_WAIT=0 MIN_VMAF=0 "$@" nice -n 19 ./build.sh --chain) >"$FX/build.log" 2>&1
}
plate_runs() { grep -c 'out/shot[0-9]/frame_' "$FX/ffmpeg.log"; }
slow_encodes() { tr '\037' '\n' <"$FX/ffmpeg.log" | grep -A1 -x -- -preset | grep -cx slow; }
plate_frames() {   # -progress frame= of the plate run(s)
  local i=0 f=0 l; while IFS= read -r l; do
    [[ $l == *out/shot0/frame_* ]] && f=$((f + $(grep '^frame=' "$FX/prog/$i" | tail -1 | cut -d= -f2)))
    i=$((i + 1)); done <"$FX/ffmpeg.log"; echo $f
}
dur_ok() { ffprobe -v error -select_streams v:0 -show_entries stream=duration -of csv=p=0 "$1" | awk -v s=$S -v f=$FPS '{d = $1 - s; print (d <= 1 / f + 1e-6 && d >= -1 / f - 1e-6) ? 1 : 0}'; }
tags() { ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,color_space,color_primaries,color_transfer,color_range -of csv=p=0 "$1"; }

fixture
run; rc=$?
[[ $rc == 0 ]] || tail -5 "$FX/build.log"
ok "$([[ $rc == 0 ]] && echo 1 || echo 0)" "build.sh --chain exit 0 (rc $rc)"
ok "$([[ $(plate_runs) == 1 ]] && echo 1 || echo 0)" "plates decoded by $(plate_runs) ffmpeg run (want 1)"
ok "$([[ $(plate_frames) == 24 ]] && echo 1 || echo 0)" "-progress: plate run output $(plate_frames) frames per stream (24: one pass)"
ok "$([[ $(slow_encodes) == 2 ]] && echo 1 || echo 0)" "libx264 slow encodes: $(slow_encodes) (2 web, no master)"
ok "$([[ $(tags "$O/fx-16x9.mp4") == h264,160,90,tv,bt709,bt709,bt709 ]] && echo 1 || echo 0)" "16x9: $(tags "$O/fx-16x9.mp4")"
ok "$([[ $(tags "$O/fx-9x16.mp4") == h264,90,160,tv,bt709,bt709,bt709 ]] && echo 1 || echo 0)" "9x16: $(tags "$O/fx-9x16.mp4")"
for t in 16x9 9x16; do
  ok "$(dur_ok "$O/fx-$t.mp4")" "$t video duration $S s +- 1 frame"
  ok "$(awk -v a="$(lufs "$O/fx-$t.mp4")" -v m="$(lufs "$O/mix.wav")" 'BEGIN{d = a - m; print (a != "" && d <= 0.5 && d >= -0.5) ? 1 : 0}')" "$t loudness $(lufs "$O/fx-$t.mp4") LUFS = mix $(lufs "$O/mix.wav") +- 0.5"
done
B=$O/build.json
ok "$(jq -e '(.steps | keys) == ["composite","quality_16x9","quality_9x16","review_16x9","review_9x16"] and ([.aspects[].vmaf] | all(type == "number"))' "$B" >/dev/null 2>&1 && echo 1 || echo 0)" "build.json steps $(jq -c '.steps | keys' "$B" 2>/dev/null), vmaf vs lossless ref $(jq -c '[.aspects[].vmaf]' "$B" 2>/dev/null)"
ok "$([[ -z $(find "$O" -name 'master-*' -o -name '*.mkv' -o -name '*.png' | head -1) ]] && echo 1 || echo 0)" "no master, no ref .mkv, no png left"

fixture
run MV_MASTER=1; rc=$?
ok "$([[ $rc == 0 && $(plate_runs) == 1 && $(slow_encodes) == 4 ]] && echo 1 || echo 0)" "MV_MASTER=1: rc $rc, plate runs $(plate_runs), slow encodes $(slow_encodes) (2 web + 2 master)"
ok "$(jq -e '.steps.master_16x9 > 0 and .steps.master_9x16 > 0' "$B" >/dev/null 2>&1 && echo 1 || echo 0)" "MV_MASTER=1: master_16x9 + master_9x16 timed steps"
ok "$(b test -s "$O/master-16x9.mp4" -a -s "$O/master-9x16.mp4")" "MV_MASTER=1: out/master-16x9.mp4 + master-9x16.mp4"
ok "$([[ $(dur_ok "$O/master-9x16.mp4") == 1 && -n $(ffprobe -v error -select_streams a -show_entries stream=codec_name -of csv=p=0 "$O/master-9x16.mp4") ]] && echo 1 || echo 0)" "MV_MASTER=1: master 9x16 $S s +- 1 frame with audio"
echo "mv-film-chain: $((n - bad))/$n"
[[ $bad == 0 ]]
