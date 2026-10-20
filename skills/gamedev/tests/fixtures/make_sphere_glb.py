"""Writes a smooth metal UV sphere glb (radius 0.5, no textures, metallic 1, roughness 0.15) to argv[1]."""
import json, math, struct, sys
R, S = 48, 96
pos, nrm, uv, idx = [], [], [], []
for i in range(R + 1):
    t = math.pi * i / R
    for j in range(S + 1):
        p = 2 * math.pi * j / S
        n = (math.sin(t) * math.cos(p), math.cos(t), math.sin(t) * math.sin(p))
        pos += [c * 0.5 for c in n]; nrm += n; uv += [j / S, i / R]
for i in range(R):
    for j in range(S):
        a, b = i * (S + 1) + j, (i + 1) * (S + 1) + j
        idx += [a, a + 1, b, b, a + 1, b + 1]
blobs = [struct.pack(f"{len(pos)}f", *pos), struct.pack(f"{len(nrm)}f", *nrm), struct.pack(f"{len(uv)}f", *uv), struct.pack(f"{len(idx)}I", *idx)]
views, off = [], 0
for b in blobs:
    views.append({"buffer": 0, "byteOffset": off, "byteLength": len(b)}); off += len(b)
n = len(pos) // 3
acc = [{"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3", "min": [-0.5] * 3, "max": [0.5] * 3},
       {"bufferView": 1, "componentType": 5126, "count": n, "type": "VEC3"},
       {"bufferView": 2, "componentType": 5126, "count": n, "type": "VEC2"},
       {"bufferView": 3, "componentType": 5125, "count": len(idx), "type": "SCALAR"}]
doc = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
       "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
       "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [0.95, 0.93, 0.88, 1], "metallicFactor": 1, "roughnessFactor": 0.15}}],
       "accessors": acc, "bufferViews": views, "buffers": [{"byteLength": off}]}
j = json.dumps(doc).encode(); j += b" " * (-len(j) % 4)
bin_ = b"".join(blobs)
with open(sys.argv[1], "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(bin_)))
    f.write(struct.pack("<II", len(j), 0x4E4F534A) + j + struct.pack("<II", len(bin_), 0x004E4942) + bin_)
