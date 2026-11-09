#!/usr/bin/env bash
# mv-bad-input.test.sh: bad or short inputs end in one mv-* line and a usage rc, never a traceback or "unbound variable"; fixtures deleted on exit.
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
S=$HERE/../scripts
FX=$(mktemp -d "${TMPDIR:-/tmp}/mv-bad-input-test.XXXXXX")
trap 'rm -rf "$FX"' EXIT
cd "$FX" || exit 1
bad=0 n=0
ok() { n=$((n + 1)); if [[ $1 == 1 ]]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad + 1)); fi; }
# clean <want-rc> <label> <cmd...>: rc matches, stderr names the script and has no traceback or shell error
clean() {
  local want=$1 label=$2 err rc; shift 2
  err=$("$@" 2>&1 >/dev/null </dev/null); rc=$?
  ok "$([[ $rc == "$want" && $err == *mv-* && $err != *Traceback* && $err != *unbound* ]] && echo 1 || echo 0)" "$label (rc $rc)"
}

ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=f=300:d=1:sample_rate=48000" tone.wav
"$S/mv-mix" --out short.wav --duration 1.5 --music tone.wav >/dev/null 2>&1
ok "$([[ -s short.wav ]] && echo 1 || echo 0)" "mv-mix: music bed under 2 s mixes"

echo '{"clips":{"vo":{"words":[{"w":"go","s":59.5,"e":59.6},{"w":"in","s":59.9996,"e":60.1}]}}}' >cues.json
"$S/mv-captions" cues.json vo caps >/dev/null
ok "$(grep -q ':60' caps.ass caps.srt && echo 0 || echo 1)" "mv-captions: no :60 seconds field"
ok "$(grep -q '^Dialogue: 0,0:01:00.00,' caps.ass && grep -q '^00:01:00,000 -->' caps.srt && echo 1 || echo 0)" "mv-captions: 59.9996 s rolls to the next minute"
clean 2 "mv-captions: no cues file" "$S/mv-captions" nope.json vo caps
clean 2 "mv-captions: unknown clip" "$S/mv-captions" cues.json nope caps

mkdir empty
if [[ -x ${MV_OTIO_VENV:-$HOME/.local/opt/mv-otio}/bin/python ]]; then
  clean 2 "mv-otio: no build.json" "$S/mv-otio" empty
else
  echo "SKIP mv-otio: no venv"
fi
if [[ -x ${MV_BEATS_VENV:-$HOME/.local/opt/mv-beats}/bin/python ]]; then
  echo hi >junk.ogg; echo '{}' >e.json
  clean 1 "mv-beats: unreadable audio" "$S/mv-beats" junk.ogg
  clean 2 "mv-beats: json without beats" "$S/mv-beats" e.json --snap 1
else
  echo "SKIP mv-beats: no venv"
fi
for c in new remotion bundle variants bench mc blender clean; do
  out=$("$S/mv-render" $c 2>&1 </dev/null); rc=$?
  ok "$([[ $rc == 2 && $out == usage:* && $out != *unbound* ]] && echo 1 || echo 0)" "mv-render $c without args: usage (rc $rc)"
done

echo "mv-bad-input.test: $((n - bad))/$n passed"
[[ $bad == 0 ]]
