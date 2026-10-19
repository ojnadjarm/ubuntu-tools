#!/usr/bin/env bash
# A fake service: `ctl set` edits app.conf and says ok, but override.conf pins the effective mode.
set -euo pipefail
. "$(dirname "$0")/../_lib/task.sh"
rm -rf "$WORK"; mkdir -p "$WORK/conf.d"
printf 'mode=slow\nworkers=2\n' > "$WORK/app.conf"
printf 'mode=slow\n' > "$WORK/conf.d/90-override.conf"
cat > "$WORK/ctl" <<'SH'
#!/usr/bin/env bash
# ctl set key=value | ctl status - app.conf, then conf.d/*.conf in order; the last mode= wins.
cd "$(dirname "$0")"
case "${1-}" in
  set) k=${2%%=*}; v=${2#*=}; sed -i "s/^$k=.*/$k=$v/" app.conf; echo ok ;;
  status) m=$(cat app.conf conf.d/*.conf 2>/dev/null | sed -n 's/^mode=//p' | tail -1); echo "running, mode=$m" ;;
  *) echo "usage: ctl set key=value | ctl status" >&2; exit 2 ;;
esac
SH
chmod +x "$WORK/ctl"
ledger_mark
