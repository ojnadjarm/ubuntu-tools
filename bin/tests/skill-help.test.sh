#!/usr/bin/env bash
# T527: every executable in the motion-video and gamedev skill scripts prints usage on stdout with rc 0 for -h/--help; bad args stay rc 2.
# Heavy tools are stubs first on PATH, so a help flag that falls through fails here instead of running a job.
set -uo pipefail
MV=$HOME/.claude/skills/motion-video/scripts GD=$HOME/.claude/skills/gamedev/scripts
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stubs" "$WORK/tmp" "$WORK/cwd"
printf '#!/bin/sh\necho "${0##*/} $*" >>"%s/calls"\nexit 1\n' "$WORK" >"$WORK/stubs/stub"
chmod +x "$WORK/stubs/stub"
for s in godot godot-mono weston blender curl glslang spirv-val spirv-cross ffmpeg ffprobe npx node npm cmake wine Xvfb; do
  ln -s stub "$WORK/stubs/$s"
done
export PATH="$WORK/stubs:$PATH" TMPDIR="$WORK/tmp" MV_LIBRARY="$WORK/lib"
cd "$WORK/cwd" || exit 1
fail=0 n=0
bad() { echo "FAIL $*"; fail=$((fail + 1)); }

for d in "$MV" "$GD"; do
  for f in "$d"/*; do
    [[ -f $f && -x $f ]] || continue
    for a in -h --help; do
      n=$((n + 1))
      out=$(timeout 20 "$f" "$a" </dev/null 2>/dev/null); rc=$?
      [[ $rc == 0 ]] || { bad "${f##*/} $a rc=$rc"; continue; }
      grep -qi '^usage' <<<"$out" || bad "${f##*/} $a: no usage on stdout"
    done
  done
done
[[ -s $WORK/calls ]] && bad "help reached a tool: $(sort -u "$WORK/calls" | head -3 | tr '\n' ';')"

# Bad args keep rc 2 (scripts whose no-arg run is a real job are left out).
for c in "$GD/asset-pipeline.sh" "$GD/cc0-fetch.sh" "$GD/cpp-vk-run.sh" "$GD/game-ci" "$GD/new-cpp-game" "$GD/shader-check.sh" \
  "$MV/mv-encode" "$MV/mv-mix" "$MV/mv-new" "$MV/mv-render" "$MV/mv-captions" "$MV/mv-review" "$MV/mv-assets bogus"; do
  [[ -x ${c%% *} ]] || continue
  n=$((n + 1))
  timeout 20 $c </dev/null >/dev/null 2>&1; rc=$?
  [[ $rc == 2 ]] || bad "${c##*/} bad args rc=$rc (want 2)"
done

echo "skill-help: $n checks, $fail failed"
[[ $fail == 0 ]]
