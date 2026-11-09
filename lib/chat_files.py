"""Chat attachments (T1515-P33): store a file under the chat store, type from its bytes, images without metadata, a
seat's own copy."""
import io
import json
import os
import re
import secrets
import shutil

import chat_store

MAX_BYTES = 10 << 20
MAX_FILES = 5
THUMB_PX = 640
FID = re.compile(r"^[0-9a-f]{16}$")
IMAGES = ((b"\x89PNG\r\n\x1a\n", "image/png"), (b"\xff\xd8\xff", "image/jpeg"), (b"GIF87a", "image/gif"),
          (b"GIF89a", "image/gif"))
MAGIC = ((b"%PDF-", "application/pdf"), (b"PK\x03\x04", "application/zip"))
FORMAT = {"image/png": "PNG", "image/jpeg": "JPEG", "image/webp": "WEBP"}


def sniff(data):
    """The MIME type from the first bytes: PNG/JPEG/GIF/WebP, PDF, ZIP, UTF-8 text, else application/octet-stream."""
    for magic, mime in IMAGES + MAGIC:
        if data.startswith(magic):
            return mime
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    head = data[:4096]
    if b"\x00" not in head:
        try:
            head.decode("utf-8")
            return "text/plain"
        except UnicodeDecodeError as e:
            if e.start >= len(head) - 3:
                return "text/plain"
    return "application/octet-stream"


def clean_name(name):
    """A display name: the last path part, no control characters, at most 120 characters; 'file' when empty."""
    base = re.sub(r"[\x00-\x1f\x7f]", "", os.path.basename(str(name).replace("\\", "/"))).strip()
    return base[:120] or "file"


def _folder():
    return os.path.join(chat_store.root(), "files")


def path(fid, thumb=False):
    """The stored file of id fid (thumb: its WebP thumbnail); ValueError on a bad id."""
    if not isinstance(fid, str) or not FID.match(fid):
        raise ValueError(f"bad file id: {fid!r}")
    return os.path.join(_folder(), fid + (".thumb.webp" if thumb else ""))


def meta(fid):
    """{id, name, size, mime} of a stored file; ValueError when there is none."""
    try:
        with open(path(fid) + ".json") as f:
            return json.load(f)
    except OSError:
        raise ValueError(f"no file {fid}") from None


def _image(data, mime):
    """(bytes without EXIF/XMP/text metadata, upright, ICC kept; WebP thumbnail) of an image; None when it does not decode.
    A GIF keeps its bytes: the format has no EXIF."""
    from PIL import Image, ImageOps
    try:
        with Image.open(io.BytesIO(data)) as im:
            im.load()
            icc, out = im.info.get("icc_profile"), io.BytesIO()
            if mime == "image/gif":
                clean, first = data, im
            elif getattr(im, "n_frames", 1) > 1:
                im.save(out, "WEBP", save_all=True, quality=90, icc_profile=icc)
                clean, first = out.getvalue(), im
            else:
                first = ImageOps.exif_transpose(im)
                first.info.pop("exif", None)
                if mime == "image/jpeg" and first.mode not in ("RGB", "L", "CMYK"):
                    first = first.convert("RGB")
                first.save(out, FORMAT[mime], icc_profile=icc, **({} if mime == "image/png" else {"quality": 92}))
                clean = out.getvalue()
            small = first.convert("RGBA" if first.mode in ("RGBA", "LA", "PA", "P") else "RGB")
            small.thumbnail((THUMB_PX, THUMB_PX))
            thumb = io.BytesIO()
            small.save(thumb, "WEBP", quality=80)
            return clean, thumb.getvalue()
    except Exception:
        return None


def _write(p, data):
    tmp = f"{p}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    os.replace(tmp, p)


def save(data, name):
    """Store bytes under the name; {id, name, size, mime}. Images are stored without metadata, with a thumbnail; an
    image that does not decode is kept as application/octet-stream. ValueError when empty or over MAX_BYTES."""
    if not data:
        raise ValueError("empty file")
    if len(data) > MAX_BYTES:
        raise ValueError(f"file over {MAX_BYTES >> 20} MiB: {len(data)} bytes")
    mime, thumb = sniff(data), None
    if mime.startswith("image/"):
        got = _image(data, mime)
        if got:
            data, thumb = got
        else:
            mime = "application/octet-stream"
    os.makedirs(_folder(), mode=0o700, exist_ok=True)
    fid = secrets.token_hex(8)
    m = {"id": fid, "name": clean_name(name), "size": len(data), "mime": mime}
    _write(path(fid), data)
    if thumb:
        _write(path(fid, thumb=True), thumb)
    _write(path(fid) + ".json", json.dumps(m).encode())
    return m


def drop(fid):
    """Delete a stored file that no message will carry (its post was held or refused)."""
    for p in (path(fid), path(fid, thumb=True), path(fid) + ".json"):
        try:
            os.remove(p)
        except FileNotFoundError:
            pass


def seat_dir(seat):
    """The seat's own folder for received files: po-<seat>/state/chat-files when the PO folder exists, else the
    store's seats/<seat>/files."""
    home = os.path.dirname(os.path.dirname(chat_store.root()))
    po = os.path.join(home, f"po-{chat_store._name(seat, 'seat')}")
    return os.path.join(po, "state", "chat-files") if os.path.isdir(po) else os.path.join(chat_store.root(), "seats",
                                                                                            seat, "files")


def give(seat, m):
    """The local path of the seat's own copy of attachment m (copied on first use), named <id>-<safe name>."""
    folder = seat_dir(seat)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", m["name"]).lstrip(".") or "file"
    dest = os.path.join(folder, f"{m['id']}-{safe}")
    if not os.path.exists(dest):
        tmp = f"{dest}.{os.getpid()}.tmp"
        shutil.copyfile(path(m["id"]), tmp)
        os.replace(tmp, dest)
    return dest


def lines(seat, files):
    """One `file: <path> (<mime>, <size> bytes)` line per attachment, each copied for the seat; `file: <name> (missing)`
    when the store lost it."""
    out = []
    for f in files or ():
        try:
            out.append(f"file: {give(seat, f)} ({f['mime']}, {f['size']} bytes)")
        except OSError:
            out.append(f"file: {f['name']} (missing)")
    return out
