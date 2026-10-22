#!/usr/bin/env bash
# Render lane: encode (size cap, audio mux, still -> jpg, PNG cleanup) on synthetic frames, then a DarkSaddler draft
# build per look (grim, painterly, cinematic) + render of turntable and expressions with exposure, clipping and size
# bands, distinct look presets with material shading, expressions that differ cell to cell, and the 3-look comparison
# sheet.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
c3d=$here/scripts/char3d
spec=$here/specs/darksaddler.json
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

e=$tmp/enc
mkdir -p "$e/frames/clip" "$e/frames/still"
heavy run --ticket T1032 -- ffmpeg -loglevel error -f lavfi -i "mandelbrot=s=1280x720:r=30" -frames:v 60 "$e/frames/clip/%04d.png"
ffmpeg -loglevel error -f lavfi -i "testsrc=s=640x360" -frames:v 1 "$e/frames/still/0001.png"
ffmpeg -loglevel error -f lavfi -i "sine=f=220:d=3" "$e/talk.wav"
python3 - "$e" <<'PY'
import json, sys
e = sys.argv[1]
json.dump({'spec': {'qa': {'thresholds': {'mp4_mb': 0.4}}}, 'files': {'audio:talk': e + '/talk.wav'},
           'renders': {'clip': {'frames_dir': e + '/frames/clip', 'frames': 60, 'fps': 30, 'clip': 'talk'},
                       'still': {'frames_dir': e + '/frames/still', 'frames': 1, 'fps': 30}}}, open(e + '/build.json', 'w'))
PY
heavy run --ticket T1032 -- python3 "$here/scripts/c3d/encode.py" "$e" >/dev/null
python3 - "$e" <<'PY' || fail "encode"
import json, os, subprocess, sys
e = sys.argv[1]
r = json.load(open(e + '/build.json'))['renders']
assert r['clip']['mb'] <= 0.4 and r['clip']['audio'], r['clip']
streams = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_name', '-of', 'csv=p=0', r['clip']['file']],
                         capture_output=True, text=True).stdout.split()
assert streams == ['h264', 'aac'], streams
assert r['still']['file'].endswith('.jpg') and os.path.getsize(r['still']['file']) > 0, r['still']
assert not os.path.exists(e + '/frames/clip') and not os.path.exists(e + '/frames/still'), 'PNGs left'
PY
echo "ok encode: size cap, audio mux, jpg still, PNGs deleted"

for L in grim painterly cinematic; do
  python3 - "$spec" "$tmp/$L.json" "$L" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s['look']['name'] = sys.argv[3]
s['motion']['clips'] = [{'id': 'idle', 'type': 'idle', 'seconds': 1.0, 'loop': True}]
s['renders'] = [r for r in s['renders'] if r['id'] in ('turntable', 'expressions')]
s['secondary'].pop('cloth', None)
json.dump(s, open(sys.argv[2], 'w'))
PY
  "$c3d" build "$tmp/$L.json" --out "$tmp/$L" --draft --until lookdev >/dev/null || fail "build $L"
  "$c3d" render "$tmp/$L.json" --out "$tmp/$L" --draft --shots turntable,expressions --max-frames 2 >/dev/null || fail "render $L"
done
python3 - "$tmp" <<'PY' || fail "render bands"
import json, os, sys
seen = set()
for look in ('grim', 'painterly', 'cinematic'):
    b = json.load(open(f'{sys.argv[1]}/{look}/build.json'))
    lk, r = b['stages']['lookdev'], b['renders']
    assert lk['stub'] is False and lk['look'] == look and lk['rigs'] == [f'{look}.wide', f'{look}.close'] and lk['shaded'] > 0, lk
    seen.add((lk['hdri'], lk['view'], json.dumps(lk['grade'], sort_keys=True)))
    assert sorted(r) == ['expressions', 'turntable'], sorted(r)
    assert r['turntable']['rig'] == f'{look}.wide' and r['expressions']['rig'] == f'{look}.close', r
    for sid, x in r.items():
        s = x['stats']
        assert os.path.getsize(x['file']) > 0 and x['mb'] <= 20, (look, sid, x)
        assert 0.25 <= s['luma_mean'] <= 0.75 and s['clip_hi_pct'] <= 0.5, (look, sid, s)
    assert r['expressions']['cells'] == len(b['spec']['face']['expressions']) and r['expressions']['file'].endswith('.jpg')
    assert r['expressions']['expr_delta_min'] >= 0.005, ('expressions look identical', r['expressions'])
    print('ok render', look, {k: (v['stats']['luma_mean'], v['stats']['clip_hi_pct'], v['mb']) for k, v in r.items()})
assert len(seen) == 3, 'looks share HDRI, AgX look and grade'
PY
python3 "$here/scripts/gallery.py" "$tmp/sheet" --compare "$tmp/grim" "$tmp/painterly" "$tmp/cinematic" >/dev/null
test -s "$tmp/sheet/looks-compare.jpg" || fail "compare sheet"
echo "PASS render"
