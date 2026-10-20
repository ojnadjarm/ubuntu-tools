#!/usr/bin/env bash
# mv-pse.test.sh: the photosensitive flash check in mv-review (general and saturated-red flashes per 1 s) on lavfi fixtures deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HERE/../scripts
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-pse-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
js() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }
TAG="setparams=range=tv:colorspace=bt709:color_primaries=bt709:color_trc=bt709"
mk() { ffmpeg -hide_banner -loglevel error -y -threads 4 -f lavfi -i "$2" -vf "$3,format=yuv420p,$TAG" \
  -c:v libx264 -preset ultrafast -threads 4 "$FX/$1.mp4"; }
review() { "$BIN/mv-review" "$FX/$1.mp4" --out "$FX/r" >"$FX/$1.log" 2>&1; }

mk f5 "color=c=black:s=320x180:r=30:d=3" "format=gbrp,geq=r='if(lt(mod(T*5,1),0.5),255,0)':g='if(lt(mod(T*5,1),0.5),255,0)':b='if(lt(mod(T*5,1),0.5),255,0)'"
mk f2 "color=c=black:s=320x180:r=30:d=3" "format=gbrp,geq=r='if(lt(mod(T*2,1),0.5),255,0)':g='if(lt(mod(T*2,1),0.5),255,0)':b='if(lt(mod(T*2,1),0.5),255,0)'"
mk red5 "color=c=black:s=320x180:r=30:d=3" "format=gbrp,geq=r='if(lt(mod(T*5,1),0.5),255,0)':g=0:b=0"
mk dolly "testsrc2=s=1280x720:r=30:d=3" "crop=640:360:x='t*100':y='t*50',scale=320:180"

review f5; J=$FX/r/f5.review.json
ok "$(js "$J" "int(d['pse']['general_max'] > 3 and d['pse']['general'][0][0] < 1 and any(f.startswith('flash') for f in d['fails']))")" \
  "5 Hz full-screen flicker -> FAIL flash at 0-1 s ($(grep -o 'flash [^,|]*' "$FX/f5.log" | head -1))"
review f2; J=$FX/r/f2.review.json
ok "$(js "$J" "int(d['pse']['general_max'] <= 3 and d['pse']['red_max'] == 0 and not any('flash' in f for f in d['fails']))")" \
  "2 Hz flicker -> PASS ($(js "$J" "d['pse']"))"
review red5; J=$FX/r/red5.review.json
ok "$(js "$J" "int(d['pse']['red_max'] > 3 and any(f.startswith('red flash') for f in d['fails']))")" \
  "5 Hz red flicker -> FAIL red ($(grep -o 'red flash [^,|]*' "$FX/red5.log" | head -1))"
review dolly; J=$FX/r/dolly.review.json
ok "$(js "$J" "int(d['pse']['general_max'] == 0 and d['pse']['red_max'] == 0)")" "moving shot -> PASS ($(js "$J" "d['pse']"))"
"$BIN/mv-review" "$FX/f5.mp4" --out "$FX/n" --no-pse >"$FX/n.log" 2>&1
ok "$(js "$FX/n/f5.review.json" "int('pse' not in d and not any('flash' in f for f in d['fails']))")" "--no-pse skips the check"

echo "mv-pse.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
