#!/usr/bin/env python3
"""gallery.py DIR [--title T] [--compare OUT...]: DIR/index.html linking every mp4/jpg/png under DIR; --compare first
tiles one frame per shot of each char3d build OUT (one row per look) into DIR/looks-compare.jpg."""
import argparse
import html
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ORDER = ['body', 'face', 'hair-props', 'garments', 'props', 'rig', 'facerig', 'motion', 'secondary',
         'lookdev-render', 'export-docs', 'qa', 'modeling', 'lookdev', 'research']
KINDS = {'.mp4', '.jpg', '.jpeg', '.png'}
CELL_W = 640
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
CSS = """
:root{--bg:#120f1a;--card:#1d1828;--ink:#ece6f6;--dim:#a99cc0;--gold:#d8b24a;--violet:#9b6bff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:clamp(15px,0.35vw + 13px,19px)/1.5 system-ui,sans-serif}
main{width:min(100% - 2*clamp(12px,3vw,48px),2400px);margin:0 auto;padding:clamp(16px,3vw,48px) 0}
h1{font-size:clamp(1.6rem,1.2vw + 1.2rem,2.6rem);margin:0 0 .2em;color:var(--gold)}
h2{font-size:clamp(1.1rem,.6vw + 1rem,1.6rem);margin:2em 0 .6em;border-bottom:1px solid #3a3150;padding-bottom:.3em}
p.lead{color:var(--dim);margin:0}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,clamp(300px,22vw,520px)),1fr));gap:clamp(12px,1.5vw,28px)}
figure{margin:0;background:var(--card);border-radius:10px;overflow:hidden;border:1px solid #2c2440}
figure video,figure img{display:block;width:100%;height:auto;aspect-ratio:16/9;object-fit:contain;background:#000}
figcaption{padding:.6em .8em;display:flex;flex-wrap:wrap;gap:.2em .8em;justify-content:space-between}
figcaption a{color:var(--ink);text-decoration:none;font-weight:600;overflow-wrap:anywhere}
figcaption a:hover{color:var(--violet)}
figcaption span{color:var(--dim);font-size:.85em}
"""


def probe(path):
    """'1920x1080 · 6.0 s' for a video, '1920x1080' for an image, '' when ffprobe cannot read it."""
    cmd = ['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height:format=duration',
           '-of', 'json', str(path)]
    try:
        info = json.loads(subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout)
        s = info['streams'][0]
    except (ValueError, KeyError, IndexError, subprocess.TimeoutExpired):
        return ''
    dur = info.get('format', {}).get('duration')
    return f"{s['width']}x{s['height']}" + (f' · {float(dur):.1f} s' if path.suffix == '.mp4' and dur else '')


def card(root, path):
    rel = html.escape(path.relative_to(root).as_posix(), quote=True)
    meta = ' · '.join(x for x in (probe(path), f'{path.stat().st_size / 1e6:.1f} MB') if x)
    media = (f'<video src="{rel}" controls muted playsinline preload="metadata"></video>' if path.suffix == '.mp4'
             else f'<img src="{rel}" alt="{html.escape(path.stem)}" loading="lazy">')
    return (f'<figure>{media}<figcaption><a href="{rel}">{html.escape(path.name)}</a>'
            f'<span>{meta}</span></figcaption></figure>')


def sections(root):
    files = sorted(p for p in root.rglob('*') if p.is_file() and p.suffix.lower() in KINDS)
    groups = {}
    for p in files:
        rel = p.relative_to(root)
        groups.setdefault(rel.parts[0] if len(rel.parts) > 1 else '', []).append(p)
    rank = {name: i for i, name in enumerate(ORDER)}
    return sorted(groups.items(), key=lambda kv: (kv[0] != '', rank.get(kv[0], len(ORDER)), kv[0]))


def frame(path, tmp):
    """A still as is, a video's middle frame as a PIL image."""
    if path.suffix != '.mp4':
        return Image.open(path).convert('RGB')
    dur = float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(path)],
                               capture_output=True, text=True).stdout or 0)
    png = Path(tmp) / f'{path.parent.parent.name}_{path.stem}.png'
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-ss', f'{dur / 2:.2f}', '-i', str(path), '-frames:v', '1', str(png)],
                   check=True)
    return Image.open(png).convert('RGB')


def compare(outs, dst):
    """Rows = builds (looks), columns = shots in the first build's order; each cell labelled look / shot."""
    rows = []
    for out in outs:
        b = json.loads((out / 'build.json').read_text())
        rows.append((b['stages'].get('lookdev', {}).get('look', out.name),
                     {sid: Path(r['file']) for sid, r in b['renders'].items() if r.get('file')}))
    shots = list(rows[0][1])
    ch = CELL_W * 9 // 16
    sheet = Image.new('RGB', (CELL_W * len(shots), ch * len(rows)), (18, 15, 26))
    font = ImageFont.truetype(FONT, 22)
    draw = ImageDraw.Draw(sheet)
    with tempfile.TemporaryDirectory() as tmp:
        for y, (look, files) in enumerate(rows):
            for x, sid in enumerate(shots):
                if sid in files:
                    im = frame(files[sid], tmp)
                    im.thumbnail((CELL_W, ch))
                    sheet.paste(im, (x * CELL_W + (CELL_W - im.width) // 2, y * ch + (ch - im.height) // 2))
                draw.text((x * CELL_W + 12, y * ch + 8), f'{look} / {sid}', font=font, fill=(236, 230, 246),
                          stroke_width=3, stroke_fill=(0, 0, 0))
    sheet.save(dst, quality=90)
    print(f'gallery: {len(rows)} looks x {len(shots)} shots -> {dst}')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('dir', type=Path)
    ap.add_argument('--title', default='char3d previews')
    ap.add_argument('--compare', nargs='+', type=Path, metavar='OUT', help='char3d build dirs, one per look')
    a = ap.parse_args()
    root = a.dir.expanduser().resolve()
    if a.compare:
        root.mkdir(parents=True, exist_ok=True)
        compare([p.expanduser().resolve() for p in a.compare], root / 'looks-compare.jpg')
    body, n = [], 0
    for name, files in sections(root):
        body.append(f'<h2>{html.escape(name or "Final renders")} <span>({len(files)})</span></h2>'
                    f'<div class="grid">{"".join(card(root, p) for p in files)}</div>')
        n += len(files)
    page = (f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(a.title)}</title>'
            f'<style>{CSS}</style></head><body><main><h1>{html.escape(a.title)}</h1>'
            f'<p class="lead">{n} files · regenerate: <code>gallery.py {html.escape(a.dir.name)}</code></p>'
            f'{"".join(body)}</main></body></html>\n')
    (root / 'index.html').write_text(page)
    print(f'gallery: {n} files in {len(body)} sections -> {root / "index.html"}')


if __name__ == '__main__':
    main()
