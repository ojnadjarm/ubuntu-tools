#!/usr/bin/env bash
# Gamelyn frame 0 matches the owner-approved pixels; every template renders a non-empty sprite; new-character copies.
set -euo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
for c in gamelyn gakata ojo tier; do
  python3 "$S/scripts/sprite.py" "$S/chars/$c.py" "$T/$c" --frames 0 --cell 240 >/dev/null
done
python3 - "$T" <<'PY'
import sys, hashlib
import numpy as np
from PIL import Image
t = sys.argv[1]
for c in ('gamelyn', 'gakata', 'ojo', 'tier'):
    a = np.array(Image.open(f'{t}/{c}/a00.png'))
    n = int((a[..., 3] > 0).sum()); assert n > 1500, (c, n)
    print(c, 'opaque px', n)
h = hashlib.sha1(np.array(Image.open(f'{t}/gamelyn/a00.png')).tobytes()).hexdigest()[:12]
print('gamelyn a00', h); assert h == '70f6af2b23c5', 'gamelyn drifted from the approved look'
e = np.array(Image.open(f'{t}/gamelyn/e00.png')); assert e.max() > 100, 'blade glow mask missing'
PY
"$S/scripts/new-character" mira knight "$T/new" >/dev/null && test -s "$T/new/mira.py"
echo "selftest ok"
