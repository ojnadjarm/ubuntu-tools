# Fleet: standing owner decisions (T396)
One line per decision: `- date · decision · "owner's words"`. Fleet briefs name this file; `brief-lint` warns when they do not.
Project ledgers: `$AGENT_WORK/decisions/<project>.md` (ailearning, portfolio, vass). Code: `lib/decisions.py`.

- 2026-09-07 · Never git commit or push in a user repo · (AGENTS.md §5.1, after the benchmark push incident)
- 2026-09-07 · Tests, benchmarks and experiments run on throwaway fixtures in a sandbox proven by a selftest · (AGENTS.md §5.6)
- 2026-10-08 · Do only what was asked; offer the next step in one line, never queue it · "I never said create an integration just to create me a sandbox"
- 2026-09-21 · Replies are 2-3 short lines; briefs cap the report at ~6 lines, numbers only · "just give me really really short sentences"
- 2026-09-25 · Queue mid-run asks in a follow-up brief; never stop or re-steer a running agent unasked · "you could have waited"
- 2026-09-07 · Machine-internal decisions are the agent's; report the choice in one line · "you are the one to manage"
- 2026-09-07 · No dollar caps or cost targets; the Max plan is the budget · "you put too heavy restriction"
- 2026-09-15 · No reviewer gate per ticket; ship fast, the owner is QA · "You keep adding layers and layers verifications"
- 2026-09-24 · The owner judges mockups; send each link the moment it finishes · "NO, I MUST BE THE JUDGE"
- 2026-09-23 · Architecture (patterns, SOLID) written before any implementation · "IS a mandate"
- 2026-09-05 · Research first and start from something; building from zero needs a stated reason · "we cannot keep doing things that are already done"
- 2026-09-24 · Judge tools by usefulness, never by usage · "judge them by usefulness"
- 2026-10-07 · Machine values only via config.env; tracked files use placeholders · "that is for this PC"
- 2026-10-07 · ~/agents holds fleet tooling only; owner deliverables go to ~/drop or their own repo · "that kind of stuff MUST be on drop"
- 2026-09-07 · The Dark Eye is standalone; fleet work lives in ~/agents · "the dark eye is a standalone project"
- 2026-09-23 · Every agent is `worker` (Opus, high); never max unless he asks · (owner, final)
- 2026-09-24 · Every web page is fluid and responsive at 400-2560 (ailearning excepted) · "ALL WEB DEVELOPMENT MUST BE RESPONSIVE WITHOUT EXCEPTIONS"
- 2026-09-24 · Review material lives on this machine as a local link; no cloud artifacts · "everything should be on our server"
- 2026-10-16 · Automatic reboots re-enabled inside the gated window · "we can re-enable the autorestart"
- 2026-10-19 · Money: keep the research/plans (~/drop/money), build nothing more until he says so · "keep the money plans but we are not going to implement anything yet"
