#!/usr/bin/env bash
# mv-otio.test.sh: a recorded 3-shot build (fixtures/otio-out) -> mv-otio; the .otio reloads with 3 shots at build.json's cut frames and its duration, sources absolute and present, and melt renders the .kdenlive at that duration (+-1 frame) with audio. MV_OTIO_FULL=1 builds a fresh 3 s draft film instead; OUT=<a built out/> uses that one.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PY=${MV_OTIO_VENV:-$HOME/.local/opt/mv-otio}/bin/python
FX=$(mktemp -d)
trap 'rm -rf "$FX"' EXIT
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }

if [[ -z ${OUT:-} && ${MV_OTIO_FULL:-0} == 1 ]]; then
  export CREATIVE_CI_LOG=$FX/creative-ci.jsonl
  "$HERE/../scripts/mv-new" "$FX/demo" --kind film >/dev/null
  (cd "$FX/demo" && MV_EDIT=1 MAX_PER_CPU=${MAX_PER_CPU:-4} GATE_WAIT=${GATE_WAIT:-600} ./build.sh --draft) >"$FX/build.log" 2>&1 || tail -5 "$FX/build.log"
  OUT=$FX/demo/out
elif [[ -z ${OUT:-} ]]; then
  OUT=$FX/out
  cp -r "$HERE/fixtures/otio-out" "$OUT"
  sed -i "s|@OUT@|$OUT|g" "$OUT/build.json"
fi
B=$OUT/build.json NAME=$(jq -r .name "$B" 2>/dev/null)
"$HERE/../scripts/mv-otio" "$OUT" >"$FX/otio.log" 2>&1
rc=$?
ok "$([[ $rc == 0 && -s $OUT/$NAME.otio && -s $OUT/$NAME.kdenlive ]] && echo 1 || echo 0)" "mv-otio exit $rc: .otio + .kdenlive$([[ -s $OUT/$NAME.fcpxml ]] && echo ' + .fcpxml')"

ok "$("$PY" -I - "$OUT/$NAME.otio" "$B" <<'PY'
import json, os, sys
import opentimelineio as otio
tl, b = otio.adapters.read_from_file(sys.argv[1]), json.load(open(sys.argv[2]))
fps, v1 = b["fps"], tl.video_tracks()[0]
shots = [c for c in v1 if isinstance(c, otio.schema.Clip)]
starts = [round(v1.range_of_child(c).start_time.to_frames()) for c in shots]
want = [round(s * fps) for s in b["cuts"]["starts"]]
dur = tl.duration().rescaled_to(fps).value
ok = len(shots) == len(b["cuts"]["frames"]) == 3 and all(abs(x - y) <= 1 for x, y in zip(starts, want)) \
    and abs(dur - b["seconds"] * fps) <= 1
print(1 if ok else 0, file=sys.stdout)
print(f"shots {len(shots)} starts {starts} want {want} frames {dur:g}/{b['seconds'] * fps}", file=sys.stderr)
PY
)" "otio reload: 3 shots, cut frames and total duration = build.json +-1 frame"

ok "$("$PY" -I - "$OUT/$NAME.otio" <<'PY'
import os, sys
import opentimelineio as otio
tl = otio.adapters.read_from_file(sys.argv[1])
kinds = [t.kind for t in tl.tracks]
urls = [c.media_reference.target_url for c in tl.find_clips()]
print(1 if kinds.count("Video") == 2 and kinds.count("Audio") >= 3 and all(os.path.isabs(u) and os.path.isfile(u) for u in urls) else 0)
PY
)" "tracks: shots + title video, music + sfx + vo audio; every clip an absolute, existing path"

mkdir -p "$FX/o24" && jq '.fps = 24 | .cuts.frames |= map(. * 2) | .size = "320x180"' "$B" >"$FX/o24/build.json"
"$HERE/../scripts/mv-otio" "$FX/o24" >/dev/null 2>&1
ok "$(grep -q 'frameDuration="25/600s"' "$FX/o24/$NAME.fcpxml" 2>/dev/null && echo 1 || echo 0)" ".fcpxml at 24 fps (the adapter has FCP rates only; the 12 fps draft skips it)"

dur=$(jq -r '.seconds' "$B") fps=$(jq -r '.fps' "$B")
nice melt -quiet "$OUT/$NAME.kdenlive" -consumer "avformat:$FX/cut.mp4" vcodec=libx264 acodec=aac real_time=-1 >"$FX/melt.log" 2>&1
got=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FX/cut.mp4" 2>/dev/null)
aud=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$FX/cut.mp4" 2>/dev/null | head -1)
ok "$(awk -v g="${got:-0}" -v d="$dur" -v f="$fps" 'BEGIN{x = g - d; if (x < 0) x = -x; print (x <= 1 / f + 1e-3) ? 1 : 0}')" "melt renders the .kdenlive: ${got:-none} s vs $dur s (+-1 frame at $fps fps)"
ok "$([[ $aud == audio ]] && echo 1 || echo 0)" "melt render has audio"
echo "mv-otio: $((n - bad))/$n"
[[ $bad == 0 ]]
