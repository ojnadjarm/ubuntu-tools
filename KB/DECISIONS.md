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
- 2026-10-19 · ai-avatars: T702's posed-SDF method is the avatar standard, packaged as skill /pixel-avatar (T705); walks refined, rest kept · "702 win over 701 ... we create the skill over T702 But we need to refine the walk animations"
- 2026-10-19 · Maps: the T703/T707 slice method is the map standard, packaged as skill /pixel-scene (T709); it calls /pixel-foliage for all vegetation · "After that skill for the map and JUST FOR THE FOLLIAGE"
- 2026-10-20 · ai-avatars: drop T701 for good; T702 avatars stay, animations kept, hands rebuilt as mitten + grip-state model in /pixel-avatar (T712) · "keep just T702 avatars T701 Not good enough ... we need to improve hands but the animations looks really good"
- 2026-10-20 · Foliage: T715 rigid-piece method (whole-pixel cluster/leaf steps, baked atlases, no displacement shader) is the /pixel-foliage standard; T710/T713 code kept in legacy/ and served to pixel-scene by a species.py shim until maps switch · brief T715 "throw away the T710/T713 foliage method ... build a new one from zero"
- 2026-10-20 · Ticket ids: wave 18 #1/#2/#3 keep T716/T717/T718 for evidence and history, referred to as T700#1/T700#2/T700#3; the Vass briefs/reports (MIRASMANT-26 T716/T717, MIRASMANT-5 T718) are never renamed; new ids only from `ticket-id next` (planners `--reserve`) (T741) · brief T741 "Vass briefs never renamed"
- 2026-10-20 T735 self-kill guard: owner accepted 10/17 replay coverage as final.
- 2026-10-27 · discord-liaison: one live job per conversation (forum thread, or one author in #general); a new message there stops the live job and starts one with the whole thread; triage decides on the newest message; the bot nudges a path unit, 20 s debounce, 3-min timer as fallback; code reacts 👀 on arrival (T1421) · "cada mensaje que envio crea un nuevo agente… hace una peticion de un mensaje anterior"
