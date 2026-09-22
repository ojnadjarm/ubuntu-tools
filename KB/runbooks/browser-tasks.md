# Runbook: end a browser task without leaving a tree behind

1. The Playwright MCP server and its headless Chrome live as long as the session that opened
   them, not as long as the task: 1.5-2 GB RSS and ~23 wakes/s on an otherwise idle box, for
   days (TSP-020). Close the page with `browser_close` as the last step of every browser task.
2. See it: `pc doctor --quick --json | jq '.[]|select(.name=="browsers")'` — a WARN row once a
   `playwright-mcp` or headless-chrome tree is older than 24 h or above 1 GB. `pc idle`'s
   `other_rss_mb` is the same total, next to `fleet_rss_mb`.
3. The row never kills anything: the tree usually belongs to a live interactive session, so
   ending it is the owner's call (quit that session, or `browser_close` from it).
4. Permanent fix, owner-only: `--isolated` in the Playwright MCP config (fresh in-memory
   profile per session, browser closed on disconnect) — it lives in his Claude settings.
