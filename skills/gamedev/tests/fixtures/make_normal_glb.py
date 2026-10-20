"""Writes a normal-mapped quad glb (argv[2] px, default 256, base colour + rivet/ripple normal map) to argv[1]; regenerates tests/fixtures/assets/normal-mapped.glb and normal-mapped-128.glb."""
import io
import json
import struct
import sys

import numpy as np
from PIL import Image

N = int(sys.argv[2]) if len(sys.argv) > 2 else 256


def png(a):
    b = io.BytesIO()
    Image.fromarray(a).save(b, "PNG", optimize=True)
    return b.getvalue()


y, x = np.mgrid[0:N, 0:N].astype(np.float32) / N
color = np.stack([0.55 + 0.35 * x, 0.45 + 0.3 * y, 0.35 + 0.2 * (1 - x) * y], -1)
cx, cy = (x * N / 32) % 1 - 0.5, (y * N / 32) % 1 - 0.5
dome = np.exp(-(cx * cx + cy * cy) / 0.03)
h = dome + 0.02 * np.sin(x * 2 * np.pi * N / 32) * np.sin(y * 2 * np.pi * N * 3 / 128)
gy, gx = np.gradient(h * 6)
n = np.stack([-gx, -gy, np.ones_like(h)], -1)
n /= np.linalg.norm(n, axis=-1, keepdims=True)
images = [png((color * 255 + 0.5).astype(np.uint8)), png(((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8))]

pos = np.array([[-1, 0, 1], [1, 0, 1], [1, 0, -1], [-1, 0, -1]], np.float32)
nrm = np.tile(np.array([0, 1, 0], np.float32), (4, 1))
tan = np.tile(np.array([1, 0, 0, 1], np.float32), (4, 1))
uv = np.array([[0, 1], [1, 1], [1, 0], [0, 0]], np.float32)
idx = np.array([0, 1, 2, 0, 2, 3], np.uint16)
blobs = [pos.tobytes(), nrm.tobytes(), tan.tobytes(), uv.tobytes(), idx.tobytes() + b"\0\0", *images]
views, off = [], 0
for i, b in enumerate(blobs):
    views.append({"buffer": 0, "byteOffset": off, "byteLength": len(b) - (2 if i == 4 else 0)})
    off += (len(b) + 3) & ~3
    blobs[i] = b + b"\0" * (-len(b) % 4)
acc = [
    {"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [-1, 0, -1], "max": [1, 0, 1]},
    {"bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC3"},
    {"bufferView": 2, "componentType": 5126, "count": 4, "type": "VEC4"},
    {"bufferView": 3, "componentType": 5126, "count": 4, "type": "VEC2"},
    {"bufferView": 4, "componentType": 5123, "count": 6, "type": "SCALAR"},
]
for v in views[:4]:
    v["target"] = 34962
views[4]["target"] = 34963
bin_ = b"".join(blobs)
g = {
    "asset": {"version": "2.0", "generator": "make_normal_glb.py"},
    "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "Plate"}],
    "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TANGENT": 2, "TEXCOORD_0": 3}, "indices": 4, "material": 0}]}],
    "materials": [{"name": "Riveted", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0}, "normalTexture": {"index": 1}}],
    "textures": [{"source": 0}, {"source": 1}],
    "images": [{"bufferView": 5, "mimeType": "image/png"}, {"bufferView": 6, "mimeType": "image/png"}],
    "accessors": acc, "bufferViews": views, "buffers": [{"byteLength": len(bin_)}],
}
js = json.dumps(g, separators=(",", ":")).encode()
js += b" " * (-len(js) % 4)
with open(sys.argv[1], "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(bin_)))
    f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    f.write(struct.pack("<II", len(bin_), 0x004E4942) + bin_)
