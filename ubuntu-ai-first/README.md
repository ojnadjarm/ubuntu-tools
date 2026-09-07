# Ubuntu AI-first — read me (owner)

1. **What this is.** The plan to make `moodle-lab` a machine that Claude agents run 24/7: desktop, browsers, files, services, kernel settings, scheduling, self-repair. Main work stays Moodle development in Docker.
2. **Where the plan is.** `~/agents/ubuntu-ai-first/PLAN.md` (vision, current state, architecture, roadmap, risks, 5 questions for you).
3. **Tickets.** `~/agents/ubuntu-ai-first/tickets/T01…T27-*.md`, one per task, 30–90 min of agent work each, phase order. Each has Goal, Steps, Success check, Rollback.
4. **How a ticket runs.** You tell the orchestrator "run T05". It spawns one Opus agent with the ticket file as the brief, the agent does the work, runs the success check itself, reports; the orchestrator relays the result in your terms and stops the agent.
5. **Order.** Phase 0 first (safety net, always-on desktop, reboot survival, push channel, `pc status`). Then desktop control, browser, agent runtime, OS tuning, extras. Dependencies are listed at the end of the roadmap.
6. **Your part.** Answer the 5 questions in PLAN §7 (defaults are fine), subscribe to the ntfy topic after T04, close the lid once after T02, and confirm the agent roster after T19.
7. **Rules that never change.** Agents never commit or push git. Agents never ask you about machine state they can read themselves. Two SSH paths are kept alive before any access change.
8. **Where to look later.** `agents-status` (what runs when), `agents-log` (what agents did), `~/agents/<name>/REPORT.md` (last run of each persistent agent), `agents-stop` (kill switch).
9. **Progress.** The orchestrator marks finished tickets in PLAN §5 with `[done YYYY-MM-DD]`.
