#!/usr/bin/env bash
# build.sh (film): mv-beats cuts -> 3 Blender plates (GAME set: 3 replay windows of a cpp-vulkan game, its audio as SFX) || Remotion alpha titles (only their visible spans) -> mv-sfx cues + mv-mix -> mv-layout (MV_LAYOUT=0 skips) -> composite + film LUT straight to h264-web 16x9 + 9x16 in one plate decode (MV_MASTER=1: + h264-master step) -> mv-quality -> mv-review; out/build.json + one creative-ci.jsonl line (mvlib.sh mv_finish) -> mv-report (out/<name>-<aspect>.report.html) (MV_EDIT=1: + .edit, out/edit sources for mv-otio). --chain re-runs layout..review on an existing out/. cpu_s = the build's child CPU seconds, steps_cpu the same per timed step; Blender plates run MV_PLATE_JOBS (1) at a time beside the titles; both titles render from one cached mv-render bundle.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
NAME=${NAME:-__NAME__}
DRAFT=0; [[ ${1:-} == --draft ]] && DRAFT=1
CHAIN=0; [[ ${1:-} == --chain ]] && CHAIN=1
GAME=${GAME:-__GAME__} GAME_DB=${GAME_DB:-0}
REPLAY=${REPLAY:-$GAME/input/trailer.json} GAME_BIN=${GAME_BIN:-$GAME/build/dev/game}
SECONDS_TOTAL=${SECONDS_TOTAL:-$([[ $DRAFT == 1 ]] && echo 3 || { [[ -n $GAME ]] && echo 30 || echo 15; })}
FPS=${FPS:-$([[ $DRAFT == 1 ]] && echo 12 || { [[ -n $GAME ]] && echo 60 || echo 24; })}
SIZE=${SIZE:-$([[ $DRAFT == 1 ]] && echo 640x360 || echo 1920x1080)}   # --draft renders Blender at 50 %
SHOTS=(${SHOTS:-orbit crane push})
MUSIC=${MUSIC:-$HOME/.local/share/motion-video/music/ambient-loop.ogg}
TARGET=${TARGET:-web} LUT=${LUT:-film} MIN_VMAF=${MIN_VMAF:-93}
TITLE=${TITLE:-$(jq -r '.name | ascii_upcase' brand.json)} SUBTITLE=${SUBTITLE:-$([[ -n $GAME ]] && echo 'Gameplay trailer' || echo 'A film in three moves')}
SHOT_PY=${SHOT_PY:-$HOME/.claude/skills/motion-video/templates/blender/shot.py}
MAX_PER_CPU=${MAX_PER_CPU:-$([[ $DRAFT == 1 ]] && echo 2 || echo 1)} GATE_WAIT=${GATE_WAIT:-0}
VK_RUN=${VK_RUN:-$HOME/.claude/skills/gamedev/scripts/cpp-vk-run.sh}
MV_PLATE_JOBS=${MV_PLATE_JOBS:-1}   # Blender plates at once: they share the one GPU
MV_DUCK_ON=${MV_DUCK_ON:-}   # mv-mix --duck-on; empty: sfx,game when any SFX/game stem is mixed, else vo
MV_EDIT=${MV_EDIT:-0}   # 1: also write out/edit + build.json .edit for mv-otio
MV_MASTER=${MV_MASTER:-0}   # 1: also keep out/master-<aspect>.mp4 (h264-master), its own timed step
MV_LAYOUT=${MV_LAYOUT:-1}   # 0: skip the mv-layout check of the camera dumps
export MV_X265_PRESET=${MV_X265_PRESET:-medium}   # mv-encode libx265 preset for any hevc/hevc-hdr10 step a project copy adds (slow: 1,239.8 CPU s at 1080p)
BUNDLE=${BUNDLE:-$HOME/.cache/motion-video/bundle-$NAME}
PATH=$(readlink -f "$(dirname "$(readlink -f "$SHOT_PY")")/../../scripts"):$PATH
source "$(dirname "$(readlink -f "$(command -v mv-review)")")/mvlib.sh"
[[ -z $GAME || ( -x $GAME_BIN && -f $REPLAY ) ]] || { echo "build: no game binary $GAME_BIN or replay $REPLAY" >&2; exit 2; }
W=${SIZE%x*} H=${SIZE#*x}
[[ $DRAFT == 1 ]] && W=$((W / 2)) H=$((H / 2))
VW=$(( (H * 9 / 16) / 2 * 2 ))   # 9x16 crop width out of the 16x9 plate
VW9=$((W * 9 / 16 / 2 * 2)) VH9=$W   # 9x16 delivery size: plate width becomes the height

ci-window >/dev/null || { echo "build: CI window, render later" >&2; exit 3; }
busy=$(quiet-gate --max-per-cpu "$MAX_PER_CPU" --wait "$GATE_WAIT") || { echo "build: ${busy#quiet-gate: busy, }, render later" >&2; exit 3; }
if [[ $CHAIN == 1 ]]; then rm -rf out/t out/c; else rm -rf out; fi
mkdir -p out/t out/c
now() { date +%s.%N; }
timed() {   # step wall seconds to out/t/<step>; `times` before and after (no subshell: it would reset them) to out/c/<step>
  local k=$1 t rc=0; shift; t=$(now); times >"out/c/$k"; "$@" || rc=$?; times >>"out/c/$k"
  awk -v a="$t" -v b="$(now)" 'BEGIN{printf "%.1f", b - a}' >"out/t/$k"
  return $rc
}

node_deps() {   # one shared node_modules per package.json hash
  [[ -e node_modules ]] && return
  local cache=$HOME/.cache/motion-video/node_modules-$(sha256sum package.json | cut -c1-12)
  if [[ ! -d $cache/node_modules ]]; then
    mkdir -p "$cache" && cp package.json "$cache/"
    (cd "$cache" && npm install --no-audit --no-fund --loglevel=error) >&2
  fi
  ln -s "$cache/node_modules" node_modules
}

plan_cuts() {   # 3 shot lengths whose cuts sit on downbeats (beats when the piece is under 2 usable bars), whole frames
  mv-beats "$MUSIC" --downbeats --out out/beats.json >/dev/null 2>&1
  python3 -I - out/beats.json "$SECONDS_TOTAL" "$FPS" "${#SHOTS[@]}" >out/cuts.json <<'PY'
import json, sys
b, total, fps, n = json.load(open(sys.argv[1])), float(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
lo = total / (2 * n)
def pick(grid):
    pts = sorted(t for t in grid if lo <= t <= total - lo)
    cuts = []
    for k in range(1, n):
        want = total * k / n
        free = [t for t in pts if not cuts or t - cuts[-1] >= lo]
        if not free:
            return None
        cuts.append(min(free, key=lambda t: abs(t - want)))
    return cuts
for grid in ("downbeats", "beats"):
    cuts = pick([x["t"] for x in b[grid]])
    if cuts:
        break
else:
    grid, cuts = "even", [total * k / n for k in range(1, n)]
frames = [round(t * fps) for t in [0] + cuts] + [round(total * fps)]
print(json.dumps({"grid": grid, "tempo": b.get("tempo"), "cuts": [round(f / fps, 4) for f in frames[1:-1]],
                  "frames": [frames[i + 1] - frames[i] for i in range(n)], "starts": [round(f / fps, 4) for f in frames[:-1]]}))
PY
}

plate() {   # shot index, camera move
  local i=$1 n; n=$(jq ".frames[$i]" out/cuts.json)
  MV_CAMERA=$2 MV_LOOK=filmic MV_DEPTH=16 MV_FPS=$FPS MV_SIZE=$SIZE MV_BRAND=$PWD/brand.json \
    MV_SECONDS=$(awk -v n="$n" -v f="$FPS" 'BEGIN{printf "%.6f", (n + 0.5) / f}') \
    mv-render blender "$SHOT_PY" "out/shot$i" $([[ $DRAFT == 1 ]] && echo --draft) -- --dump-camera "$PWD/out/cam$i.json" >"out/shot$i.log"
}

game_plates() {   # replay pass 1: event ticks + game audio; one window per shot round a pickup/win; pass 2 captures up to the last window
  local run=("$VK_RUN" --no-validate --size "${W}x$H" --timeout 3600) i j f
  "${run[@]}" --frames 1000000 "$GAME_BIN" --replay "$REPLAY" --audio-out out/game.wav >out/game.log
  python3 -I - out/game.log out/cuts.json "$FPS" "$(jq '.ticks | length' "$REPLAY")" >out/windows.json <<'PY'
import json, re, sys
log, c, fps, n = open(sys.argv[1]).read(), json.load(open(sys.argv[2])), int(sys.argv[3]), int(sys.argv[4])
ev = [int(t) for t in re.findall(r"^GAME (?:pickup n=\d+|win t=\S+) tick=(\d+)$", log, re.M)]
k, step = len(c["frames"]), 60 / fps
lens = [round(f * step) for f in c["frames"]]
pick = [ev[round(i * (len(ev) - 1) / max(k - 1, 1))] for i in range(k)] if ev else [n * (i + 0.5) / k for i in range(k)]
starts, end = [], 0
for i, ln in enumerate(lens):
    end = max(0, min(max(int(pick[i] - 0.4 * ln), end), n - sum(lens[i:])))
    starts.append(end)
    end += ln
print(json.dumps({"events": ev, "picked": pick, "starts": starts, "ticks": lens, "end": end,
                  "frames": [[s + round(j * step) for j in range(f)] for s, f in zip(starts, c["frames"])]}))
PY
  mkdir -p out/cap
  "${run[@]}" --frames "$(jq .end out/windows.json)" "$GAME_BIN" --replay "$REPLAY" --capture-every out/cap >out/cap.log
  for i in "${!SHOTS[@]}"; do
    mkdir -p "out/shot$i"; j=0
    for f in $(jq -r ".frames[$i][]" out/windows.json); do
      j=$((j + 1)); ln -s "$PWD/out/cap/$(printf 'frame_%05d.png' "$f")" "out/shot$i/$(printf 'frame_%04d.png' "$j")"
    done
  done
}

plates() {   # MV_PLATE_JOBS Blender plates at a time
  local i
  for i in "${!SHOTS[@]}"; do
    (( $(jobs -rp | wc -l) < MV_PLATE_JOBS )) || wait -n
    timed "plate$i" plate "$i" "${SHOTS[$i]}" &
  done
  wait
}

title() {   # aspect tag, width, height; the out/spans.json frames back to back as alpha PNGs; shared bundle, own process group (Remotion kills its group on exit), CPU GL (the GPU is Blender's)
  setsid -w npx remotion render "$BUNDLE" Title "out/title-$1" --log=error --sequence --image-format=png \
    --frames=0-$(jq '[.[] | .[1] - .[0] + 1] | add - 1' out/spans.json) \
    --width="$2" --height="$3" --concurrency=$([[ $DRAFT == 1 ]] && echo 2 || echo 4) --gl=swangle \
    --props="$(jq -nc --arg t "$TITLE" --arg s "$SUBTITLE" --argjson f "$FPS" --argjson d "$SECONDS_TOTAL" \
      --argjson c "$(jq -c .cuts out/cuts.json)" --argjson sp "$(cat out/spans.json)" '{title: $t, subtitle: $s, fps: $f, seconds: $d, cuts: $c, spans: $sp}')"
}

title_spans() {   # the frames Title.tsx shows: shot 1 (title) and last cut + 0.2 s to the end (lower third)
  jq -c --argjson f "$FPS" --argjson s "$SECONDS_TOTAL" '[[0, (.cuts[0] * $f | round) - 1], [(.cuts[-1] * $f + 0.2 * $f | round), ($s * $f | round) - 1]]' \
    out/cuts.json >out/spans.json
}

sfx() {   # game: its own mix cut to each replay window; film: whoosh centred on each move's fastest frame, hit where it stops; offset by the shot start
  local i d args=()
  [[ -n $GAME ]] && for i in "${!SHOTS[@]}"; do
    d=$(jq ".ticks[$i] / 60" out/windows.json)
    ffmpeg -v error -y -ss "$(jq ".starts[$i] / 60" out/windows.json)" -t "$d" -i out/game.wav \
      -af "afade=t=in:d=0.01,afade=t=out:st=$(awk -v d="$d" 'BEGIN{print d - 0.01}'):d=0.01" "out/game$i.wav"
    args+=(--sfx "out/game$i.wav@$(jq ".starts[$i]" out/cuts.json)@$GAME_DB")
  done
  [[ -z $GAME ]] && for i in "${!SHOTS[@]}"; do
    mv-sfx cues "out/cam$i.json" --out "out/cues$i.json" --fps "$FPS" >/dev/null
    local start; start=$(jq ".starts[$i]" out/cuts.json)
    while IFS=$'\t' read -r kind at dur; do
      if [[ $kind == whoosh ]]; then
        mv-sfx whoosh --dur "$dur" --seed $((i + 1)) --out "out/whoosh$i.wav" >/dev/null
        args+=(--sfx "out/whoosh$i.wav@$(awk -v s="$start" -v t="$at" -v d="$dur" 'BEGIN{x = s + t - d / 2; printf "%.3f", x < 0 ? 0 : x}')@-10")
      else
        [[ -f out/hit.wav ]] || mv-sfx hit --out out/hit.wav >/dev/null
        args+=(--sfx "out/hit.wav@$(awk -v s="$start" -v t="$at" 'BEGIN{printf "%.3f", s + t}')@-12")
      fi
    done < <(jq -r '.events[] | [.kind, .t, (.dur // 0)] | @tsv' "out/cues$i.json")
  done
  local duck=${MV_DUCK_ON:-$( ((${#args[@]})) && echo sfx,game || echo vo)}
  mv-mix --out out/mix.wav --duration "$SECONDS_TOTAL" --music "$MUSIC" --fit bars --target "$TARGET" --duck-on "$duck" "${args[@]}" >out/mix.log
  printf '%s\n' "${args[@]}" | grep -vx -- --sfx >out/sfx.list
}

edit_media() {   # editable sources for mv-otio: graded plates, alpha title, fitted music bed, all kept in out/edit
  mkdir -p out/edit
  local i; for i in "${!SHOTS[@]}"; do
    mv-encode "out/shot$i/frame_%04d.png" "out/edit/shot$i.mp4" --fps "$FPS" --lut "$LUT" --preset h264-master >/dev/null & done
  title_full 16x9 "$W" "$H"
  mv-encode 'out/title-full/%04d.png' out/edit/title-16x9.webm --fps "$FPS" --preset vp9-alpha >/dev/null &
  mv-mix --out out/edit/music.wav --duration "$SECONDS_TOTAL" --music "$MUSIC" --fit bars --target "$TARGET" >/dev/null &
  wait
}

title_full() {   # aspect tag, width, height: full-length out/title-full/%04d.png links, the spans' frames with one transparent frame between them
  local t=(out/title-$1/*.png) a b f src
  read -r a b < <(jq -r '"\(.[0][1] + 1) \(.[1][0])"' out/spans.json)
  mkdir -p out/title-full
  ffmpeg -v error -y -f lavfi -i "color=c=black@0:s=$2x$3,format=rgba" -frames:v 1 out/title-full/blank.png
  for ((f = 0; f < ${#t[@]} + b - a; f++)); do
    if ((f < a)); then src=${t[f]}; elif ((f >= b)); then src=${t[f - b + a]}; else src=out/title-full/blank.png; fi
    ln -s "$PWD/$src" "out/title-full/$(printf %04d "$f").png"
  done
}

composite() {   # plates concat -> 16x9 + centre-cropped 9x16, title spans overlaid at their offsets, film LUT, a soft Y knee, then per aspect h264-web delivery (mv-encode --codec-args) + lossless VMAF reference, AAC mix, one decode
  local in=() fc="" i a b tag lut=$LUT web
  local knee="if(gt(val\\,208)\\,208+23*tanh((val-208)/23)\\,if(lt(val\\,32)\\,32-12*tanh((32-val)/12)\\,val))"   # soft Y shoulder/toe to 20-231: headroom for the h264-web encode's ringing
  [[ -f $lut ]] || lut=$(dirname "$(readlink -f "$(command -v mv-encode)")")/../luts/$LUT.cube
  web=$(mv-encode --codec-args h264-web); mapfile -t web <<<"$web"
  read -r a b < <(jq -r '"\(.[0][1] + 1) \(.[1][0])"' out/spans.json)
  for i in "${!SHOTS[@]}"; do in+=(-framerate "$FPS" -i "out/shot$i/frame_%04d.png"); fc+="[$i:v]"; done
  local k=${#SHOTS[@]} outs=()
  fc+="concat=n=$k:v=1:a=0,scale=$W:$H:flags=lanczos:out_color_matrix=bt709:out_range=tv,format=yuv444p10le,split[a][b];"
  fc+="[b]crop=$VW:$H,scale=$VW9:$VH9:flags=lanczos,setsar=1[v];"
  for i in 0 1; do   # [a] 16x9, [v] 9x16 under title input k+i: span 1 at frame 0, span 2 shifted to its first frame b
    fc+="[$((k + i)):v]scale=out_color_matrix=bt709:out_range=tv,format=yuva444p10le,split[s${i}t][s${i}b];[s${i}t]trim=end_frame=$a[s${i}a];[s${i}b]trim=start_frame=$a,setpts=PTS+$((b - a))/($FPS*TB)[s${i}c];"
    fc+="[$([[ $i == 0 ]] && echo a || echo v)][s${i}a]overlay=format=yuv444p10:eof_action=pass[m$i];[m$i][s${i}c]overlay=format=yuv444p10:eof_action=pass,"
    fc+="lut3d=file='$lut':interp=tetrahedral,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,lutyuv=y=$knee,limiter=min=16:max=235:planes=1,limiter=min=16:max=240:planes=6,"
    fc+="setparams=colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv,split[o$i][r$i];"
    tag=$([[ $i == 0 ]] && echo 16x9 || echo 9x16)
    outs+=(-map "[o$i]" "${web[@]}" -map "$((k + 2)):a:0" -c:a aac -b:a 192k -t "$SECONDS_TOTAL" -movflags +faststart "out/$NAME-$tag.mp4"
      -map "[r$i]" -c:v libx264 -preset ultrafast -qp 0 -t "$SECONDS_TOTAL" "out/ref-$tag.mkv")
  done
  ffmpeg -v error -y "${in[@]}" -framerate "$FPS" -pattern_type glob -i 'out/title-16x9/*.png' -framerate "$FPS" -pattern_type glob -i 'out/title-9x16/*.png' \
    -i out/mix.wav -filter_complex "${fc%;}" "${outs[@]}"
}

layout() {   # mv-layout on both aspects into out/layout.txt; exit 1 on any FAIL, 2 on missing input
  local a rc=0
  : >out/layout.txt
  for a in 16x9 9x16; do mv-layout out --aspect "$a" >>out/layout.txt 2>&1 || rc=$((rc > $? ? rc : $?)); done
  return $rc
}

titles() { mv-render bundle . "$BUNDLE" >/dev/null; timed title_16x9 title 16x9 "$W" "$H" & timed title_9x16 title 9x16 "$VW9" "$VH9" & wait; }
if [[ $CHAIN == 0 ]]; then
  timed beats plan_cuts
  node_deps
  title_spans
  pids=()
  t=$(now)
  if [[ -n $GAME ]]; then timed plates game_plates & pids+=($!)
  else plates & pids+=($!); fi
  titles & pids+=($!)
  for p in "${pids[@]}"; do wait "$p"; done
  awk -v a="$t" -v b="$(now)" 'BEGIN{printf "%.1f", b - a}' >out/t/render_wall
  timed sfx_mix sfx
fi
fails=() aspects=()
if [[ $MV_LAYOUT != 0 ]] && command -v mv-layout >/dev/null && compgen -G 'out/cam[0-9]*.json' >/dev/null; then
  l=0; timed layout layout || l=$?
  [[ $l == 1 ]] && fails+=("mv-layout $(grep -c '^FAIL' out/layout.txt) FAIL (out/layout.txt)")
  [[ $l == 2 ]] && echo "build: mv-layout n/a: $(tail -1 out/layout.txt)" >&2
fi
timed composite composite
[[ $MV_EDIT == 1 ]] && timed edit_media edit_media
for tag in 16x9 9x16; do
  [[ $MV_MASTER == 1 ]] && timed "master_$tag" mv-encode "out/ref-$tag.mkv" "out/master-$tag.mp4" --preset h264-master --audio out/mix.wav >/dev/null
  q=0; timed "quality_$tag" mv-quality "out/ref-$tag.mkv" "out/$NAME-$tag.mp4" --min-vmaf "$MIN_VMAF" --json >"out/quality-$tag.json" || q=$?
  r=0; timed "review_$tag" mv-review "out/$NAME-$tag.mp4" --target "$TARGET" >/dev/null || r=$?
  vmaf=$(jq '.vmaf // null' "out/quality-$tag.json" 2>/dev/null) || vmaf=null
  [[ $q == 0 ]] || fails+=("$tag: vmaf $vmaf < $MIN_VMAF")
  [[ $r == 0 ]] || fails+=("$tag: mv-review $(jq -r '.fails | join(", ")' "out/$NAME-$tag.review.json" 2>/dev/null)")
  aspects+=("$(jq -n --arg a "$tag" --argjson v "$vmaf" --arg r "$([[ $r == 0 ]] && echo PASS || echo FAIL)" \
    --argjson mb "$(stat -c %s "out/$NAME-$tag.mp4")" '{($a): {vmaf: $v, review: $r, mb: (($mb / 1048576 * 100 | round) / 100)}}')")
done
times >out/times.txt   # in this shell: a pipe would run it in a subshell with no children
cpu_s=$(tail -1 out/times.txt | awk '{for (i = 1; i <= 2; i++) {split($i, a, /[ms]/); c += a[1] * 60 + a[2]}} END{printf "%.1f", c}')
steps=$(for f in out/t/*; do printf '%s %s\n' "${f##*/}" "$(cat "$f")"; done | jq -Rn '[inputs | split(" ") | {(.[0]): (.[1] | tonumber)}] | add')
steps_cpu=$(for f in out/c/*; do printf '%s %s\n' "${f##*/}" "$(awk '{for (i = 1; i <= 2; i++) {split($i, a, /[ms]/); c += (NR > 2 ? 1 : -1) * (a[1] * 60 + a[2])}} END{printf "%.1f", c}' "$f")"; done |
  jq -Rn '[inputs | split(" ") | {(.[0]): (.[1] | tonumber)}] | add')
jq -n --arg n "$NAME" --argjson d "$DRAFT" --argjson s "$SECONDS_TOTAL" --argjson f "$FPS" --argjson cpu "$cpu_s" --arg sz "${W}x$H" \
  --argjson cuts "$(cat out/cuts.json)" --argjson steps "$steps" --argjson steps_cpu "$steps_cpu" --argjson asp "$(printf '%s\n' "${aspects[@]}" | jq -s add)" \
  --argjson edit "$([[ $MV_EDIT == 1 ]] || { echo null; exit; }; jq -n --arg o "$PWD/out" --argjson k "${#SHOTS[@]}" --rawfile sfx out/sfx.list '{plates: [range($k) | "\($o)/edit/shot\(.).mp4"],
    title: "\($o)/edit/title-16x9.webm", music: "\($o)/edit/music.wav", vo: null,
    sfx: [$sfx | split("\n")[] | select(. != "") | split("@") | {file: "\($o)/\(.[0] | ltrimstr("out/"))", at: (.[1] | tonumber), db: (.[2] | tonumber)}]}')" \
  '{name: $n, draft: ($d == 1), seconds: $s, fps: $f, size: $sz, cuts: $cuts, steps: $steps, steps_cpu: $steps_cpu, cpu_s: $cpu, aspects: $asp} + if $edit then {edit: $edit} else {} end' >out/build.json
rc=0; mv_finish "$NAME" out/build.json "${fails[@]}" || rc=1
mv-report out >/dev/null
rm -rf out/shot[0-9]* out/cap out/title-* out/ref-*.mkv out/t out/c out/times.txt
[[ $rc == 0 ]] || exit 1
echo "build: PASS $(jq -c '.steps' out/build.json) -> out/build.json"
