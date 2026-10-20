"""glTF 2.0 reader (stdlib only): .glb/.gltf load, strided and normalized accessors, images and codecs, clips, skins, triangles, bounds."""
import base64
import json
import os
import struct

COMPONENTS = {5120: ("b", 127), 5121: ("B", 255), 5122: ("h", 32767), 5123: ("H", 65535), 5125: ("I", 0), 5126: ("f", 0)}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
SLOTS = ("baseColorTexture", "metallicRoughnessTexture", "normalTexture", "occlusionTexture", "emissiveTexture")


def load(path):
    """Returns (gltf json, buffer 0 bytes) of a .glb or .gltf; ValueError when the file is neither."""
    d = open(path, "rb").read()
    if d[:4] == b"glTF":
        if len(d) < 20:
            raise ValueError("truncated glb header")
        n, kind = struct.unpack_from("<I4s", d, 12)
        if kind != b"JSON":
            raise ValueError("first glb chunk is not JSON")
        gltf = json.loads(d[20:20 + n])
        o = 20 + n
        if len(d) >= o + 8 and d[o + 4:o + 8] == b"BIN\0":
            return gltf, d[o + 8:o + 8 + struct.unpack_from("<I", d, o)[0]]
        return gltf, b""
    if d.lstrip()[:1] != b"{":
        raise ValueError("not a glTF (.glb or .gltf)")
    gltf = json.loads(d)
    uri = (gltf.get("buffers") or [{}])[0].get("uri")
    if not uri:
        return gltf, b""
    if uri.startswith("data:"):
        return gltf, base64.b64decode(uri.split(",", 1)[1])
    return gltf, open(os.path.join(os.path.dirname(path), uri), "rb").read()


def accessor(gltf, bin_, i):
    """Rows (tuples) of accessor i, honouring byteStride and normalized integers; sparse accessors are not applied."""
    acc = gltf["accessors"][i]
    fmt, top = COMPONENTS[acc["componentType"]]
    width = WIDTHS[acc["type"]]
    if "bufferView" not in acc:
        return [(0,) * width] * acc["count"]
    view = gltf["bufferViews"][acc["bufferView"]]
    if view.get("buffer", 0) != 0:
        raise ValueError(f"accessor {i}: only buffer 0 is read")
    stride = view.get("byteStride") or struct.calcsize(fmt) * width
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    row = struct.Struct(f"<{width}{fmt}")
    try:
        rows = [row.unpack_from(bin_, base + j * stride) for j in range(acc["count"])]
    except struct.error as e:
        raise ValueError(f"accessor {i}: {e}") from None
    if acc.get("normalized") and top:
        rows = [tuple(max(v / top, -1.0) for v in r) for r in rows]
    return rows


def image_bytes(gltf, bin_, i, base=""):
    """Encoded bytes of image i (bufferView, data: uri, or a uri relative to base)."""
    m = gltf["images"][i]
    if "bufferView" in m:
        v = gltf["bufferViews"][m["bufferView"]]
        o = v.get("byteOffset", 0)
        return bin_[o:o + v["byteLength"]]
    if m["uri"].startswith("data:"):
        return base64.b64decode(m["uri"].split(",", 1)[1])
    return open(os.path.join(base, m["uri"]), "rb").read()


def image_info(data):
    """(codec, width, height) of encoded image bytes; codec is ktx2-etc1s, ktx2-uastc, ktx2, png, jpeg, webp or unknown."""
    if data[:12] == b"\xabKTX 20\xbb\r\n\x1a\n" and len(data) >= 48:
        fmt, w, h = struct.unpack_from("<I4xII", data, 12)
        scheme = struct.unpack_from("<I", data, 44)[0]
        return ("ktx2-etc1s" if scheme == 1 else "ktx2-uastc" if fmt == 0 else "ktx2"), w, h
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
        return ("png",) + struct.unpack_from(">II", data, 16)
    if data[:2] == b"\xff\xd8":
        o = 2
        while o + 9 <= len(data) and data[o] == 0xFF:
            mk, n = data[o + 1], struct.unpack_from(">H", data, o + 2)[0]
            if 0xC0 <= mk <= 0xCF and mk not in (0xC4, 0xC8, 0xCC):
                h, w = struct.unpack_from(">HH", data, o + 5)
                return "jpeg", w, h
            o += 2 + n
        return "jpeg", None, None
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp", None, None
    return "unknown", None, None


def images(gltf, bin_, base=""):
    """One dict per image: index, name, codec, bytes, width, height (codec missing when its file cannot be read)."""
    out = []
    for i, m in enumerate(gltf.get("images", [])):
        try:
            data = image_bytes(gltf, bin_, i, base)
        except OSError:
            out.append({"index": i, "name": m.get("name", ""), "codec": "missing", "bytes": 0, "width": None, "height": None})
            continue
        codec, w, h = image_info(data)
        out.append({"index": i, "name": m.get("name") or m.get("uri", ""), "codec": codec, "bytes": len(data), "width": w, "height": h})
    return out


def texture_source(gltf, t):
    """Image index of texture t, through KHR_texture_basisu / EXT_texture_webp / EXT_texture_avif when present."""
    tex = gltf["textures"][t]
    ext = tex.get("extensions", {})
    for name in ("KHR_texture_basisu", "EXT_texture_webp", "EXT_texture_avif"):
        if "source" in ext.get(name, {}):
            return ext[name]["source"]
    return tex.get("source")


def material_textures(gltf, m):
    """{slot: image index} of material dict m over the core PBR texture slots."""
    refs = {**m, **m.get("pbrMetallicRoughness", {})}
    return {s: texture_source(gltf, refs[s]["index"]) for s in SLOTS if s in refs}


def clips(gltf, bin_):
    """One dict per animation: name, start s, length s, channels [{node, path, interpolation, times, values}]."""
    out = []
    for k, anim in enumerate(gltf.get("animations", [])):
        inputs = {}

        def times(a):
            if a not in inputs:
                inputs[a] = [r[0] for r in accessor(gltf, bin_, a)]
            return inputs[a]
        ends = [t for s in anim["samplers"] if times(s["input"]) for t in (times(s["input"])[0], times(s["input"])[-1])]
        chans = []
        for ch in anim["channels"]:
            s = anim["samplers"][ch["sampler"]]
            chans.append({"node": ch["target"].get("node"), "path": ch["target"].get("path"), "interpolation": s.get("interpolation", "LINEAR"),
                          "times": times(s["input"]), "values": accessor(gltf, bin_, s["output"])})
        start = min(ends) if ends else 0.0
        out.append({"name": anim.get("name") or f"clip{k}", "start": start, "length": (max(ends) - start) if ends else 0.0, "channels": chans})
    return out


def skins(gltf):
    """One dict per skin: name, joints (node indices), joint_names, skeleton."""
    nodes = gltf.get("nodes", [])
    return [{"name": s.get("name") or f"skin{k}", "joints": s["joints"], "skeleton": s.get("skeleton"),
             "joint_names": [nodes[j].get("name", f"node{j}") for j in s["joints"]]} for k, s in enumerate(gltf.get("skins", []))]


def tri_count(gltf, prim=None):
    """Triangles of one primitive (TRIANGLES, STRIP, FAN), or of every mesh primitive once when prim is None."""
    if prim is None:
        return sum(tri_count(gltf, p) for m in gltf.get("meshes", []) for p in m["primitives"])
    a = prim.get("indices", prim.get("attributes", {}).get("POSITION"))
    n = gltf["accessors"][a]["count"] if a is not None else 0
    mode = prim.get("mode", 4)
    return n // 3 if mode == 4 else max(n - 2, 0) if mode in (5, 6) else 0


def node_matrix(nd):
    """Row-major 4x4 local matrix of a glTF node (matrix, or translation x rotation x scale)."""
    if "matrix" in nd:
        m = nd["matrix"]
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    x, y, z, w = nd.get("rotation", [0, 0, 0, 1])
    t, sc = nd.get("translation", [0, 0, 0]), nd.get("scale", [1, 1, 1])
    rot = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
           [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
           [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[rot[r][c] * sc[c] for c in range(3)] + [t[r]] for r in range(3)] + [[0, 0, 0, 1]]


def node_matrices(gltf):
    """{node index: row-major 4x4 world matrix} at rest."""
    nodes = gltf.get("nodes", [])
    parent = {c: i for i, nd in enumerate(nodes) for c in nd.get("children", [])}
    world = {}

    def of(i):
        if i not in world:
            m = node_matrix(nodes[i])
            if i in parent:
                p = of(parent[i])
                m = [[sum(p[r][j] * m[j][c] for j in range(4)) for c in range(4)] for r in range(4)]
            world[i] = m
        return world[i]
    return {i: of(i) for i in range(len(nodes))}


def bounds(gltf, bin_):
    """(min xyz, max xyz) of every mesh node's POSITION box at rest in world space, None without meshes."""
    world, pts = node_matrices(gltf), []
    for i, nd in enumerate(gltf.get("nodes", [])):
        if "mesh" not in nd:
            continue
        for p in gltf["meshes"][nd["mesh"]]["primitives"]:
            a = p.get("attributes", {}).get("POSITION")
            if a is None:
                continue
            acc = gltf["accessors"][a]
            lo, hi = acc.get("min"), acc.get("max")
            if lo is None or hi is None:
                rows = accessor(gltf, bin_, a)
                lo, hi = [min(r[k] for r in rows) for k in range(3)], [max(r[k] for r in rows) for k in range(3)]
            m = world[i]
            for c in ((x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])):
                pts.append([sum(m[r][k] * c[k] for k in range(3)) + m[r][3] for r in range(3)])
    if not pts:
        return None
    return [min(p[k] for p in pts) for k in range(3)], [max(p[k] for p in pts) for k in range(3)]
