#!/usr/bin/env bash
# pc-harness uninstaller — reverses install.sh steps 3, 4 and 6.
# Keeps secrets/, log/, backups/ and config.env: they are owner data, not installed files.
set -uo pipefail
HARNESS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$HARNESS_DIR/bin/env.sh"

# The orchestrator session unit stays unless asked for by name (AGENTS.md §5.2).
KEEP=claude-orchestrator.service
for a in "$@"; do
  case "$a" in
    --with-orchestrator) KEEP="";;
    -h|--help) echo "usage: uninstall.sh [--with-orchestrator]   (removes PATH links, units and the adapter wiring; keeps your data and, without the flag, $KEEP)"; exit 0;;
    *) echo "uninstall.sh: unknown option $a" >&2; exit 2;;
  esac
done

echo "1. adapter"
agent="${HARNESS_AGENT:-}"
if [ -n "$agent" ] && [ -x "$HARNESS_DIR/adapters/$agent/uninstall" ]; then
  "$HARNESS_DIR/adapters/$agent/uninstall" | sed 's/^/  /'
else
  echo "  no adapter uninstaller for '${agent:-none}'"
fi

echo "2. units"
UD="$HOME/.config/systemd/user"
for d in "$HARNESS_DIR"/*/; do
  [ -r "$d/BRIEF.md" ] || continue
  n="$(basename "$d")"
  systemctl --user disable --now "agent@$n.timer" >/dev/null 2>&1 && echo "  disabled agent@$n.timer"
  [ -d "$UD/agent@$n.timer.d" ] && rm -rf "$UD/agent@$n.timer.d" && echo "  removed agent@$n.timer.d"
  [ -f "$UD/agent@$n.service.d/timeout.conf" ] && rm -f "$UD/agent@$n.service.d/timeout.conf" \
    && rmdir --ignore-fail-on-non-empty "$UD/agent@$n.service.d" && echo "  removed agent@$n.service.d/timeout.conf"
done
for u in "$HARNESS_DIR"/units/*; do
  n="$(basename "$u")"
  [ "$n" = "$KEEP" ] && { echo "  kept $n (use --with-orchestrator to remove it)"; continue; }
  case "$n" in agent@*) ;; *) systemctl --user disable --now "$n" >/dev/null 2>&1 && echo "  disabled $n";; esac
  [ -f "$UD/$n" ] && rm -f "$UD/$n" && echo "  removed unit $n"
done
systemctl --user daemon-reload; echo "  daemon-reload"

echo "3. commands"
for t in "$HOME"/.local/bin/*; do
  [ -L "$t" ] || continue
  case "$(readlink -f "$t")" in "$HARNESS_DIR"/bin/*) rm -f "$t"; echo "  unlinked $(basename "$t")";; esac
done

echo
echo "uninstall.sh: done. Kept secrets/, log/, backups/ and $HARNESS_CONFIG."
echo "Re-install with: $HARNESS_DIR/install.sh"
