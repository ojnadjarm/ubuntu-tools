#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
sed -i '/^- T901 /d' "$WORK/FILE-CLAIMS.md"
jq -nc '{stale:true,holder:"T901",cleared:true,reason:"history.md says T901 finished on 2026-10-02; removed its line, T902 is live and kept"}'
