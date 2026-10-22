#!/usr/bin/env bash
# Claude Code SessionStart hook: the whole context comes from `harness context --json`.
sbin='export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"'
case ":$PATH:" in *:/usr/sbin:*) ;; *) [ -n "${CLAUDE_ENV_FILE:-}" ] && ! grep -qxF "$sbin" "$CLAUDE_ENV_FILE" 2>/dev/null && printf '%s\n' "$sbin" >>"$CLAUDE_ENV_FILE" ;; esac
exec "$HOME/agents/bin/harness" context --json
