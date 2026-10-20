"""Decodes every KTX2 image of a gltfpack output glb, compares it with the source image and prints ASSET QUALITY lines (PSNR, normal-map angle p95, codec, bytes) plus FAIL lines over the gates."""
import argparse
import io
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
import glb  # noqa: E402

SLOTS = {"normalTexture": "normal", "baseColorTexture": "color", "emissiveTexture": "color",
         "metallicRoughnessTexture": "orm", "occlusionTexture": "orm"}
MIN_PSNR = {("color", "etc1s"): 31, ("color", "uastc"): 38, ("orm", "etc1s"): 33, ("orm", "uastc"): 33}


def load_glb(path):
    """Returns (json, buffer 0) of a glb or .gltf, or None when the file is neither."""
    try:
        return glb.load(path)
    except ValueError:
        return None


def slots(g):
    """Maps (material key, slot) to (class, image index); the key is the material name, else its index."""
    out = {}
    for mi, m in enumerate(g.get("materials", [])):
        tex = glb.material_textures(g, m)
        for slot, cls in SLOTS.items():
            if slot in tex:
                out[(m.get("name") or str(mi), slot)] = (cls, tex[slot])
    return out


def decode_ktx(data, ktx, tmp):
    """Transcodes KTX2 bytes to an RGB float array in [0, 1] with `ktx extract`."""
    k, p = os.path.join(tmp, "i.ktx2"), os.path.join(tmp, "i.png")
    open(k, "wb").write(data)
    subprocess.run([ktx, "extract", "--transcode", "rgba8", k, p], check=True, capture_output=True)
    return np.asarray(Image.open(p).convert("RGB"), np.float64) / 255


def metrics(src, dec, cls):
    """Returns PSNR in dB over RGB and, for normal maps, the p95 angular error in degrees."""
    mse = np.mean((src - dec) ** 2)
    psnr = 99.0 if mse == 0 else 10 * np.log10(1 / mse)
    if cls != "normal":
        return psnr, None
    a, b = src * 2 - 1, dec * 2 - 1
    a /= np.maximum(np.linalg.norm(a, axis=-1, keepdims=True), 1e-6)
    b /= np.maximum(np.linalg.norm(b, axis=-1, keepdims=True), 1e-6)
    ang = np.degrees(np.arccos(np.clip(np.sum(a * b, -1), -1, 1)))
    return psnr, float(np.percentile(ang, 95))


def min_psnr(a, cls, codec):
    """Returns the PSNR floor for a class and codec: its --min-psnr-CLASS, else --min-psnr, else MIN_PSNR."""
    for v in (getattr(a, f"min_psnr_{cls}"), a.min_psnr):
        if v is not None:
            return v
    return MIN_PSNR[(cls, codec)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("label")
    ap.add_argument("--etc1s", help="the same LOD packed all-ETC1S, for the byte cost")
    ap.add_argument("--ktx", default="ktx")
    ap.add_argument("--min-psnr", type=float, help="PSNR floor for every class (default: MIN_PSNR per class and codec)")
    ap.add_argument("--min-psnr-color", type=float)
    ap.add_argument("--min-psnr-orm", type=float)
    ap.add_argument("--max-normal-angle", type=float, default=5)
    a = ap.parse_args()
    src, out = load_glb(a.src), load_glb(a.out)
    if not src or not out:
        return
    ref = load_glb(a.etc1s) if a.etc1s else None
    s_map, r_map = slots(src[0]), slots(ref[0]) if ref else {}
    seen = set()
    with tempfile.TemporaryDirectory() as tmp:
        for key, (cls, oi) in slots(out[0]).items():
            if oi in seen or key not in s_map or out[0]["images"][oi].get("mimeType") != "image/ktx2":
                continue
            seen.add(oi)
            data = glb.image_bytes(*out, oi)
            codec = "etc1s" if glb.image_info(data)[0] == "ktx2-etc1s" else "uastc"
            tag = f"ASSET QUALITY {a.label} {cls} image={oi}"
            try:
                dec = decode_ktx(data, a.ktx, tmp)
                s = Image.open(io.BytesIO(glb.image_bytes(*src, s_map[key][1], os.path.dirname(a.src)))).convert("RGB")
            except (subprocess.CalledProcessError, OSError) as e:
                print(f"ASSET QUALITY FAIL {a.label} {cls} image={oi}: cannot decode ({type(e).__name__})")
                continue
            if s.size != (dec.shape[1], dec.shape[0]):
                s = s.resize((dec.shape[1], dec.shape[0]), Image.BILINEAR)
            psnr, angle = metrics(np.asarray(s, np.float64) / 255, dec, cls)
            cost = f" etc1s_bytes={len(glb.image_bytes(*ref, r_map[key][1]))}" if key in r_map else ""
            gate = f"max_angle={a.max_normal_angle:g}" if angle is not None else f"min_psnr={min_psnr(a, cls, codec):g}"
            print(f"{tag} psnr={psnr:.1f}" + (f" angle_p95={angle:.2f}" if angle is not None else "") + f" codec={codec} bytes={len(data)}{cost} {gate}")
            if angle is not None and angle > a.max_normal_angle:
                print(f"ASSET QUALITY FAIL {a.label} {cls} image={oi} angle_p95={angle:.2f} > {a.max_normal_angle:g}")
            if angle is None and psnr < min_psnr(a, cls, codec):
                print(f"ASSET QUALITY FAIL {a.label} {cls} image={oi} psnr={psnr:.1f} < {min_psnr(a, cls, codec):g}")


main()
