#!/bin/dash
# Claude Code PreToolUse hook front: exits on calls without trigger bytes, else runs sleep-loop-block-impl.py (T896).
c=cat; [ -x /usr/bin/gnucat ] && c=gnucat
buf=$($c; echo x)
buf=${buf%x}
case $buf in
*pkill*|*pgrep*) ;;
*sleep*) case $buf in *until*|*while*|*for*) ;; *) exit 0 ;; esac ;;
*) exit 0 ;;
esac
self=$(readlink -f "$0")
printf '%s' "$buf" | exec /usr/bin/python3 -IS "${self%/*}/sleep-loop-block-impl.py"
