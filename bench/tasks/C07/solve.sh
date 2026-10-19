#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
"$WORK/ctl" set mode=fast >/dev/null
sed -i 's/^mode=.*/mode=fast/' "$WORK/conf.d/90-override.conf"
m=$("$WORK/ctl" status | sed -n 's/.*mode=//p')
jq -nc --arg m "$m" '{done:($m=="fast"),mode_now:$m,reason:"ctl set only edits app.conf; conf.d/90-override.conf pinned slow, changed it too; status reads fast"}'
