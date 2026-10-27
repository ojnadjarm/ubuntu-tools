"""Stand-in for concept-img in tests: writes a tiny PNG to --out and logs the prompt file it got."""
import sys

a = sys.argv
out, prompt = a[a.index('--out') + 1], a[a.index('--prompt-file') + 1]
with open(out, 'wb') as f:
    f.write(b'\x89PNG\r\n\x1a\n' + b'0' * 64)
