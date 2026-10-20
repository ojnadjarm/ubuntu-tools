#!/usr/bin/env bash
# A failing loudnorm probe must stop with ffmpeg's own error, not a ValueError traceback (stubbed Kokoro).
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
echo 'a.wav: Invalid data found when processing input' >&2
exit 183
SH
chmod +x "$T/bin/ffmpeg"
echo '{"voice":{"voice":"af_heart","speed":1},"clips":[{"id":"a","sentences":[]}]}' > "$T/u.json"
PATH="$T/bin:$PATH" PYTHONPATH="$T/stub" python3 "$HERE/render_narration.py" "$T/u.json" "$T/out" >/dev/null 2>"$T/err"; rc=$?
fail=0
{ [ $rc != 0 ] && ! grep -q Traceback "$T/err" && grep -q 'Invalid data found' "$T/err"; } \
  || { echo "FAIL: failed probe: rc $rc, $(tail -1 "$T/err")"; fail=1; }
[ $fail = 0 ] && echo "ok test_master_probe"; exit $fail
