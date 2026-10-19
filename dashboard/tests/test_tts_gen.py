"""tts-gen.js remakes a sentence wav when its drill text changes, with Kokoro stubbed."""
import json, os, shutil, subprocess, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash.services.voice import NODE

JS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src", "tts-gen.js")
STUB = """class OfflineTts { generate({ text }) { return { samples: new Float32Array(text.length * 10), sampleRate: 24000 }; } }
module.exports = { OfflineTts };
"""


@unittest.skipUnless(os.path.exists(NODE), "node missing")
class TtsGen(unittest.TestCase):
    def run_gen(self, d, text):
        with open(os.path.join(d, "voice_prompts.json"), "w") as f:
            json.dump({"prompts": [{"id": "d01", "group": "drill", "text": text, "targets": []}]}, f)
        subprocess.run([NODE, os.path.join(d, "src", "tts-gen.js")], check=True, capture_output=True,
                       env={**os.environ, "HOME": d})
        return os.path.getsize(os.path.join(d, "state", "tts", "s-d01.wav")) - 44

    def test_edited_text_regenerates_wav(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "src"))
            shutil.copy(JS, os.path.join(d, "src"))
            mod = os.path.join(d, "the-dark-eye", "body", "node_modules", "sherpa-onnx-node")
            os.makedirs(mod)
            with open(os.path.join(mod, "index.js"), "w") as f:
                f.write(STUB)
            self.assertEqual(self.run_gen(d, "old"), 3 * 10 * 2)
            self.assertEqual(self.run_gen(d, "a new sentence"), 14 * 10 * 2)


if __name__ == "__main__":
    unittest.main()
