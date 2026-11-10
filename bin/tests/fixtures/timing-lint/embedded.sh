#!/usr/bin/env bash
# Fixture for timing-lint: Python in a shell heredoc; line 7 is the one finding.
python3 - <<'PY'
import time
t = time.perf_counter()
ms = (time.perf_counter() - t) * 1000
check("search under 20 ms", ms < 20, ms)
check("count", len([1]) < 2)
PY
