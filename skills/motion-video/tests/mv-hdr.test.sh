#!/usr/bin/env bash
# mv-hdr.test.sh: mv-encode hevc-hdr10/av1-hlg tags, metadata and measured MaxCLL/MaxFALL; mv-review HDR report and PQ fail.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-hdr.XXXXXX")
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
is() { [[ $1 == "$2" ]] && echo 1 || echo 0; }
tags() { ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt,color_space,color_transfer,color_primaries,color_range -of csv=p=0 "$1"; }
side() { ffprobe -v error -read_intervals %+#1 -select_streams v:0 -show_frames -show_entries frame=side_data_list -of json "$1" |
  python3 -c 'import json,sys; s=[d for f in json.load(sys.stdin)["frames"][:1] for d in f.get("side_data_list",[])]
md=[d for d in s if d["side_data_type"]=="Mastering display metadata"]; cl=[d for d in s if d["side_data_type"]=="Content light level metadata"]
print(md[0]["max_luminance"] if md else "-", "%d,%d" % (cl[0]["max_content"], cl[0]["max_average"]) if cl else "-")'; }
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
enc() { nice -n 10 "$BIN/mv-encode" "$@" 2>&1; }

# 16-bit master: left half white, right half black -> MaxCLL 203 nit, MaxFALL ~101.5
mkdir -p "$FX/seq"
ff -f lavfi -i color=white:s=160x240:r=24:d=0.5 -f lavfi -i color=black:s=160x240:r=24:d=0.5 \
  -filter_complex "[0][1]hstack,format=rgb48le,lutrgb=r='if(gt(val,32768),65535,0)':g='if(gt(val,32768),65535,0)':b='if(gt(val,32768),65535,0)'" "$FX/seq/f_%03d.png"

out=$(enc "$FX/seq/f_%03d.png" "$FX/hdr10.mp4" --fps 24 --preset hevc-hdr10)
ok "$(is "$(tags "$FX/hdr10.mp4")" yuv420p10le,tv,bt2020nc,smpte2084,bt2020)" "hevc-hdr10 10-bit BT.2020 PQ tags"
ok "$([[ $out == *'maxcll=203 maxfall=10'[12]* ]] && echo 1 || echo 0)" "hevc-hdr10 measured MaxCLL 203 MaxFALL 101-102 ($(grep -o 'maxcll.*' <<<"$out"))"
read -r ml cl <<<"$(side "$FX/hdr10.mp4")"
ok "$([[ $ml == 10000000/10000 && $cl == 203,10[12] ]] && echo 1 || echo 0)" "hevc-hdr10 mastering-display 1000 nit + content light SEI ($ml $cl)"
y=$(ffmpeg -v error -i "$FX/hdr10.mp4" -frames:v 1 -f rawvideo -pix_fmt yuv420p10le - | python3 -c 'import sys,numpy as n; print(n.frombuffer(sys.stdin.buffer.read(),n.uint16)[40*320+40])')
ok "$([[ $y -ge 570 && $y -le 576 ]] && echo 1 || echo 0)" "hevc-hdr10 SDR white at PQ 203 nit (Y=$y, want ~573)"

enc "$FX/seq/f_%03d.png" "$FX/hlg.mp4" --fps 24 --preset av1-hlg >/dev/null
ok "$(is "$(tags "$FX/hlg.mp4")" yuv420p10le,tv,bt2020nc,arib-std-b67,bt2020)" "av1-hlg 10-bit BT.2020 HLG tags"
read -r ml cl <<<"$(side "$FX/hlg.mp4")"
ok "$([[ $ml == 256000/256 && $cl == 203,10[12] ]] && echo 1 || echo 0)" "av1-hlg mastering-display + content light OBUs ($ml $cl)"

enc "$FX/seq/f_%03d.png" "$FX/x.mp4" --fps 24 --preset hevc-hdr10 --finish film >/dev/null
ok "$(is $? 2)" "hevc-hdr10 --finish film -> rc 2"
enc "$FX/seq/f_%03d.png" "$FX/sdr.mp4" --fps 24 --preset h264-master >/dev/null
ok "$([[ $(tags "$FX/sdr.mp4") == yuv420p,tv,bt709,bt709,bt709 && $(side "$FX/sdr.mp4") == '- -' ]] && echo 1 || echo 0)" "h264-master stays BT.709 SDR, no HDR metadata"

"$BIN/mv-review" --out "$FX/rv" "$FX/hdr10.mp4" >/dev/null 2>&1
ok "$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); h=r["hdr"]
print(int(h["kind"]=="pq" and h["mastering_max"]==1000 and h["maxcll"]==203 and not any("hdr" in f for f in r["fails"])))' "$FX/rv/hdr10.review.json")" "mv-review reports PQ, 1000 nit mastering, MaxCLL 203, no hdr fail"
ff -f lavfi -i testsrc2=s=320x240:r=24:d=0.5 -pix_fmt yuv420p10le -c:v libx265 \
  -x265-params log-level=error:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc "$FX/bare.mp4"
"$BIN/mv-review" --out "$FX/rv" "$FX/bare.mp4" >/dev/null 2>&1
ok "$(python3 -c 'import json,sys; print(int("hdr pq without mastering metadata" in json.load(open(sys.argv[1]))["fails"]))' "$FX/rv/bare.review.json")" "mv-review FAILs a PQ file without mastering metadata"

echo "mv-hdr.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
