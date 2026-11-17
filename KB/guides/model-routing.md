# Which model runs a task: model routing by class (fix, touchup, build, review, plan, art)

Ticket: T1728 · Last verified: 2026-11-17 by the 14-day run baseline (`~/agent-work/research/2026-11-17/T1728/`)

## When to use
Before every spawn, brief or headless job: name the task's class; the class picks the model and effort, not the topic.
Not for test tiers of a finished diff: that is `change-class` (`guide change-tiers`).

## The path we took
The model was picked by topic in 9 places. Now one CLI, `model-route`, holds the table; `po-work` and the Discord
liaison call it; briefs and agent definitions point at `model-route --table`. This block is its output:
```
Model routing (owner 2026-11-17, T1728): Opus by default. Fable is the scarce budget: only where its judgement pays, and then as the lead.
class    model             effort  who works  when
fix      opus              high    itself     a bug, a red test, a small change or tweak; any topic, visual included
touchup  opus              high    itself     a change to an existing visual or audio piece: colour, spacing, crop, timing, copy, re-encode
build    opus              high    itself     build from a brief or a plan, any size: feature, refactor, wiring, tests, shipping a picked look
review   opus              high    itself     review, audit, research, a question
plan     claude-fable-5-2  high    lead       a plan, an architecture, a ticket table, a hard design with no precedent
art      claude-fable-5-2  medium  itself     a new audiovisual piece whose look is the deliverable: art direction, mockups, character, scene, film, sound identity
1. No class is build. Unsure between two rows: take the Opus row.
2. Lead: Fable writes the plan and one brief per piece, hands the pieces to Opus workers (its own `worker` sub-agents for up to 3 file-disjoint pieces, else the caller starts each as build), reviews their diffs and reports. It edits no product file.
3. Fable does the work itself only for art: a look cannot be split. In a mixed job the art pieces are art; the code, encodes, tests and skill round them are build.
4. A request for Fable on an Opus row is downgraded to Opus with one log line. The owner's own words naming a model win: --owner-said "<his words>".
5. High is the top effort. No dollar caps.
```
Agent definitions: `worker` = fix, touchup, build, review; `planner` = plan (leads); `worker-max` = art.

## Exact commands
```bash
model-route --table                                   # the rule above
model-route --classes                                 # the class names
model-route --class touchup --json                    # model, effort, who, downgraded, note
model-route --class art --model <m> --owner-said "<his words>"   # his named model wins
po-work <p> start T<n> --brief <path> --class <class> --channel <channel> --thread <thread> --asked-by <who>
discord-liaison job <message-id> [--project <id>] --class <class> "<task>"
```
Unknown class: exit 2, nothing starts. A downgrade line from `po-work` or the liaison is correct, not an error.
The class, model and note land in `state/work/T<n>.json` or `job.json`, so the next baseline reads them.

## Baseline (14 days, 2026-11-03 to 11-17, before the rule)
- 1283 agent runs: Opus 1099, Fable 130; Fable took 23 % of weighted-token spend.
- 124 Fable agent runs, all but 2 since 11-09.
- Under this rule 52 of them (42 %, 38 % of Fable agent spend) go to Opus; 9 become lead plus Opus workers.
- 59 stay Fable (33 art, 25 plan, 1 owner-named); 4 face restyles are borderline (touchup by the table).

## Pitfalls (measured)
- The topic rule ("audiovisual = Fable") sent 52 of 124 Fable runs to work Opus does: fixes, touch-ups, builds.
- Reviews ran on `worker-max` on 2026-11-09: a review is `review`, on `worker`, whatever the topic.
- `--owner-said` is recorded, not checked against his message: use it only with his own words.
- New CLI in `~/agents/bin`: run `~/agents/install.sh --links` or live sessions get "command not found".

## Links
- Code: `~/agents/bin/model-route`, `~/agents/bin/po-work`, `~/agents/discord-liaison/liaison/models.py`
- Tests: `bash ~/agents/bin/tests/model-route.test.sh`, `bash ~/agents/bin/tests/po-work.test.sh`
- Design / results: `~/agent-work/research/2026-11-17/T1728/ROUTING.md`, `BASELINE.md`
