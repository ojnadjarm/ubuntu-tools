#!/usr/bin/env bash
# T278: no file git would push may hold this machine's values; they live in config.env and private-values.
# Usage: no-machine-values.test.sh [repo-dir]   (default: the repo this script lives in)
# Values are read at run time, never written here: config.env, hostname, tailnet/LAN IPs, MACs, $HOME,
# $USER, git identity, and the deny list ~/.config/pc-harness/private-values (one literal per line).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${1:-$(git -C "$HERE" rev-parse --show-toplevel)}"
CONF="${HARNESS_CONFIG:-$HOME/.config/pc-harness/config.env}"
PRIV="${PRIVATE_VALUES:-$HOME/.config/pc-harness/private-values}"
# Recorded history keeps its literals on purpose (frozen benchmark arms and trajectories).
SKIP="${NO_MACHINE_VALUES_SKIP:-^bench/}"
bad=0
ok() { if [ "$1" = 1 ]; then echo "PASS $2"; else echo "FAIL $2"; bad=$((bad+1)); fi; }

values() {
  local fqdn
  [ -r "$CONF" ] && (set -a; . "$CONF"; printf '%s\n' "${HARNESS_HOST:-}" "${HARNESS_LAN_IP:-}" \
    "${HARNESS_TAILNET_FQDN:-}" "${HARNESS_BUDS_MAC:-}" "${HARNESS_OWNER_EMAIL:-}" "${HARNESS_OWNER_NAME:-}")
  fqdn="$( [ -r "$CONF" ] && (. "$CONF"; printf '%s' "${HARNESS_TAILNET_FQDN:-}"))"
  [ -n "$fqdn" ] && printf '%s\n' "${fqdn%%.*}" "$(printf '%s' "$fqdn" | cut -d. -f2)"
  hostname; printf '%s\n' "$HOME" "$(id -un)"
  git config --global user.email; git config --global user.name
  tailscale ip 2>/dev/null
  ip -4 -o addr show scope global 2>/dev/null | awk '$2 !~ /^(docker|br-|veth|tailscale)/ {sub("/.*","",$4); print $4}'
  ip -o link 2>/dev/null | awk '$2 !~ /^(docker|br-|veth|lo:)/ {for(i=1;i<NF;i++) if($i=="link/ether") print $(i+1)}'
  [ -r "$PRIV" ] && grep -vE '^\s*(#|$)' "$PRIV"
} 2>/dev/null

# patterns: one ERE per value, bounded so 10.0.0.1 does not match 10.0.0.12.
patterns() {
  values | awk 'length($0) >= 4' | sort -u | while IFS= read -r v; do
    e="$(printf '%s' "$v" | sed 's/[][\.*^$+?(){}|/]/\\&/g')"
    printf '(^|[^[:alnum:]])%s([^[:alnum:]]|$)\n' "$e"
  done
}

# scan <dir> <patternfile>: prints "file:line:text" for every hit in a file git would push.
scan() {
  (cd "$1" && git ls-files --cached --others --exclude-standard -z | tr '\0' '\n' | sort -u \
     | grep -vE "$SKIP" | while IFS= read -r f; do
         [ -L "$f" ] || [ ! -f "$f" ] && continue
         printf '%s\0' "$f"
       done | xargs -0 -r grep -nIiE -D skip -d skip -f "$2" 2>/dev/null)
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
patterns > "$tmp/pat"
n="$(wc -l < "$tmp/pat")"
[ "$n" -ge 3 ] && ok 1 "machine values read at run time ($n)" || ok 0 "machine values read at run time ($n)"

# Selftest: a throwaway repo with one planted value must go red, a clean one green.
mkdir -p "$tmp/fx" && git -C "$tmp/fx" init -q && echo "clean" > "$tmp/fx/a.txt"
[ -z "$(scan "$tmp/fx" "$tmp/pat")" ] && ok 1 "selftest: clean fixture passes" || ok 0 "selftest: clean fixture passes"
printf 'url http://%s:8070/\n' "$(hostname)" > "$tmp/fx/b.txt"
[ -n "$(scan "$tmp/fx" "$tmp/pat")" ] && ok 1 "selftest: planted value caught" || ok 0 "selftest: planted value caught"

out="$(scan "$REPO" "$tmp/pat")"
if [ -z "$out" ]; then ok 1 "no machine values in $(basename "$REPO")"
else
  ok 0 "no machine values in $(basename "$REPO") ($(printf '%s\n' "$out" | wc -l) hits)"
  printf '%s\n' "$out" | cut -d: -f1 | sort | uniq -c | sort -rn | head -40
  printf '%s\n' "$out" | cut -c1-160 | head -20
fi

[ "$bad" = 0 ] && echo "all no-machine-values cases pass" || echo "$bad FAILURES"
exit $([ "$bad" = 0 ] && echo 0 || echo 1)
