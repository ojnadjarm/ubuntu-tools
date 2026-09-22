"""Per-target pronunciation verdict for the drill prompts."""
import json, os, shutil, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server

CORPUS = os.path.expanduser("~/agents/asr-corpus")


def prompt(pid):
    return [p for p in server.prompts() if p["id"] == pid][0]


class Verdict(unittest.TestCase):
    def test_final_consonant(self):
        v = server.pattern_verdict(prompt("d01"), "Star the tests, the ports, the agent stop.")
        by = {x["word"]: x for x in v}
        self.assertEqual((by["Start"]["status"], by["Start"]["reason"]), ("miss", "final t missing"))
        self.assertEqual(by["tests"]["status"], "hit")
        self.assertEqual(by["agents"]["reason"], "final s missing")
        self.assertEqual(by["stopped"]["reason"], "final t missing")

    def test_v_b(self):
        v = {x["word"]: x for x in server.pattern_verdict(prompt("d10"), "Berify the browser and the airbots.")}
        self.assertEqual((v["Verify"]["status"], v["Verify"]["reason"]), ("miss", "b for v"))
        self.assertEqual(v["browser"]["status"], "hit")
        self.assertEqual(v["earbuds"]["heard"], "airbots")

    def test_ch_sh(self):
        v = {x["word"]: x for x in server.pattern_verdict(prompt("d17"), "Shards, cheap, persh, jest, choose.")}
        self.assertEqual(v["Charts"]["reason"], "sh for ch")
        self.assertEqual(v["cheap"]["status"], "hit")
        self.assertEqual(v["digest"]["reason"], "heard as 'jest'")

    def test_vowel(self):
        v = {x["word"]: x for x in server.pattern_verdict(prompt("d24"), "Mod, note, cut, road, boat.")}
        self.assertEqual((v["Mode"]["status"], v["Mode"]["reason"]), ("miss", "heard as 'mod'"))
        self.assertEqual(v["note"]["status"], "hit")
        self.assertEqual(v["code"]["heard"], "cut")

    def test_timestamp_from_tokens(self):
        v = server.pattern_verdict(prompt("d03"), "Two agents, four prompts, ten users.",
                                   ["two", " agent", "s", " four", " prompts", " ten", " users"],
                                   [0.0, 0.2, 0.5, 0.7, 1.0, 1.4, 1.7])
        self.assertEqual(v[0]["at"], 0.7)

    def test_non_drill_prompt_gets_no_verdict(self):
        self.assertEqual(server.pattern_verdict(prompt("p08"), "run pc status"), [])

    def test_real_sidecars_are_unchanged_and_verdict_free(self):
        tmp = tempfile.mkdtemp()
        names = sorted(f for f in os.listdir(CORPUS) if f.endswith(".json"))[:5]
        self.assertEqual(len(names), 5)
        for n in names:
            shutil.copy(os.path.join(CORPUS, n), os.path.join(tmp, n))
        old, server.CORPUS = server.CORPUS, tmp
        try:
            st = server.corpus_stats()
        finally:
            server.CORPUS = old
        self.assertEqual(st["clips"], 5)
        for takes in st["takes"].values():
            for m in takes:
                self.assertNotIn("verdict", m)
        for n in names:
            self.assertEqual(open(os.path.join(tmp, n)).read(), open(os.path.join(CORPUS, n)).read())
        shutil.rmtree(tmp)

    def test_drill_sidecar_gets_a_verdict_through_stats(self):
        tmp = tempfile.mkdtemp()
        side = {"id": "20260922-120000-ab12", "prompt_id": "d01", "prompt": prompt("d01")["text"],
                "transcript": "Star the tests, check the ports, the agents stopped.", "seconds": 3}
        json.dump(side, open(os.path.join(tmp, side["id"] + ".json"), "w"))
        old, server.CORPUS = server.CORPUS, tmp
        try:
            st = server.corpus_stats()
        finally:
            server.CORPUS = old
        v = {x["word"]: x for x in st["takes"]["d01"][0]["verdict"]}
        self.assertEqual(v["Start"]["reason"], "final t missing")
        self.assertEqual(v["tests"]["status"], "hit")
        shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main()
