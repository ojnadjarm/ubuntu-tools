# Memory recall: the trigger network that hints memories on every prompt (memory-recall)

Ticket: T1624 (R0-R8) · Last verified: 2026-11-11 by `memory check --recall` (ship gate met, 231 cues), `memory-recall-digest.test.sh`, `claude-install-args.test.sh`

## When to use
- A prompt shows `memory stirs (hints, not orders; open: memory show <id>)`: open a hint only when it matters (`memory show <id>`).
- You change the network, its carriers, its check or the keeper's concepts; you want the weekly number; you need to switch it off.
- Not for reading a card on purpose (`memory load`, guide `agent-memory`) or noting a lesson (`memory note`).

## The path we took
Design N1 "Constellation" (owner picks D1-D5 all A, 2026-11-11): concepts and memories as a graph, activation spreads
2 steps from the prompt's cue words (fan effect, base level from his dates), a memory fires above its threshold with
2 cue paths, one per place and rival set, at most 3, each once a session, never a line on a loaded card. No plain
search in the product path: word matching lives only in the check, as the control arm. No model at prompt time.
| Part | What |
|---|---|
| `lib/memory_cue.py` | prompt → at most 8 cue concepts (accent folding, stop words) |
| `lib/memory_net.py` | `born`, `build` (`net/graph.json` + git-ignored `graph.private.json`), `fire` |
| `lib/memory_recall.py`, `lib/memory_hint.py` | scope by `memory_route.pages_for` (the `memory load` rule), session state, block ≤ 300 B, ids-only events |
| `lib/memory_learn.py`, `lib/memory_fold.py` | nightly fold in `memory apply`: opens grow links, 5 ignores cut one, decay; `net/links.tsv`; week digest |
| `lib/memory_concepts.py` | keeper rows `net/concepts.d/<d>.tsv` (gist, concepts, situations, Spanish aliases) |
| `lib/memory_recall_check.py` | `memory check --recall`: network vs control arm on quiz + `checks/cues.d/recall.tsv` |
| `adapters/claude/hooks/memory-recall` | UserPromptSubmit + SubagentStart carrier; `adapters/claude/run` appends `memory recall --file` |
| `lib/memory_view.py` | `memory net export --json`, dashboard Memory › Network tab and its "try a prompt" box |
PRIVATE pages: id and place only, only in the owner's own session; a worker never opens `graph.private.json`.
Protected projects: hints from core and their own card, no event, nothing learned.

## Exact commands
```bash
memory recall --explain "a prompt to try"     # dry run: hints and the why path; nothing written
memory recall --json "a prompt to try"        # same, as JSON (the dashboard try box)
memory show <id>                              # open a hint (counts as "opened" for the nightly fold)
memory net build && memory net stats          # rebuild the graph by hand (memory apply does it nightly)
memory check --recall                         # ship gate table vs the control arm; exit 0 = met
MEMORY_RECALL=off                             # kill switch (env or config.env)
~/agents/adapters/claude/install --plan       # the hook entries the installer would merge; --help prints usage
```
Sunday digest: `memory apply` prints `recall: N hints, N opened, N links grown, N faded (7 days)` (folds of the last 7
days, `$AGENT_WORK/memory-recall/folds.tsv`); the keeper copies it into its Sunday report.

## Pitfalls (measured)
- Ship gate on the real store: hard cues 28/40 is exactly the 70 % gate (R5): one lost paraphrase cue turns it red;
  better keeper rows for paraphrase (11/20) are the lever, not a lower threshold.
- Keeper concept↔concept links made p95 112-300 ms and 8-10/30 quiet prompts fire (R5): `CC_W = 0`, keep it off.
- Path labels over concept cliques grew factorially (a 2-word Spanish cue hung > 60 s, R5): a hop label is one hop.
- Without `net/graph.json` every prompt pays `born` (~0.3 s, R2); with it the cold hook was p50 70 / p95 90 ms at load 13 (R6).
- Going through `bin/memory` in the hook cost 130-200 ms (argparse, imports, R6): the hook calls `memory_recall.recall` in process.
- `UserPromptSubmit` never fires for an Agent-tool subagent (R0): the `SubagentStart` hook carries its brief.
- A fired block costs about 140 tokens and stays in the session history (R0): keep it at most 3 hints.
- `adapters/claude/install --help` once ran the real install and wrote `~/.claude/settings.json` (R8): fixed, unknown flags exit 2.

## Links
- Code: see the table; `bin/memory` verbs `recall`, `show`, `net build|stats|export`, `check --recall`
- Tests: `bin/tests/memory-net.test.sh`, `memory-recall.test.sh`, `memory-recall-check.test.sh`, `memory-learn.test.sh`,
  `memory-concepts.test.sh`, `memory-recall-hook.test.sh`, `memory-recall-digest.test.sh`, `claude-install-args.test.sh`
- Design / results: `~/agent-work/research/2026-11-11/T1624/` (PLAN.md, COMMON-RULES.md, done/R0-R8.md)
- Skill: `/memory`
