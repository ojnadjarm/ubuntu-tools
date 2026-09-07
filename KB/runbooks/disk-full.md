# Runbook: disk over 85 % (pc status FAIL resources.disk_root)

1. Where: `df -h /` then `sudo ncdu -x /` (or `du -xhd1 / 2>/dev/null | sort -h | tail`).
2. Usual suspects, cheapest first:
   - `docker system df` -> `docker system prune -af --volumes` (WARNING: `--volumes` drops Moodle DB
     data of stopped stacks; dump first: `docker exec moodle52-db-1 pg_dump -U moodle moodle > ~/dump.sql`).
   - journald: `journalctl --disk-usage` -> `sudo journalctl --vacuum-size=500M`.
   - apt cache: `sudo apt clean`.
   - `~/.cache` (playwright browsers, npm): `du -xhd1 ~/.cache | sort -h | tail`.
3. Old backups: `~/agents/backups` keeps the last 20 tarballs; delete older ones by hand.
4. Verify: `pc status --check` exit 0, and tell the owner what was deleted with `notify-owner`.
