#!/usr/bin/env bash
# NARRATION_KBPS=default re-renders one clip of a 64/96k sheet (kbps null), as tools/narrate.sh needs for U02/U03 (stubbed Kokoro).
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
(unset NARRATION_KBPS; run) || { echo "FAIL: full 64/96k render crashed"; fail=1; }
: > "$T/ff"; NARRATION_KBPS=default run b; rc=$?
{ [ $rc = 0 ] && grep -q -- '-b:a 64k' "$T/ff" && grep -q -- '-b:a 96k' "$T/ff"; } \
  || { echo "FAIL: NARRATION_KBPS=default on a 64/96k sheet: rc $rc, $(tail -1 "$T/err")"; fail=1; }
kb=$(python3 -c "import json; print(json.load(open('$T/out/cues.json')).get('kbps'))" 2>/dev/null)
[ "$kb" = "None" ] || { echo "FAIL: cues.json kbps=$kb, want null"; fail=1; }
: > "$T/ff"; NARRATION_KBPS=24 run b; rc=$?
{ [ $rc != 0 ] && ! grep -q 'b.m4a' "$T/ff"; } || { echo "FAIL: NARRATION_KBPS=24 against a 64/96k sheet: rc $rc"; fail=1; }
NARRATION_KBPS=24 run || { echo "FAIL: full 24k render crashed"; fail=1; }
: > "$T/ff"; NARRATION_KBPS=default run b; rc=$?
{ [ $rc != 0 ] && ! grep -q 'b.m4a' "$T/ff"; } || { echo "FAIL: NARRATION_KBPS=default against a 24k sheet: rc $rc"; fail=1; }
[ $fail = 0 ] && echo "ok test_kbps_default"; exit $fail
