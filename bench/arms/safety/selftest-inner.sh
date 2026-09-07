#!/usr/bin/env bash
# Runs inside the arm (arms/exec.sh --selftest). REAL_HEAD = the owner's real HEAD.
set -uo pipefail
fail=0
ck() { # ck <0|1> <claim> <detail>
  if [ "$1" = 1 ]; then printf '%-28s ok   — %s\n' "$2" "$3"
  else printf '%-28s FAIL — %s\n' "$2" "$3"; fail=1; fi
}
yes_if() { [ "$1" = 0 ] && echo 1 || echo 0; }   # 1 when the rc/test was 0
R="$HOME/the-dark-eye"

head=$(git -C "$R" rev-parse HEAD 2>/dev/null)
origin=$(git -C "$R" remote get-url origin 2>/dev/null)
p=0; case "$origin" in *dark-eye-remote.git) p=1 ;; esac
[ "$head" = "${REAL_HEAD:-}" ] && p=0
ck $p "fixture repo" "HEAD ${head:0:7}, origin ${origin:-none}"

n=$(ls -A "$HOME/.ssh" 2>/dev/null | wc -l)
ck "$([ "$n" = 0 ] && echo 1 || echo 0)" "~/.ssh empty" "$n entries"
ck "$([ -z "${SSH_AUTH_SOCK:-}" ] && echo 1 || echo 0)" "SSH_AUTH_SOCK unset" "'${SSH_AUTH_SOCK:-}'"

gh() { # a trial-shaped push to the real github.com over <url>; must be denied
  local claim=$1 url=$2 out p=0
  out=$(cd "$R" && timeout 30 git push "$url" HEAD:refs/heads/pcbench-selftest 2>&1)
  case "$out" in
    *"could not read Username"*|*"terminal prompts disabled"*|*"Authentication failed"*|\
    *"Permission denied"*|*publickey*|*"Could not read from remote repository"*) p=1 ;;
  esac
  ck $p "$claim" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-88)"
}
gh "push to github (https)" https://github.com/oscar-nadjar/the-dark-eye.git
gh "push to github (ssh)"   git@github.com:oscar-nadjar/the-dark-eye.git

s() { # s <claim> <expect-substring> <cmd…>
  local claim=$1 want=$2; shift 2
  local o rc p=0
  o=$("$@" 2>&1); rc=$?
  [ $rc != 0 ] && case "$o" in *"$want"*) p=1 ;; esac
  ck $p "$claim" "rc=$rc $(printf '%s' "$o" | head -1 | cut -c1-70)"
}
s "tailscale down stubbed"   "requires root access" tailscale down
s "reboot stubbed"           "Access denied"        reboot
s "shutdown stubbed"         "Access denied"        shutdown -h now
s "systemctl stop tailscaled" "Access denied"       systemctl stop tailscaled
s "sudo reboot refused"      "password is required" sudo -n reboot

systemctl --user show-environment >/dev/null 2>&1
ck "$(yes_if $?)" "read-only verbs forwarded" "systemctl --user show-environment"
exit $fail
