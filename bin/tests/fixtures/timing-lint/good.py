# Fixture for timing-lint: the same measurements against load-aware budgets; 0 findings.
import time
from budget import budget
t0 = time.monotonic()
took = time.monotonic() - t0
check(f"fast ({took:.2f} s, budget {budget(0.35):.2f} s)", took < budget(0.35))
ms = (time.time() - t0) * 100
check('latency', ms < budget(0.1) * 1000)
check('scan', time.time() - t0 <= budget(0.5))
