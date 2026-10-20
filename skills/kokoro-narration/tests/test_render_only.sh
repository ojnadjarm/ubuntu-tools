#!/usr/bin/env bash
# Re-rendering selected clips must work with no cues.json and with a clip missing from it (stubbed Kokoro).
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
echo 'Parsed_loudnorm {"input_i":"-20","input_tp":"-3","input_lra":"1","input_thresh":"-30","target_offset":"0"}' >&2
SH
chmod +x "$T/bin/ffmpeg"
echo '{"voice":{"voice":"af_heart","speed":1},"clips":[{"id":"a","sentences":[]},{"id":"b","sentences":[]}]}' > "$T/u.json"
run() { PATH="$T/bin:$PATH" PYTHONPATH="$T/stub" python3 "$HERE/render_narration.py" "$T/u.json" "$T/out" "$@" >/dev/null; }
fail=0
check() { python3 -c "import json,sys; c=json.load(open('$T/out/cues.json'))['clips']; sys.exit(0 if set(c)=={'a','b'} else 1)" || { echo "FAIL: $1"; fail=1; }; }
run b || { echo "FAIL: no cues.json crashed"; fail=1; }; check "no cues.json"
echo '{"clips":{"b":{"src":"audio/b"}}}' > "$T/out/cues.json"
run b || { echo "FAIL: clip missing from cues.json crashed"; fail=1; }; check "clip missing from cues.json"
[ $fail = 0 ] && echo "ok test_render_only"; exit $fail
