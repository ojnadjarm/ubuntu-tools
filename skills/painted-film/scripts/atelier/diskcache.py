"""Disk cache of what no frame changes (seed banks, the brush bank): made once per key, read back by later frames,
workers and runs. numpy only: runs in Blender too."""
import hashlib
import os
import shutil

import numpy as np


def key(*parts):
    """A hash of arrays (dtype, shape, bytes), bytes and other values (repr)."""
    h = hashlib.sha256()
    for p in parts:
        h.update(b"\0")
        if isinstance(p, np.ndarray):
            h.update(b"%s%s" % (str(p.dtype).encode(), str(p.shape).encode()))
            p = np.ascontiguousarray(p).view(np.uint8)  # hashed in place, no copy
        h.update(p if isinstance(p, (bytes, np.ndarray)) else repr(p).encode())
    return h.hexdigest()[:24]


def get(folder, name, make):
    """make() -> {name: array or number}, read from folder/name/ when there, else made and written there; arrays come
    back mapped read-only (pages read when touched, shared by the workers), numbers as Python numbers. folder None:
    made, nothing written."""
    if folder is None:
        return make()
    path = os.path.join(folder, name)
    if os.path.isdir(path):
        out = {}
        for n in sorted(os.listdir(path)):
            a = np.load(os.path.join(path, n), mmap_mode="r")
            out[n[:-4]] = a.item() if a.ndim == 0 else a
        return out
    out = make()
    tmp = "%s.%d" % (path, os.getpid())
    os.makedirs(tmp, exist_ok=True)
    for k, v in out.items():
        np.save(os.path.join(tmp, k + ".npy"), np.asarray(v))
    try:
        os.rename(tmp, path)
    except OSError:  # another worker wrote it first: the same arrays
        shutil.rmtree(tmp)
    return out
