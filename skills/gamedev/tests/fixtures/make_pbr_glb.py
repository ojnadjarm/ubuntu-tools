"""Writes a PBR UV sphere glb (base colour, normal, ORM PNGs; no tangents) to argv[1]; --no-base-color drops the base colour map."""
import io
import json
import struct
import sys

import numpy as np
from PIL import Image

N = 256
out, no_base = sys.argv[1], "--no-base-color" in sys.argv[2:]


def png(a):
    b = io.BytesIO()
    Image.fromarray(a).save(b, "PNG", optimize=True)
    return b.getvalue()


def u8(a):
    return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)


y, x = np.mgrid[0:N, 0:N].astype(np.float32) / N
tile = ((x * 8).astype(int) + (y * 4).astype(int)) % 2
color = np.stack([0.75 - 0.4 * tile, 0.45 + 0.1 * tile, 0.25 + 0.5 * tile * y], -1)
cx, cy = (x * 16) % 1 - 0.5, (y * 8) % 1 - 0.5
h = np.exp(-(cx * cx + cy * cy) / 0.02)
gy, gx = np.gradient(h * 4)
n = np.stack([-gx, -gy, np.ones_like(h)], -1)
n /= np.linalg.norm(n, axis=-1, keepdims=True)
orm = np.stack([1 - 0.5 * h, 0.2 + 0.7 * (1 - tile), tile.astype(np.float32)], -1)
maps = {"base": u8(color), "normal": u8(n * 0.5 + 0.5), "orm": u8(orm)}
if no_base:
    del maps["base"]

rings, segs = 24, 48
v, u = np.mgrid[0:rings + 1, 0:segs + 1].astype(np.float32)
theta, phi = v / rings * np.pi, u / segs * 2 * np.pi
nrm = np.stack([np.sin(theta) * np.cos(phi), np.cos(theta), -np.sin(theta) * np.sin(phi)], -1).reshape(-1, 3)
pos = nrm.copy()
uv = np.stack([u / segs, v / rings], -1).reshape(-1, 2)
idx = []
for r in range(rings):
    for s in range(segs):
        a, b = r * (segs + 1) + s, (r + 1) * (segs + 1) + s
        idx += [a, b, a + 1, a + 1, b, b + 1]
idx = np.array(idx, np.uint16)

blobs = [pos.astype(np.float32).tobytes(), nrm.astype(np.float32).tobytes(), uv.astype(np.float32).tobytes(),
         idx.tobytes(), *[png(m) for m in maps.values()]]
views, off = [], 0
for i, b in enumerate(blobs):
    views.append({"buffer": 0, "byteOffset": off, "byteLength": len(b)})
    blobs[i] = b + b"\0" * (-len(b) % 4)
    off += len(blobs[i])
for vw in views[:3]:
    vw["target"] = 34962
views[3]["target"] = 34963
count = len(pos)
acc = [
    {"bufferView": 0, "componentType": 5126, "count": count, "type": "VEC3", "min": [-1, -1, -1], "max": [1, 1, 1]},
    {"bufferView": 1, "componentType": 5126, "count": count, "type": "VEC3"},
    {"bufferView": 2, "componentType": 5126, "count": count, "type": "VEC2"},
    {"bufferView": 3, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
]
slot = {k: i for i, k in enumerate(maps)}
pbr = {"metallicFactor": 1, "roughnessFactor": 1}
if "base" in slot:
    pbr["baseColorTexture"] = {"index": slot["base"]}
else:
    pbr["baseColorFactor"] = [0.2, 0.5, 0.8, 1]
pbr["metallicRoughnessTexture"] = {"index": slot["orm"]}
material = {"name": "Studded", "pbrMetallicRoughness": pbr, "normalTexture": {"index": slot["normal"]},
            "occlusionTexture": {"index": slot["orm"]}}
bin_ = b"".join(blobs)
g = {
    "asset": {"version": "2.0", "generator": "make_pbr_glb.py"},
    "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "Sphere"}],
    "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
    "materials": [material],
    "textures": [{"source": i} for i in range(len(maps))],
    "images": [{"bufferView": 4 + i, "mimeType": "image/png"} for i in range(len(maps))],
    "accessors": acc, "bufferViews": views, "buffers": [{"byteLength": len(bin_)}],
}
js = json.dumps(g, separators=(",", ":")).encode()
js += b" " * (-len(js) % 4)
with open(out, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(bin_)))
    f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    f.write(struct.pack("<II", len(bin_), 0x004E4942) + bin_)
