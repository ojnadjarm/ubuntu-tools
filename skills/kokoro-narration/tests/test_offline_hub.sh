#!/usr/bin/env bash
# Kokoro must load from the local Hugging Face cache: HF_HUB_OFFLINE=1 at import unless the caller set it (stubbed Kokoro).
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub" "$T/bin"
cat > "$T/stub/kokoro.py" <<PY
import os
open("$T/env", "w").write(os.environ.get("HF_HUB_OFFLINE", "unset"))
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
echo '{"voice":{"voice":"af_heart","speed":1},"clips":[{"id":"a","sentences":[]}]}' > "$T/u.json"
run() { PATH="$T/bin:$PATH" PYTHONPATH="$T/stub" python3 "$HERE/render_narration.py" "$T/u.json" "$T/out" >/dev/null 2>&1; }
fail=0
(unset HF_HUB_OFFLINE; run); got=$(cat "$T/env" 2>/dev/null)
[ "$got" = "1" ] || { echo "FAIL: HF_HUB_OFFLINE at kokoro import was '$got', want 1"; fail=1; }
HF_HUB_OFFLINE=0 run; got=$(cat "$T/env" 2>/dev/null)
[ "$got" = "0" ] || { echo "FAIL: caller's HF_HUB_OFFLINE=0 became '$got'"; fail=1; }
[ $fail = 0 ] && echo "ok test_offline_hub"; exit $fail
