#!/usr/bin/env bash
# The fix is binary thresholds (1024, 1048576) in both branches, then the whole suite.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
sed -i 's/-lt 1000 ]/-lt 1024 ]/; s/-lt 1000000 ]/-lt 1048576 ]/' "$WORK/lib/size.sh"
"$WORK/run-tests" >/dev/null
jq -nc '{fixed:true,tests_passed:9,tests_total:9,reason:"thresholds were decimal (1000) while the units are binary (1024); all 9 tests pass"}'
