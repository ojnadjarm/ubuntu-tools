# Fixture for timing-lint: bare Python wall asserts; lines 5 7 9 11 are findings.
import time
t0 = time.monotonic()
took = time.monotonic() - t0
check(f"fast ({took:.2f} s)", took < 0.35)
ms = (time.time() - t0) * 100
check('latency', ms < 100)
lines = 3  # not a timing: lines < 5 is fine
check('scan', time.time() - t0 <= 0.5)
dt = time.perf_counter() - t0
check('per command', dt / lines < 0.001)
check('count', lines < 5)
