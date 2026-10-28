#!/usr/bin/env bash
# Gamelyn frame 0 matches the owner-approved pixels (hands rework 2026-10-28); every template renders a non-empty sprite; the spectral kobold glows; new-character copies.
set -euo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
for c in gamelyn gakata ojo tier kobold kobold_alzado kobold_espectral; do
  python3 "$S/scripts/sprite.py" "$S/chars/$c.py" "$T/$c" --frames 0 --cell 240 >/dev/null
done
python3 - "$T" <<'PY'
import sys, hashlib
import numpy as np
from PIL import Image
t = sys.argv[1]
for c in ('gamelyn', 'gakata', 'ojo', 'tier', 'kobold', 'kobold_alzado', 'kobold_espectral'):
    a = np.array(Image.open(f'{t}/{c}/a00.png'))
    n = int((a[..., 3] > 0).sum()); assert n > 700, (c, n)
    print(c, 'opaque px', n)
h = hashlib.sha1(np.array(Image.open(f'{t}/gamelyn/a00.png')).tobytes()).hexdigest()[:12]
print('gamelyn a00', h); assert h == 'd254c2bdf49b', 'gamelyn drifted from the approved look'
e = np.array(Image.open(f'{t}/gamelyn/e00.png')); assert e.max() > 100, 'blade glow mask missing'
e = np.array(Image.open(f'{t}/kobold_espectral/e00.png')); assert (e > 20).sum() > 500, 'spectral glow mask missing'
PY
"$S/scripts/new-character" mira knight "$T/new" >/dev/null && test -s "$T/new/mira.py"
"$S/scripts/new-character" kob kobold "$T/new" >/dev/null && test -s "$T/new/kob.py"
echo "selftest ok"
