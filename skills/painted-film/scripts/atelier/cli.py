"""film: the painted-film command line (A1: check; A3: ref)."""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

import cv2

from .metrics import DEFAULT_GATES, gate, lookdist, measure

FRAME = re.compile(r"f_(\d{4})\.png$")
FRAME_EXR = re.compile(r"^f_(\d{4})\.lit\.exr$")
FLICK_KEYS = ("mean", "worst_1s", "floor", "excess", "excess_1s", "broad", "pop", "pop_still", "tile")


def frame_range(d):
    n = sorted(int(m.group(1)) for m in (FRAME.search(p) for p in os.listdir(d)) if m)
    if len(n) < 3:
        sys.exit("film check: fewer than 3 f_NNNN.png frames in %s" % d)
    return n[0], n[-1]


def flow_dir(d, given):
    """The flow comes from the reference pass when the clip has one beside it (ref, else raw), else from the frames."""
    if given:
        return given
    for name in ("ref", "raw"):
        p = os.path.join(os.path.dirname(os.path.abspath(d.rstrip("/"))), name)
        if os.path.isdir(p) and glob.glob(os.path.join(p, "f_*.png")):
            return p
    return d


def decode(mp4, out, first):
    subprocess.run(["ffmpeg", "-v", "error", "-i", mp4, "-pix_fmt", "rgb24", "-start_number", str(first),
                    os.path.join(out, "f_%04d.png")], check=True)


def short(r):
    return " ".join("%s %.4f" % (k, r[k]) for k in FLICK_KEYS if r.get(k) is not None)


def check(a):
    gates, report, failed = DEFAULT_GATES, {"path": os.path.abspath(a.path)}, []
    target = cv2.imread(a.target) if a.target else None
    if a.target and target is None:
        sys.exit("film check: cannot read target %s" % a.target)
    if a.still:
        pics = [a.path] if os.path.isfile(a.path) else sorted(p for p in glob.glob(os.path.join(a.path, "*"))
                                                             if p.lower().endswith((".png", ".jpg", ".jpeg")))
        stills = {os.path.basename(p): cv2.imread(p) for p in pics}
    else:
        first, last = frame_range(a.path)
        fd = flow_dir(a.path, a.flow)
        report.update(flow=os.path.abspath(fd), frames=[first, last])
        with tempfile.TemporaryDirectory(prefix="film-check-") as tmp:
            sources = [a.path]
            if a.mp4:
                decode(a.mp4, tmp, first)
                sources.append(tmp)
            res = measure(sources, first, last, fd, workers=a.jobs)
        report["flick"] = res[0]
        failed += gate(res[0], gates)
        print("frames  %s | motion %.2f px, %d still frames" % (short(res[0]), res[0]["motion"], res[0]["still_frames"]))
        if a.mp4:
            res[1]["encode_added"] = res[1]["mean"] - res[0]["mean"]
            report["mp4"] = dict(res[1], file=os.path.abspath(a.mp4))
            failed += ["mp4." + k for k in gate(res[1], gates)]
            print("mp4     %s | encode_added %.4f" % (short(res[1]), res[1]["encode_added"]))
        mid = (first + last) // 2
        stills = {"f_%04d.png" % mid: cv2.imread(os.path.join(a.path, "f_%04d.png" % mid))} if target is not None else {}
    if target is not None:
        report["look"] = {}
        for name, img in stills.items():
            r = lookdist(img, target)
            report["look"][name] = r
            failed += ["%s.%s" % (name, k) for k in gate(r, gates)]
            print("%s  A1 top3_value %.1f | A2 palette_dist %.2f warm %.1f cool %.1f chroma %.1f | A5 fine %.2f mid %.2f broad %.2f"
                  " | A7 edge_px %.1f empty_tiles %.1f" % (name, r["top3_value"], r["palette_dist"], r["warm"], r["cool"],
                                                           r["chroma_mean"], r["band_fine"], r["band_mid"], r["band_broad"],
                                                           r["edge_px"], r["empty_tiles"]))
    report.update(gates=gates, failed=failed)
    out = os.path.join(a.path if os.path.isdir(a.path) else os.path.dirname(os.path.abspath(a.path)), "check.json")
    with open(out, "w") as fh:
        json.dump(report, fh, indent=1)
    print("failed: %s" % (", ".join(failed) or "none"))
    print("wrote %s" % out)
    return 1 if failed else 0


def ref(a):
    """The reference stage: Blender renders the shot's frames to OUT (thin call; the cache comes in A6)."""
    out = os.path.abspath(a.out)
    expr = "import sys; sys.path.insert(0, %r); from atelier import ref; ref.main()" % os.path.dirname(os.path.dirname(
        os.path.abspath(__file__)))
    cmd = [os.environ.get("FILM_BLENDER", "blender"), "-b", "--factory-startup", "--python-exit-code", "1",
           "--python-expr", expr, "--", os.path.abspath(a.shot), out, "--frames", a.frames]
    cmd += ["--scale", str(a.scale)] if a.scale else []
    cmd += ["--samples", str(a.samples)] if a.samples else []
    cmd += ["--seed-pair"] if a.seed_pair else []
    rc = subprocess.run(cmd).returncode
    if rc or not a.seed_pair:
        return rc
    from . import refio
    for f in sorted(int(m.group(1)) for m in (FRAME_EXR.search(p) for p in os.listdir(os.path.join(out, "seed2"))) if m):
        d = refio.seed_diff(refio.load(os.path.join(out, "f_%04d" % f)), refio.load(os.path.join(out, "seed2", "f_%04d" % f)))
        print("SEED f_%04d seed-pair difference %.4f %% (sigma 2)" % (f, d))
    return rc


def main(argv=None):
    p = argparse.ArgumentParser(prog="film", description="painted-film engine")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="measure a clip (flicker, encode) or stills (look) and gate them; writes check.json")
    c.add_argument("path", metavar="DIR_OR_SHOT", help="folder of f_NNNN.png frames (with --still: stills or one picture)")
    c.add_argument("--target", help="target picture for the look distance")
    c.add_argument("--mp4", help="the encoded file of these frames: its flicker and what the encode adds")
    c.add_argument("--still", action="store_true", help="look measures only, on every picture in the folder")
    c.add_argument("--flow", help="folder the flow is taken from (default: ../ref or ../raw beside the frames, else the frames)")
    c.add_argument("-j", "--jobs", type=int, default=8, help="worker processes (at most 8)")
    r = sub.add_parser("ref", help="render the reference passes of a shot's frames in Blender (EEVEE)")
    r.add_argument("shot", metavar="SHOT", help="folder with shot.json (its \"scene\" module exposes scene())")
    r.add_argument("--out", help="folder for f_NNNN.{lit,albedo,depth,normal,ident}.exr + .json (default: shot.json work/ref)")
    r.add_argument("--frames", default="0", help="frames, e.g. 24-35 or 24,84")
    r.add_argument("--draft", action="store_true", help="half size")
    r.add_argument("--scale", type=float, help="size against the shot's (default: shot.json ref.scale, else 1)")
    r.add_argument("--samples", type=int, help="EEVEE samples (default: shot.json ref.samples, else 24)")
    r.add_argument("--seed-pair", action="store_true", help="also render with the sampling pattern moved against the picture; print the difference")
    a = p.parse_args(argv)
    if a.cmd == "ref":
        if a.draft:
            a.scale = 0.5
        if not a.out:
            with open(os.path.join(a.shot, "shot.json")) as fh:
                a.out = os.path.join(os.path.expanduser(json.load(fh)["work"]), "ref")
        return ref(a)
    a.jobs = max(1, min(8, a.jobs))
    return check(a)


if __name__ == "__main__":
    sys.exit(main())
