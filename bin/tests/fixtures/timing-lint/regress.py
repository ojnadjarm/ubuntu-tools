# Fixture for budget.test.sh: a step 10x slower than its 0.05 s base, judged by budget(); exit 1 means red.
import os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'lib'))
from budget import budget
t0 = time.monotonic()
time.sleep(0.5)
took = time.monotonic() - t0
print(f'took {took:.2f} s, budget {budget(0.05):.2f} s')
sys.exit(0 if took < budget(0.05) else 1)
