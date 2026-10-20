#!/usr/bin/env bash
# mv-encode-subs.test.sh: --subs keeps the whole picture (no cut at the last caption) for sequence and file inputs; 160x90 fixtures deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
ENC=$HERE/../scripts/mv-encode
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-encode-subs-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
# near <seconds>: 1 when within one 24 fps frame of 2.0 s
near() { awk -v d="$1" 'BEGIN{print (d >= 2 - 1/24 && d <= 2 + 1/24) ? 1 : 0}'; }
vsecs() { ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 "$1" | awk '{print $1 / 24}'; }
csecs() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
scodec() { ffprobe -v error -select_streams s:0 -show_entries stream=codec_name -of csv=p=0 "$1"; }

mkdir "$FX/seq"
ff -f lavfi -i "testsrc2=s=160x90:r=24" -frames:v 48 "$FX/seq/f_%04d.png"
ff -f lavfi -i "sine=f=440:d=2:sample_rate=48000" "$FX/tone.wav"
printf '1\n00:00:00,000 --> 00:00:01,000\nhello\n' >"$FX/caps.srt"
ff -framerate 24 -i "$FX/seq/f_%04d.png" -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$FX/in.mp4"

"$ENC" "$FX/seq/f_%04d.png" "$FX/seq.mp4" --fps 24 --audio "$FX/tone.wav" --subs "$FX/caps.srt" --preset h264-web >/dev/null
ok "$(near "$(vsecs "$FX/seq.mp4")")" "sequence + audio + subs: video $(vsecs "$FX/seq.mp4") s"
ok "$(near "$(csecs "$FX/seq.mp4")")" "sequence + audio + subs: container $(csecs "$FX/seq.mp4") s"
ok "$([[ $(scodec "$FX/seq.mp4") == mov_text ]] && echo 1 || echo 0)" "sequence .mp4 subs: mov_text"

"$ENC" "$FX/in.mp4" "$FX/file.mp4" --audio "$FX/tone.wav" --subs "$FX/caps.srt" --preset h264-web >/dev/null
ok "$(near "$(vsecs "$FX/file.mp4")")" "mp4 + audio + subs: video $(vsecs "$FX/file.mp4") s"
ok "$(near "$(csecs "$FX/file.mp4")")" "mp4 + audio + subs: container $(csecs "$FX/file.mp4") s"
ok "$([[ $(scodec "$FX/file.mp4") == mov_text ]] && echo 1 || echo 0)" "mp4 subs: mov_text"

"$ENC" "$FX/seq/f_%04d.png" "$FX/alpha.webm" --fps 24 --audio "$FX/tone.wav" --subs "$FX/caps.srt" --preset vp9-alpha >/dev/null
ok "$(near "$(vsecs "$FX/alpha.webm")")" "vp9-alpha sequence + subs: video $(vsecs "$FX/alpha.webm") s"
ok "$([[ $(scodec "$FX/alpha.webm") == webvtt ]] && echo 1 || echo 0)" "vp9-alpha .webm subs: webvtt"

echo "$((n - bad))/$n passed"
[[ $bad == 0 ]]
