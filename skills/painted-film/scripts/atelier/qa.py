"""film qa: judge a change on fixed frames, close-ups and 1 s loops in seconds (Q1 of T2051); every check prints its seconds."""
import argparse
import contextlib
import hashlib
import json
import os
import subprocess
import sys
import time

import cv2
import numpy as np

from . import cli
from .metrics.flick import flows, grey, resid

TOL = 2.0  # of 255: a pixel whose difference after the 1 px blur is over this has changed
BORDER = 16  # px: a window's border, where the canvas finish reads past the window
BAND = 24  # px: a sheet cell's label band
GOLDEN = os.path.expanduser("~/agent-work/motion/golden")


@contextlib.contextmanager
def timed(check):
    t0 = time.time()
    yield
    print("QA %s %.1f s" % (check, time.time() - t0), flush=True)


def diff(a, b):
    """(map, share): each pixel's largest channel difference after a 1 px blur (of 255), and the share of pixels over TOL."""
    blur = lambda v: cv2.GaussianBlur(v.astype(np.float32), (0, 0), 1.0)  # noqa: E731
    d = np.abs(blur(a) - blur(b)).max(2)
    return d, float((d > TOL).mean())


def box(dmap):
    """(x0, y0, x1, y1), inclusive, around every changed pixel; None when none changed."""
    ys, xs = np.nonzero(dmap > TOL)
    return None if not len(xs) else (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))


def marked(img, b):
    """The picture with the box drawn in red."""
    out = np.ascontiguousarray(img).copy()
    if b is not None:
        t = max(2, img.shape[1] // 320)
        cv2.rectangle(out, (b[0] - t, b[1] - t), (b[2] + t, b[3] + t), (255, 40, 40), t)
    return out


def heat(dmap, b=None):
    """The difference map as a picture (8 of 255 is full scale), the box drawn."""
    return marked(cv2.applyColorMap(np.clip(dmap * 32, 0, 255).astype(np.uint8), cv2.COLORMAP_INFERNO)[..., ::-1], b)


def sheet(cells, labels, path, cols=4, title=None):
    """RGB cells on a grid, cols a row, each at the first cell's width (480 px at most) with its label above it (a None
    cell is left blank); the title on top."""
    cw = min(next(c for c in cells if c is not None).shape[1], 480)
    cells = [c if c is None or c.shape[1] == cw else
             cv2.resize(c, (cw, round(c.shape[0] * cw / c.shape[1])), interpolation=cv2.INTER_AREA) for c in cells]
    ch = max(c.shape[0] for c in cells if c is not None)
    tiles = []
    for c, text in zip(cells, labels):
        t = np.zeros((ch + BAND, cw, 3), np.uint8)
        if c is not None:
            t[:BAND] = 40
            t[BAND:BAND + c.shape[0]] = c
            cv2.putText(t, text, (4, BAND - 7), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
        tiles.append(t)
    tiles += [np.zeros_like(tiles[0])] * (-len(tiles) % cols)
    img = cv2.vconcat([cv2.hconcat(tiles[i:i + cols]) for i in range(0, len(tiles), cols)])
    if title:
        head = np.full((2 * BAND, img.shape[1], 3), 20, np.uint8)
        cv2.putText(head, title, (6, 2 * BAND - 14), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 1, cv2.LINE_AA)
        img = cv2.vconcat([head, img])
    cv2.imwrite(path, img[..., ::-1], [cv2.IMWRITE_JPEG_QUALITY, 92])
    return img


def flickmap(frames, flow, sigma=2.0):
    """Where consecutive RGB frames flicker: the mean of what is left of each after warping its neighbours onto it
    (metrics.flick's measure), the flow from the BGR reference frames; a picture, 8 of 255 at full scale."""
    acc = 0.0
    for i in range(1, len(frames) - 1):
        fb, ff, ok, grid = flows([grey(flow[i + k].astype(np.float32)) for k in (-1, 0, 1)])
        r = resid([frames[i + k].astype(np.float32) for k in (-1, 0, 1)], fb, ff, grid, sigma)
        acc = acc + np.abs(r).mean(2) * ok
    m = acc / (len(frames) - 2)
    print("QA flicker mean %.4f %% of full scale" % (m.mean() / 2.55), flush=True)
    return heat(m)


def with_key(look, key, value):
    """The look with one key (dotted path, e.g. mark.width) set; the look itself untouched."""
    out = dict(look)
    d, parts = out, key.split(".")
    for p in parts[:-1]:
        d[p] = dict(d.get(p, {}))
        d = d[p]
    d[parts[-1]] = value
    return out


def label(key, v):
    return "%s=%s" % (key, json.dumps(v))


def pair(render, golden_dir, frames, loupes, base_look, look, size, loupe_size, out):
    """The golden pair: the frames (at size) and the loupes {name: (frame, window)} (at loupe_size) painted now
    against the golden ones in golden_dir (painted with base_look first when missing); one row a picture: name,
    share, box. Writes the pictures and pair.jpg (golden, now with the box, the difference) to out."""
    names = ["f_%04d" % f for f in frames] + list(loupes)
    files = ["f_%04d.png" % f for f in frames] + ["loupe_%s.png" % n for n in loupes]
    jobs = [(f, size, None) for f in frames] + [(f, loupe_size, tuple(w)) for f, w in loupes.values()]
    os.makedirs(out, exist_ok=True)
    with timed("pair"):
        missing = [i for i, n in enumerate(files) if not os.path.exists(os.path.join(golden_dir, n))]
        if missing:
            with timed("golden"):
                os.makedirs(golden_dir, exist_ok=True)
                for i, img in zip(missing, render([(jobs[i][0], base_look, *jobs[i][1:]) for i in missing])):
                    cv2.imwrite(os.path.join(golden_dir, files[i]), img[..., ::-1])
            print("QA golden %s (%d pictures)" % (golden_dir, len(missing)), flush=True)
        gold = [cv2.imread(os.path.join(golden_dir, n))[..., ::-1] for n in files]
        now = render([(f, look, *j) for f, *j in jobs])
        rows, cells, labels = [], [], []
        for n, f, g, p in zip(names, files, gold, now):
            cv2.imwrite(os.path.join(out, f), p[..., ::-1])
            dmap, share = diff(g, p)
            b = box(dmap)
            rows.append({"name": n, "share": share, "box": b})
            print("QA pair %s share %.4f %% box %s" % (n, 100 * share, b), flush=True)
        cols = max(len(frames), len(loupes), 1)
        for block in (slice(0, len(frames)), slice(len(frames), len(names))):  # the frames, then the loupes
            part = list(zip(rows[block], gold[block], now[block]))
            if not part:
                continue
            pad = [None] * (cols - len(part))
            cells += [g for _, g, _ in part] + pad + [marked(p, r["box"]) for r, _, p in part] + pad
            cells += [heat(diff(g, p)[0], r["box"]) for r, g, p in part] + pad
            labels += ["golden " + r["name"] for r, _, _ in part] + pad + ["now " + r["name"] for r, _, _ in part] + pad
            labels += ["change %s %.3f %%" % (r["name"], 100 * r["share"]) for r, _, _ in part] + pad
        changed = sum(r["share"] > 0 for r in rows)
        sheet(cells, labels, os.path.join(out, "pair.jpg"), cols=cols,
              title="golden pair: %s" % ("no change" if not changed else "%d of %d changed" % (changed, len(rows))))
    return rows


def crop(render, frame, window, look, size, path):
    """One close-up alone: the window of frame painted from the seeds that can touch it."""
    with timed("crop"):
        img = render([(frame, look, size, tuple(window))])[0]
        cv2.imwrite(path, img[..., ::-1])
    return img


def wedge(render, frame, window, look, size, key, values, path):
    """The same close-up at each value of one look key, on one sheet, 3 a row."""
    with timed("wedge"):
        labels = [label(key, v) for v in values]
        cells = render([(frame, with_key(look, key, v), size, tuple(window)) for v in values])
        sheet(cells, labels, path, cols=3)
    return cells, labels


def strip(render, frames, window, look, size, flow, out):
    """A 1 s loop of one close-up: consecutive frames of the window painted, and where they flicker (flow: the BGR
    reference crops); frames f_NNNN.png and strip.jpg (first, middle, last, the flicker map) to out."""
    with timed("strip"):
        pics = render([(f, look, size, tuple(window)) for f in frames])
        for f, p in zip(frames, pics):
            cv2.imwrite(os.path.join(out, "f_%04d.png" % f), p[..., ::-1])
        fmap = flickmap(pics, flow)
        k = [0, len(pics) // 2, len(pics) - 1]
        sheet([pics[i] for i in k] + [fmap], ["f_%04d" % frames[i] for i in k] + ["flicker"], os.path.join(out, "strip.jpg"))
    return pics, fmap


def fml(render, frames, look, size, path):
    """First, middle and last frame of the shot."""
    with timed("fml"):
        pics = render([(f, look, size, None) for f in frames])
        sheet(pics, ["f_%04d" % f for f in frames], path, cols=3)
    return pics


# the command line: `film qa CHECK SHOT`


def _job(job):
    shot, prefix, look, size, window = job
    from . import refio
    from .paint import paint_frame
    return paint_frame(cli.scene_of(shot), refio.load(prefix), look, size, window)


def engine_commit():
    """The engine's last commit, and whether what a painted frame depends on differs from it."""
    root = os.path.normpath(os.path.join(cli.ENGINE, "..", ".."))
    git = lambda *a: subprocess.run(["git", "-C", root] + list(a), capture_output=True, text=True).stdout.strip()  # noqa: E731
    return git("log", "-1", "--format=%h", "--", "."), bool(git("status", "--porcelain", "--", *cli.engine_files(), "looks"))


def renderer(a, cfg, work):
    """render(jobs): (frame, look, size, window) -> RGB pictures; the reference stage first (cached), a draft-size job
    from the draft reference, a pool of at most a.jobs workers."""
    draft = cli.frame_size(cfg, True)

    def ref_dir(frames, half):
        d = os.path.join(work, "draft", "ref") if half else os.path.join(work, "ref")
        ns = argparse.Namespace(shot=a.shot, out=d, frames=",".join(map(str, sorted(set(frames)))), scale=0.5 if half else None,
                                samples=None, seed_pair=False)
        if cli.ref(ns):
            sys.exit("film qa: the reference stage failed")
        return d

    def render(jobs):
        dirs = {}
        for half in (True, False):
            fs = [f for f, _, size, _ in jobs if (tuple(size) == draft) == half]
            if fs:
                dirs[half] = ref_dir(fs, half)
        todo = [(a.shot, os.path.join(dirs[tuple(size) == draft], "f_%04d" % f), lk, tuple(size), w) for f, lk, size, w in jobs]
        n = cli.pool_size(min(a.jobs, len(todo)))
        if n > 1:
            with cli.pool(n) as p:
                p.apply(cli.warm, (a.shot, todo[0][2]))
                return list(p.imap(_job, todo))
        return [_job(j) for j in todo]

    return render


def turntable_shot(work):
    """A shot folder in work whose scene is the engine's turntable fixture; the fixture's hash in its module keys the cache."""
    src = os.path.normpath(os.path.join(cli.ENGINE, "..", "..", "fixtures"))
    with open(os.path.join(src, "turntable.py"), "rb") as fh:
        sha = hashlib.sha256(fh.read()).hexdigest()[:16]
    shot = os.path.join(work, "shot")
    os.makedirs(shot, exist_ok=True)
    with open(os.path.join(shot, "shot.json"), "w") as fh:
        json.dump({"name": "turntable", "scene": "table", "fps": 24, "size": [480, 270], "work": work}, fh)
    with open(os.path.join(shot, "table.py"), "w") as fh:
        fh.write("# fixtures/turntable.py %s\nimport sys\nsys.path.insert(0, %r)\nfrom turntable import scene  # noqa: E402,F401\n"
                 % (sha, src))
    return shot


def main(a):
    if a.check == "turntable":
        a.shot = turntable_shot(os.path.expanduser(a.work or os.path.join(GOLDEN, "turntable")))
    elif not a.shot:
        sys.exit("film qa %s: SHOT is needed" % a.check)
    cfg = cli.shot_cfg(a.shot)
    with open(cli.look_path(a.look)) as fh:
        base = json.load(fh)
    look = base
    for kv in a.set or []:
        k, _, v = kv.partition("=")
        look = with_key(look, k, json.loads(v))
    q = cfg.get("qa", {})
    loupes = {n: (v["frame"], tuple(v["window"])) for n, v in q.get("loupes", {}).items()}
    full, draft = cli.frame_size(cfg, False), cli.frame_size(cfg, True)
    work = os.path.expanduser(a.work or cfg["work"])
    out = os.path.abspath(a.out or os.path.join(work, "qa", a.check))
    os.makedirs(out, exist_ok=True)
    render = renderer(a, cfg, work)
    if a.loupe:
        a.frame, a.window = loupes[a.loupe]
    elif a.window:
        a.window = tuple(int(v) for v in a.window.split(","))
    if a.check == "pair":
        commit, dirty = engine_commit()
        gold = os.path.expanduser(a.golden) if a.golden else os.path.join(GOLDEN, cfg.get("name", "shot"), commit)
        if dirty and not os.path.isdir(gold):
            sys.exit("film qa pair: no golden at %s and the engine differs from %s: commit it first, or pass --golden" % (gold, commit))
        rows = pair(render, gold, q["golden"], loupes, base, look, draft, full, out)
        print("QA %s: %s" % (os.path.join(out, "pair.jpg"), "no change" if not any(r["share"] for r in rows) else "changed"))
    elif a.check == "crop":
        path = os.path.join(out, "crop_%04d_%s.png" % (a.frame, "_".join(map(str, a.window))))
        crop(render, a.frame, a.window, look, full, path)
        print("QA %s" % path)
    elif a.check == "wedge":
        values = json.loads("[%s]" % a.values)[:9]
        wedge(render, a.frame, a.window, look, full, a.key, values, os.path.join(out, "wedge.jpg"))
        print("QA %s" % os.path.join(out, "wedge.jpg"))
    elif a.check == "strip":
        frames = list(range(a.frame, a.frame + a.n))
        x, y, w, h = a.window
        flow_dir = os.path.join(work, "ref")
        with timed("ref"):
            cli.ref(argparse.Namespace(shot=a.shot, out=flow_dir, frames="%d-%d" % (frames[0], frames[-1]), scale=None,
                                       samples=None, seed_pair=False))
        flow = [cv2.imread(os.path.join(flow_dir, "f_%04d.png" % f))[y:y + h, x:x + w] for f in frames]
        strip(render, frames, a.window, look, full, flow, out)
        print("QA %s" % os.path.join(out, "strip.jpg"))
    elif a.check == "clay":
        with timed("clay"):
            frames = cli.frames_of(a.frames) if a.frames else q["golden"]
            d = os.path.join(work, "ref")
            cli.ref(argparse.Namespace(shot=a.shot, out=d, frames=",".join(map(str, frames)), scale=None, samples=None, seed_pair=False))
            cells = [cv2.imread(os.path.join(d, "f_%04d.png" % f))[..., ::-1] for f in frames]
            labels = ["plain f_%04d" % f for f in frames]
            target = cv2.imread(os.path.expanduser(cfg.get("target", "")))
            if target is not None:
                cells, labels = [target[..., ::-1]] + cells, ["target"] + labels
            sheet(cells, labels, os.path.join(out, "clay.jpg"), cols=min(len(cells), 3))
        print("QA %s" % os.path.join(out, "clay.jpg"))
    elif a.check == "fml":
        last = round(cli.scene_of(a.shot).duration * cfg.get("fps", 24)) - 1
        fml(render, [0, last // 2, last], look, draft, os.path.join(out, "fml.jpg"))
        print("QA %s" % os.path.join(out, "fml.jpg"))
    elif a.check == "turntable":
        with timed("turntable"):
            frames = list(range(0, 24, 3))
            pics = render([(f, look, full, None) for f in frames])
            sheet(pics, ["turn %d deg" % (15 * f) for f in frames], os.path.join(out, "turntable.jpg"))
        print("QA %s" % os.path.join(out, "turntable.jpg"))
    return 0
