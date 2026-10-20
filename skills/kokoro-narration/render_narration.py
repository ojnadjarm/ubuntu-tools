"""Render a unit's narration with Kokoro fp32 and write mastered clips plus a cue sheet of word-start marks."""
import json, os, re, subprocess, sys, pathlib
os.environ.setdefault("HF_HUB_OFFLINE", "1")
import numpy as np, soundfile as sf, torch
from kokoro import KPipeline

if len(sys.argv) < 3:
    sys.exit("usage: render_narration.py <unit.json> <out-dir> [clip-id…]")
UNIT = json.loads(pathlib.Path(sys.argv[1]).read_text())
OUT = pathlib.Path(sys.argv[2])
RAW = OUT.parent / (OUT.name + ".raw")
SR, LEAD, GAP, TERM_GAP, BIAS = 24000, 0.15, 0.30, 0.65, 0.04
KBPS = os.environ.get("NARRATION_KBPS")
CUE = re.compile(r"\{(\w+)\}")

torch.set_num_threads(8)
voice, speed = UNIT["voice"]["voice"], UNIT["voice"]["speed"]
pipe = KPipeline(lang_code=voice[0], repo_id="hexgrad/Kokoro-82M")


def words_of(text):
    """Alphanumeric words in order, as Kokoro tokenises them."""
    return [w for w in re.findall(r"[A-Za-z0-9']+", text)]


def render(sentence):
    """Return audio, word timings and cue→word-index for one sentence."""
    marks, plain = {}, ""
    pieces = CUE.split(sentence.rstrip("|"))
    for i, p in enumerate(pieces):
        if i % 2:
            marks[p] = len(plain)
        else:
            plain += p
    text, lead = plain.strip(), len(plain) - len(plain.lstrip())
    chunks, words, pos, off, at = [], [], [], 0.0, 0
    for r in pipe(text, voice=voice, speed=speed):
        a = r.audio.numpy()
        for tk in r.tokens or []:
            c = text.find(tk.text, at)
            at = c + len(tk.text) if c >= 0 else at
            if tk.start_ts is not None and any(ch.isalnum() for ch in tk.text):
                words.append({"w": tk.text, "s": off + tk.start_ts, "e": off + tk.end_ts})
                pos.append(c)
        chunks.append(a); off += len(a) / SR
    expected = words_of(plain)
    if len(expected) != len(words):
        print(f"WARN word count {len(words)} != {len(expected)}: {plain}", file=sys.stderr)
    if marks and (not words or -1 in pos):
        sys.exit(f"cannot place {sorted(marks)}: Kokoro words {[w['w'] for w in words]} do not match: {plain}")
    marks = {m: next((k for k, c in enumerate(pos) if c >= mc - lead), len(words) - 1) for m, mc in marks.items()}
    return np.concatenate(chunks), words, marks, sentence.endswith("|")


def master(src, stem):
    """Two-pass EBU R128 loudnorm to -16 LUFS / -1.5 dBTP, then Opus and AAC."""
    probe = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(src), "-af", "loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json",
                            "-f", "null", "-"], capture_output=True, text=True)
    if probe.returncode or "Parsed_loudnorm" not in probe.stderr:
        sys.exit(f"loudnorm probe failed for {src} (rc {probe.returncode}): {probe.stderr[-500:]}")
    probe = probe.stderr
    j = probe[probe.index("{", probe.rindex("Parsed_loudnorm")):]
    m = json.loads(j[: j.index("}") + 1])
    af = (f"loudnorm=I=-16:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
          f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
    wav = RAW / f"{stem}.m.wav"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-af", af, "-ar", "48000", str(wav)], check=True)
    encode(wav, stem)
    return float(m["input_i"])


def encode(wav, stem):
    """Opus and AAC from a mastered WAV: 64k / 96k, or NARRATION_KBPS for both (AAC then at 24 kHz)."""
    opus, aac = (f"{KBPS}k", ["-b:a", f"{KBPS}k", "-ar", "24000"]) if KBPS else ("64k", ["-b:a", "96k"])
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "libopus", "-b:a", opus, str(OUT / "audio" / f"{stem}.opus")], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "aac", *aac, str(OUT / "audio" / f"{stem}.m4a")], check=True)


RAW.mkdir(parents=True, exist_ok=True)
(OUT / "audio").mkdir(parents=True, exist_ok=True)
sheet = {"voice": UNIT["voice"], "bias": BIAS, "clips": {}}
only = set(sys.argv[3:])
prev = json.loads((OUT / "cues.json").read_text()) if (OUT / "cues.json").exists() and only else None
if prev and "kbps" in prev:
    if KBPS and KBPS != str(prev["kbps"] or "default"):
        sys.exit(f"NARRATION_KBPS={KBPS} but cues.json was rendered at {prev['kbps'] or '64/96'}k: re-render all clips or "
                 f"set NARRATION_KBPS={prev['kbps'] or 'default'}")
    KBPS = prev["kbps"] and str(prev["kbps"])
KBPS = None if KBPS == "default" else KBPS
sheet["kbps"] = KBPS and int(KBPS)
for clip in UNIT["clips"]:
    if only and clip["id"] not in only:
        if prev and clip["id"] in prev["clips"]:
            sheet["clips"][clip["id"]] = prev["clips"][clip["id"]]
            continue
        print(f"NOTE {clip['id']} has no earlier render; rendering it", file=sys.stderr)
    audio, words, marks, t = [np.zeros(int(SR * LEAD), np.float32)], [], {}, LEAD
    for s in clip["sentences"]:
        a, ws, mk, long_gap = render(s["text"] if isinstance(s, dict) else s)
        words += [{"w": w["w"], "s": round(t + w["s"], 3), "e": round(t + w["e"], 3)} for w in ws]
        for name, wi in mk.items():
            wi = min(wi, len(ws) - 1)
            marks[name] = round(t + ws[wi]["s"] + BIAS, 3)
        gap = TERM_GAP if long_gap else GAP
        audio += [a.astype(np.float32), np.zeros(int(SR * gap), np.float32)]
        t += len(a) / SR + gap
    audio = np.concatenate(audio)
    src = RAW / f"{clip['id']}.wav"
    sf.write(src, audio, SR)
    lufs = master(src, clip["id"])
    dur = round(len(audio) / SR, 3)
    wpm = round(len(words) / (dur / 60), 1)
    sheet["clips"][clip["id"]] = {"src": f"audio/{clip['id']}", "duration": dur, "marks": marks, "words": words}
    print(json.dumps({"clip": clip["id"], "dur": dur, "wpm": wpm, "rawLUFS": lufs, "marks": marks}), flush=True)
(OUT / "cues.json").write_text(json.dumps(sheet, indent=1))
