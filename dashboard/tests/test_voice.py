"""Voice training: prompts, the word diff, clip storage and deletion on a throwaway corpus dir."""
import json, os, subprocess, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server

WAV = os.path.expanduser("~/the-dark-eye/body/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/test_wavs/en.wav")


class Voice(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        server.CORPUS = os.path.join(self.tmp.name, "corpus")
        self.real_floor_file = server.FLOOR_FILE
        self.real_transcribe = server.transcribe
        server.transcribe = lambda wav: {"text": "run pc status and tell me the battery please", "model": "fake", "decode_ms": 1}

    def tearDown(self):
        server.transcribe = self.real_transcribe
        server.FLOOR_FILE = self.real_floor_file
        self.tmp.cleanup()

    def test_prompts(self):
        p = server.prompts()
        self.assertGreaterEqual(len(p), 40)
        self.assertEqual(len({x["id"] for x in p}), len(p))
        self.assertTrue(all(x["lang"] == "en" and x["text"] for x in p))
        self.assertTrue(all(x["len"] in ("short", "long") for x in p))
        self.assertGreaterEqual(sum(x["len"] == "long" for x in p), 15)

    def test_word_diff(self):
        ops, wer = server.word_diff("Está bien, run pc status.", "esta bien run PC status")
        self.assertEqual(ops, [["eq", ["esta", "bien", "run", "pc", "status"], ["esta", "bien", "run", "pc", "status"]]])
        self.assertEqual(wer, 0.0)
        ops, wer = server.word_diff("run pc see", "run pc sea now")
        self.assertEqual([o[0] for o in ops], ["eq", "sub"])
        self.assertEqual(wer, round(2 / 3, 3))

    def test_spelling_only_differences_are_not_errors(self):
        for prompt, heard in [("The eye bridge on port eighty six forty two.", "The I Bridge on port 8642."),
                              ("run moodle-ci and pcbench, ok?", "run moodle ci and pc bench, okay"),
                              ("pc see, the sink, the disk, two", "PC C, the sync, the disc, to"),
                              ("the recogniser, the four hundred users", "the recognizer, the 400 users")]:
            ops, wer = server.word_diff(prompt, heard)
            self.assertEqual((wer, {o[0] for o in ops}), (0.0, {"eq"}), (prompt, heard))
        ops, wer = server.word_diff("Tailscale, example-host, the tailnet", "Tail scale, exemplost, the tailnet")
        self.assertEqual(ops[0], ["sub", ["tailscale", "example", "host"], ["tail", "scale", "exemplost"]])
        self.assertEqual(wer, 0.6)

    def test_stats_rescore_every_take_without_touching_the_sidecar(self):
        os.makedirs(server.CORPUS)
        side = {"id": "20260922-120000-ab12", "prompt_id": "p08", "prompt": "run pc see", "transcript": "run PC C", "seconds": 1,
                "diff": [["sub", ["see"], ["c"]]], "wer": 0.333}
        json.dump(side, open(os.path.join(server.CORPUS, side["id"] + ".json"), "w"))
        st = server.corpus_stats()
        self.assertEqual((st["takes"]["p08"][0]["wer"], st["takes"]["p08"][0]["diff"]), (0.0, [["eq", ["run", "pc", "see"], ["run", "pc", "c"]]]))
        self.assertEqual(json.load(open(os.path.join(server.CORPUS, side["id"] + ".json")))["wer"], 0.333)

    def _drill_take(self, transcript):
        os.makedirs(server.CORPUS, exist_ok=True)
        side = {"id": "20260922-130000-cd34", "prompt_id": "d02", "prompt": "He closed the tab and skipped the restarts.",
                "transcript": transcript, "seconds": 3}
        json.dump(side, open(os.path.join(server.CORPUS, side["id"] + ".json"), "w"))
        return server.corpus_stats()

    def test_his_wer_subtracts_the_machine_floor(self):
        st = self._drill_take("He close the tab and skipped the restarts.")
        take = st["takes"]["d02"][0]
        self.assertEqual((take["wer"], take["floor_wer"], take["his_wer"]), (0.125, 0.25, 0.0))
        self.assertTrue(st["floor"]["ok"])

    def test_a_miss_the_floor_also_misses_is_the_machines(self):
        st = self._drill_take("He close the tab and skipped the restarts.")
        v = {x["word"]: x for x in st["takes"]["d02"][0]["verdict"]}
        self.assertEqual((v["closed"]["status"], v["closed"].get("machine")), ("miss", True))
        self.assertEqual(st["patterns"]["final-consonant"], {"hit": 3, "miss": 0, "machine": 1})

    def test_a_miss_of_his_own_still_counts(self):
        st = self._drill_take("He closed the tap and skipped the restarts.")
        v = {x["word"]: x for x in st["takes"]["d02"][0]["verdict"]}
        self.assertEqual((v["tab"]["status"], v["tab"].get("machine")), ("miss", None))
        self.assertEqual(st["patterns"]["final-consonant"]["miss"], 1)

    def test_missing_floor_degrades_to_raw_scores(self):
        server.FLOOR_FILE = os.path.join(self.tmp.name, "gone.json")
        st = self._drill_take("He close the tab and skipped the restarts.")
        take = st["takes"]["d02"][0]
        self.assertEqual((take["floor_wer"], take["his_wer"]), (None, 0.125))
        self.assertEqual(st["floor"]["ok"], False)
        self.assertIn("missing", st["floor"]["note"])

    def test_progress_persists_cleared_steps(self):
        server.PROGRESS_FILE = os.path.join(self.tmp.name, "pronunciation.json")
        self.assertEqual(server.progress_get(), {"cleared": {}})
        self.assertEqual(server.progress_add("nope")[0], 400)
        code, out = server.progress_add("d01")
        self.assertEqual((code, list(out["cleared"])), (200, ["d01"]))
        server.progress_add("d02")
        self.assertEqual(sorted(server.progress_get()["cleared"]), ["d01", "d02"])

    def test_save_and_delete(self):
        raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", WAV, "-t", "2", "-c:a", "libopus", "-f", "webm", "-"],
                             capture_output=True).stdout
        code, meta = server.save_clip(raw, "audio/webm;codecs=opus", "p08")
        self.assertEqual(code, 200, meta)
        files = sorted(os.listdir(server.CORPUS))
        self.assertEqual(files, [meta["id"] + ".json", meta["id"] + ".wav"])
        self.assertAlmostEqual(meta["seconds"], 2.0, delta=0.1)
        side = json.load(open(os.path.join(server.CORPUS, meta["id"] + ".json")))
        self.assertEqual((side["prompt_id"], side["prompt"], side["transcript"]), ("p08", "Run pc status and tell me the battery.", meta["transcript"]))
        self.assertEqual([o[0] for o in side["diff"]], ["eq", "ins"])
        st = server.corpus_stats()
        self.assertEqual((st["clips"], st["per_prompt"]), (1, {"p08": 1}))
        self.assertEqual(server.delete_clip(meta["id"]), (200, {"id": meta["id"], "removed": 2}))
        self.assertEqual(os.listdir(server.CORPUS), ["spoiled"])
        self.assertEqual(sorted(os.listdir(os.path.join(server.CORPUS, "spoiled"))), files)
        self.assertEqual(server.corpus_stats()["clips"], 0)

    def test_clear_takes_archives_one_drill_prompt(self):
        server.PROGRESS_FILE = os.path.join(self.tmp.name, "pronunciation.json")
        server.progress_add("d02")
        os.makedirs(server.CORPUS)
        for cid, pid in (("20260922-130000-aa01", "d02"), ("20260922-130100-aa02", "d02"), ("20260922-130200-aa03", "d03"), ("20260922-130300-aa04", "p08")):
            json.dump({"id": cid, "prompt_id": pid, "prompt": "x", "seconds": 1}, open(os.path.join(server.CORPUS, cid + ".json"), "w"))
            open(os.path.join(server.CORPUS, cid + ".wav"), "wb").write(b"RIFF")
        code, out = server.clear_takes("d02")
        self.assertEqual((code, out["archived"]), (200, 2))
        self.assertEqual(sorted(os.listdir(out["dir"])), ["20260922-130000-aa01.json", "20260922-130000-aa01.wav", "20260922-130100-aa02.json", "20260922-130100-aa02.wav"])
        self.assertEqual(os.path.dirname(out["dir"]), os.path.join(server.CORPUS, "archive"))
        st = server.corpus_stats()
        self.assertEqual((st["clips"], sorted(st["takes"]), st["per_prompt"].get("d02")), (2, ["d03", "p08"], None))
        self.assertEqual(list(server.progress_get()["cleared"]), ["d02"])
        self.assertEqual(server.clear_takes("d02")[1]["archived"], 0)

    def test_stats_are_cached_until_the_corpus_changes(self):
        from dash.services import voice
        os.makedirs(server.CORPUS)
        calls, real = [], voice._corpus_stats
        voice._corpus_stats = lambda: calls.append(1) or real()
        try:
            first = server.corpus_stats()
            self.assertIs(server.corpus_stats(), first)
            self.assertEqual(voice.stats_body()[0], json.dumps(first).encode())
            self.assertEqual(len(calls), 1)
            path = os.path.join(server.CORPUS, "20260922-120000-ab12.json")
            json.dump({"id": "20260922-120000-ab12", "prompt_id": "p08", "prompt": "run pc see", "transcript": "run pc see", "seconds": 1}, open(path, "w"))
            self.assertEqual(server.corpus_stats()["clips"], 1)
            json.dump({"id": "20260922-120000-ab12", "prompt_id": "p08", "prompt": "run pc see", "transcript": "run pc", "seconds": 1}, open(path, "w"))
            os.utime(path, ns=(os.stat(path).st_mtime_ns + 10**9,) * 2)
            self.assertEqual(server.corpus_stats()["takes"]["p08"][0]["transcript"], "run pc")
            self.assertEqual(len(calls), 3)
        finally:
            voice._corpus_stats = real

    def test_stats_change_after_save_and_after_delete(self):
        raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", WAV, "-t", "1", "-c:a", "libopus", "-f", "webm", "-"], capture_output=True).stdout
        self.assertEqual(server.corpus_stats()["clips"], 0)
        code, meta = server.save_clip(raw, "audio/webm;codecs=opus", "p08")
        self.assertEqual(code, 200, meta)
        st = server.corpus_stats()
        self.assertEqual((st["clips"], st["last"]["id"]), (1, meta["id"]))
        server.delete_clip(meta["id"])
        st = server.corpus_stats()
        self.assertEqual((st["clips"], st["last"]), (0, None))

    def test_prompts_reread_when_the_file_changes(self):
        path = os.path.join(self.tmp.name, "prompts.json")
        json.dump({"prompts": [{"id": "x1", "text": "a"}]}, open(path, "w"))
        real, server.PROMPTS_FILE = server.PROMPTS_FILE, path
        try:
            self.assertIs(server.prompts(), server.prompts())
            json.dump({"prompts": [{"id": "x1", "text": "b"}]}, open(path, "w"))
            os.utime(path, ns=(os.stat(path).st_mtime_ns + 10**9,) * 2)
            self.assertEqual(server.prompts()[0]["text"], "b")
        finally:
            server.PROMPTS_FILE = real

    def test_clear_takes_refuses_anything_but_a_drill_prompt(self):
        for bad in ("nope", "p08", "../d02", "", None, ["d02"]):
            self.assertEqual(server.clear_takes(bad)[0], 400, bad)

    def test_tokens_are_kept_in_the_sidecar(self):
        server.transcribe = lambda wav: {"text": "run pc status", "model": "fake", "decode_ms": 1,
                                         "tokens": ["run", " pc", " status"], "timestamps": [0.0, 0.4, 0.8], "durations": []}
        raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", WAV, "-t", "1", "-c:a", "libopus", "-f", "webm", "-"], capture_output=True).stdout
        code, meta = server.save_clip(raw, "audio/webm;codecs=opus", "p08")
        self.assertEqual(code, 200, meta)
        side = json.load(open(os.path.join(server.CORPUS, meta["id"] + ".json")))
        self.assertEqual(side["tokens"], ["run", " pc", " status"])
        self.assertEqual(len(side["timestamps"]), len(side["tokens"]))
        self.assertNotIn("durations", side)
        self.assertEqual(server.corpus_stats()["clips"], 1)

    def test_long_take(self):
        raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-stream_loop", "-1", "-i", WAV, "-t", "60", "-c:a", "libopus", "-f", "webm", "-"],
                             capture_output=True).stdout
        self.assertLess(len(raw), server.CLIP_MAX)
        code, meta = server.save_clip(raw, "audio/webm;codecs=opus", "p60")
        self.assertEqual(code, 200, meta)
        self.assertAlmostEqual(meta["seconds"], 60.0, delta=0.2)

    def test_prompt_hash_guards_against_the_wrong_prompt(self):
        import hashlib
        raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", WAV, "-t", "1", "-c:a", "libopus", "-f", "webm", "-"], capture_output=True).stdout
        other = hashlib.sha256("Switch to audio notes mode.".encode()).hexdigest()
        code, out = server.save_clip(raw, "audio/webm;codecs=opus", "p08", other)
        self.assertEqual(code, 409, out)
        self.assertFalse(os.path.isdir(server.CORPUS))
        right = hashlib.sha256("Run pc status and tell me the battery.".encode()).hexdigest()
        self.assertEqual(server.save_clip(raw, "audio/webm;codecs=opus", "p08", right)[0], 200)

    def test_refusals(self):
        self.assertEqual(server.save_clip(b"x", "audio/webm", "nope")[0], 400)
        self.assertEqual(server.save_clip(b"", "audio/webm", "p01")[0], 400)
        for bad in ("../x", "/etc/passwd", "", "20260922-094742-1afd/../a", None):
            self.assertEqual(server.delete_clip(bad)[0], 400, bad)
        self.assertEqual(server.delete_clip("20260922-094742-1afd")[0], 404)

    def test_bad_audio_keeps_source(self):
        code, out = server.save_clip(b"not audio at all" * 100, "audio/webm", "p01")
        self.assertEqual(code, 500)
        self.assertTrue(os.path.isfile(os.path.join(server.CORPUS, out["kept"])))


if __name__ == "__main__":
    unittest.main()
