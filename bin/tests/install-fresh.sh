#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034,SC2088  # strings run by eval or by the container shell
# T456: install.sh, then uninstall.sh, on fresh Ubuntu containers (systemd PID 1, --network none, tracked files only).
# usage: install-fresh.sh [--suite] [--skills] [--gamedev] [24.04 26.04 ...]   last line: PASS/FAIL install-fresh ...
# --suite: also run FLEET_FRESH=1 bin/tests/run.sh -j 4 in every release's container (host-only files SKIP); red list per release
#   to ${SUITE_OUT%.txt}-<ver>.txt. --skills: ship the untracked skills/ too and run run.sh --skills (docker shimmed).
#   It gets the latest node <N>.x tarball (N: DEPS.tsv node row, 5th field), sha256-checked on the host and logged.
#   That container starts on the bridge for `install.sh --test-deps` (apt) and the npm:/playwright: test rows of DEPS.tsv,
#   and is cut off the network before install.sh.
#   SUITE_ONLY=<glob> passes run.sh --only. --gamedev (with --suite --skills): in the release matching this host, `install.sh --gamedev` on the bridge (apt + vcpkg)
#   and the host's vcpkg binary cache mounted read-only, so the C++ template builds offline and runs on lavapipe.
set -uo pipefail
REAL="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
FX="$REAL/bin/tests/fixtures/install-fresh"
SUITE=0 SKILLS="" GAMEDEV=0
while [ $# -gt 0 ]; do case $1 in --suite) SUITE=1; shift;; --skills) SKILLS=--skills; shift;; --gamedev) GAMEDEV=1; shift;; *) break;; esac; done
VCACHE="${VCPKG_DEFAULT_BINARY_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/vcpkg/archives}"
SUITE_OUT="${SUITE_OUT:-${AGENT_WORK:-$HOME/agent-work}/evidence/install-fresh/fresh-suite.txt}"
VERSIONS=("${@:-24.04}"); [ $# -gt 0 ] || VERSIONS=(24.04 26.04)
C="t456-install-fresh-$$"
trap 'docker rm -f "$C" >/dev/null 2>&1' EXIT
fails=0; summary=""
ok() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails + 1)); fi; }
# A random non-word user: no-person-hardcoded greps the tree for the user name, so it must appear nowhere.
CU="fx$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"; CH="/home/$CU"
X() { docker exec -u "$CU" -e USER="$CU" -e HOME="$CH" -e XDG_RUNTIME_DIR="/run/user/$CUID" \
        -e PATH="$CH/.local/bin:/usr/local/bin:/usr/bin:/bin" -w "$CH" "$C" bash -c "$1"; }

# Latest node <N>.x linux-x64 from nodejs.org, checked against its SHASUMS256.txt and cached; extracted dir on stdout.
node_dist() {
  local maj u sums name d="$HOME/.cache/install-fresh"
  maj="$(awk -F'\t' '$1 == "node" { sub(/^>= /, "", $5); print $5 }' "$REAL/bin/DEPS.tsv")"
  u="https://nodejs.org/dist/latest-v${maj:?no node min in DEPS.tsv}.x"
  sums="$(curl -fsSL "$u/SHASUMS256.txt")" || return 1
  name="$(awk '$2 ~ /-linux-x64\.tar\.xz$/ { print $2 }' <<<"$sums")"
  mkdir -p "$d"
  if [ ! -d "$d/${name%.tar.xz}" ]; then
    curl -fsSL -o "$d/$name" "$u/$name" && (cd "$d" && grep "  $name\$" <<<"$sums" | sha256sum -c --quiet) \
      && tar -xJf "$d/$name" -C "$d" && rm "$d/$name" || return 1
  fi
  echo "  node: $name sha256 $(awk -v n="$name" '$2 == n { print $1 }' <<<"$sums") ($u)" >&2
  echo "$d/${name%.tar.xz}"
}

# Host residue the run must not touch: fleet links and user units.
host_state() { find "$HOME/.local/bin" "$HOME/.config/systemd/user" -printf '%p %l %s %T@\n' 2>/dev/null | sort | md5sum; }
before="$(host_state)"

for v in "${VERSIONS[@]}"; do
  echo "== ubuntu:$v"
  docker build -q --build-arg "BASE=ubuntu:$v" --build-arg "CU=$CU" -t "install-fresh:$v" "$FX" >/dev/null \
    || { echo "  FAIL image build"; fails=$((fails + 1)); continue; }
  # No --privileged, no binds: SYS_ADMIN only to remount the private cgroup namespace rw for systemd;
  # seccomp and the /proc masks off so bwrap may pivot_root and mount proc (the bwrap-sandboxed tests).
  net=none; [ "$SUITE" = 1 ] && net=bridge
  # The binary cache only hits with this host's gcc and vcpkg cmake, i.e. the same release.
  gd=0 mnt=(); [ "$GAMEDEV$SUITE" = 11 ] && [ -n "$SKILLS" ] && [ "$v" = "$(sed -n 's/^VERSION_ID="\(.*\)"$/\1/p' /etc/os-release)" ] \
    && gd=1 mnt=(-v "$VCACHE:/opt/vcpkg-archives:ro")
  docker run -d -t --name "$C" --network "$net" --cgroupns=private --cap-add SYS_ADMIN \
    --security-opt apparmor=unconfined --security-opt seccomp=unconfined --security-opt systempaths=unconfined \
    --tmpfs /run --tmpfs /run/lock --tmpfs /tmp "${mnt[@]}" \
    "install-fresh:$v" sh -c 'mount -o remount,rw /sys/fs/cgroup && exec /sbin/init' >/dev/null
  CUID="$(docker exec "$C" id -u "$CU")"
  ok "systemd boots" 'docker exec "$C" timeout 60 sh -c "until systemctl is-system-running 2>/dev/null | grep -qE \"^(running|degraded)\\$\"; do sleep 1; done"'
  ok "systemd --user reachable" 'X "timeout 30 sh -c \"until systemctl --user show-environment >/dev/null 2>&1; do sleep 1; done\""'

  docker exec "$C" mkdir -p "$CH/agents" "$CH/.config/pc-harness"
  # Untracked units/, bin/DEPS.tsv, bin/quiet-gate and test helpers ship too (a clone lacks them until the owner adds them).
  # The box's own config fixture stays out: no-person-hardcoded would find its host and owner name.
  (cd "$REAL" && { git ls-files -z; git ls-files -z --others --exclude-standard units/ bin/DEPS.tsv bin/quiet-gate bin/tests/host-only.txt bin/tests/lib/ bin/tests/fixtures/ dashboard/tests/fixtures/ ${SKILLS:+skills/}; } \
    | python3 -c 'import sys,os;sys.stdout.write("\0".join(p for p in sys.stdin.read().split("\0") if p and os.path.lexists(p) and not p.startswith("bin/tests/fixtures/install-fresh/")))' \
    | tar --null -T - -cf -) | docker cp - "$C:$CH/agents"
  docker cp "$FX/config.env" "$C:$CH/.config/pc-harness/config.env"
  docker exec "$C" chown -R "$CU:$CU" "$CH"
  if [ "$net" = bridge ]; then
    nd="$(node_dist)" && tar -C "$nd" --owner=0 --group=0 -cf - bin include lib share | docker cp - "$C:/usr/local"
    ok "node >= 22.15 in /usr/local ($(docker exec "$C" node --version 2>&1))" \
      'docker exec "$C" node -e "const [a, b] = process.versions.node.split(\".\").map(Number); process.exit(a > 22 || (a == 22 && b >= 15) ? 0 : 1)"'
    ok "install.sh --test-deps: $(docker exec "$C" "$CH/agents/install.sh" --test-deps 2>&1 | tail -n 1)" \
      'docker exec "$C" "$CH/agents/install.sh" --test-deps 2>&1 | grep -qx "install.sh: test deps present"'
    # DEPS.tsv test rows npm:<pkg> (npm -g, which checks the registry's sha512) and playwright:<browser>.
    npms="$(awk -F'\t' '$4 == "test" && $1 ~ /^npm:/ { printf "%s ", substr($1, 5) }' "$REAL/bin/DEPS.tsv")"
    pws="$(awk -F'\t' '$4 == "test" && $1 ~ /^playwright:/ { printf "%s ", substr($1, 12) }' "$REAL/bin/DEPS.tsv")"
    for n in $npms; do echo "  npm: $n@$(docker exec "$C" npm view "$n" version 2>/dev/null) $(docker exec "$C" npm view "$n" dist.integrity 2>/dev/null)"; done
    ok "npm -g $npms+ playwright $pws" 'docker exec "$C" npm install -g --no-fund --no-audit $npms >/dev/null 2>&1 \
      && docker exec "$C" playwright-core install-deps $pws >/dev/null 2>&1 && X "playwright-core install $pws" >/dev/null 2>&1'
    echo "  playwright: $(X 'ls ~/.cache/ms-playwright' | tr '\n' ' ')"
    if [ "$gd" = 1 ]; then
      ok "install.sh --gamedev: $(docker exec -e HOME="$CH" "$C" "$CH/agents/install.sh" --gamedev 2>&1 | tail -n 1)" \
        'docker exec "$C" chown -R "$CU:$CU" "$CH/opt" && X "~/agents/install.sh --gamedev" 2>&1 | grep -qx "install.sh: gamedev present"'
    fi
    docker network disconnect bridge "$C"
  fi
  ok "sandbox: no network, no mounts but the read-only vcpkg cache, not privileged" \
    '[[ "$(docker inspect -f "{{range \$k, \$_ := .NetworkSettings.Networks}}{{\$k}} {{end}}{{range .Mounts}}{{.Destination}}:{{.RW}} {{end}}{{.HostConfig.Privileged}}" "$C")" =~ ^(none )?(/opt/vcpkg-archives:false )?"false"$ ]] && [ "$(docker exec "$C" ip -o link | grep -vc " lo:")" = 0 ]'

  out="$(X '~/agents/install.sh 2>&1; echo "EXIT=$?"')"
  printf '%s\n' "$out" | grep -E '^ *(MISSING|missing advisory|not from apt|sudo apt install|could not|adapter .* exited|.*: line [0-9]+:)' | sed 's/^ */  install: /' | sort -u
  ok "install.sh prints the missing tools and one apt line" '[ "$(grep -c "^  sudo apt install " <<<"$out")" = 1 ]'
  ok "install.sh exits 0" 'grep -qx "EXIT=0" <<<"$out"'
  ok "install.sh applied changes" 'grep -qE "^install.sh: [0-9]+ change\(s\) applied" <<<"$out"'
  ok "fleet units enabled" '[ "$(X "systemctl --user list-units --all --no-legend \"agent@*.timer\" | wc -l")" -gt 0 ]'
  shipped="$(find "$REAL/units" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)"
  missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$shipped") \
    <(X "systemctl --user list-unit-files --no-legend" | awk '{print $1}' | LC_ALL=C sort))"
  echo "  units/: $(grep -c . <<<"$shipped"), missing: [${missing//$'\n'/ }]"
  ok "every unit in units/ is a user unit file" '[ -z "$missing" ]'
  pulse="$(X "systemctl --user is-enabled pulse-5h-reset.timer orchestrator-pulse.timer 2>/dev/null" | tr '\n' ' ')"
  ok "pulse-5h-reset.timer enabled, orchestrator-pulse.timer off by UNITS_OFF (got $pulse)" '[ "$pulse" = "enabled disabled " ]'
  hooks="$(X "jq -r '.hooks[][].hooks[].command' ~/.claude/settings.json 2>/dev/null" | grep -c '/agents/')"
  want="$(jq -r '.hooks[][].hooks[].command' "$REAL/adapters/claude/settings.fragment.json" | grep -c .)"
  ok "hooks wired in ~/.claude/settings.json ($hooks of $want)" '[ "$hooks" -ge "$want" ]'
  ok "harness context" 'X "harness context" | grep -q "^Machine now:"'
  ok "pc status --brief rc 0" 'X "pc status --brief" >/dev/null 2>&1'
  ok "pc status --json" 'X "pc status --json 2>/dev/null" | jq -e "type == \"object\"" >/dev/null'
  ok "guide wait" 'X "guide wait" | grep -q "^guide "'

  out2="$(X '~/agents/install.sh 2>&1; echo "EXIT=$?"')"
  n2="$(sed -n 's/^install.sh: \([0-9]*\) change(s) applied$/\1/p; s/^install.sh: no changes$/0/p' <<<"$out2")"
  [ "$n2" = 0 ] || grep -E '^  (linked|installed|schedule|unit timeout|daemon-reload|enabled|regenerated|created|wrote) ' <<<"$out2" | sed 's/^ */  again: /'
  ok "second install: ${n2:-?} change(s) applied, $(grep -o 'EXIT=[0-9]*' <<<"$out2")" '[ "$n2" = 0 ] && grep -qx "EXIT=0" <<<"$out2"'

  if [ "$SUITE" = 1 ]; then
    so="${SUITE_OUT%.txt}-$v.txt"
    mkdir -p "$(dirname "$so")"
    vb=; [ "$gd" = 1 ] && vb="export VCPKG_BINARY_SOURCES='clear;files,/opt/vcpkg-archives,read'; "
    X "${vb}export FLEET_FRESH=1; ~/agents/bin/tests/run.sh -j 4 $SKILLS ${SUITE_ONLY:+--only '$SUITE_ONLY'} 2>&1" >"$so.log"
    { tail -n 1 "$so.log"
      [ -n "$SKILLS" ] && awk '/^SKIP host-only skills\// || $1 ~ /^(ok|FAIL)$/ && $2 ~ /^skills\// { t++; if ($1 != "FAIL") g++ } END { printf "skills %d/%d pass-or-skip\n", g, t }' "$so.log"
      grep -E '^FAIL (bin|hooks|adapters|dashboard|skills)/' "$so.log" | sort -k2 | while read -r _ f rest; do
        head -n 5 "$REAL/$f" 2>/dev/null | grep -qE '^(#|//) host-only' && rest="$rest host-only"; echo "FAIL $f $rest"
      done; } >"$so"
    echo "  suite (ubuntu:$v): $(head -n 1 "$so")${SKILLS:+, $(sed -n 2p "$so")}, $(grep '^FAIL ' "$so" | grep -vc ' host-only$') red not host-only; red list $so"
  fi

  X '~/agents/uninstall.sh' >/dev/null 2>&1
  ok "uninstall keeps claude-orchestrator.service" 'X "test -f ~/.config/systemd/user/claude-orchestrator.service"'
  X '~/agents/uninstall.sh --with-orchestrator' >/dev/null 2>&1
  links="$(X 'find ~/.local/bin ~/.claude -type l -exec readlink -f {} \; 2>/dev/null | grep -c "^$HOME/agents/"')"
  units="$(X 'find ~/.config/systemd/user -mindepth 1 \( ! -type d -o -name "agent@*" \) 2>/dev/null | wc -l')"
  ok "uninstall: 0 fleet links (got $links)" '[ "$links" = 0 ]'
  ok "uninstall: 0 fleet units (got $units)" '[ "$units" = 0 ]'
  docker rm -f "$C" >/dev/null
  summary="$summary $v"
done

ok "host ~/.local/bin and systemd user dir untouched" '[ "$(host_state)" = "$before" ]'
[ "$fails" = 0 ] && echo "PASS install-fresh:${summary// / ubuntu:}" \
  || echo "FAIL install-fresh: $fails check(s) failed"
