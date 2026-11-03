"""transcribe.js reads the wav's own sample rate; --serve loads the model once for many clips and exits when idle."""
import json, os, subprocess, sys, tempfile, unittest, wave
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash.services import voice
from dash.services.voice import NODE

JS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "transcribe.js")
BODY = os.path.expanduser("~/the-dark-eye/body")
SHERPA = os.path.join(BODY, "node_modules", "sherpa-onnx-node")
# Real readWave, stub recognizer: the 0.6B model load was ~90 % of this test's CPU (T905).
STUB = """const real = require(%s);
class OfflineRecognizer {
  constructor() { if (process.env.STUB_LOADS) require("fs").appendFileSync(process.env.STUB_LOADS, "x"); }
  createStream() { return { acceptWaveform() {} }; }
  decode() {}
  getResult() { return { text: "", tokens: [], timestamps: [] }; }
}
module.exports = { readWave: real.readWave, OfflineRecognizer };
"""


@unittest.skipUnless(os.path.exists(NODE) and os.path.isdir(SHERPA), "node or sherpa-onnx-node missing")
class Transcribe(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = self.tmp.name
        self.body = os.path.join(d, "body")
        os.makedirs(os.path.join(self.body, "node_modules", "sherpa-onnx-node"))
        with open(os.path.join(self.body, "node_modules", "sherpa-onnx-node", "index.js"), "w") as f:
            f.write(STUB % json.dumps(SHERPA))
        os.symlink(os.path.join(BODY, "src"), os.path.join(self.body, "src"))
        self.loads = os.path.join(d, "loads")
        self.env = dict(os.environ, EYE_BODY=self.body, STUB_LOADS=self.loads)
        self.wav = os.path.join(d, "a.wav")
        with wave.open(self.wav, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000)
            w.writeframes(b"\0\0" * 24000)

    def tearDown(self):
        self.tmp.cleanup()

    def test_24k_wav_duration(self):
        out = json.loads(subprocess.run([NODE, JS, self.wav], capture_output=True, text=True, check=True, env=self.env).stdout)
        self.assertAlmostEqual(out["seconds"], 1.0, places=3)

    def test_serve_loads_once_and_exits_idle(self):
        p = subprocess.Popen([NODE, JS, "--serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
                             env=dict(self.env, TRANSCRIBE_IDLE_MS="300"))
        for path in (self.wav, os.path.join(self.tmp.name, "missing.wav"), self.wav):
            p.stdin.write(path + "\n"); p.stdin.flush()
            out = json.loads(p.stdout.readline())
            self.assertIn("seconds" if path == self.wav else "error", out)
        self.assertEqual(p.wait(timeout=10), 0)
        self.assertEqual(open(self.loads).read(), "x")

    def test_voice_transcribe_reuses_server(self):
        real = voice.SERVE, os.environ.get("EYE_BODY"), os.environ.get("STUB_LOADS")
        voice.SERVE = [NODE, JS, "--serve"]
        os.environ.update(EYE_BODY=self.body, STUB_LOADS=self.loads)
        try:
            a, b = voice.transcribe(self.wav), voice.transcribe(self.wav)
        finally:
            voice.stop_server()
            voice.SERVE = real[0]
            for k, v in zip(("EYE_BODY", "STUB_LOADS"), real[1:]):
                os.environ.pop(k) if v is None else os.environ.__setitem__(k, v)
        self.assertAlmostEqual(a["seconds"], 1.0, places=3)
        self.assertEqual(a["text"], b["text"])
        self.assertEqual(open(self.loads).read(), "x")


if __name__ == "__main__":
    unittest.main()
