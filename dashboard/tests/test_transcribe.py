"""transcribe.js reads the wav's own sample rate instead of assuming 16 kHz."""
import json, os, subprocess, sys, tempfile, unittest, wave
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash.services.voice import NODE

JS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "transcribe.js")
BODY = os.path.expanduser("~/the-dark-eye/body")
SHERPA = os.path.join(BODY, "node_modules", "sherpa-onnx-node")
# Real readWave, stub recognizer: the 0.6B model load was ~90 % of this test's CPU (T905).
STUB = """const real = require(%s);
class OfflineRecognizer {
  createStream() { return { acceptWaveform() {} }; }
  decode() {}
  getResult() { return { text: "", tokens: [], timestamps: [] }; }
}
module.exports = { readWave: real.readWave, OfflineRecognizer };
"""


@unittest.skipUnless(os.path.exists(NODE) and os.path.isdir(SHERPA), "node or sherpa-onnx-node missing")
class Transcribe(unittest.TestCase):
    def test_24k_wav_duration(self):
        with tempfile.TemporaryDirectory() as d:
            body = os.path.join(d, "body")
            os.makedirs(os.path.join(body, "node_modules", "sherpa-onnx-node"))
            with open(os.path.join(body, "node_modules", "sherpa-onnx-node", "index.js"), "w") as f:
                f.write(STUB % json.dumps(SHERPA))
            os.symlink(os.path.join(BODY, "src"), os.path.join(body, "src"))
            wav = os.path.join(d, "a.wav")
            with wave.open(wav, "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000)
                w.writeframes(b"\0\0" * 24000)
            out = json.loads(subprocess.run([NODE, JS, wav], capture_output=True, text=True, check=True,
                                            env=dict(os.environ, EYE_BODY=body)).stdout)
        self.assertAlmostEqual(out["seconds"], 1.0, places=3)


if __name__ == "__main__":
    unittest.main()
