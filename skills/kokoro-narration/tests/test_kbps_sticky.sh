#!/usr/bin/env bash
# A partial re-render must keep the bitrate saved in cues.json, and stop when NARRATION_KBPS contradicts it (stubbed Kokoro).
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub" "$T/bin"
cat > "$T/stub/kokoro.py" <<'PY'
class KPipeline:
    def __init__(self, **k): pass
    def __call__(self, text, **k): return iter(())
PY
cat > "$T/stub/torch.py" <<'PY'
def set_num_threads(n): pass
PY
cat > "$T/stub/numpy.py" <<'PY'
float32 = "f"
def zeros(n, t): return [0.0] * n
def concatenate(xs): return [v for x in xs for v in x]
PY
cat > "$T/stub/soundfile.py" <<'PY'
def write(*a): pass
PY
cat > "$T/bin/ffmpeg" <<'SH'
#!/bin/sh
echo "$*" >> "$FFLOG"
echo 'Parsed_loudnorm {"input_i":"-20","input_tp":"-3","input_lra":"1","input_thresh":"-30","target_offset":"0"}' >&2
SH
chmod +x "$T/bin/ffmpeg"
echo '{"voice":{"voice":"af_heart","speed":1},"clips":[{"id":"a","sentences":[]},{"id":"b","sentences":[]}]}' > "$T/u.json"
run() { FFLOG="$T/ff" PATH="$T/bin:$PATH" PYTHONPATH="$T/stub" python3 "$HERE/render_narration.py" "$T/u.json" "$T/out" "$@" >/dev/null 2>"$T/err"; }
fail=0
NARRATION_KBPS=24 run || { echo "FAIL: full render crashed"; fail=1; }
kb=$(python3 -c "import json; print(json.load(open('$T/out/cues.json')).get('kbps'))" 2>/dev/null)
[ "$kb" = "24" ] || { echo "FAIL: cues.json kbps=$kb, want 24"; fail=1; }
: > "$T/ff"; (unset NARRATION_KBPS; run b) || { echo "FAIL: partial re-render crashed"; fail=1; }
grep -q 'b.m4a' "$T/ff" && ! grep -q -- '-b:a 96k\|-b:a 64k' "$T/ff" && grep -q -- '-b:a 24k' "$T/ff" \
  || { echo "FAIL: partial re-render without NARRATION_KBPS did not reuse 24k: $(grep -o -- '-b:a [0-9]*k' "$T/ff" | tr '\n' ' ')"; fail=1; }
: > "$T/ff"; NARRATION_KBPS=32 run b; rc=$?
{ [ $rc != 0 ] && ! grep -q Traceback "$T/err" && ! grep -q 'b.m4a' "$T/ff"; } \
  || { echo "FAIL: NARRATION_KBPS=32 against a 24k sheet: rc $rc, $(tail -1 "$T/err")"; fail=1; }
[ $fail = 0 ] && echo "ok test_kbps_sticky"; exit $fail
