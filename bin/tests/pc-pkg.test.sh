#!/usr/bin/env bash
# pc-pkg against stub sudo/apt-get/apt-cache/apt-mark/dpkg-query and a temp ledger: new set parsed, already installed, refusals, ledgered install, undo, ownership, auto marks, ci-window; mutants go red.
set -uo pipefail
BIN="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
. "$HOME/agents/bin/tests/lib/assert.sh"

real_sum() { md5sum "$HOME/agents/log/changes.jsonl" 2>/dev/null; }
before=$(real_sum)
mkdir -p "$W/path" "$W/db"; touch "$W/db/iw" "$W/db/curl" "$W/db/oldpkg"
cat >"$W/path/sudo" <<'EOF'
#!/bin/sh
[ "$1" = -n ] && shift
exec "$@"
EOF
cat >"$W/path/apt-get" <<EOF
#!/usr/bin/env bash
db=$W/db; echo "apt-get \$*" >>$W/calls
sim=0; op=; pk=()
for a; do case \$a in -s) sim=1;; -*) ;; install|remove) op=\$a;; *) pk+=("\$a");; esac; done
for p in "\${pk[@]}"; do case " iw nvme-cli libnvme1 clash curl oldpkg docker.io dockerish " in *" \$p "*) ;; *) echo "E: Unable to locate package \$p"; exit 100;; esac; done
list=()
for p in "\${pk[@]}"; do
  if [ "\$op" = install ]; then
    for q in \$([ "\$p" = nvme-cli ] && echo libnvme1; [ "\$p" = dockerish ] && echo docker.io) \$p; do [ -e "\$db/\$q" ] || list+=("\$q"); done
  else
    for q in \$p \$([ "\$p" = libnvme1 ] && echo nvme-cli); do [ -e "\$db/\$q" ] && list+=("\$q"); done
  fi
done
for q in "\${list[@]}"; do
  if [ \$sim = 1 ]; then [ "\$op" = install ] && echo "Inst \$q (1.0 Ubuntu:26.04 [amd64])" || echo "Remv \$q [1.0]"
  elif [ "\$op" = install ]; then touch "\$db/\$q"; case " \${pk[*]} " in *" \$q "*) rm -f "\$db/\$q.auto";; *) touch "\$db/\$q.auto";; esac
  else rm -f "\$db/\$q" "\$db/\$q.auto"; fi
done
[ \$sim = 1 ] && [ "\$op \${pk[*]}" = "install clash" ] && echo 'Remv oldpkg [1.0]'
exit 0
EOF
cat >"$W/path/dpkg-query" <<EOF
#!/bin/sh
for p; do case \$p in -*) continue;; esac; [ -e "$W/db/\$p" ] && echo "\$p installed" || echo "\$p not-installed"; done
EOF
cat >"$W/path/apt-mark" <<EOF
#!/bin/sh
op=\$1; shift
[ "\$op" = auto ] && echo "apt-mark auto \$*" >>$W/calls
for p; do case \$op in showauto) [ -e "$W/db/\$p.auto" ] && echo "\$p";; auto) touch "$W/db/\$p.auto";; esac; done
exit 0
EOF
cat >"$W/path/apt-cache" <<'EOF'
#!/bin/sh
for p; do case $p in -*|show) continue;; esac; printf 'Package: %s\nInstalled-Size: 2048\n\n' "$p"; done
EOF
chmod +x "$W/path/"*
export PATH="$W/path:$PATH" PC_LEDGER="$W/changes.jsonl" XDG_RUNTIME_DIR="$W"
h=$(date +%H); [ "$h" -lt 20 ] && export CI_WINDOW=23:00-23:30 || export CI_WINDOW=03:00-03:30
[ "$(command -v sudo)" = "$W/path/sudo" ] && [ "$(command -v apt-get)" = "$W/path/apt-get" ] \
  && ok 'sandbox: sudo and apt-get are stubs' || nok sandbox 'real sudo or apt-get on PATH'

pk() { "$BIN/pc-pkg" "$@"; }
ev 'line 2 is the pc help signature' '[[ "$(sed -n 2p "$BIN/pc-pkg")" == "# pc pkg install|remove"* ]]'
is 'dry run prints the new set with its size' "$(pk install nvme-cli)" 'would: install libnvme1 nvme-cli (4.0 MB)'
ev 'dry run only simulates' '! grep -v -- " -s " "$W/calls"'
is 'already installed is nothing' "$(pk install iw)" 'nothing: already installed'
is 'a mix prints only the new part' "$(pk install iw nvme-cli)" 'would: install libnvme1 nvme-cli (4.0 MB)'
pk install nvme-cli --auto curl >/dev/null 2>&1; is 'an --auto name outside the new set exits 2' "$?" 2
pk install docker.io >/dev/null 2>&1; is 'a deny-listed name exits 3' "$?" 3
pk install linux-image-generic >/dev/null 2>&1; is 'linux-* exits 3' "$?" 3
pk install dockerish >/dev/null 2>&1; is 'a deny-listed dependency exits 3' "$?" 3
is 'an install that would remove a package is refused' "$(pk install clash 2>&1; echo $?)" $'pc pkg: refused, apt would also remove or upgrade: oldpkg\n1'
pk install -oAPT::x=1 >/dev/null 2>&1; is 'an option as a package name exits 2' "$?" 2
is 'an unknown package exits 1 with apt'"'"'s error' "$(pk install nosuch 2>&1; echo $?)" $'E: Unable to locate package nosuch\n1'
is 'remove of a non-ledger package is refused' "$(pk remove curl 2>&1; echo $?)" $'pc pkg: refused, curl was not installed by pc pkg (no ledger row)\n1'

out=$(CI_WINDOW=00:00-23:59 pk install nvme-cli --apply 2>&1 >/dev/null); rc=$?
is 'apply inside ci-window is refused on stderr' "$out|$rc" 'pc pkg: refused, inside the CI window 00:00-23:59|1'
: >"$W/calls"
out=$(pk install iw nvme-cli --apply 2>&1); rc=$?
id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
is 'apply exits 0 and ends with the undo id' "$rc|$(tail -1 <<<"$out")" "0|rollback: pc undo $id"
ev 'both packages installed' '[ -e "$W/db/nvme-cli" ] && [ -e "$W/db/libnvme1" ]'
is 'only the requested new name reaches apt-get' "$(grep -v -- ' -s ' "$W/calls")" 'apt-get install -y -q --no-install-recommends nvme-cli'
is 'ledger row: exact new set, verified' "$(jq -rs --arg id "$id" 'map(select(.id == $id)) | "\(.[0].target)|\(.[0].after)|\(.[1].verified)"' "$PC_LEDGER")" 'pkg libnvme1 nvme-cli|installed|true'
is 'rollback is pc pkg remove of the new set' "$(jq -rs '.[0].rollback' "$PC_LEDGER")" "$BIN/pc-pkg remove libnvme1 nvme-cli --apply"
is 'remove of a ledger package names its dependents' "$(pk remove libnvme1)" 'would: remove libnvme1 nvme-cli (4.0 MB)'
is 'remove of an absent package is nothing' "$(pk remove clash 2>&1)" 'nothing: not installed'

"$BIN/pc-undo" "$id" --apply >"$W/undo" 2>&1; rc=$?
ev 'pc undo removes the new set' '[ "$rc" = 0 ] && [ ! -e "$W/db/nvme-cli" ] && [ ! -e "$W/db/libnvme1" ] && [ -e "$W/db/iw" ]'
is 'the undo is verified' "$(jq -rs 'map(select(has("verified"))) | last | .verified' "$PC_LEDGER")" true
touch "$W/db/nvme-cli" "$W/db/libnvme1"
is 'a package undone, then reinstalled by hand, is not owned' "$(pk remove nvme-cli 2>&1; echo $?)" $'pc pkg: refused, nvme-cli was not installed by pc pkg (no ledger row)\n1'
rm -f "$W/db/nvme-cli" "$W/db/libnvme1"

pk install nvme-cli --apply >/dev/null 2>&1
out=$(pk remove libnvme1 --apply 2>&1); rc=$?; id=$(sed -n 's/^rollback: pc undo //p' <<<"$out")
is 'remove applies; its rollback restores the auto mark' "$rc|$(jq -rs --arg id "$id" 'map(select(.id == $id)) | .[0].rollback' "$PC_LEDGER")" "0|$BIN/pc-pkg install libnvme1 nvme-cli --apply --auto libnvme1"
: >"$W/calls"
"$BIN/pc-undo" "$id" --apply >/dev/null 2>&1; rc=$?
is 'undo of a remove re-marks only the dependency auto' "$rc|$(grep -v -- ' -s ' "$W/calls")|$(set -- "$W"/db/*.auto; echo $#)" $'0|apt-get install -y -q --no-install-recommends libnvme1 nvme-cli\napt-mark auto libnvme1|1'

M="$W/mut"; mkdir -p "$M"; ln -s "$BIN/pclib.sh" "$M/pclib.sh"; [ -e "$BIN/env.sh" ] && ln -s "$BIN/env.sh" "$M/env.sh"; ln -s "$BIN/ci-window" "$M/ci-window"
sed 's/|docker\*|/|/' "$BIN/pc-pkg" >"$M/pc-pkg"; chmod +x "$M/pc-pkg"
is 'mutant without docker* in the deny-list is red' "$("$M/pc-pkg" install docker.io 2>&1; echo $?)" $'would: install docker.io (2.0 MB)\n0'
sed 's/\[\[ \$mine == \*" \${p%:\*} "\* \]\] ||/true ||/' "$BIN/pc-pkg" >"$M/pc-pkg"
"$M/pc-pkg" remove curl >/dev/null 2>&1; [ $? = 0 ] && ok 'mutant without the ledger check is red' || nok mutant 'still refused'

is 'real ledger untouched' "$(real_sum)" "$before"
exit $bad
