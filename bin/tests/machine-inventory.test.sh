#!/usr/bin/env bash
# Fixture test for machine-inventory: /etc changes from a fixture etckeeper repo, snaps, units, --check.
# Fixture-only (FLEET §5.6): MI_ETC is a temp git repo, MI_SUDO is empty, HOME is a temp dir; sudo,
# etckeeper, systemctl, gsettings, tmux, dpkg are blocked shims and snap/apt-mark/zcat are fixture
# shims on a PATH without ~/agents/bin, proven by the selftest.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/machine-inventory"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
SHIM="$WORK/shim"; BLOCKED="$WORK/blocked.log"; E="$WORK/etc"; U="$WORK/home/.config/systemd/user"
mkdir -p "$SHIM" "$E/systemd/system/multi-user.target.wants" "$U/c.service.d"
bad=0
ok()  { printf 'ok   %s\n' "$1"; }
nok() { printf 'FAIL %s: %s\n' "$1" "$2"; bad=1; }

for c in sudo etckeeper systemctl gsettings tmux dpkg dpkg-query; do
  printf '#!/bin/sh\necho "BLOCKED %s $*" >>"%s"\nexit 97\n' "$c" "$BLOCKED" >"$SHIM/$c"
done
printf '#!/bin/sh\nprintf "Name Version\\nfirefox 1\\nmyapp 2\\n"\n' >"$SHIM/snap"
printf '#!/bin/sh\n:\n' >"$SHIM/apt-mark"
printf '#!/bin/sh\n:\n' >"$SHIM/zcat"
chmod +x "$SHIM"/*

run() {
  env -i HOME="$WORK/home" PATH="$SHIM:/usr/bin:/bin" MI_ETC="${MI_ETC:-$E}" MI_SUDO= MI_INSTALL_END=1600000000 \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t ${GIT_COMMITTER_DATE:+GIT_COMMITTER_DATE=$GIT_COMMITTER_DATE} "$@"
}

# Selftest: every live-state command resolves to a shim, and a real call is refused with 97.
for c in sudo etckeeper systemctl gsettings tmux snap apt-mark zcat dpkg; do
  [ "$(run bash -c "command -v $c")" = "$SHIM/$c" ] || { echo "selftest FAIL: $c not shimmed"; exit 1; }
done
run systemctl --user stop sentinel-check.timer; r1=$?
run gsettings set org.gnome.mutter dynamic-workspaces true; r2=$?
[ "$r1" = 97 ] && [ "$r2" = 97 ] && [ "$(wc -l <"$BLOCKED")" = 2 ] || { echo "selftest FAIL: real call not blocked ($r1 $r2)"; exit 1; }
: >"$BLOCKED"; ok "selftest: shims on PATH, real systemctl/gsettings blocked, /etc is a fixture repo"

# Baseline (2023) holds keep/mod/gone/hostname and pre.conf, written between install end (2020) and baseline.
for f in keep mod gone; do echo "$f" >"$E/$f.conf"; done
echo host >"$E/hostname"; echo pre >"$E/pre.conf"; touch -d @1650000000 "$E/pre.conf"
run git -C "$E" init -q && run git -C "$E" add -A && GIT_COMMITTER_DATE=@1700000000 run git -C "$E" commit -qm base
[ "$(run git -C "$E" log -1 --format=%ct)" = 1700000000 ] || { echo "selftest FAIL: baseline date"; exit 1; }
run git -C "$E" rm -q gone.conf && run git -C "$E" commit -qm gone
echo changed >>"$E/mod.conf"; echo other >"$E/hostname"; echo new >"$E/new.conf"
ln -s /usr/lib/systemd/system/foo.service "$E/systemd/system/multi-user.target.wants/foo.service"
touch "$U/a.service" "$U/b.timer"

out=$(run bash "$BIN" --etc 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$out" = $'D gone.conf\nM mod.conf\nA new.conf\nA pre.conf' ] \
  && ok "--etc: committed, uncommitted and pre-baseline changes; generated and enablement links skipped" \
  || nok "--etc" "rc=$rc out=$(echo $out)"

out=$(run bash "$BIN" --etc-list 2>&1)
[ "$out" = "$E/mod.conf"$'\n'"$E/new.conf"$'\n'"$E/pre.conf" ] && ok "--etc-list: absolute, existing only" || nok "--etc-list" "$(echo $out)"

[ "$(run bash "$BIN" --snaps)" = myapp ] && ok "--snaps: defaults dropped" || nok "--snaps" "$(run bash "$BIN" --snaps)"
[ "$(run bash "$BIN" --units | paste -sd' ')" = "a.service b.timer c.service.d" ] && ok "--units: fixture units and drop-ins" \
  || nok "--units" "$(run bash "$BIN" --units | paste -sd' ')"

printf 'Restore `/etc/mod.conf`, `/etc/new.conf`, `/etc/pre.conf` and `/etc/gone*`.\nsnap myapp; units a.service b.timer c.service.d\n' >"$WORK/doc.md"
out=$(run bash "$BIN" --check "$WORK/doc.md" 2>&1); rc=$?
[ "$rc" = 0 ] && [[ $out == "gaps: 0"* ]] && ok "--check: full doc, exit 0" || nok "--check full" "rc=$rc $out"

sed -i 's|`/etc/new.conf`, ||; s| b.timer||' "$WORK/doc.md"
out=$(run bash "$BIN" --check "$WORK/doc.md" 2>&1); rc=$?
[ "$rc" = 1 ] && [[ $out == *"GAP etc A /etc/new.conf"* && $out == *"GAP unit b.timer"* && $out == *"gaps: 2"* ]] \
  && ok "--check: missing items listed, exit 1" || nok "--check gaps" "rc=$rc $out"

out=$(run bash "$BIN" --check "$WORK/nodoc.md" 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == *"cannot read"* ]] && ok "--check unreadable doc: exit 2" || nok "--check nodoc" "rc=$rc $out"

mkdir "$WORK/empty"
out=$(MI_ETC="$WORK/empty" run bash "$BIN" --etc 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == *"no etckeeper history"* ]] && ok "no etckeeper repo: refused, exit 2" || nok "no history" "rc=$rc $out"

out=$(run bash "$BIN" --bogus 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == usage:* ]] && ok "bad argument: usage, exit 2" || nok "bad argument" "rc=$rc"

[ -s "$BLOCKED" ] && nok "no blocked calls" "$(head -1 "$BLOCKED")" || ok "no blocked call during the run"
[ "$bad" = 0 ] && echo "PASS machine-inventory" || { echo "FAIL machine-inventory"; exit 1; }
