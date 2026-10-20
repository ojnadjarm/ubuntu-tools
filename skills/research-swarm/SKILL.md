---
name: research-swarm
description: Run a research swarm as a Workflow script. Use when a brief asks for a swarm, lanes, spikes, mockups plus judge, options compared, an adversarial verify, or to resume a stalled workflow. Lanes (research, spikes, diagnosis lenses, mockups), a judge, an adversarial critic.
---

Triggers: verifier, T65/T69/T70/T71 pattern, steering.

# research-swarm: lanes → judge → critic, as a Workflow script

Only run one when the owner or orchestrator asked for it. For the script API, load `/workflow-authoring`.
Start from `~/.claude/skills/research-swarm/template.js` (T70's shape) or from a past script:
`~/.claude/projects/*/*/workflows/scripts/`
(`t65-…` lanes → synthesis → 3 mockups → judge · `t69-…` 3 lenses → fix a copy → adversarial verify · `t70-…` spikes + research → judge → critic).

1. The brief is a **file** (`~/agent-work/briefs/TNN-*.md`). Every prompt starts with the `guide` line ("First run `guide <lane words>` and use the top hit"),
   then "Read <brief> first; it is binding", with one output root. Workflow agents get no guides from the SubagentStart hook (T391).
2. Each lane is a fresh `worker` with a `schema` returning `{file, headline, test_link?}`. The file is `findings.md`,
   because subagents cannot write `report.md`. Pass results onward as `JSON.stringify(...)`, and `.filter(Boolean)` + `log` the count.
3. Lanes that measure share one laptop GPU: tell them to wait for a quiet machine (`wait-for --until`) and to measure A/B in one run.
4. The judge plays every test link itself over https (`/drop-link`), never `http://…:8070`. The critic or verifier
   re-measures with its **own** scripts and tries to refute the claims.
5. The judge ranks, and the owner decides: hand him the playable links.
6. **Never SendMessage to a running workflow agent.** It hands back to you, its `agent()` never resolves, and the phase stalls.
   To steer, append to the brief file (lanes not yet started read it). If you did message one, run TaskStop on it,
   edit that lane's prompt to "ALREADY DONE: read <file>, return it", and re-run the Workflow with `scriptPath` +
   `resumeFromRunId` (finished agents replay from cache).
7. Afterwards, write or update a guide (`guide --new <slug>`), and a skill if the procedure repeats.

Full guide with the measured pitfalls: `~/agents/KB/guides/research-swarm-and-judge.md`.
