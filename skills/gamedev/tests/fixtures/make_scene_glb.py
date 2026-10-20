"""Writes a 3-material glb to argv[1]: unit boxes at x = -2, 0, 2 (child nodes of a root), each with its own solid PNG base colour; argv[2:] are the three colours as r,g,b in 0..255."""
import io
import json
import struct
import sys

import numpy as np
from PIL import Image

out = sys.argv[1]
colors = [tuple(int(c) for c in a.split(",")) for a in sys.argv[2:5]]


def png(rgb):
    b = io.BytesIO()
    Image.new("RGB", (4, 4), rgb).save(b, "PNG")
    return b.getvalue()


pos, nrm, uv, idx = [], [], [], []
for axis in range(3):
    for sign in (1.0, -1.0):
        n = np.zeros(3, np.float32)
        n[axis] = sign
        u = np.roll(n, 1)
        v = np.cross(n, u)
        base = len(pos)
        for cu, cv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            pos.append(0.5 * (n + cu * u + cv * v))
            nrm.append(n)
            uv.append(((cu + 1) / 2, (1 - cv) / 2))
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
pos, nrm, uv = (np.array(a, np.float32) for a in (pos, nrm, uv))
idx = np.array(idx, np.uint16)

blobs = [pos.tobytes(), nrm.tobytes(), uv.tobytes(), idx.tobytes(), *[png(c) for c in colors]]
views, off = [], 0
for i, b in enumerate(blobs):
    views.append({"buffer": 0, "byteOffset": off, "byteLength": len(b)})
    blobs[i] = b + b"\0" * (-len(b) % 4)
    off += len(blobs[i])
for vw in views[:3]:
    vw["target"] = 34962
views[3]["target"] = 34963
attrs = {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}
gltf = {
    "asset": {"version": "2.0"},
    "scene": 0,
    "scenes": [{"nodes": [0]}],
    "nodes": [{"children": [1, 2, 3]}] + [{"mesh": i, "translation": [2.0 * (i - 1), 0, 0]} for i in range(3)],
    "meshes": [{"primitives": [{"attributes": attrs, "indices": 3, "material": i}]} for i in range(3)],
    "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": i}, "metallicFactor": 0.0, "roughnessFactor": 1.0}}
                  for i in range(3)],
    "textures": [{"source": i} for i in range(3)],
    "images": [{"bufferView": 4 + i, "mimeType": "image/png"} for i in range(3)],
    "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3",
         "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
        {"bufferView": 1, "componentType": 5126, "count": len(pos), "type": "VEC3"},
        {"bufferView": 2, "componentType": 5126, "count": len(pos), "type": "VEC2"},
        {"bufferView": 3, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
    ],
    "bufferViews": views,
    "buffers": [{"byteLength": off}],
}
js = json.dumps(gltf).encode()
js += b" " * (-len(js) % 4)
bin_ = b"".join(blobs)
with open(out, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_)))
    f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    f.write(struct.pack("<II", len(bin_), 0x004E4942) + bin_)
