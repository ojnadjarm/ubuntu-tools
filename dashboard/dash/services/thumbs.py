"""/thumb/<path>?w=: WebP thumbnails of ~/drop images, cropped to the grid's 16:10 cell, disk-cached by mtime."""
import hashlib, os, urllib.parse
from PIL import Image, ImageOps
from dash.env import HERE
from dash.routes import route
from dash.services import files

CACHE = os.path.join(HERE, "state", "thumbs")
EXTS = (".png", ".jpg", ".jpeg", ".gif", ".webp")
WIDTHS = (160, 320, 640)


def thumb(full, w):
    """(webp bytes, ETag) of full scaled and centre-cropped to w x 10/16 w; generated once per (file, mtime, size, w)."""
    st = os.stat(full)
    etag = '"t%d-%x-%x"' % (w, st.st_mtime_ns, st.st_size)
    out = os.path.join(CACHE, hashlib.sha1((full + etag).encode()).hexdigest() + ".webp")
    try:
        with open(out, "rb") as f:
            return f.read(), etag
    except FileNotFoundError:
        pass
    h = w * 10 // 16
    with Image.open(full) as im:
        im.draft("RGB", (w * 2, h * 2))
        im = ImageOps.exif_transpose(im)
        im = im.convert("RGBA" if im.mode in ("RGBA", "LA", "PA") or "transparency" in im.info else "RGB")
        W, H = im.size
        s = min(W / w, H / h)
        cw, ch = w * s, h * s
        box = ((W - cw) / 2, (H - ch) / 2, (W + cw) / 2, (H + ch) / 2)
        im = im.resize((w, h), Image.LANCZOS, box=box, reducing_gap=2.0)
        os.makedirs(CACHE, exist_ok=True)
        tmp = out + ".%d.tmp" % os.getpid()
        im.save(tmp, "WEBP", quality=80, method=4)
    os.replace(tmp, out)
    with open(out, "rb") as f:
        return f.read(), etag


@route("GET", "/thumb/", prefix=True)
def thumb_route(h, path):
    hit = files.fs_path(path[7:])
    if not hit or not hit[1] or not os.path.isfile(hit[0]) or os.path.splitext(hit[0])[1].lower() not in EXTS:
        return h.send(404, b"not found\n", "text/plain")
    raw = urllib.parse.parse_qs(h.path.partition("?")[2]).get("w", ["320"])[0]
    w = min(WIDTHS, key=lambda x: abs(x - int(raw))) if raw.isdigit() else 320
    try:
        body, etag = thumb(hit[0], w)
    except (OSError, Image.DecompressionBombError, ValueError):
        return h.send(404, b"not found\n", "text/plain")
    h.send(200, body, "image/webp", etag)
