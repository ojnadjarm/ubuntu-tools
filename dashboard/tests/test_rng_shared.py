"""One mulberry32 for /next: shapes.js exports rng, life.js and avatar.js import it."""
import json, os, re, subprocess, unittest

JS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "static", "next", "js")
REF = """
import { pathToFileURL } from "node:url";
const { rng } = await import(pathToFileURL(process.argv[1] + "/shapes.js").href);
const ref = (a) => () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
let bad = 0;
for (const s of [0, 1, 7, 52, 2166136261, 4294967295]) { const a = rng(s), b = ref(s); for (let i = 0; i < 500; i++) if (a() !== b()) bad++; }
console.log(JSON.stringify({ bad }));
"""


class SharedRng(unittest.TestCase):
    def test_one_definition(self):
        hits = {}
        for root, _, files in os.walk(JS):
            for f in files:
                if f.endswith(".js"):
                    n = open(os.path.join(root, f)).read().count("0x6d2b79f5")
                    if n:
                        hits[os.path.relpath(os.path.join(root, f), JS)] = n
        self.assertEqual(hits, {"shapes.js": 1})

    def test_importers(self):
        for f in ("gl/life.js", "avatar.js"):
            src = open(os.path.join(JS, f)).read()
            self.assertRegex(src, re.compile(r'^import \{[^}]*\brng\b[^}]*\} from "\.{1,2}/shapes\.js";', re.M), f)

    def test_matches_mulberry32(self):
        out = subprocess.run(["node", "--input-type=module", "-e", REF, os.path.abspath(JS)],
                             capture_output=True, text=True, check=True, timeout=30)
        self.assertEqual(json.loads(out.stdout), {"bad": 0})


if __name__ == "__main__":
    unittest.main()
