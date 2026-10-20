#!/usr/bin/env bash
# build.sh: [Kokoro VO] -> render each aspect -> mix + captions -> graded h264 master -> mv-review -> out/build.json + one creative-ci.jsonl line; exit 1 on a review FAIL.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
KIND=__KIND__ NAME=${NAME:-__NAME__} COMP=${COMP:-__COMP__}
LUT=${LUT:-film} VO_AT=${VO_AT:-1.0} PRESET=${PRESET:-h264-master}
MUSIC=${MUSIC:-$HOME/.local/share/motion-video/music/ambient-loop.ogg}
ASPECTS=${ASPECTS:-"16x9:1920:1080 9x16:1080:1920"}
SFX=(${SFX:-})   # "file@sec[@db] file@cue:NAME[+ms][@db] ..." passed to mv-mix
KOKORO_PY=${KOKORO_PY:-$HOME/.local/opt/kokoro/bin/python}
source "$(dirname "$(readlink -f "$(command -v mv-review)")")/mvlib.sh"
mkdir -p out
now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN{printf "%.1f", b - a}'; }
results=() failed=()

if [[ -f vo.unit.json && ! -f vo/cues.json ]]; then
  "$KOKORO_PY" "$HOME/.claude/skills/kokoro-narration/render_narration.py" vo.unit.json vo 2>&1 | tail -1
  rm -rf vo.raw
fi
busy=$(quiet-gate --max-per-cpu 1) || { echo "build: ${busy#quiet-gate: busy, }, render later" >&2; exit 3; }

for a in $ASPECTS; do
  IFS=: read -r tag w h <<<"$a"
  raw=$PWD/out/raw-$tag.mp4
  t=$(now)
  if [[ $KIND == explainer ]]; then
    MV_SIZE=${w}x$h mv-render mc . "$raw"
  else
    mv-render remotion . "$COMP" "$raw" -- --width="$w" --height="$h" --crf=10
  fi
  render_s=$(since "$t") mix_s=0
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$raw")
  mix=() enc=()
  [[ -f vo/cues.json ]] && mix+=(--vo vo/audio/vo.m4a --vo-at "$VO_AT" --cues vo/cues.json)
  [[ -n $MUSIC ]] && mix+=(--music "$MUSIC")
  for s in "${SFX[@]}"; do mix+=(--sfx "$s"); done
  if [[ ${#mix[@]} -gt 0 ]]; then
    t=$(now)
    mv-mix --out out/mix-$tag.wav --duration "$dur" "${mix[@]}"
    enc+=(--audio out/mix-$tag.wav)
    mix_s=$(since "$t")
  fi
  if [[ -f vo/cues.json ]]; then
    mv-captions vo/cues.json vo out/caps-$tag --offset "$VO_AT" --size "${w}x$h"
    enc+=(--burn out/caps-$tag.ass --subs out/caps-$tag.srt)
  fi
  [[ -n $LUT ]] && enc+=(--lut "$LUT")
  t=$(now)
  mv-encode "$raw" "out/$NAME-$tag.mp4" --preset "$PRESET" "${enc[@]}"
  encode_s=$(since "$t")
  rm -f "$raw" out/mix-$tag.wav
  rc=0; mv-review "out/$NAME-$tag.mp4" || rc=$?
  reasons=$(jq -c '.fails' "out/$NAME-$tag.review.json" 2>/dev/null) || reasons=null
  if [[ $rc != 0 ]]; then
    [[ $reasons == null || $reasons == '[]' ]] && reasons="[\"mv-review exit $rc\"]"
    failed+=("$tag: $(jq -r 'join(", ")' <<<"$reasons")")
    review=FAIL
  else
    review=PASS
  fi
  results+=("$(jq -n --arg a "$tag" --argjson r "$render_s" --argjson m "$mix_s" --argjson e "$encode_s" --arg v "$review" \
    --argjson why "$reasons" '{($a): {render_s: $r, mix_s: $m, encode_s: $e, review: $v, reasons: $why}}')")
done
printf '%s\n' "${results[@]}" | jq -s 'add' >out/build.json
mv_finish "$NAME" out/build.json "${failed[@]}" || exit 1
echo "build: PASS $(jq -r 'del(.review, .fails) | keys | join(" ")' out/build.json) -> out/build.json"
