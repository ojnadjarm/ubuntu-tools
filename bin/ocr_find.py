"""OCR a PNG with tesseract (binarized, both polarities) and locate fuzzy text matches."""
import json as _json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from difflib import SequenceMatcher

import numpy as np
from PIL import Image

SCALE = 2
THRESHOLD = 150
MINCONF = 30
RATIO = 0.85
BLOCK = 8
MAX_GLYPHS = 150

img, query, want_all, want_json, region = sys.argv[1:6]
ox, oy = (int(region.split(',')[0]), int(region.split(',')[1])) if region else (0, 0)
DASHES = str.maketrans({c: '-' for c in '—–―‒−_'})


def norm(s):
    """Canonicalise a string so OCR's dash and underscore confusions match the real glyph."""
    return s.lower().translate(DASHES).replace('=', '--')


def tess(path, psm):
    """Run tesseract on an image file and return its raw TSV output."""
    return subprocess.run(['tesseract', path, 'stdout', '--psm', psm, '-l', 'eng', 'tsv'],
                          capture_output=True, text=True, timeout=30).stdout


def ocr(job):
    """OCR one whole image and return (text, x, y, w, h, conf, line-key) rows."""
    im, psm = job
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
        im.save(f.name)
        try:
            out = tess(f.name, psm)
        finally:
            os.unlink(f.name)
    rows = []
    for line in out.splitlines()[1:]:
        c = line.split('\t')
        if len(c) < 12 or not c[11].strip():
            continue
        try:
            conf = float(c[10])
        except ValueError:
            continue
        if conf >= MINCONF:
            rows.append((c[11].strip(), int(c[6]), int(c[7]), int(c[8]), int(c[9]), conf,
                         (psm, int(c[2]), int(c[3]), int(c[4]))))
    return rows


def clusters(im):
    """Bounding boxes of small isolated ink clusters in a binarized image."""
    a = np.asarray(im) == 0
    h, w = a.shape
    a = a[:h // BLOCK * BLOCK, :w // BLOCK * BLOCK]
    a = a.reshape(h // BLOCK, BLOCK, w // BLOCK, BLOCK).any(axis=(1, 3))
    seen = np.zeros(a.shape, bool)
    boxes = []
    for sy, sx in zip(*np.nonzero(a)):
        if seen[sy, sx]:
            continue
        stack = [(sy, sx)]
        seen[sy, sx] = True
        y0 = y1 = sy
        x0 = x1 = sx
        while stack:
            y, x = stack.pop()
            y0, y1, x0, x1 = min(y0, y), max(y1, y), min(x0, x), max(x1, x)
            for ny in range(max(0, y - 1), min(a.shape[0], y + 2)):
                for nx in range(max(0, x - 1), min(a.shape[1], x + 2)):
                    if a[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        bw, bh = (x1 - x0 + 1) * BLOCK, (y1 - y0 + 1) * BLOCK
        if 6 <= bw <= 90 and 6 <= bh <= 70:
            boxes.append((int(x0) * BLOCK, int(y0) * BLOCK, (int(x1) + 1) * BLOCK, (int(y1) + 1) * BLOCK))
    return boxes[:MAX_GLYPHS]


def glyph(job):
    """OCR one isolated cluster in single-line mode; returns a row or None."""
    im, box, psm = job
    pad = 12
    crop = im.crop((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad))
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
        crop.save(f.name)
        try:
            out = tess(f.name, psm)
        finally:
            os.unlink(f.name)
    for line in out.splitlines()[1:]:
        c = line.split('\t')
        if len(c) >= 12 and c[11].strip():
            try:
                conf = float(c[10])
            except ValueError:
                continue
            if conf >= MINCONF:
                return (c[11].strip(), box[0], box[1], box[2] - box[0], box[3] - box[1], conf,
                        ('g', box[0], box[1], 0))
    return None


def match(rows, q, nq):
    """Fuzzy-match OCR rows against the query and return deduplicated centres."""
    lines = {}
    for t, x, y, w, h, conf, key in rows:
        lines.setdefault(key, []).append((x, t, x, y, w, h, conf))
    cands = []
    for ws in lines.values():
        ws.sort()
        for i in range(len(ws)):
            for n in range(1, nq + 1):
                grp = ws[i:i + n]
                if len(grp) < n:
                    break
                r = SequenceMatcher(None, norm(' '.join(g[1] for g in grp)), q).ratio()
                if r < RATIO:
                    continue
                x0 = min(g[2] for g in grp)
                y0 = min(g[3] for g in grp)
                x1 = max(g[2] + g[4] for g in grp)
                y1 = max(g[3] + g[5] for g in grp)
                cands.append((r, sum(g[6] for g in grp) / len(grp),
                              ' '.join(g[1] for g in grp),
                              ox + (x0 + x1) // 2 // SCALE, oy + (y0 + y1) // 2 // SCALE,
                              ox + x0 // SCALE, oy + y0 // SCALE,
                              (x1 - x0) // SCALE, (y1 - y0) // SCALE))
    seen, uniq = [], []
    # ratio, then coarse confidence, then glyph area: a button label beats a smaller look-alike icon.
    for c in sorted(cands, key=lambda c: (-c[0], -round(c[1] / 5), -c[7] * c[8])):
        if any(abs(c[3] - s[0]) < 12 and abs(c[4] - s[1]) < 12 for s in seen):
            continue
        seen.append((c[3], c[4]))
        uniq.append(c)
    return uniq


base = Image.open(img).convert('L')
big = base.resize((base.width * SCALE, base.height * SCALE), Image.LANCZOS)
light = big.point(lambda p: 0 if p > THRESHOLD else 255)
dark = big.point(lambda p: 255 if p > THRESHOLD else 0)
q = norm(query)
nq = max(1, len(q.split()))

# the plain upscaled greyscale catches what binarizing distorts (document text: "alpha" -> "aloha")
with ThreadPoolExecutor(5) as ex:
    rows = [r for b in ex.map(ocr, [(light, '6'), (light, '11'), (dark, '6'), (dark, '11'), (big, '6')]) for r in b]
if len(query) <= 3:
    psm = '10' if len(query) == 1 else '7'
    jobs = [(im, b, psm) for im in (light, dark) for b in clusters(im)]
    with ThreadPoolExecutor(8) as ex:
        rows += [r for r in ex.map(glyph, jobs) if r]
uniq = match(rows, q, nq)

if not uniq:
    sys.exit(1)
out = uniq if want_all == '1' else uniq[:1]
if want_json == '1':
    print(_json.dumps([{'text': c[2], 'ratio': round(c[0], 3), 'conf': round(c[1], 1),
                        'x': c[3], 'y': c[4], 'box': [c[5], c[6], c[7], c[8]]} for c in out]))
else:
    for c in out:
        print(c[3], c[4])
