"""Voice corpus: prompts, the error floor, word diff, drill verdicts, clips in and out, stats."""
import gzip, hashlib, json, os, re, subprocess, sys, urllib.parse
from datetime import datetime
from dash.cache import lock
from dash.env import HERE, HOME
from dash.routes import route

CORPUS = os.path.join(HOME, "agents", "asr-corpus")
PROMPTS_FILE = os.path.join(HERE, "voice_prompts.json")
CLIP_ID = re.compile(r"^\d{8}-\d{6}-[a-z0-9]{4}$")
CLIP_MAX = 32 << 20
NODE = os.path.expanduser("~/.nvm/versions/node/v24.20.0/bin/node")


_memo = {}


def _mtime(path):
    """mtime in ns, or None when the path is missing."""
    try:
        return os.stat(path).st_mtime_ns
    except OSError:
        return None


def prompts():
    """The prompt list, re-read only when voice_prompts.json changes."""
    key = (PROMPTS_FILE, _mtime(PROMPTS_FILE))
    hit = _memo.get("prompts")
    if not hit or hit[0] != key:
        hit = _memo["prompts"] = (key, json.load(open(PROMPTS_FILE))["prompts"])
    return hit[1]


FLOOR_FILE = os.path.join(HERE, "state", "floor.json")


def floor():
    """The machine's own error floor per prompt: ({id: floor prompt}, note); empty with a note when floor.json is missing, and a prompt whose text has changed is dropped as stale."""
    try:
        d = json.load(open(FLOOR_FILE))
    except (OSError, ValueError):
        return {}, "floor.json missing: scores are raw, not his residue"
    cur = {p["id"]: p["text"] for p in prompts()}
    keep = {k: v for k, v in d.get("prompts", {}).items() if cur.get(k) == v.get("text")}
    stale = sorted(set(d.get("prompts", {})) - set(keep))
    return keep, "floor stale for %d prompt(s): %s" % (len(stale), ", ".join(stale)) if stale else None


NUM = {w: i for i, w in enumerate("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split())}
TENS = {w: 20 + 10 * i for i, w in enumerate("twenty thirty forty fifty sixty seventy eighty ninety".split())}
SAME = {"eye": "i", "c": "see", "sink": "sync", "disc": "disk", "to": "2", "too": "2", "okay": "ok"}


def words(text):
    """Lowercase (display, key) pairs: no punctuation, accents or hyphens, so 'Está' and 'esta', 'moodle-ci' and 'moodle ci' compare equal."""
    import unicodedata
    t = unicodedata.normalize("NFKD", text.lower().replace("-", " "))
    t = "".join(c for c in t if not unicodedata.combining(c))
    return spoken_numbers(re.findall(r"[a-z0-9]+(?:'[a-z0-9]+)*", t))


def spoken_numbers(toks):
    """'eighty seventy one' and '8071' become the same key; a homophone keeps its spelling but scores as its twin."""
    out, i = [], 0
    while i < len(toks):
        j, digits = i, ""
        while j < len(toks) and (toks[j] in NUM or toks[j] in TENS or toks[j] in ("hundred", "thousand") and digits):
            w = toks[j]
            if w in ("hundred", "thousand"):
                digits = str(int(digits) * (100 if w == "hundred" else 1000))
            elif w in TENS and j + 1 < len(toks) and toks[j + 1] in NUM and 0 < NUM[toks[j + 1]] < 10:
                digits += str(TENS[w] + NUM[toks[j + 1]])
                j += 1
            else:
                digits += str(TENS.get(w, NUM.get(w)))
            j += 1
        if digits:
            out.append((" ".join(toks[i:j]), digits))
            i = j
        else:
            w = toks[i]
            out.append((w, SAME.get(w, re.sub(r"is(e|es|ed|er|ing)$", r"iz\1", w) if len(w) > 5 else w)))
            i += 1
    return out


def word_diff(prompt, heard):
    """Word-level diff prompt -> heard: [[op, prompt_words, heard_words]] with op eq/sub/del/ins, plus the WER."""
    import difflib
    a, b = words(prompt), words(heard)
    ka, kb = [k for _, k in a], [k for _, k in b]
    ops, errs = [], 0
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, ka, kb, autojunk=False).get_opcodes():
        if op == "replace" and "".join(ka[i1:i2]) == "".join(kb[j1:j2]):
            op = "equal"  # 'pcbench' heard as 'pc bench': the same words, split
        ops.append([{"equal": "eq", "replace": "sub", "delete": "del", "insert": "ins"}[op], [w for w, _ in a[i1:i2]], [w for w, _ in b[j1:j2]]])
        if op != "equal":
            errs += max(i2 - i1, j2 - j1)
    return ops, (round(errs / len(a), 3) if a else 0.0)


def _final_sound(missing, before):
    """The sound an -ed/-s ending really carries: 'stopped' minus 'stop' is a final t, 'closed' minus 'close' a final d."""
    if missing.endswith("ed"):
        return "t" if (missing[:-2] or before)[-1] in "pkfsth" else "d"
    return missing


def _token_end(word_key, tokens, timestamps):
    """End timestamp of the token run that spells word_key, or None."""
    if not tokens or not timestamps or len(tokens) != len(timestamps):
        return None
    acc, start = "", 0
    for i, t in enumerate(tokens):
        if t.startswith((" ", "\u2581")) or not acc:
            acc, start = "", i
        acc += re.sub(r"[^a-z0-9]", "", t.lower())
        if acc == word_key:
            return round(timestamps[i] + (timestamps[i + 1] - timestamps[i] if i + 1 < len(timestamps) else 0.0), 2)
    return None


def pattern_verdict(prompt, heard, tokens=None, timestamps=None, machine=()):
    """Per-target hit/miss for a drill prompt: [{word, status, reason, heard, at}]; [] when the prompt has no targets.
    machine holds the words the error floor misses too: a miss on one of those carries machine: True and is not his."""
    if not prompt.get("targets") or not heard:
        return []
    pattern, keys = prompt.get("pattern"), [k for _, k in words(heard)]
    out = []
    for tgt in prompt["targets"]:
        w = words(tgt["word"])[0][1]
        c = words(tgt["confusable"])[0][1]
        at = _token_end(w, tokens, timestamps)
        if w in keys:
            out.append({"word": tgt["word"], "status": "hit", "at": at})
            continue
        got, reason = None, None
        if c in keys:
            got = c
        elif pattern == "final-consonant":
            got = next((k for k in keys if len(k) < len(w) and w.startswith(k)), None)
        elif pattern == "v-b":
            got = next((k for k in keys if k.startswith("b") and w.startswith("v") and k[1:] == w[1:]), None)
        elif pattern == "ch-sh":
            got = next((k for k in keys if k.replace("sh", "ch") == w or k.replace("sh", "j") == w), None)
        if got is not None:
            if pattern == "final-consonant" and w.startswith(got):
                reason = "final %s missing" % _final_sound(w[len(got):], got)
            elif pattern == "v-b":
                reason = "b for v"
            elif pattern == "ch-sh" and "sh" in got and "sh" not in w:
                reason = "sh for ch" if "ch" in w else "sh for j"
            else:
                reason = "heard as '%s'" % got
        miss = {"word": tgt["word"], "status": "miss", "reason": reason or "not heard", "heard": got, "at": at}
        if tgt["word"] in machine:
            miss["machine"] = True
        out.append(miss)
    return out


def transcribe(wav):
    """Run transcribe.js in its own transient unit (the model needs ~1.1 GB, the dashboard unit is capped); None if it fails."""
    cmd = ["systemd-run", "--user", "--quiet", "--wait", "--pipe", "--collect", "-p", "MemoryMax=2G",
           NODE, os.path.join(HERE, "transcribe.js"), wav]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
        return json.loads(out.stdout) if out.returncode == 0 and out.stdout.strip() else None
    except (subprocess.SubprocessError, ValueError, OSError):
        return None


def _corpus_key():
    """What corpus_stats depends on: the corpus dir, its sidecars (count, newest mtime), the prompts and the floor."""
    try:
        side = [e.stat().st_mtime_ns for e in os.scandir(CORPUS) if e.name.endswith(".json")]
    except OSError:
        side = []
    return (CORPUS, _mtime(CORPUS), len(side), max(side, default=0), _mtime(PROMPTS_FILE), FLOOR_FILE, _mtime(FLOOR_FILE))


def corpus_stats():
    """/api/voice/stats, recomputed only when _corpus_key() changes or a clip is saved, deleted or cleared."""
    key = _corpus_key()
    hit = _memo.get("stats")
    if not hit or hit["key"] != key:
        hit = _memo["stats"] = {"key": key, "val": _corpus_stats()}
    return hit["val"]


def stats_body():
    """corpus_stats() as (JSON bytes, gzip bytes, ETag), serialised once per recompute."""
    corpus_stats()
    hit = _memo["stats"]
    if "body" not in hit:
        body = json.dumps(hit["val"]).encode()
        hit["body"], hit["gz"], hit["etag"] = body, gzip.compress(body, 6), '"%s"' % hashlib.sha1(body).hexdigest()[:16]
    return hit["body"], hit["gz"], hit["etag"]


def _corpus_stats():
    """Clip count, total speech seconds, clips per prompt, the last clip, every take per prompt."""
    per, n, secs, last, takes = {}, 0, 0.0, None, {}
    fl, note = floor()
    patterns = {}
    if os.path.isdir(CORPUS):
        for f in sorted(os.listdir(CORPUS)):
            if not f.endswith(".json"):
                continue
            try:
                m = json.load(open(os.path.join(CORPUS, f)))
            except (OSError, ValueError):
                continue
            n += 1
            if m.get("transcript"):
                m["diff"], m["wer"] = word_diff(m["prompt"], m["transcript"])
                f = fl.get(m.get("prompt_id")) or {}
                m["floor_wer"] = f.get("wer")
                m["his_wer"] = max(0.0, round(m["wer"] - f["wer"], 3)) if f else m["wer"]
                p = [x for x in prompts() if x["id"] == m.get("prompt_id")]
                if p and p[0].get("targets"):
                    mach = {x["word"] for x in f.get("verdict", []) if x["status"] == "miss"}
                    m["verdict"] = pattern_verdict(p[0], m["transcript"], m.get("tokens"), m.get("timestamps"), mach)
                    c = patterns.setdefault(p[0].get("pattern"), {"hit": 0, "miss": 0, "machine": 0})
                    for x in m["verdict"]:
                        c["hit" if x["status"] == "hit" else "machine" if x.get("machine") else "miss"] += 1
            secs += m.get("seconds") or 0
            per[m.get("prompt_id", "")] = per.get(m.get("prompt_id", ""), 0) + 1
            takes.setdefault(m.get("prompt_id", ""), []).append(m)
            last = m
    return {"clips": n, "seconds": round(secs, 1), "per_prompt": per, "last": last, "takes": takes, "dir": CORPUS,
            "patterns": patterns, "floor": {"ok": bool(fl), "prompts": len(fl), "note": note}}


def save_clip(raw, mime, prompt_id, prompt_sha=None):
    """Store one recording: 16 kHz mono wav + JSON sidecar (prompt, time, transcript, diff); returns (status, sidecar).
    prompt_sha, when given, is the sha256 of the prompt text the phone showed; a mismatch is refused so no clip is filed under the wrong prompt."""
    hit = [p for p in prompts() if p["id"] == prompt_id]
    if not hit or not raw:
        return 400, {"error": "unknown prompt" if not hit else "empty clip"}
    if prompt_sha and prompt_sha != hashlib.sha256(hit[0]["text"].encode()).hexdigest():
        return 409, {"error": "prompt mismatch: the text on screen was not prompt %s, nothing saved" % prompt_id}
    os.makedirs(CORPUS, exist_ok=True)
    cid = datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + os.urandom(2).hex()
    wav = os.path.join(CORPUS, cid + ".wav")
    ext = {"audio/webm": ".webm", "audio/ogg": ".ogg", "audio/mp4": ".m4a", "audio/wav": ".wav"}.get(mime.split(";")[0].strip(), ".bin")
    src = os.path.join(CORPUS, cid + ".src" + ext)
    open(src, "wb").write(raw)
    conv = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", src, "-ac", "1", "-ar", "16000",
                           "-c:a", "pcm_s16le", "-f", "wav", "-rf64", "never", "-fflags", "+bitexact", wav], capture_output=True, text=True, timeout=60)
    if conv.returncode != 0 or not os.path.exists(wav):
        return 500, {"error": "ffmpeg failed: " + conv.stderr.strip()[-200:], "kept": os.path.basename(src)}
    os.remove(src)
    seconds = round(max(0, os.path.getsize(wav) - 44) / 32000, 2)
    tr = transcribe(wav)
    meta = {"id": cid, "prompt_id": prompt_id, "prompt": hit[0]["text"], "lang": hit[0]["lang"],
            "recorded_at": datetime.now().astimezone().isoformat(timespec="seconds"), "seconds": seconds,
            "source_mime": mime, "wav": os.path.basename(wav), "sample_rate": 16000,
            "transcript": tr["text"] if tr else None, "model": tr["model"] if tr else None,
            "decode_ms": tr["decode_ms"] if tr else None}
    if tr:
        meta["diff"], meta["wer"] = word_diff(hit[0]["text"], tr["text"])
        for k in ("tokens", "timestamps", "durations"):
            if tr.get(k):
                meta[k] = tr[k]
        if hit[0].get("targets"):
            meta["verdict"] = pattern_verdict(hit[0], tr["text"], meta.get("tokens"), meta.get("timestamps"))
    json.dump(meta, open(os.path.join(CORPUS, cid + ".json"), "w"), ensure_ascii=False, indent=1)
    _memo.pop("stats", None)
    return 200, meta


def delete_clip(cid):
    """Move one clip and its sidecar by id into spoiled/ — a take he threw away is where the model fails hardest; the id pattern is the whole confinement."""
    if not CLIP_ID.match(cid or ""):
        return 400, {"error": "bad id"}
    gone = 0
    for ext in (".wav", ".json"):
        p = os.path.join(CORPUS, cid + ext)
        if os.path.isfile(p):
            os.makedirs(os.path.join(CORPUS, "spoiled"), exist_ok=True)
            os.replace(p, os.path.join(CORPUS, "spoiled", cid + ext))
            gone += 1
    _memo.pop("stats", None)
    return (200 if gone else 404), {"id": cid, "removed": gone}


def clear_takes(pid):
    """Move every take of one drill prompt (sidecar + wav) into archive/<date>/, out of the page, the stats and the WER; progress is untouched."""
    if not isinstance(pid, str) or not any(p["id"] == pid and p.get("group") == "drill" for p in prompts()):
        return 400, {"error": "unknown drill prompt"}
    dest = os.path.join(CORPUS, "archive", datetime.now().strftime("%Y-%m-%d"))
    moved = 0
    with lock:
        for f in sorted(os.listdir(CORPUS)) if os.path.isdir(CORPUS) else []:
            cid = f[:-5]
            if not f.endswith(".json") or not CLIP_ID.match(cid):
                continue
            try:
                if json.load(open(os.path.join(CORPUS, f))).get("prompt_id") != pid:
                    continue
            except (OSError, ValueError):
                continue
            os.makedirs(dest, exist_ok=True)
            for ext in (".wav", ".json"):
                if os.path.isfile(os.path.join(CORPUS, cid + ext)):
                    os.replace(os.path.join(CORPUS, cid + ext), os.path.join(dest, cid + ext))
            moved += 1
    _memo.pop("stats", None)
    return 200, {"prompt_id": pid, "archived": moved, "dir": dest}


@route("GET", "/api/voice/prompts")
def prompts_route(h, path):
    want = urllib.parse.parse_qs(h.path.partition("?")[2]).get("group", [""])[0]
    h.json([p for p in prompts() if (p.get("group") == want if want else p.get("group") != "drill")])


@route("GET", "/api/voice/stats")
def stats_route(h, path):
    body, gz, etag = stats_body()
    h.send(200, body, "application/json", etag, gz)


@route("POST", "/api/voice/clip")
def clip_route(h, path):
    size, mime = int(h.headers.get("Content-Length") or 0), h.headers.get("Content-Type") or ""
    if size > CLIP_MAX:
        code, out = 413, {"error": "clip too big: %d bytes, limit %d" % (size, CLIP_MAX)}
    else:
        code, out = save_clip(h.rfile.read(size), mime, h.headers.get("X-Prompt-Id") or "", h.headers.get("X-Prompt-Sha") or None)
    print("voice clip: %d %s %d bytes %s %s" % (code, mime, size, out.get("id") or "-", out.get("error") or ""), file=sys.stderr, flush=True)
    h.json(out, code)


@route("POST", "/api/voice/delete")
def delete_route(h, path):
    body = h.body_json(4096, {})
    code, out = delete_clip(body.get("id") if isinstance(body, dict) else "")
    h.json(out, code)


@route("POST", "/api/voice/clear")
def clear_route(h, path):
    body = h.body_json(4096, {})
    code, out = clear_takes(body.get("prompt_id") if isinstance(body, dict) else None)
    h.json(out, code)
