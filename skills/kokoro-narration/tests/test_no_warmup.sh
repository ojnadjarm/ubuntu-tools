#!/usr/bin/env bash
# Kokoro must synthesise only the unit's sentences: no throwaway warm-up call (stubbed Kokoro).
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub" "$T/bin"
cat > "$T/stub/kokoro.py" <<PY
class KPipeline:
    def __init__(self, **k): pass
    def __call__(self, text, **k):
        open("$T/calls", "a").write(text + "\n")
        return iter(())
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
echo '{"voice":{"voice":"af_heart","speed":1},"clips":[{"id":"a","sentences":["Hello there."]}]}' > "$T/u.json"
PATH="$T/bin:$PATH" PYTHONPATH="$T/stub" python3 "$HERE/render_narration.py" "$T/u.json" "$T/out" >/dev/null 2>&1
if [ "$(cat "$T/calls" 2>/dev/null)" = "Hello there." ]; then echo "ok test_no_warmup"; exit 0; fi
echo "FAIL: Kokoro calls were: $(tr '\n' '|' < "$T/calls" 2>/dev/null)"; exit 1
