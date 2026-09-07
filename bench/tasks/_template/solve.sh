#!/usr/bin/env bash
# The oracle: <= 5 new-toolbox commands, prints the answer JSON check.sh must accept.
set -euo pipefail
jq -nc '{answer:"the true reading"}'
