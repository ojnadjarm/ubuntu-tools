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
. "$HOME/agents/bin/tests/lib/assert.sh"

for c in sudo etckeeper systemctl gsettings tmux dpkg dpkg-query; do
  printf '#!/bin/sh\necho "BLOCKED %s $*" >>"%s"\nexit 97\n' "$c" "$BLOCKED" >"$SHIM/$c"
done
printf '#!/bin/sh\nprintf "Name Version\\nfirefox 1\\nmyapp 2\\n"\n' >"$SHIM/snap"
printf '#!/bin/sh\ncat "%s" 2>/dev/null\n:\n' "$WORK/apt-manual" >"$SHIM/apt-mark"
printf '#!/bin/sh\ncat "%s" 2>/dev/null\n:\n' "$WORK/apt-history" >"$SHIM/zcat"
chmod +x "$SHIM"/*

run() {
  env -i HOME="$WORK/home" PATH="$SHIM:/usr/bin:/bin" MI_ETC="${MI_ETC:-$E}" MI_SUDO= MI_INSTALL_END=1600000000 MI_HARNESS="$WORK/harness" \
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

# Packages: one in the doc, one in a DEPS.tsv apt column, one in an install.sh-read DEPS list, one in a literal apt line, one nowhere.
mkdir -p "$WORK/harness/bin"
printf '# gamedev-cpp: inlist\nfoo\tdepspkg other\tverb\toptional:media\nbar\t-\tverb\trequired\n' >"$WORK/harness/bin/DEPS.tsv"
printf 'pkgs="$(sed -n '"'"'s/^# gamedev-cpp: //p'"'"' bin/DEPS.tsv)"\necho "install with: sudo apt install literalpkg"\n' >"$WORK/harness/install.sh"
printf 'Start-Date: 2099-01-01  10:00:00\nCommandline: apt-get install x\nInstall: docpkg:amd64 (1), depspkg:amd64 (1), inlist:amd64 (1), literalpkg:amd64 (1), lonely:amd64 (1)\n' >"$WORK/apt-history"
printf 'docpkg\ndepspkg\ninlist\nliteralpkg\nlonely\n' >"$WORK/apt-manual"
printf 'Restore `/etc/mod.conf`, `/etc/new.conf`, `/etc/pre.conf` and `/etc/gone*`.\nsnap myapp; units a.service b.timer c.service.d; apt docpkg\n' >"$WORK/doc.md"
out=$(run bash "$BIN" --check -v "$WORK/doc.md" 2>&1); rc=$?
[ "$rc" = 1 ] && [[ $out == *"GAP package lonely"* && $out == *"gaps: 1"* \
  && $out == *"ok package docpkg documented by: doc"* && $out == *"ok package depspkg documented by: DEPS.tsv"* \
  && $out == *"ok package inlist documented by: install.sh"* && $out == *"ok package literalpkg documented by: install.sh"* ]] \
  && ok "--check -v: DEPS.tsv row and install.sh lists cover packages, unlisted one stays GAP" || nok "--check packages" "rc=$rc $out"
out=$(run bash "$BIN" --check "$WORK/doc.md" 2>&1)
[[ $out != *"documented by"* ]] && ok "--check without -v: no source lines" || nok "--check quiet" "$out"
# T1003: `apt  install dbla  dblb` (double spaces) yields dbla and dblb, not the word install.
printf 'sudo apt  install dbla  dblb\n' >"$WORK/harness/install.sh"
printf 'Start-Date: 2099-01-01  10:00:00\nInstall: dbla:amd64 (1), dblb:amd64 (1), install:amd64 (1)\n' >"$WORK/apt-history"
printf 'dbla\ndblb\ninstall\n' >"$WORK/apt-manual"
out=$(run bash "$BIN" --check -v "$WORK/doc.md" 2>&1)
[[ $out == *"ok package dbla documented by: install.sh"* && $out == *"ok package dblb documented by: install.sh"* \
  && $out == *"GAP package install"* && $out == *"gaps: 1"* ]] \
  && ok "--check: apt install words split on runs of spaces" || nok "--check double space" "$out"
rm -f "$WORK/apt-history" "$WORK/apt-manual"

out=$(run bash "$BIN" --check "$WORK/nodoc.md" 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == *"cannot read"* ]] && ok "--check unreadable doc: exit 2" || nok "--check nodoc" "rc=$rc $out"

mkdir "$WORK/empty"
out=$(MI_ETC="$WORK/empty" run bash "$BIN" --etc 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == *"no etckeeper history"* ]] && ok "no etckeeper repo: refused, exit 2" || nok "no history" "rc=$rc $out"

out=$(run bash "$BIN" --bogus 2>&1); rc=$?
[ "$rc" = 2 ] && [[ $out == usage:* ]] && ok "bad argument: usage, exit 2" || nok "bad argument" "rc=$rc"

# Pristine check on a 50-file fixture: stub sudo logs each call, stub dpkg owns every file, even files ship unchanged.
S2="$WORK/shim2"; E2="$WORK/etc2"; mkdir -p "$S2" "$E2"; cp "$SHIM"/* "$S2"/
printf '#!/bin/sh\necho "$*" >>"%s"\n[ "$1" = -n ] && shift\nexec "$@"\n' "$WORK/sudo.log" >"$S2/sudo"
printf '#!/bin/sh\necho "$*" >>"%s"\nshift\necho "diversion by other from: /etc/f2.conf"\nfor p; do echo "pkg:amd64: $p"; done\n' "$WORK/dpkg.log" >"$S2/dpkg"
printf '#!/bin/sh\necho pkg\ncat "%s"\n' "$WORK/conffiles" >"$S2/dpkg-query"
chmod +x "$S2"/*
echo base >"$E2/base"; run git -C "$E2" init -q && run git -C "$E2" add -A && run git -C "$E2" commit -qm base
for i in $(seq 1 50); do
  echo "f$i" >"$E2/f$i.conf"
  [ $((i % 2)) = 0 ] && h=$(md5sum <"$E2/f$i.conf" | cut -d' ' -f1) || h=0
  echo " /etc/f$i.conf $h" >>"$WORK/conffiles"
done
out=$(env -i HOME="$WORK/home" PATH="$S2:/usr/bin:/bin" MI_ETC="$E2" MI_SUDO="sudo -n" MI_PRISTINE=1 MI_INSTALL_END=1600000000 \
  bash "$BIN" --etc 2>&1)
want=$(for i in $(seq 1 2 49); do echo "A f$i.conf"; done | LC_ALL=C sort -k2)
n=$(grep -c md5sum "$WORK/sudo.log"); d=$(grep -c '^-S ' "$WORK/dpkg.log")
[ "$out" = "$want" ] && [ "$n" = 1 ] && [ "$d" = 1 ] \
  && ok "--etc pristine: 50 files in 1 dpkg -S and 1 sudo md5sum, diversion skipped, 25 changed listed" \
  || nok "--etc pristine" "dpkg -S calls=$d md5sum sudo calls=$n out=$(echo $out | head -c 200)"

[ -s "$BLOCKED" ] && nok "no blocked calls" "$(head -1 "$BLOCKED")" || ok "no blocked call during the run"
[ "$bad" = 0 ] && echo "PASS machine-inventory" || { echo "FAIL machine-inventory"; exit 1; }
