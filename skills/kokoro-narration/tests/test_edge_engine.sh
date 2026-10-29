#!/usr/bin/env bash
# --engine edge: words and {cue} marks from edge-tts word boundaries, Alvaro default for Spanish, tail trimmed, no Kokoro load.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
PY=${KOKORO_PY:-$HOME/.local/opt/kokoro/bin/python}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub" "$T/bin"
cat > "$T/stub/kokoro.py" <<'PY'
raise ImportError("kokoro must not load with --engine edge")
PY
cat > "$T/stub/edge_tts.py" <<PY
class Communicate:
    def __init__(self, text, voice, **k):
        open("$T/call", "w").write(f"{voice} {k.get('rate')} {k.get('boundary')}")
        self.words = text.rstrip(".").split()
    async def stream(self):
        yield {"type": "audio", "data": b"mp3"}
        for k, w in enumerate(self.words):
            yield {"type": "WordBoundary", "offset": int((0.1 + k * 0.5) * 1e7), "duration": int(0.4 * 1e7), "text": w}
PY
cat > "$T/bin/ffmpeg" <<'SH'
#!/bin/sh
case "$*" in *f32le*) head -c $((24000 * 4 * 5)) /dev/zero ;; esac
echo 'Parsed_loudnorm {"input_i":"-20","input_tp":"-3","input_lra":"1","input_thresh":"-30","target_offset":"0"}' >&2
SH
chmod +x "$T/bin/ffmpeg"
echo '{"voice":{"voice":"ef_dora","speed":0.95},"clips":[{"id":"a","sentences":["Así {m}llega el {n}correo."]}]}' > "$T/u.json"
PATH="$T/bin:$PATH" PYTHONPATH="$T/stub" "$PY" "$HERE/render_narration.py" --engine edge "$T/u.json" "$T/out" >/dev/null 2>"$T/err"
rc=$?
fail=0
[ $rc = 0 ] || { echo "FAIL: rc $rc: $(tail -3 "$T/err")"; fail=1; }
[ "$(cat "$T/call" 2>/dev/null)" = "es-ES-AlvaroNeural -5% WordBoundary" ] || { echo "FAIL: call '$(cat "$T/call" 2>/dev/null)'"; fail=1; }
got=$("$PY" -c "
import json; c = json.load(open('$T/out/cues.json')); a = c['clips']['a']
print(a['marks']['m'], a['marks']['n'], len(a['words']), a['words'][0]['s'], a['duration'], c['voice']['engine'], c['voice']['voice'])" 2>&1)
# words at 0.15 lead + 0.1 + k*0.5; marks +0.04 bias; audio cut at last end 2.0 + 0.15 tail, then 0.30 gap.
[ "$got" = "0.79 1.79 4 0.25 2.6 edge-tts es-ES-AlvaroNeural" ] || { echo "FAIL: got '$got'"; fail=1; }
[ $fail = 0 ] && echo "ok test_edge_engine"; exit $fail
