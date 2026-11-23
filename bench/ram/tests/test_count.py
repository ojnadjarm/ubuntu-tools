"""count.py on a hand-made two-epoch transcript."""
import os, subprocess, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
COUNT = os.path.join(os.path.dirname(HERE), "count.py")


class CountTest(unittest.TestCase):
    def test_row(self):
        out = subprocess.run([sys.executable, COUNT, os.path.join(HERE, "mini-transcript.jsonl"), "off"],
                             capture_output=True, text=True, check=True).stdout.strip()
        # calls, compactions, after, back, re-orient, input, output, tool-output, notes, digests
        self.assertEqual(out, "| off | 9 | 1 | 5 | 1 | 2 | 8600 | 155 | 2080 | 1 | 1 |")

    def test_header(self):
        out = subprocess.run([sys.executable, COUNT, "--header", os.path.join(HERE, "mini-transcript.jsonl")],
                             capture_output=True, text=True, check=True).stdout.splitlines()
        self.assertEqual(len(out), 3)
        self.assertTrue(out[0].startswith("| arm | calls | compactions |"))


if __name__ == "__main__":
    unittest.main()
