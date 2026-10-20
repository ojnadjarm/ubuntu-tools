#!/usr/bin/env bash
# A {cue} mark must land on its word when Kokoro tokenises differently, and fail cleanly with no timed words (stubbed Kokoro).
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub" "$T/bin"
cat > "$T/stub/kokoro.py" <<'PY'
import numpy
class Tok:
    def __init__(self, text, k, timed): self.text, self.start_ts, self.end_ts = text, (k if timed else None), k + 0.5
class Res:
    def __init__(self, toks): self.tokens, self.audio = toks, self
    def numpy(self): return numpy.zeros(24000 * max(len(self.tokens), 1), "f")
class KPipeline:
    def __init__(self, **k): pass
    def __call__(self, text, **k):
        parts = text.replace(".", " .").split() if text.startswith("...") else text[:-1].split() + ["."]
        yield Res([Tok(p, k, not text.startswith("...")) for k, p in enumerate(parts)])
PY
cat > "$T/stub/torch.py" <<'PY'
def set_num_threads(n): pass
PY
cat > "$T/stub/numpy.py" <<'PY'
class A(list):
    def astype(self, t): return self
float32 = "f"
def zeros(n, t): return A([0.0] * n)
def concatenate(xs): return A(v for x in xs for v in x)
PY
cat > "$T/stub/soundfile.py" <<'PY'
def write(*a): pass
PY
cat > "$T/bin/ffmpeg" <<'SH'
#!/bin/sh
echo 'Parsed_loudnorm {"input_i":"-20","input_tp":"-3","input_lra":"1","input_thresh":"-30","target_offset":"0"}' >&2
SH
chmod +x "$T/bin/ffmpeg"
run() { echo "{\"voice\":{\"voice\":\"af_heart\",\"speed\":1},\"clips\":[{\"id\":\"a\",\"sentences\":[\"$1\"]}]}" > "$T/u.json"
        PATH="$T/bin:$PATH" PYTHONPATH="$T/stub" python3 "$HERE/render_narration.py" "$T/u.json" "$T/out" >/dev/null 2>"$T/err"; }
fail=0
run "A well-known {m}U.S. test." || { echo "FAIL: mismatch sentence crashed"; cat "$T/err"; fail=1; }
got=$(python3 -c "import json; print(json.load(open('$T/out/cues.json'))['clips']['a']['marks'].get('m'))" 2>/dev/null)
[ "$got" = "2.19" ] || { echo "FAIL: {m} at $got, want 2.19 (start of U.S.)"; fail=1; }
run "...{m}..."; rc=$?
{ [ $rc != 0 ] && ! grep -q Traceback "$T/err"; } || { echo "FAIL: mark with no timed words: rc $rc, $(tail -1 "$T/err")"; fail=1; }
[ $fail = 0 ] && echo "ok test_mark_alignment"; exit $fail
