"""film: the painted-film command line (A1: check; A3: ref; A6: the cached stages paint, still, encode, sheet)."""
import argparse
import glob
import hashlib
import importlib
import json
import multiprocessing
import os
import re
import subprocess
import sys
import tempfile
import time

import cv2
import numpy as np

from .metrics import DEFAULT_GATES, gate, lookdist, measure

FRAME = re.compile(r"f_(\d{4})\.png$")
FRAME_EXR = re.compile(r"^f_(\d{4})\.lit\.exr$")
ENGINE = os.path.dirname(os.path.abspath(__file__))
LOOKS = os.path.join(ENGINE, "..", "..", "looks")
NOT_REF = ("cli.py", "paint.py", "medium", "metrics")  # engine parts the reference pass does not run
NOT_PAINT = ("cli.py", "metrics")  # engine parts a painted frame does not depend on
MB_PER_WORKER = 3000  # a paint worker holds 2 to 4.5 GB (T2019 lead's note): 4 workers need 12 GB available
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


def frames_of(spec):
    """'144-215' or '24,84' -> the frame numbers."""
    out = []
    for part in spec.split(","):
        lo, _, hi = part.partition("-")
        out += range(int(lo), int(hi or lo) + 1)
    return out


def shot_cfg(shot):
    with open(os.path.join(shot, "shot.json")) as fh:
        return json.load(fh)


def shot_files(shot):
    """What a shot's frames depend on: its shot.json and its Python modules."""
    return [os.path.join(shot, n) for n in sorted(os.listdir(shot)) if n == "shot.json" or n.endswith(".py")]


def engine_files(root=ENGINE, ref_only=False):
    """The engine's code files a stage's output depends on (the reference: only the parts Blender runs; the paint:
    all but the command line and the metrics)."""
    skip, out = NOT_REF if ref_only else NOT_PAINT, []
    for d, dirs, names in os.walk(root):
        dirs[:] = sorted(n for n in dirs if n != "__pycache__" and n not in skip)
        out += [os.path.join(d, n) for n in sorted(names) if n.endswith((".py", ".c")) and n not in skip]
    return out


def digest(paths, *extra):
    """A key of the files' contents and the extra values: equal keys, equal outputs."""
    h = hashlib.sha256(json.dumps(extra).encode())
    for p in paths:
        with open(p, "rb") as fh:
            h.update(b"\0" + os.path.basename(p).encode() + b"\0" + fh.read())
    return h.hexdigest()[:24]


def ref_key(shot, frame, cfg, engine=ENGINE):
    return digest(shot_files(shot) + engine_files(engine, ref_only=True), "ref", frame, cfg)


def paint_key(shot, look, frame, size, ref_dir, engine=ENGINE):
    """Key of a painted frame: shot, look file, engine, frame, size and the key of its reference frame."""
    rk = os.path.join(ref_dir, "f_%04d.key" % frame)
    with open(rk) if os.path.exists(rk) else open(os.devnull) as fh:
        rk = fh.read()
    return digest(shot_files(shot) + [look] + engine_files(engine), "paint", frame, list(size), rk)


def stale(out, keys, ext=".png"):
    """Frames whose output in out is missing or was made from other inputs than keys[frame]."""
    def holds(f):
        p = os.path.join(out, "f_%04d" % f)
        if not (os.path.exists(p + ext) and os.path.exists(p + ".key")):
            return False
        with open(p + ".key") as fh:
            return fh.read() == keys[f]
    return [f for f in sorted(keys) if not holds(f)]


def done(out, frame, key):
    """Write a made frame's key beside it (after the frame itself)."""
    p = os.path.join(out, "f_%04d.key" % frame)
    with open(p + ".part", "w") as fh:
        fh.write(key)
    os.replace(p + ".part", p)


def look_path(name):
    return os.path.abspath(name) if os.path.isfile(name) else os.path.normpath(os.path.join(LOOKS, name + ".json"))


def dirs(a):
    """(reference folder, painted frames folder): <work>[/draft]/ref and <work>[/draft]/<look name>."""
    base = os.path.expanduser(a.work or shot_cfg(a.shot)["work"])
    base = os.path.join(base, "draft") if a.draft else base
    return os.path.join(base, "ref"), os.path.join(base, os.path.splitext(os.path.basename(look_path(a.look)))[0])


def frame_size(cfg, draft):
    W, H = cfg.get("size", (1920, 1080))
    return (W // 2, H // 2) if draft else (W, H)


def pool_size(asked, avail_mb=None):
    """Workers of a pool: at most asked and 4, one per MB_PER_WORKER available (fewer under 12 GB), at least 1."""
    if avail_mb is None:
        with open("/proc/meminfo") as fh:
            avail_mb = next(int(ln.split()[1]) for ln in fh if ln.startswith("MemAvailable:")) // 1024
    return max(1, min(asked, 4, avail_mb // MB_PER_WORKER))


def _worker_init():
    cv2.setNumThreads(1)


def pool(n):
    """n fresh processes, each with one BLAS thread (set before numpy loads in it) and one OpenCV thread."""
    for v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS"):
        os.environ[v] = "1"
    return multiprocessing.get_context("spawn").Pool(n, initializer=_worker_init)


_SCENE = {}


def _paint_job(job):
    shot, look, size, ref_dir, out, f, key = job
    from . import refio
    from .paint import paint_frame
    if "s" not in _SCENE:
        sys.path.insert(0, os.path.abspath(shot))
        _SCENE["s"] = importlib.import_module(shot_cfg(shot).get("scene", "shot")).scene()
    t0 = time.process_time()
    img = paint_frame(_SCENE["s"], refio.load(os.path.join(ref_dir, "f_%04d" % f)), look, size)
    p = os.path.join(out, "f_%04d" % f)
    cv2.imwrite(p + ".part.png", img[..., ::-1])
    os.replace(p + ".part.png", p + ".png")
    done(out, f, key)
    cpu = time.process_time() - t0
    print("PAINT f_%04d CPU-s %.1f" % (f, cpu), flush=True)
    return cpu


def ref(a):
    """The reference stage: Blender renders the shot's stale frames to OUT, each with its key and the lit as a PNG
    (the flow `film check` reads); a frame whose key holds is skipped."""
    out = os.path.abspath(a.out)
    cfg = dict(shot_cfg(a.shot).get("ref", {}))
    cfg.update({k: v for k, v in (("scale", a.scale), ("samples", a.samples)) if v})
    keys = {f: ref_key(a.shot, f, cfg) for f in frames_of(a.frames)}
    todo = sorted(keys) if a.seed_pair else stale(out, keys, ".json")
    print("REF %d of %d frames to render -> %s" % (len(todo), len(keys), out), flush=True)
    if not todo:
        return 0
    expr = "import sys; sys.path.insert(0, %r); from atelier import ref; ref.main()" % os.path.dirname(ENGINE)
    cmd = [os.environ.get("FILM_BLENDER", "blender"), "-b", "--factory-startup", "--python-exit-code", "1",
           "--python-expr", expr, "--", os.path.abspath(a.shot), out, "--frames", ",".join(map(str, todo))]
    cmd += ["--scale", str(a.scale)] if a.scale else []
    cmd += ["--samples", str(a.samples)] if a.samples else []
    cmd += ["--seed-pair"] if a.seed_pair else []
    start = time.time()
    rc = subprocess.run(cmd).returncode
    from . import refio
    for f in todo:
        p = os.path.join(out, "f_%04d" % f)
        if os.path.exists(p + ".json") and os.path.getmtime(p + ".json") >= start:
            lit = refio._rgb(refio.read_exr(p + ".lit.exr"), "RGB")
            cv2.imwrite(p + ".png", (refio.display(lit) * 255 + 0.5).astype(np.uint8)[..., ::-1])
            done(out, f, keys[f])
            with open(p + ".json") as fh:
                print("REF f_%04d render %.2f s" % (f, json.load(fh)["render_s"]), flush=True)
    if rc or not a.seed_pair:
        return rc
    for f in sorted(int(m.group(1)) for m in (FRAME_EXR.search(p) for p in os.listdir(os.path.join(out, "seed2"))) if m):
        d = refio.seed_diff(refio.load(os.path.join(out, "f_%04d" % f)), refio.load(os.path.join(out, "seed2", "f_%04d" % f)))
        print("SEED f_%04d seed-pair difference %.4f %% (sigma 2)" % (f, d))
    return rc


def paint(a):
    """The paint stage: the reference stage first (cached), then each stale frame painted by a pool of workers."""
    cfg = shot_cfg(a.shot)
    ref_dir, out = dirs(a)
    rc = ref(argparse.Namespace(shot=a.shot, out=ref_dir, frames=a.frames, scale=0.5 if a.draft else None, samples=None,
                                seed_pair=False))
    if rc:
        return rc
    lp = look_path(a.look)
    with open(lp) as fh:
        look = json.load(fh)
    size = frame_size(cfg, a.draft)
    keys = {f: paint_key(a.shot, lp, f, size, ref_dir) for f in frames_of(a.frames)}
    todo = stale(out, keys)
    os.makedirs(out, exist_ok=True)
    n = pool_size(min(a.jobs, len(todo))) if todo else 0
    print("PAINT %d of %d frames at %dx%d, look %s, %d workers -> %s" % (len(todo), len(keys), size[0], size[1], lp, n, out),
          flush=True)
    jobs = [(a.shot, look, size, ref_dir, out, f, keys[f]) for f in todo]
    if n > 1:
        with pool(n) as p:
            cpu = list(p.imap_unordered(_paint_job, jobs, chunksize=1))
    else:
        cpu = [_paint_job(j) for j in jobs]
    if cpu:
        print("PAINT CPU-s a frame: median %.1f, max %.1f (%d workers)" % (np.median(cpu), max(cpu), n), flush=True)
    return 0


def still(a):
    """Painted stills of the listed frames (the paint stage), each beside the target with --pair."""
    a.frames = a.which
    rc = paint(a)
    if rc or not a.pair:
        return rc
    target, out = cv2.imread(os.path.expanduser(a.pair)), dirs(a)[1]
    if target is None:
        sys.exit("film still: cannot read %s" % a.pair)
    for f in frames_of(a.which):
        img = cv2.imread(os.path.join(out, "f_%04d.png" % f))
        h = img.shape[0]
        t = cv2.resize(target, (round(target.shape[1] * h / target.shape[0]), h), interpolation=cv2.INTER_AREA)
        cv2.imwrite(os.path.join(out, "pair_%04d.png" % f), cv2.hconcat([img, t]))
        print("STILL %s" % os.path.join(out, "pair_%04d.png" % f))
    return 0


def encode(a):
    """The encode stage: the paint stage first (cached), then the frames in one file with mv-encode's encoder
    settings. The look's "encode" block is the default: preset, crf, grain (temporal luma noise before the encode)."""
    rc = paint(a)
    if rc:
        return rc
    with open(look_path(a.look)) as fh:
        e = dict(json.load(fh).get("encode", {"preset": "av1-10"}))
    e.update({k: v for k, v in (("preset", a.preset), ("crf", a.crf), ("grain", a.grain)) if v is not None})
    args = subprocess.run(["mv-encode", "--codec-args", e["preset"]], capture_output=True, text=True,
                          check=True).stdout.splitlines()
    if e.get("crf") is not None:
        args[args.index("-crf") + 1] = str(e["crf"])
    vf = ["scale=out_color_matrix=bt709:out_range=tv", "format=" + ("yuv420p10le" if e["preset"].endswith("-10") else "yuv420p")]
    vf += ["noise=c0s=%g:c0f=t" % e["grain"]] if e.get("grain") else []
    fs, out = frames_of(a.frames), dirs(a)[1]
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(shot_cfg(a.shot).get("fps", 24)),
           "-start_number", str(fs[0]), "-i", os.path.join(out, "f_%04d.png"), "-frames:v", str(len(fs)),
           "-vf", ",".join(vf)] + args + ["-movflags", "+faststart", os.path.abspath(a.mp4)]
    t0 = time.time()
    rc = subprocess.run(cmd).returncode
    if not rc:
        print("ENCODE %s: %s crf %s grain %s, %d frames, %d bytes, %.1f s" % (a.mp4, e["preset"], e.get("crf"), e.get("grain", 0),
                                                                          len(fs), os.path.getsize(a.mp4), time.time() - t0))
    return rc


def sheet(a):
    """A contact sheet of the painted frames: up to 6 across the range, 3 a row, each with its number."""
    out = dirs(a)[1]
    have = [f for f in frames_of(a.frames) if os.path.exists(os.path.join(out, "f_%04d.png" % f))]
    if not have:
        sys.exit("film sheet: no painted frames in %s" % out)
    pick = sorted({have[round(i * (len(have) - 1) / 5)] for i in range(6)})
    tiles = []
    for f in pick:
        img = cv2.imread(os.path.join(out, "f_%04d.png" % f))
        img = cv2.resize(img, (640, round(640 * img.shape[0] / img.shape[1])), interpolation=cv2.INTER_AREA)
        cv2.putText(img, "f_%04d" % f, (12, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
        tiles.append(img)
    tiles += [np.zeros_like(tiles[0])] * (-len(tiles) % 3)
    path = os.path.join(out, "sheet.png")
    cv2.imwrite(path, cv2.vconcat([cv2.hconcat(tiles[i:i + 3]) for i in range(0, len(tiles), 3)]))
    print("SHEET %s (%s)" % (path, ", ".join("f_%04d" % f for f in pick)))
    return 0


def parser():
    p = argparse.ArgumentParser(prog="film", description="painted-film engine")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="measure a clip (flicker, encode) or stills (look) and gate them; writes check.json")
    c.add_argument("path", metavar="DIR_OR_SHOT", help="folder of f_NNNN.png frames (with --still: stills or one picture)")
    c.add_argument("--target", help="target picture for the look distance")
    c.add_argument("--mp4", help="the encoded file of these frames: its flicker and what the encode adds")
    c.add_argument("--still", action="store_true", help="look measures only, on every picture in the folder")
    c.add_argument("--flow", help="folder the flow is taken from (default: ../ref or ../raw beside the frames, else the frames)")
    c.add_argument("-j", "--jobs", type=int, default=8, help="worker processes (at most 8)")

    def stage(name, help, frames=True):
        s = sub.add_parser(name, help=help)
        s.add_argument("shot", metavar="SHOT", help="folder with shot.json (its \"scene\" module exposes scene())")
        if frames:
            s.add_argument("--frames", default="0", help="frames, e.g. 144-215 or 24,84")
        s.add_argument("--look", default="oil-tight", help="look file, or a look name in the engine's looks/")
        s.add_argument("--draft", action="store_true", help="half size (960x540 for a 1920x1080 shot)")
        s.add_argument("--work", help="work folder (default: shot.json work); frames go to <work>[/draft]/<look name>")
        s.add_argument("-j", "--jobs", type=int, default=4, help="paint workers (at most 4, fewer under 12 GB available)")
        return s

    r = stage("ref", "render the reference passes of a shot's frames in Blender (EEVEE); cached")
    r.add_argument("--out", help="folder for f_NNNN.{lit,albedo,depth,normal,ident}.exr + .json (default: <work>[/draft]/ref)")
    r.add_argument("--scale", type=float, help="size against the shot's (default: shot.json ref.scale, else 1)")
    r.add_argument("--samples", type=int, help="EEVEE samples (default: shot.json ref.samples, else 24)")
    r.add_argument("--seed-pair", action="store_true", help="also render with the sampling pattern moved against the picture; print the difference")
    stage("paint", "reference (cached), then paint the frames to <work>/<look name>/f_NNNN.png; cached")
    s = stage("still", "paint single frames; with --pair, each beside the target", frames=False)
    s.add_argument("which", metavar="FRAMES", help="frames, e.g. 84,300")
    s.add_argument("--pair", metavar="TARGET", help="target picture to set beside each still (pair_NNNN.png)")
    e = stage("encode", "reference and paint (cached), then encode the frames to one file")
    e.add_argument("mp4", metavar="OUT.mp4")
    e.add_argument("--preset", help="mv-encode preset (default: the look's encode.preset), e.g. av1-10, hevc-10, h264-master")
    e.add_argument("--crf", type=int, help="CRF (default: the look's encode.crf, else the preset's)")
    e.add_argument("--grain", type=float, help="temporal luma noise added before the encode (ffmpeg noise strength)")
    stage("sheet", "contact sheet of the painted frames (sheet.png beside them)")
    return p


def main(argv=None):
    a = parser().parse_args(argv)
    if a.cmd == "ref":
        if a.draft:
            a.scale = 0.5
        a.out = a.out or dirs(a)[0]
        return ref(a)
    if a.cmd != "check":
        return {"paint": paint, "still": still, "encode": encode, "sheet": sheet}[a.cmd](a)
    a.jobs = max(1, min(8, a.jobs))
    return check(a)


if __name__ == "__main__":
    sys.exit(main())
