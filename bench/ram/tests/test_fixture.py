"""make-fixture.py: flat modes unchanged, staged mode deterministic, gated and oracle-walkable."""
import glob, hashlib, json, os, shutil, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.join(os.path.dirname(HERE), "make-fixture.py")
N = 32


def tree(d):
    h = hashlib.sha256()
    for p in sorted(glob.glob(os.path.join(d, "**"), recursive=True)):
        if os.path.isfile(p):
            h.update(os.path.relpath(p, d).encode() + b"\0" + open(p, "rb").read())
    return h.hexdigest()


def gate(fx):
    return subprocess.run([sys.executable, "gate.py"], cwd=fx, capture_output=True, text=True)


class FixtureTest(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp(prefix="ram-fixture-test.")

    def tearDown(self):
        shutil.rmtree(self.t)

    def make(self, name, *flags):
        fx, key = os.path.join(self.t, name), os.path.join(self.t, name + ".json")
        subprocess.run([sys.executable, MF, "--seed", "1839", fx, "--key", key] + list(flags), check=True)
        return fx, json.load(open(key))

    def test_flat_modes_unchanged(self):
        # T1840's fixtures (commit 7f0ba28), seed 1839: grown default and RAM_SMALL.
        for flags, fx_hash, key_hash in [
                (["--modules", "36", "--bugs", "12"], "3d3809ef331652b4d834b5aad05f590f27a59354bf94f55447a9337ad466d552",
                 "4210b17769fd97b64df6f12411a13fa9dbe096d138b3f662ace2d7c4b1ef0116"),
                (["--modules", "24", "--bugs", "8"], "17550ffbaffafa7a6df8ec5a2b8d2d5ae32862d0d5b8df2ba90f149eb65ff1ca",
                 "022d88fc741113d68f228f230e08a97a3a031786f03959694b273ed82f6dc793")]:
            fx, key = os.path.join(self.t, flags[1]), os.path.join(self.t, flags[1] + ".json")
            subprocess.run([sys.executable, MF, "--seed", "1839", fx, "--key", key] + flags, check=True)
            self.assertEqual(tree(fx), fx_hash)
            self.assertEqual(hashlib.sha256(open(key, "rb").read()).hexdigest(), key_hash)

    def test_staged_same_seed_same_bytes(self):
        a, ka = self.make("a", "--stages", str(N))
        b, kb = self.make("b", "--stages", str(N))
        self.assertEqual(tree(a), tree(b))
        self.assertEqual(ka, kb)

    def test_staged_start_shows_stage_one_only(self):
        fx, key = self.make("s", "--stages", str(N))
        self.assertTrue(os.path.exists(os.path.join(fx, "stage-1.md")))
        self.assertFalse(os.path.exists(os.path.join(fx, "stage-2.md")))
        self.assertFalse(os.path.exists(os.path.join(fx, "QUESTIONS.md")))
        self.assertEqual(len(glob.glob(os.path.join(fx, "ledgerkit", "*.py"))), 1 + 3)
        later = [b["consumer"] for b in key["bugs"] if b["stage"] > 1]
        for p in glob.glob(os.path.join(fx, "**"), recursive=True):
            if os.path.isfile(p) and not p.endswith("stages.bin"):
                text = open(p).read()
                for m in later:
                    self.assertNotIn("ledgerkit/%s.py" % m, text)
                    self.assertNotIn("import %s" % m, text)
        r = gate(fx)
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(fx, "stage-2.md")))

    def test_edited_tests_do_not_open_the_next_stage(self):
        fx, _ = self.make("s", "--stages", str(N))
        for p in glob.glob(os.path.join(fx, "tests", "test_*.py")):
            open(p, "w").write("import unittest\n\n\nclass T(unittest.TestCase):\n    def test_ok(self):\n        pass\n")
        r = gate(fx)
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(fx, "stage-2.md")))

    def test_oracle_walk_and_late_stages_need_early_facts(self):
        fx, key = self.make("s", "--stages", str(N))
        self.assertEqual(sorted(map(int, key["patches"])), list(range(1, N + 1)))
        for n in range(1, N + 1):
            subprocess.run(["patch", "-s", "-p1", "-d", fx], input=key["patches"][str(n)], text=True, check=True)
            r = gate(fx)
            self.assertEqual(r.returncode, 0, r.stderr[-400:])
            nxt = "stage-%d.md" % (n + 1) if n < N else "QUESTIONS.md"
            self.assertTrue(os.path.exists(os.path.join(fx, nxt)), nxt)
            order = open(os.path.join(fx, nxt)).read()
            if "_CARRY" in order:
                early = [b for b in key["bugs"] if b["stage"] == n + 1 - 3 and b["slot"] == "A"][0]
                self.assertIn("ledgerkit/%s.py" % early["consumer"], order)
                self.assertIn("stage %d" % (n + 1 - 3), order)
        self.assertEqual(subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests"], cwd=fx,
                                        capture_output=True).returncode, 0)
        files = {f: open(os.path.join(fx, "tests", f), "rb").read() for f in os.listdir(os.path.join(fx, "tests"))
                 if f.endswith(".py")}
        h = hashlib.sha256()
        for f in sorted(files):
            h.update(f.encode() + b"\0" + files[f])
        self.assertEqual(h.hexdigest(), key["tests_sha256"])
        self.assertEqual(len(key["answers"]), 6)
        q = open(os.path.join(fx, "QUESTIONS.md")).read()
        self.assertEqual(q.count("stage"), 6)
        # A carried rate is checked by a seal: its value is in no test file.
        carried = [b for b in key["bugs"] if b["stage"] == 1 and b["slot"] == "A"][0]["v2"]
        stage4 = [f for f in files if f.startswith("test_") and b"_CARRY" in open(os.path.join(fx, "ledgerkit", f[8:]), "rb").read()]
        self.assertTrue(stage4)
        for f in stage4:
            self.assertIn(b"seal(", files[f])
            self.assertNotIn(b", %d)" % (7 * carried), files[f])


if __name__ == "__main__":
    unittest.main()
