"""count.py on a built transcript shaped like a real auto-compaction (cwd on every row, boundary, summary)."""
import os, subprocess, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
COUNT = os.path.join(os.path.dirname(HERE), "count.py")


class CompactionTest(unittest.TestCase):
    def test_row(self):
        out = subprocess.run([sys.executable, COUNT, os.path.join(HERE, "compact-transcript.jsonl"), "off"],
                             capture_output=True, text=True, check=True).stdout.strip()
        # Back: stage-1.md (absolute Read before, relative cat after), amber.py, and lien.py (seen before only as a
        # grep match line); gamma.py was only named in a gate message, so it is not back.
        # calls, compactions, after, back, re-orient, input, output, tool-output, notes, digests
        self.assertEqual(out, "| off | 11 | 1 | 6 | 3 | 1 | 20200 | 300 | 3070 | 0 | 0 |")


if __name__ == "__main__":
    unittest.main()
