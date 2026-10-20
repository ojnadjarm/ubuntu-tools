#!/usr/bin/env bash
# pc-harness installer — idempotent. A second run prints "no changes".
# Never touches secrets/, log/, backups/ or an existing config.env.
set -uo pipefail
HARNESS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$HARNESS_DIR/bin/env.sh"

DEV=0; LINKS=0; TESTDEPS=0; GAMEDEV=0; PLAN=0
for a in "$@"; do
  case "$a" in
    --dev) DEV=1;;
    --links) LINKS=1;;
    --test-deps) TESTDEPS=1;;
    --gamedev) GAMEDEV=1;;
    --plan) PLAN=1;;
    -h|--help) echo 'usage: install.sh [--plan] [--dev|--links|--test-deps|--gamedev]   (--plan writes nothing: prints would: <kind> <what> per change, then plan: N changes; --dev also installs the QA tools of GH19; --links runs only step 3; --test-deps only apt-installs what bin/tests/run.sh needs; --gamedev only installs the C++ template toolchain, vcpkg and lavapipe)'; exit 0;;
    *) echo "install.sh: unknown option $a" >&2; exit 2;;
  esac
done

changes=0
note() { echo "  $*"; changes=$((changes + 1)); }
skip() { [ "${VERBOSE:-0}" = 1 ] && echo "  = $*"; return 0; }
would() { echo "would: $*"; changes=$((changes + 1)); }
planned() { [ "$PLAN" = 1 ] && { echo "plan: $changes changes"; exit "${1:-0}"; }; }

# Step 3, also run alone by --links.
link_commands() {
  echo "3. commands -> ~/.local/bin"
  [ "$PLAN" = 1 ] || mkdir -p "$HOME/.local/bin"
  for f in "$HARNESS_DIR"/bin/*; do
    [ -f "$f" ] && [ -x "$f" ] || continue
    n="$(basename "$f")"
    case "$n" in pc-*|*.sh|*.py) continue;; esac
    t="$HOME/.local/bin/$n"
    if [ "$(readlink -f "$t" 2>/dev/null)" = "$(readlink -f "$f")" ]; then skip "$n"; continue; fi
    [ "$PLAN" = 1 ] && { would link "$n"; continue; }
    ln -sfn "$f" "$t"; note "linked $n"
  done
  # nvm loads only in interactive shells: link its default node (alias chain default -> lts/* -> vX) too.
  nv=default; for _ in 1 2 3 4; do [ -f "$HOME/.nvm/alias/$nv" ] && read -r nv <"$HOME/.nvm/alias/$nv"; done
  for f in "$HOME/.nvm/versions/node/$nv/bin/"{node,npm,npx}; do
    [ -x "$f" ] || continue
    n="$(basename "$f")"; t="$HOME/.local/bin/$n"
    if [ "$(readlink -f "$t" 2>/dev/null)" = "$(readlink -f "$f")" ]; then skip "$n"; continue; fi
    [ "$PLAN" = 1 ] && { would link "$n (nvm $nv)"; continue; }
    ln -sfn "$f" "$t"; note "linked $n (nvm $nv)"
  done
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "  advisory: ~/.local/bin is not on PATH";; esac
}
if [ "$LINKS" = 1 ]; then
  link_commands
  planned
  [ "$changes" = 0 ] && echo "install.sh: no changes" || echo "install.sh: $changes change(s) applied"
  exit 0
fi

# DEPS.tsv level `test` plus its `# test-also:` tools (rows kept at a stronger level); apt only, then exit.
if [ "$TESTDEPS" = 1 ]; then
  also=" $(sed -n 's/^# test-also: //p' "$HARNESS_DIR/bin/DEPS.tsv" | tr '\n' ' ')"
  pkgs=""
  while IFS=$'\t' read -r t apt _ level; do
    case "$t" in ''|'#'*) continue;; esac
    [ "$level" = test ] || [[ "$also" == *" $t "* ]] || continue
    [ "$apt" = - ] && { echo "  not from apt: $t"; continue; }
    case "$t" in
      python3:*) python3 -c "import ${t#python3:}" 2>/dev/null && continue;;
      *) PATH="$PATH:/usr/sbin:/sbin" command -v "$t" >/dev/null && continue;;
    esac
    pkgs="$pkgs $apt"
  done <"$HARNESS_DIR/bin/DEPS.tsv"
  [ -z "$pkgs" ] && { planned; echo "install.sh: test deps present"; exit 0; }
  # shellcheck disable=SC2086
  [ "$PLAN" = 1 ] && { would apt install $pkgs; planned; }
  sudo=sudo; [ "$(id -u)" = 0 ] && sudo=
  # shellcheck disable=SC2086
  $sudo apt-get update -qq && DEBIAN_FRONTEND=noninteractive $sudo apt-get install -y -qq --no-install-recommends $pkgs >/dev/null
  rc=$?; echo "install.sh: test deps:$pkgs (apt rc $rc)"; exit "$rc"
fi

# DEPS.tsv `# gamedev-cpp:` apt packages, vcpkg at the C++ template's builtin-baseline in $VCPKG_ROOT, the FLIP venv; then exit.
if [ "$GAMEDEV" = 1 ]; then
  sudo=sudo; [ "$(id -u)" = 0 ] && sudo=
  pkgs="$(sed -n 's/^# gamedev-cpp: //p' "$HARNESS_DIR/bin/DEPS.tsv")"
  # shellcheck disable=SC2086
  missing="$(dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' $pkgs 2>/dev/null | awk '$1 == "ii" { print $2 }' | sort | comm -13 - <(printf '%s\n' $pkgs | sort) | paste -sd ' ')"
  # shellcheck disable=SC2086
  if [ -n "$missing" ] && [ "$PLAN" = 1 ]; then would apt install $missing
  elif [ -n "$missing" ]; then
    # shellcheck disable=SC2086
    if ! { $sudo apt-get update -qq && DEBIAN_FRONTEND=noninteractive $sudo apt-get install -y -qq --no-install-recommends $missing >/dev/null; }; then
      echo "install.sh: gamedev apt failed: $missing" >&2; exit 1
    fi
    note "apt: $missing"
  fi
  VCPKG_ROOT="${VCPKG_ROOT:-$HOME/opt/gamedev/vcpkg}"
  base="$(jq -r '."builtin-baseline"' "$HARNESS_DIR/skills/gamedev/templates/cpp-vulkan/vcpkg.json")" || exit 1
  if [ "$(git -C "$VCPKG_ROOT" rev-parse HEAD 2>/dev/null)" != "$base" ] && [ "$PLAN" = 1 ]; then would vcpkg "$base in $VCPKG_ROOT"
  elif [ "$(git -C "$VCPKG_ROOT" rev-parse HEAD 2>/dev/null)" != "$base" ]; then
    if ! { mkdir -p "$VCPKG_ROOT" && git -C "$VCPKG_ROOT" init -q \
      && git -C "$VCPKG_ROOT" fetch -q --depth 1 https://github.com/microsoft/vcpkg.git "$base" \
      && git -C "$VCPKG_ROOT" -c advice.detachedHead=false checkout -q FETCH_HEAD; }; then
      echo "install.sh: vcpkg $base fetch failed" >&2; exit 1
    fi
    note "vcpkg $base in $VCPKG_ROOT"
  fi
  if [ ! -x "$VCPKG_ROOT/vcpkg" ] && [ "$PLAN" = 1 ]; then would vcpkg "bootstrap $VCPKG_ROOT/vcpkg"
  elif [ ! -x "$VCPKG_ROOT/vcpkg" ]; then
    "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics >/dev/null || { echo "install.sh: vcpkg bootstrap failed" >&2; exit 1; }
    note "bootstrapped $VCPKG_ROOT/vcpkg"
  fi
  flip="$HOME/opt/gamedev/flip-venv"
  if [ ! -x "$flip/bin/flip" ] && [ "$PLAN" = 1 ]; then would venv "flip-evaluator 1.7 in $flip"
  elif [ ! -x "$flip/bin/flip" ]; then
    { python3 -m venv "$flip" && "$flip/bin/pip" install -q flip-evaluator==1.7 >/dev/null; } || { echo "install.sh: flip-evaluator install failed" >&2; exit 1; }
    note "flip-evaluator 1.7 in $flip"
  fi
  planned
  # vcpkg hashes its own cmake into every package ABI: fetch it now so a later offline build hits the binary cache.
  "$VCPKG_ROOT/vcpkg" fetch cmake >/dev/null || { echo "install.sh: vcpkg fetch cmake failed" >&2; exit 1; }
  [ "$changes" = 0 ] && echo "install.sh: gamedev present" || echo "install.sh: gamedev $changes change(s) applied"
  exit 0
fi

## 1. Prerequisites -----------------------------------------------------------
echo "1. prerequisites"
# bin/DEPS.tsv: tool, apt package(s), verbs, required|advisory, optional min version. Prints what is missing or too old and one apt line; never installs.
req=""; adv=""; noapt=""; pkgs=" "
while IFS=$'\t' read -r t apt _ level min; do
  case "$t" in ''|'#'*) continue;; esac
  case "$t" in
    python3:*) command -v python3 >/dev/null && python3 -c "import ${t#python3:}" 2>/dev/null && continue;;
    *) if PATH="$PATH:/usr/sbin:/sbin" command -v "$t" >/dev/null; then
         v="$("$t" --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
         [ -n "$min" ] && [ "${v:-0}" -lt "${min#>= }" ] && echo "  OLD $t ${v:-?}: needs $min ($level)"
         continue
       fi;;
  esac
  if [ "$level" = required ]; then req="$req $t"; else adv="$adv $t"; fi
  if [ "$apt" = - ]; then noapt="$noapt $t"; continue; fi
  for p in $apt; do case "$pkgs" in *" $p "*) ;; *) pkgs="$pkgs$p ";; esac; done
done <"$HARNESS_DIR/bin/DEPS.tsv"
[ -n "$req" ] && echo "  MISSING required ($(wc -w <<<"$req")):$req" >&2
[ -n "$adv" ] && echo "  missing advisory ($(wc -w <<<"$adv")):$adv — the verbs using them are unavailable"
[ -n "$noapt" ] && echo "  not from apt:$noapt"
[ "$pkgs" != " " ] && echo "  sudo apt install${pkgs% }"
[ -n "$req" ] && { planned 1; exit 1; }
systemctl --user show-environment >/dev/null 2>&1 || {
  [ "$PLAN" = 1 ] && { echo "plan: blocked: systemd --user unreachable"; exit 3; }
  echo "  systemd --user is not reachable (no user session)" >&2; exit 1; }
echo "  ok python3 jq systemd --user"

## 2. config.env --------------------------------------------------------------
echo "2. config"
if [ -r "$HARNESS_CONFIG" ]; then
  skip "config: $HARNESS_CONFIG"
elif [ "$PLAN" = 1 ]; then
  would config "$HARNESS_CONFIG"
else
  mkdir -p "$(dirname "$HARNESS_CONFIG")"
  { echo "# pc-harness configuration for this machine — generated by install.sh $(date +%F)."
    echo "HARNESS_HOST=$(hostname -s)"
    [ -n "${HARNESS_AGENT:-}" ] && echo "HARNESS_AGENT=$HARNESS_AGENT"
  } >"$HARNESS_CONFIG"
  chmod 600 "$HARNESS_CONFIG"
  note "created $HARNESS_CONFIG (see config.example.env for every key)"
  if [ -t 0 ]; then
    printf '  owner name  [%s]: ' "$(git config user.name 2>/dev/null)"; read -r v
    [ -n "$v" ] && echo "HARNESS_OWNER_NAME=$v" >>"$HARNESS_CONFIG"
    printf '  owner email [%s]: ' "$(git config user.email 2>/dev/null)"; read -r v
    [ -n "$v" ] && echo "HARNESS_OWNER_EMAIL=$v" >>"$HARNESS_CONFIG"
    printf '  ntfy topic  (blank to skip pushes): '; read -r v
    if [ -n "$v" ]; then
      mkdir -p "$(dirname "$NTFY_ENV_FILE")"; chmod 700 "$(dirname "$NTFY_ENV_FILE")"
      echo "NTFY_TOPIC=$v" >"$NTFY_ENV_FILE"; chmod 600 "$NTFY_ENV_FILE"
      note "wrote $NTFY_ENV_FILE"
    fi
  fi
  # shellcheck source=/dev/null
  . "$HARNESS_DIR/bin/env.sh"
fi

## 3. Commands on PATH --------------------------------------------------------
# bin/ holds three kinds of file: harness commands, `pc` subcommands (pc-*, dispatched by `pc`,
# never called directly) and libraries (*.sh, *.py). Only the first kind goes on PATH.
link_commands

## 4. systemd units and the roster --------------------------------------------
echo "4. units + roster"
UD="$HOME/.config/systemd/user"
[ "$PLAN" = 1 ] || mkdir -p "$UD"
reload=0
for u in "$HARNESS_DIR"/units/*; do
  n="$(basename "$u")"
  cmp -s "$u" "$UD/$n" && { skip "$n"; continue; }
  [ "$PLAN" = 1 ] && { would unit "$n"; reload=1; continue; }
  cp "$u" "$UD/$n"; note "installed unit $n"; reload=1
done

roster_units=""
for d in "$HARNESS_DIR"/*/; do
  [ -r "$d/BRIEF.md" ] && [ -r "$d/agent.env" ] || continue
  name="$(basename "$d")"
  SCHEDULE=""; ENABLED=no; UNIT_TIMEOUT=""
  # shellcheck source=/dev/null
  . "$d/agent.env"
  [ -n "$SCHEDULE" ] || { echo "  $name: no SCHEDULE= in agent.env, left alone"; continue; }
  dd="$UD/agent@$name.timer.d"
  cur="$(sed -n 's/^OnCalendar=\(..*\)/\1/p' "$dd/schedule.conf" 2>/dev/null | tail -1)"
  if [ "$cur" != "$SCHEDULE" ]; then
    systemd-analyze calendar "$SCHEDULE" >/dev/null || { echo "  $name: invalid SCHEDULE '$SCHEDULE'" >&2; continue; }
    if [ "$PLAN" = 1 ]; then
      would unit "agent@$name.timer.d/schedule.conf = $SCHEDULE"
    else
      mkdir -p "$dd"
      printf '[Timer]\nOnCalendar=\nOnCalendar=%s\n' "$SCHEDULE" >"$dd/schedule.conf"
      note "schedule $name = $SCHEDULE"
    fi
    reload=1
  else
    skip "schedule $name"
  fi
  if [ -n "${UNIT_TIMEOUT:-}" ]; then
    sd="$UD/agent@$name.service.d"; want="$(printf '[Service]\nTimeoutStartSec=%s\n' "$UNIT_TIMEOUT")"
    if [ "$(cat "$sd/timeout.conf" 2>/dev/null)" = "$want" ]; then :
    elif [ "$PLAN" = 1 ]; then would unit "agent@$name.service.d/timeout.conf = $UNIT_TIMEOUT s"; reload=1
    else mkdir -p "$sd"; printf '%s\n' "$want" >"$sd/timeout.conf"; note "unit timeout $name = $UNIT_TIMEOUT s"; reload=1
    fi
  fi
  [ "$ENABLED" = yes ] && roster_units="$roster_units agent@$name.timer"
done

# Units this repo ships that are not agent templates: enable them alongside the roster, except UNITS_OFF.
for u in "$HARNESS_DIR"/units/*.timer "$HARNESS_DIR"/units/*.service; do
  n="$(basename "$u")"
  case "$n" in agent@*) continue;; esac
  case " ${UNITS_OFF-orchestrator-pulse.timer} " in *" $n "*) skip "off $n"; continue;; esac
  case "$n" in *.timer) roster_units="$roster_units $n";;
                 *) grep -q '^\[Install\]' "$u" && roster_units="$roster_units $n";;
  esac
done

[ "$reload" = 1 ] && [ "$PLAN" = 1 ] && would unit daemon-reload
[ "$reload" = 1 ] && [ "$PLAN" = 0 ] && { systemctl --user daemon-reload; note "daemon-reload"; }
for u in $roster_units; do
  case "$(systemctl --user is-enabled "$u" 2>/dev/null)" in
    enabled|enabled-runtime) skip "enabled $u"; continue;;
  esac
  [ "$PLAN" = 1 ] && { would unit "enable $u"; continue; }
  systemctl --user enable --now "$u" >/dev/null 2>&1 && note "enabled $u" \
    || echo "  could not enable $u" >&2
done

## 5. Generated machine facts -------------------------------------------------
echo "5. KB/machine.md"
facts="$HARNESS_DIR/KB/machine.md"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
[ -r "$facts" ] && cat "$facts" >"$tmp"
if PC_FACTS_FILE="$tmp" "$HARNESS_DIR/bin/pc" status --facts --apply >/dev/null 2>&1 && [ -s "$tmp" ]; then
  # The header carries a generation timestamp; compare only the body so a re-run is a no-op.
  if [ -r "$facts" ] && [ "$(grep -v '^# Machine facts (generated' "$tmp")" = "$(grep -v '^# Machine facts (generated' "$facts")" ]; then
    skip "KB/machine.md up to date"
  elif [ "$PLAN" = 1 ]; then
    would config "$facts"
  else
    cp "$tmp" "$facts"; note "regenerated KB/machine.md"
  fi
else
  echo "  could not run pc status --facts --apply — KB/machine.md left as is"
fi

## 6. Agent adapter -----------------------------------------------------------
echo "6. adapter"
agent="${HARNESS_AGENT:-}"
if [ -z "$agent" ]; then
  for c in claude codex gemini opencode; do command -v "$c" >/dev/null && { agent="$c"; break; }; done
  [ -n "$agent" ] && echo "  HARNESS_AGENT is unset; detected '$agent'"
fi
ad="$HARNESS_DIR/adapters/$agent/install"
if [ -n "$agent" ] && [ -x "$ad" ] && [ "$PLAN" = 1 ] && ! grep -q -- '--plan' "$ad"; then
  echo "  adapter $agent: not planned (adapters/$agent/install has no dry run)"
elif [ -n "$agent" ] && [ -x "$ad" ] && [ "$PLAN" = 1 ]; then
  out="$("$ad" --plan)"; rc=$?
  printf '%s\n' "$out" | sed '/^would: /!s/^/  /'
  changes=$((changes + $(grep -c '^would: ' <<<"$out")))
  [ "$rc" = 0 ] || echo "  adapter $agent plan exited $rc" >&2
elif [ -n "$agent" ] && [ -x "$ad" ]; then
  out="$("$ad")"; rc=$?
  printf '%s\n' "$out" | sed 's/^/  /'
  printf '%s' "$out" | grep -q 'no changes' || changes=$((changes + $(grep -c . <<<"$out")))
  [ "$rc" = 0 ] || echo "  adapter $agent exited $rc" >&2
else
  echo "  no adapter to install (HARNESS_AGENT='${agent}')"
fi

## 7. Optional QA tooling -----------------------------------------------------
if [ "$DEV" = 1 ]; then
  echo "7. dev tools"
  command -v shellcheck >/dev/null || echo "  install with: sudo apt install shellcheck"
  command -v shfmt >/dev/null || echo "  install with: sudo apt install shfmt"
  command -v lizard >/dev/null || echo "  install with: pipx install lizard"
  command -v jscpd >/dev/null || echo "  install with: npm install -g jscpd   (nvm node; not on PATH in non-login shells)"
  echo "  metrics: bin/tests/qa-metrics.sh [--baseline]"
fi

## 8. Verdict -----------------------------------------------------------------
echo
planned
[ "$changes" = 0 ] && echo "install.sh: no changes" || echo "install.sh: $changes change(s) applied"
echo
"$HARNESS_DIR/bin/pc" doctor --quick || echo "  advisory: pc doctor --quick found the failures above"
