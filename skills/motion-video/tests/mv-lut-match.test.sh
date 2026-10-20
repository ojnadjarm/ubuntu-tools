#!/usr/bin/env bash
# mv-lut-match.test.sh: mv-lut match on testsrc2 vs a colorbalance+eq tinted copy; fixtures are created here and deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts/mv-lut
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-lut-match-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<b)}' && echo 1 || echo 0; }
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
TINT="colorbalance=rs=-0.2:bs=0.25:rm=-0.25:bm=0.25,eq=contrast=0.9:saturation=0.7:brightness=-0.03"
de() { python3 "$FX/de.py" "$@"; }
apply() { ff ${3:+-ss "$3"} -i "$1" -vf "lut3d=file='$2':interp=tetrahedral" -frames:v 1 "$4"; }

cat >"$FX/de.py" <<'PY'
import subprocess, sys
import numpy as np
def rgb(p):
    raw = subprocess.run(['ffmpeg','-v','error','-i',p,'-frames:v','1','-f','rawvideo','-pix_fmt','rgb24','-'],capture_output=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1,3).astype(float)/255
def lab(c):
    l = np.where(c <= 0.04045, c/12.92, ((c+0.055)/1.055)**2.4)
    xyz = l @ np.array([[0.4124,0.3576,0.1805],[0.2126,0.7152,0.0722],[0.0193,0.1192,0.9505]]).T / [0.95047,1,1.08883]
    f = np.where(xyz > 216/24389, np.cbrt(xyz), (24389/27*xyz+16)/116)
    return np.stack([116*f[:,1]-16, 500*(f[:,0]-f[:,1]), 200*(f[:,1]-f[:,2])],1)
def de2000(a, b):
    L1,a1,b1 = a.T; L2,a2,b2 = b.T
    C = (np.hypot(a1,b1)+np.hypot(a2,b2))/2
    G = 0.5*(1-np.sqrt(C**7/(C**7+25**7)))
    a1p,a2p = a1*(1+G), a2*(1+G)
    C1p,C2p = np.hypot(a1p,b1), np.hypot(a2p,b2)
    h1 = np.degrees(np.arctan2(b1,a1p))%360; h2 = np.degrees(np.arctan2(b2,a2p))%360
    dL, dC = L2-L1, C2p-C1p
    dh = h2-h1; dh = np.where(dh>180, dh-360, np.where(dh<-180, dh+360, dh)); dh = np.where(C1p*C2p==0, 0, dh)
    dH = 2*np.sqrt(C1p*C2p)*np.sin(np.radians(dh/2))
    Lm, Cm = (L1+L2)/2, (C1p+C2p)/2
    hs = h1+h2; hm = np.where(np.abs(h1-h2)>180, np.where(hs<360, hs+360, hs-360), hs)/2; hm = np.where(C1p*C2p==0, hs, hm)
    T = 1-0.17*np.cos(np.radians(hm-30))+0.24*np.cos(np.radians(2*hm))+0.32*np.cos(np.radians(3*hm+6))-0.20*np.cos(np.radians(4*hm-63))
    SL = 1+0.015*(Lm-50)**2/np.sqrt(20+(Lm-50)**2); SC = 1+0.045*Cm; SH = 1+0.015*Cm*T
    RT = -2*np.sqrt(Cm**7/(Cm**7+25**7))*np.sin(np.radians(60*np.exp(-((hm-275)/25)**2)))
    return np.sqrt((dL/SL)**2+(dC/SC)**2+(dH/SH)**2+RT*(dC/SC)*(dH/SH))
if sys.argv[1] == 'identity':
    a = np.loadtxt(sys.argv[2], skiprows=2)
    b, g, r = np.meshgrid(*[np.arange(33) / 32] * 3, indexing='ij')
    print(f'{np.abs(a - np.stack([r, g, b], -1).reshape(-1, 3)).max() * 255:.4f}')
elif sys.argv[1] == 'selftest':
    print(f"{de2000(np.array([[50, 2.6772, -79.7751]]), np.array([[50, 0, -82.7485]]))[0]:.4f}")
else:
    print(f'{de2000(lab(rgb(sys.argv[1])), lab(rgb(sys.argv[2]))).mean():.3f}')
PY

ff -f lavfi -i testsrc2=s=640x360:d=1 -frames:v 1 "$FX/ref.png"
ff -i "$FX/ref.png" -vf "$TINT" "$FX/src.png"
ff -f lavfi -i testsrc2=s=640x360:r=30:d=4 -c:v libx264 -preset ultrafast -crf 12 -pix_fmt yuv420p "$FX/ref.mp4"
ff -i "$FX/ref.mp4" -vf "$TINT" -c:v libx264 -preset ultrafast -crf 12 -pix_fmt yuv420p "$FX/src.mp4"
ok "$( [[ -s $FX/ref.png && -s $FX/src.png && -s $FX/ref.mp4 && -s $FX/src.mp4 ]] && echo 1 || echo 0)" "fixtures generated"
ok "$( [[ $(de selftest) == 2.0425 ]] && echo 1 || echo 0)" "CIEDE2000 helper matches Sharma pair 1 (2.0425)"
ok "$("$BIN" --help 2>&1 | grep -q 'mv-lut match' && echo 1 || echo 0)" "--help lists match"

"$BIN" match "$FX/ref.png" "$FX/src.png" "$FX/m.cube" --sheet "$FX/sheet.jpg" >/dev/null; r=$?
apply "$FX/src.png" "$FX/m.cube" "" "$FX/matched.png"
before=$(de "$FX/ref.png" "$FX/src.png") after=$(de "$FX/ref.png" "$FX/matched.png")
ok "$( [[ $r == 0 ]] && grep -q '^LUT_3D_SIZE 33$' "$FX/m.cube" && [[ $(grep -c '^[0-9]' "$FX/m.cube") == 35937 ]] && echo 1 || echo 0)" "png: rc 0, 33^3 cube"
ok "$(lt 8 "$before")" "png: tinted mean dE2000 $before > 8"
ok "$(lt "$after" 2)" "png: matched mean dE2000 $after < 2"
ok "$( [[ $(ffprobe -v error -show_entries stream=width -of csv=p=0 "$FX/sheet.jpg" 2>/dev/null) == 1920 ]] && echo 1 || echo 0)" "sheet ref|src|matched 1920 px wide"

"$BIN" match "$FX/ref.png" "$FX/src.png" "$FX/half.cube" --strength 0.5 >/dev/null
apply "$FX/src.png" "$FX/half.cube" "" "$FX/half.png"
half=$(de "$FX/ref.png" "$FX/half.png")
ok "$( [[ $(lt "$after" "$half") == 1 && $(lt "$half" "$before") == 1 ]] && echo 1 || echo 0)" "strength 0.5 lands between ($half)"

"$BIN" match "$FX/ref.png" "$FX/ref.png" "$FX/id.cube" >/dev/null
dev=$(de identity "$FX/id.cube")
ok "$(lt "$dev" 1)" "identity input -> cube within $dev/255 of identity"

"$BIN" match "$FX/ref.mp4" "$FX/src.mp4" "$FX/v.cube" >/dev/null; r=$?
ff -ss 2 -i "$FX/ref.mp4" -frames:v 1 "$FX/vref.png"
ff -ss 2 -i "$FX/src.mp4" -frames:v 1 "$FX/vsrc.png"
apply "$FX/src.mp4" "$FX/v.cube" 2 "$FX/vmatched.png"
vb=$(de "$FX/vref.png" "$FX/vsrc.png") va=$(de "$FX/vref.png" "$FX/vmatched.png")
ok "$( [[ $r == 0 && $(lt 8 "$vb") == 1 && $(lt "$va" 2) == 1 ]] && echo 1 || echo 0)" "mp4 (3 frames): dE2000 $vb -> $va"

"$BIN" match "$FX/ref.png" "$FX/missing.png" "$FX/x.cube" >/dev/null 2>&1; r=$?
ok "$( [[ $r != 0 && ! -e $FX/x.cube ]] && echo 1 || echo 0)" "missing input -> rc $r, no cube"
"$BIN" match "$FX/ref.png" "$FX/src.png" "$FX/x.cube" --strength 2 >/dev/null 2>&1; r=$?
ok "$( [[ $r != 0 && ! -e $FX/x.cube ]] && echo 1 || echo 0)" "--strength 2 -> rc $r, no cube"

"$BIN" film "$FX/film.cube" >/dev/null
ok "$(cmp -s "$FX/film.cube" "$HERE/../luts/film.cube" && echo 1 || echo 0)" "film look unchanged"

echo "mv-lut-match.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
