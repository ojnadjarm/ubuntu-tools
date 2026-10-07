"""transcribe.js reads the wav's own sample rate instead of assuming 16 kHz."""
import json, os, subprocess, sys, tempfile, unittest, wave
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dash.services.voice import NODE

JS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "transcribe.js")
MODEL = os.path.expanduser("~/the-dark-eye/body/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8")


@unittest.skipUnless(os.path.exists(NODE) and os.path.isdir(MODEL), "node or Parakeet model missing")
class Transcribe(unittest.TestCase):
    def test_24k_wav_duration(self):
        with tempfile.TemporaryDirectory() as d:
            wav = os.path.join(d, "a.wav")
            with wave.open(wav, "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000)
                w.writeframes(b"\0\0" * 24000)
            out = json.loads(subprocess.run([NODE, JS, wav], capture_output=True, text=True, check=True).stdout)
        self.assertAlmostEqual(out["seconds"], 1.0, places=3)


if __name__ == "__main__":
    unittest.main()
