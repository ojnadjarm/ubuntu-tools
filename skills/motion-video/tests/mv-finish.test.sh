#!/usr/bin/env bash
# mv-finish.test.sh: --finish clean|film in mv-encode (banding, grain sigma, halation, legal range, AV1 grain synthesis, VBV, alpha); 640x360 and 320x180 (grain) lavfi fixtures deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
# One BLAS thread: numpy's OpenBLAS pool alone costs ~1 cpu s per import.
export OMP_NUM_THREADS=1
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-finish-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
tags=setparams=range=tv:colorspace=bt709:color_primaries=bt709:color_trc=bt709
# py <file> <expr>: first frames as numpy arrays y (luma) and v (Cr), 8-bit, then print(expr)
py() { python3 -c "
import sys,subprocess,numpy as np
def plane(p):
    r=subprocess.run(['ffmpeg','-v','error','-i',sys.argv[1],'-frames:v','6','-vf','format=yuv444p,extractplanes='+p,'-f','rawvideo','-pix_fmt','gray','-'],capture_output=True).stdout
    w,h=map(int,subprocess.run(['ffprobe','-v','error','-show_entries','stream=width,height','-of','csv=p=0',sys.argv[1]],capture_output=True,text=True).stdout.split(',')[:2])
    return np.frombuffer(r,np.uint8).reshape(-1,h,w).astype(int)
def bands(row):
    b,run=0,1
    for i in range(1,len(row)):
        if row[i]==row[i-1]: run+=1
        else: b+=run>12; run=1
    return b+(run>12)
y=plane('y'); v=plane('v') if 'v[' in sys.argv[2] else None
print(eval(sys.argv[2]))" "$1" "$2"; }
# planes <file> <plane> <out> [decoder opts]: first 6 frames of one plane as raw 8-bit
planes() { local f=$1 pl=$2 o=$3; shift 3; ffmpeg -v error -y "$@" -i "$f" -frames:v 6 -vf "format=yuva444p,extractplanes=$pl" -f rawvideo -pix_fmt gray "$o"; }

ff -f lavfi -i "color=c=black:s=640x360:r=24:d=1,format=yuv444p,geq=lum='16+floor(32*X/W)':cb=128:cr=128,$tags" -c:v ffv1 "$FX/grad.mkv"
ff -i "$FX/grad.mkv" -frames:v 6 -c:v ffv1 "$FX/grad6.mkv"
ff -f lavfi -i "color=c=0x808080:s=320x180:r=24:d=0.25,format=yuv444p,$tags" -c:v ffv1 "$FX/grey.mkv"
ff -f lavfi -i "color=c=black:s=640x360:r=24:d=0.5,drawbox=x=280:y=140:w=80:h=80:c=white:t=fill,format=yuv444p,$tags" \
  -f lavfi -i "sine=f=440:d=0.5:sample_rate=48000" -c:v ffv1 -c:a flac "$FX/box.mkv"
ff -f lavfi -i "color=c=0x808080:s=640x360:r=24:d=0.25,format=yuva444p,geq=lum='p(X,Y)':cb=128:cr=128:a='255*X/W',$tags" -c:v ffv1 "$FX/alpha.mkv"
ok "$( [[ $(py "$FX/grad.mkv" "bands(y[0,180])") -ge 30 ]] && echo 1 || echo 0)" "fixture: 8-bit 16->48 gradient has 32 flat bands"

# Every encode is independent: run them at once, then assert in order.
enc() { "$BIN/mv-encode" "$@" >/dev/null 2>&1; }
for f in none clean; do enc "$FX/grad.mkv" "$FX/g_$f.mp4" --preset h264-web --finish $f & done
for g in 1.5 2 4; do enc "$FX/grey.mkv" "$FX/grain$g.mp4" --preset h264-web --finish film --grain $g & done
enc "$FX/grey.mkv" "$FX/grain0.mp4" --preset h264-web --finish clean &
for f in clean film; do enc "$FX/box.mkv" "$FX/box_$f.mp4" --preset h264-master --finish $f --grain 0 & done
enc "$FX/box.mkv" "$FX/hot.mp4" --preset h264-web --finish film --grain 4 --loudnorm &
enc "$FX/grad6.mkv" "$FX/g10.mp4" --preset hevc-10 --finish clean &
wait
for p in av1 av1-10; do enc "$FX/grey.mkv" "$FX/$p.mkv" --preset $p --finish film --grain 2 & done
enc "$FX/alpha.mkv" "$FX/a.webm" --preset vp9-alpha --finish clean &
wait
for f in clean film; do enc "$FX/grad6.mkv" "$FX/av1_$f.mkv" --preset av1 --finish $f & done
{ enc "$FX/alpha.mkv" "$FX/af.webm" --preset vp9-alpha --finish film; echo $? > "$FX/af.rc"; } &
wait

b0=$(py "$FX/g_none.mp4" "max(bands(y[0,r]) for r in (36,180,324))")
b1=$(py "$FX/g_clean.mp4" "max(bands(y[0,r]) for r in (36,180,324))")
ok "$( [[ $b0 -ge 8 ]] && echo 1 || echo 0)" "h264-web without finish: $b0 band edges (>= 8)"
ok "$( [[ $b1 -le 1 ]] && echo 1 || echo 0)" "h264-web --finish clean: $b1 band edges (<= 1)"

for g in 1.5 2 4; do
  s=$(py "$FX/grain$g.mp4" "round(float(np.mean([f[33:-33,33:-33].std() for f in y])),2)")
  ok "$(awk -v s="$s" -v g=$g 'BEGIN{print (s >= 0.8 * g && s <= 1.2 * g) ? 1 : 0}')" "film --grain $g: sigma $s at mid-grey (target +-20 %)"
done
s=$(py "$FX/grain0.mp4" "round(float(y[:,33:-33,33:-33].std()),2)")
ok "$(awk -v s="$s" 'BEGIN{print s < 0.3 ? 1 : 0}')" "clean adds no grain (sigma $s)"

hc=$(py "$FX/box_clean.mp4" "int(v[0,170:190,362:372].mean())")
hf=$(py "$FX/box_film.mp4" "int(v[0,170:190,362:372].mean())")
ok "$( [[ $hf -ge $((hc + 2)) ]] && echo 1 || echo 0)" "film halation: red-shifted glow beside a white box (Cr $hc -> $hf)"

read -r lo hi < <(py "$FX/hot.mp4" "int(y.min()), int(y.max())" | tr -d "(),")
ok "$( [[ $lo -ge 8 && $hi -le 244 ]] && echo 1 || echo 0)" "film grain + halation stay legal before codec ringing (Y $lo-$hi)"
"$BIN/mv-review" "$FX/hot.mp4" --out "$FX/r" >"$FX/r.log" 2>&1; r=$?
ok "$( [[ $r == 0 ]] && echo 1 || echo 0)" "mv-review PASS on a film finish (rc $r)"
c=$(ffprobe -v error -select_streams v -show_entries stream=color_space,color_primaries,color_transfer,color_range -of csv=p=0 "$FX/hot.mp4")
ok "$( [[ $c == tv,bt709,bt709,bt709 ]] && echo 1 || echo 0)" "film finish keeps BT.709 limited tags ($c)"
p=$(ffprobe -v error -select_streams v -show_entries stream=pix_fmt -of csv=p=0 "$FX/g10.mp4")
ok "$( [[ $p == yuv420p10le ]] && echo 1 || echo 0)" "--finish clean dithers to 10-bit on hevc-10 ($p)"
ok "$(grep -qa 'vbv_maxrate=222 vbv_bufsize=222' "$FX/grain2.mp4" && echo 1 || echo 0)" "h264-web film at 180p24 gets the 8 Mbps 1080p24 VBV cap scaled to 222k"
for p in av1 av1-10; do
  planes "$FX/$p.mkv" y "$FX/on.raw"; planes "$FX/$p.mkv" y "$FX/off.raw" -export_side_data film_grain
  read -r on off < <(python3 -c "
import sys,numpy as np
a,b=(np.fromfile(f,np.uint8).reshape(-1,180,320)[:,33:-33,33:-33].astype(float) for f in sys.argv[1:])
print(round(float(np.mean([f.std() for f in a])),2), round(float(np.mean([f.std() for f in b])),2))" "$FX/on.raw" "$FX/off.raw")
  ok "$(awk -v a="$on" -v b="$off" 'BEGIN{print (a >= 1.6 && a <= 2.4 && b < 0.5) ? 1 : 0}')" "$p film: grain by AV1 synthesis, sigma $on decoded, $off with synthesis off"
done
k=$(( $(stat -c %s "$FX/av1_film.mkv") * 100 / $(stat -c %s "$FX/av1_clean.mkv") ))
ok "$( [[ $k -le 115 ]] && echo 1 || echo 0)" "av1 film on a gradient: size $k % of clean (<= 115)"
planes "$FX/alpha.mkv" a "$FX/a0.raw"; planes "$FX/a.webm" a "$FX/a1.raw" -c:v libvpx-vp9
d=$(python3 -c "
import sys,numpy as np
a,b=(np.fromfile(f,np.uint8).astype(int) for f in sys.argv[1:])
print(int(np.abs(a-b).max()) if a.size==b.size else 999)" "$FX/a0.raw" "$FX/a1.raw")
ok "$( [[ $d -le 1 ]] && echo 1 || echo 0)" "vp9-alpha --finish clean keeps alpha (max diff $d)"
ok "$( [[ $(cat "$FX/af.rc") == 2 ]] && echo 1 || echo 0)" "--finish film refuses vp9-alpha (halation drops alpha)"

echo "mv-finish.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
