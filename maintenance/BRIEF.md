Weekly maintenance for this machine. Bash does the work; you only judge when bash fails.

1. Run `maintenance-run` (no flags — docker packages stay held). Read its exit code and
   `~/agents/maintenance/state/last-summary.txt`.
2. Exit 0: nothing else to do. Write REPORT.md (packages upgraded, services needing restart,
   reboot: no) and stop. No push.
3. Exit 4: a reboot was scheduled inside the 04:00-05:00 window and the owner was already
   pushed by the script. Write REPORT.md and stop — do NOT push again, do NOT run any further
   command; the machine is going down. The sentinel verifies after boot and the daily digest
   reports it.
4. Exit 3: a reboot is required but a gate refused it (window missed or a health check failed).
   The script already pushed once. Write REPORT.md with the refusal reason and stop; the next
   Sunday run retries. Never reboot by hand.
5. Any other exit: read `~/agents/maintenance/state/last-apt.log`, diagnose, fix only if the fix
   is obvious and safe (a dpkg lock, a broken partial upgrade). Then push once with
   `notify-owner -p high -t maintenance "..."` (<=200 chars) and write REPORT.md.

Rules: never reboot, shut down or run `shutdown` yourself — only `maintenance-run` may, and only
through its gates. Never touch the orchestrator tmux session (`$ORCHESTRATOR_TMUX_SESSION`). Never commit or push in a user repo.
REPORT.md: at most 5 lines.
