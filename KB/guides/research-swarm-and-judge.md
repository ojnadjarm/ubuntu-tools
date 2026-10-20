# Research swarm, spikes or mockups in parallel, then a judge and a critic (Workflow scripts)

Ticket: T65, T69, T70, T70b, T71, T391 · Last verified: 2026-10-20 (T846) by paths, `template.js` read and a script-dir count; 2026-10-19 (T487) by a stubbed run of the skill template (4 agents, lanes → judge → critic, guide line 4/4, a null lane logged 1/2) and the `jq` lane-state line on `wf_ca0b15d4-36d` (10 done)

## When to use
- A brief asks for several angles at once: research lanes, engine spikes, diagnosis lenses, competing mockups, then a
  ranked recommendation. Use the skill `/research-swarm` (and `/workflow-authoring` for the script API).
- Not for one ticket of ~20 minutes: that is one fresh agent. Not for implementation phases the owner has not approved.

## The path we took
| Run | Shape | Agents · wall time |
|---|---|---|
| T65 learning framework | 5 research lanes → synthesis (3 directions) → 3 mockups → judge + plan | 10 · 268 min |
| T69 Atelier perf | 3 diagnosis lenses → fixer on a copy → adversarial verifier → plan | 8 (2 re-runs) · 211 min |
| T70 engine options | Godot + Bevy spikes and 2 research lanes → judge → critic | 6 · 149 min |
| T70b extra spikes | 2 spikes, run beside T70 and told not to write in its folders | 2 · 99 min |
| T71 2D art direction | directions + stack lanes → 3 mockups | no judge file in `T71/`; the owner judged the mockups (Cutaway) |
- Each script: `meta.phases`, a binding brief **file**, a `head` prefix naming the brief and one output root, lanes
  as `parallel(LANES.map(l => () => agent(…, {label, phase, agentType: 'worker', schema})))` + `.filter(Boolean)`,
  and each phase's JSON passed into the next prompt. Schemas stay small: `{file, headline, test_link}`.
- Scripts and journals: `~/.claude/projects/<cwd-slug>/<session>/workflows/scripts/` (the slug of the cwd the Workflow ran from:
  13 script dirs under 11 slugs on 2026-10-20) and `~/.claude/projects/-home-<user>/<session>/subagents/workflows/wf_*/{journal.jsonl,agent-*.jsonl}`.

## Exact commands
```bash
cp ~/.claude/skills/research-swarm/template.js /tmp/…/tNN.js     # fill BRIEF, OUT, LANES, then run it with the Workflow tool
# resume after a stall: Workflow { scriptPath: <saved script>, resumeFromRunId: 'wf_…' } (finished agents come from cache)
# lane states: result row = done, failed row = failed, neither = running/stalled (stalled only once the journal stops growing);
# result/failed rows carry no label, so labels come from started rows; partial lines are skipped
jq -Rrn '[inputs|fromjson?]|(map(select(.type=="result").key)) as $d|(map(select(.type=="failed").key)) as $f|map(select(.type=="started"))|unique_by(.key)[]|"\(if .key|IN($d[]) then "done           " elif .key|IN($f[]) then "failed         " else "running/stalled" end) \(.label)"' …/wf_<id>/journal.jsonl
```

## Pitfalls (measured)
- **Workflow agents get no guides from the SubagentStart hook** (T379: 5 of 105 ran `guide` early). The template's `guide()`
  line opens every prompt with `First run \`guide <lane words>\``; fill each lane's `guide` words (T391, stubbed dry run 4/4 prompts).
- **Do not SendMessage to workflow agents.** T69 `diagnose:frame` was messaged and resumed as a plain subagent. It
  ended with a handback instead of StructuredOutput, so `agent()` never resolved and the Diagnose barrier stalled.
  Fix: TaskStop, change that lane's prompt to "ALREADY DONE: read frame.md, return it", resume with `resumeFromRunId`.
  To steer a live run, append to the brief file instead.
- **Subagents cannot write `report.md`.** Both T70 spikes and both T70b spikes hit it and stuffed the report into the schema's
  `file`/`headline`. Tell every lane to write `findings.md`.
- **Parallel lanes share one Iris Xe.** Sibling Chrome, Godot and cargo runs inflated wall times 5–10× (load 5–30) and
  left the GPU 93–100 % busy before 3 of 4 Godot runs. The T69 fixer claimed 37 → 50 fps at 2560 from a 12 s window.
  The verifier measured 31 → 34 over the whole watch and found WebGL2 freezes that the fixer had missed.
  Keep the adversarial verifier or critic, with its own scripts.
- **The judge is not the owner.** The T65 judge built the plan on a Cosmos-based hybrid. The owner played all three and
  said Atelier is "by far the best", so the plan was re-based (T69). The T70 critic flagged scores that favoured whatever
  was easiest to spike tonight, and laptop numbers used as a proxy for his RX 7800 XT.
- **Links:** the T65 mockups went out on `http://…:8070`, so no secure context and a silent WebGL2 fallback. Use `/drop-link` (https :8470).
  The T70 critic also caught a dashboard link on http.
- **Loops in lane folders:** T65's r-dia polling loops ran ~60 min unseen outside the scratchpad. Use `wait-for`
  (guide `wait-for-and-stuck-loops`).
- Lanes that depend on another lane (T70b godot-web waiting on T70's Godot project): `wait-for --file … --job …`,
  and a fallback that builds a minimal version itself.
- A lane that crashes returns null. `.filter(Boolean)` hides it, so log `n/total` and have the judge list what is missing.

## Links
- Skill: `~/.claude/skills/research-swarm/` (`SKILL.md`, `template.js`)
- Briefs: `~/agent-work/briefs/T65-learning-framework.md`, `T69-atelier-winner-perf.md`, `T70-engine-options.md`, `T71-2d-art-direction.md`
- Outputs: `~/agent-work/research/2026-09-23/T65/{lanes,mockups,judge,plan.md}`, `T65/perf/{verify.md,fix/results.md}`, `~/agent-work/research/2026-09-24/T70/options.md`
- Memory: `~/.claude/projects/-home-<user>/memory/workflow-agents-no-messages.md`
