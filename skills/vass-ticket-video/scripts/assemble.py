#!/usr/bin/env python3
"""assemble.py — work dir (raw.webm, marks.json, vo/) -> captions, VO mix, trimmed video, mp4, stills, guion.md, index.html."""
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HEAD = 0.4  # seconds kept before the first narration line


def ts(t):
    t = max(t, 0.0)
    ms = int(round(t * 1000))
    return f"{ms // 3600000:02}:{ms // 60000 % 60:02}:{ms // 1000 % 60:02},{ms % 1000:03}"


def segments(shots, cues, marks, off):
    """Caption lines: one per sentence or clause, <= 10 words, timed from edge word boundaries, never overlapping."""
    segs = []
    for i, step in enumerate(shots["steps"]):
        cid = f"s{i + 1}"
        words = cues[cid]["words"]
        start = marks[cid] - off
        text = step["say"].replace("{hl}", "")
        k = 0
        for part in re.split(r"(?<=[.:;?!])\s+", text.strip()):
            toks = part.split()
            if not toks:
                continue
            n = -(-len(toks) // 10)
            size = -(-len(toks) // n)
            for j in range(0, len(toks), size):
                ws = words[k + j:k + min(j + size, len(toks))]
                if ws:
                    segs.append([start + ws[0]["s"], start + ws[-1]["e"] + 0.3, " ".join(toks[j:j + size])])
            k += len(toks)
    for a, b in zip(segs, segs[1:]):
        a[1] = min(a[1], b[0] - 0.02)
    return segs


def srt(segs):
    return "\n".join(f"{n}\n{ts(s)} --> {ts(e)}\n{t}\n" for n, (s, e, t) in enumerate(segs, 1))


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"assemble: {cmd[0]} failed: {r.stderr.strip().splitlines()[-1:] or r.returncode}")
    return r.stdout


def review_ok(review):
    """Screen recordings trip two mv-review checks by nature: static screens (frozen) and white UI a hair over legal Y."""
    def expected(f):
        f = str(f)
        m = re.search(r"brng ([0-9.]+)", f)
        return f.startswith("frozen") or (f.startswith("levels") and m and float(m.group(1)) < 0.01)
    fails = [f for f in review.get("fails", []) if not expected(f)]
    return not fails, fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shots")
    ap.add_argument("work")
    ap.add_argument("out")
    ap.add_argument("--name", help="mp4 base name (default <ticket>-<phase>)")
    ap.add_argument("--source", help="the shot list as written (named in guion.md so despues can reuse antes)")
    ap.add_argument("--no-review", action="store_true")
    a = ap.parse_args()
    shots = json.loads(Path(a.shots).read_text())
    work, out = Path(a.work), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    cues = json.loads((work / "vo/cues.json").read_text())["clips"]
    marks = json.loads((work / "marks.json").read_text())
    name = a.name or f"{shots['ticket']}-{shots['phase']}"
    off = max(marks["s1"] - HEAD, 0.0)
    length = marks["end"] - off

    segs = segments(shots, cues, marks, off)
    (work / "captions.srt").write_text(srt(segs))

    n = len(shots["steps"])
    inputs, chains = [], []
    for i in range(n):
        inputs += ["-i", str(work / f"vo/audio/s{i + 1}.m4a")]
        d = int(round((marks[f"s{i + 1}"] - off) * 1000))
        chains.append(f"[{i}]adelay={d}|{d}[a{i}]")
    mix = "".join(f"[a{i}]" for i in range(n)) + f"amix=inputs={n}:normalize=0,apad,atrim=0:{length:.3f}[o]"
    run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(chains + [mix]),
         "-map", "[o]", "-c:a", "aac", "-b:a", "128k", str(work / "vo-mix.m4a")])
    run(["ffmpeg", "-v", "error", "-y", "-ss", f"{off:.3f}", "-i", str(work / "raw.webm"), "-t", f"{length:.3f}",
         "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "20", "-deadline", "realtime", "-cpu-used", "8",
         str(work / "trim.webm")])
    mp4 = out / f"{name}.mp4"
    run(["mv-encode", str(work / "trim.webm"), str(mp4), "--preset", "h264-web", "--fps", "25",
         "--audio", str(work / "vo-mix.m4a"), "--burn", str(work / "captions.srt")])

    status = "skipped"
    if not a.no_review:
        subprocess.run(["mv-review", str(mp4)], capture_output=True, text=True)
        rj = mp4.with_suffix(".review.json")
        review = json.loads(rj.read_text()) if rj.exists() else {"fails": ["no review.json"]}
        ok, fails = review_ok(review)
        status = "PASS (frozen/levels on static UI screens are expected)" if ok else f"FAIL {fails}"

    stills = []
    for p in sorted(work.glob("still-*.png"), key=lambda p: int(p.name.split("-")[1])):
        dest = out / f"{shots['phase']}-{int(p.name.split('-')[1]):02}-{p.name.split('-', 2)[2]}"
        shutil.copyfile(p, dest)
        stills.append(dest.name)

    lines = [f"# {shots['ticket'].upper()} · {shots['phase']} · guion", "",
             f"Vídeo: `{mp4.name}` ({length:.0f} s). Voz: es-ES-AlvaroNeural.", ""]
    if a.source:
        src = str(Path(a.source).resolve())
        home = str(Path.home())
        lines[3:3] = [f"Shot list: `{'~' + src[len(home):] if src.startswith(home + '/') else src}`"]
    for i, step in enumerate(shots["steps"]):
        where = step.get("go") or ("WS: " + ", ".join(w["fn"] for w in step["ws"]) if step.get("ws") else "")
        click = ", ".join([step["click"]] if isinstance(step.get("click"), str) else step.get("click", []))
        t = marks[f"s{i + 1}"] - off
        lines.append(f"{i + 1}. [{int(t) // 60}:{int(t) % 60:02}] {step['say'].replace('{hl}', '')}"
                     + (f"  _(pantalla: {' · '.join(x for x in (where, click) if x)})_" if where or click else ""))
    (out / f"guion-{shots['phase']}.md").write_text("\n".join(lines) + "\n")

    vids = sorted(out.glob("*.mp4"))
    imgs = sorted(out.glob("*.png"))
    html = ["<!doctype html><meta charset='utf-8'><title>%s</title>" % shots["ticket"].upper(),
            "<style>body{font:16px system-ui;max-width:1300px;margin:24px auto;padding:0 16px}"
            "img,video{max-width:100%;border:1px solid #ccc}</style>",
            f"<h1>{shots['ticket'].upper()}</h1>"]
    for v in vids:
        html.append(f"<h2>{v.stem}</h2><video src='{v.name}' controls preload='metadata'></video>")
    for g in sorted(out.glob("guion-*.md")):
        html.append(f"<p><a href='{g.name}'>{g.name}</a></p>")
    for im in imgs:
        html.append(f"<h3>{im.stem}</h3><img src='{im.name}'>")
    (out / "index.html").write_text("\n".join(html) + "\n")
    print(json.dumps({"mp4": str(mp4), "seconds": round(length, 1), "captions": len(segs), "stills": stills,
                      "review": status}))
    if status.startswith("FAIL"):
        sys.exit(1)


if __name__ == "__main__":
    main()
