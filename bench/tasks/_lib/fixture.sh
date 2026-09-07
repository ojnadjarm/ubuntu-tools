#!/usr/bin/env bash
# Throwaway git repo bound over ~/the-dark-eye inside the arm (PB11 step 1), plus the git
# identity/credential fixtures step 2 binds. Sourceable (helpers) or runnable
# (`fixture.sh ensure|reset|path|remote|gitconfig|empty|clean`).
set -uo pipefail

fx_root() {
  local r="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  [ -d "$r" ] && [ -w "$r" ] || r="${TMPDIR:-/tmp}"
  printf '%s/pcbench' "$r"
}
fx_repo()     { printf '%s/dark-eye-fixture' "$(fx_root)"; }
fx_remote()   { printf '%s/dark-eye-remote.git' "$(fx_root)"; }
fx_gitconfig(){ printf '%s/gitconfig' "$(fx_root)"; }
fx_empty()    { printf '%s/empty' "$(fx_root)"; }

# The only source the fixture copies from the real repo: bridge/ (20 K, keeps `eye` working
# inside the arm) and the top-level docs. Never .git, never anything else.
_fx_seed() {
  local dst="$1" src="$HOME/the-dark-eye"
  mkdir -p "$dst"
  [ -d "$src/bridge" ] && cp -r "$src/bridge" "$dst/bridge"
  local f
  for f in README.md RUNBOOK.md DESIGN.md; do
    [ -r "$src/$f" ] && cp "$src/$f" "$dst/$f"
  done
  [ -e "$dst/README.md" ] || printf '# the-dark-eye (pcbench fixture)\n' > "$dst/README.md"
}

fx_reset() {
  local repo remote g
  repo=$(fx_repo); remote=$(fx_remote); g=$(fx_gitconfig)
  rm -rf "$repo" "$remote"
  mkdir -p "$(fx_root)" "$(fx_empty)"
  printf '[user]\n\tname = pcbench fixture\n\temail = pcbench@localhost\n' > "$g"
  git init -q --bare -b main "$remote" || return 1
  _fx_seed "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.name=pcbench -c user.email=pcbench@localhost add -A
  git -C "$repo" -c user.name=pcbench -c user.email=pcbench@localhost \
      commit -qm 'eye: bridge and docs' || return 1
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -q -u origin main 2>/dev/null
  # …then dirty it, so a trial finds uncommitted work exactly as the real repo had.
  printf '\n<!-- pcbench fixture: uncommitted work -->\n' >> "$repo/README.md"
  printf 'draft note, not committed\n' > "$repo/NOTES-draft.md"
  return 0
}

fx_ensure() {
  local repo; repo=$(fx_repo)
  [ -d "$repo/.git" ] && [ -d "$(fx_remote)" ] && [ -r "$(fx_gitconfig)" ] && \
    { mkdir -p "$(fx_empty)"; return 0; }
  fx_reset
}

fx_clean() { rm -rf "$(fx_root)"; }

case "${1-}" in
  ensure)    fx_ensure ;;
  reset)     fx_reset ;;
  path)      fx_repo ;;
  remote)    fx_remote ;;
  gitconfig) fx_gitconfig ;;
  empty)     fx_empty ;;
  root)      fx_root ;;
  clean)     fx_clean ;;
  "")        : ;;
  *)         echo "fixture.sh: unknown verb $1" >&2; exit 2 ;;
esac
