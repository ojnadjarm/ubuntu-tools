#!/bin/dash
# Claude Code PreToolUse hook front: exits on calls without trigger bytes, else runs sleep-loop-block-impl.py (T896, T1047, T1082, T1147, T1251).
c=cat; [ -x /usr/bin/gnucat ] && c=gnucat
buf=$($c; echo x)
buf=${buf%x}
miss() {
	case $buf in *'"cwd":'*) ;; *) exit 0 ;; esac
	cwd=${buf#*\"cwd\":}
	cwd=${cwd# }
	cwd=${cwd#\"}
	cwd=${cwd%%\"*}
	[ -z "$cwd" ] || [ -d "$cwd" ] && exit 0
}
case $buf in
*git*commit*|*git*push*) ;;
*pkill*|*pgrep*|*pactl*|*powerprofilesctl*|*systemctl*start*|*systemctl*stop*) ;;
*grep*{*|*-newer?t*|*apt*install*|*apt*remove*|*apt*purge*|*cd\ *rm\ *) ;;
*sleep*) case $buf in *until*|*while*|*for*) ;; *) miss ;; esac ;;
*sudo*) case $buf in *' do'*|*';do'*|*'\ndo'*|*xargs*) ;; *) miss ;; esac ;;
*) miss ;;
esac
self=$(readlink -f "$0")
printf '%s' "$buf" | exec /usr/bin/python3 -IS "${self%/*}/sleep-loop-block-impl.py"
