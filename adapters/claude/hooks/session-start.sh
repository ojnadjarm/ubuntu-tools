#!/usr/bin/env bash
# Claude Code SessionStart hook: the whole context comes from `harness context --json`.
exec "$HOME/agents/bin/harness" context --json
