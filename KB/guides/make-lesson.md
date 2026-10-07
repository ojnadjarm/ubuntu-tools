# Make a new lesson (sheet / unit) for the ailearning site in U01's shape

Ticket: T102, checkpoint postmortem T111 · Last verified: 2026-09-27 (continuity rule, T124); 2026-09-26 by a sandbox scaffold of 02-layers (tsc, unit test 4/4, vite build + all postbuild checks, browser smoke of every beat) and a fresh-agent dry run

## When to use
Starting a new lesson (Sheet II onward): spec, script, look gate, scaffold, ticket plan. Skill `/make-lesson`. For one fix inside an
existing lesson use `/explainer-engine` directly; for the look `/cutaway-style`; for audio `/kokoro-narration`.

## The path we took
- Survey: the explainer kit's starter (`src/units/a02`, bias neuron, fixed in T92) plays but has no lesson route; U01 has the route
  but its plate is specific. Chosen: copy the starter's plate/sim/state/watch and overlay U01's route files kept in the skill
  (`scaffold/`), so a new unit plays the whole route on day one with a placeholder machine.
- `new-lesson` (skill `scripts/new-lesson.mjs`, on PATH): `--spec-only` notes, `--lint` script shape, the unit scaffold (writes the
  unit, page, test, bundle seed; patches vite input and the test-changed MAP).
- Architecture: `~/agents/research/2026-09-26/T102/ARCHITECTURE.md` (Template Method route, composition root in `main.ts`).

## Exact commands
```bash
new-lesson 02-layers --spec-only --notes ~/agents/research/<date>/<ticket>
new-lesson --lint ~/agents/research/<date>/<ticket>/script.unit.json
S=<scratch>/site; rsync -a --exclude node_modules --exclude dist --exclude out --exclude .git --exclude content/.render \
  --exclude .local --exclude CLAUDE.local.md ~/projects/personal/ailearning/ $S/ && ln -s ~/projects/personal/ailearning/node_modules $S/node_modules
new-lesson 02-layers --narrate --site $S          # real site: drop --site, only in a build ticket
cd $S && npx tsc --noEmit && node --import ./tests/lib/register.mjs --test tests/unit/02-layers.test.mjs && npm run build
```

## Pitfalls (measured)
- Continuity is a mandate (owner, 2026-09-27): every lesson builds on the previous lesson's central mechanism (U01's neuron, same drawing
  and names); no new metaphor replaces it. T122's toys (fold, wedge stack, crank) were rejected for dropping the neuron; T124 rebuilt
  the U02 mockups from copies of it (`~/agents/research/2026-09-27/T124/`).
- base-check refused the cutaway kit's `loadFonts` default `'fonts/'` (page-relative): the scaffold's `main.ts` loads fonts through `BASE`.
- A sandbox copy without `.git` makes hygiene scan every file: `CLAUDE.local.md` failed it; exclude it from the copy.
- `--force` without `--narrate` once reset `cues.json` to the starter's; the render dir is now seeded only when missing.
- Sandbox 02-layers: 9 new clips rendered; bundle 1273 kB opus / 1879 kB m4a, first chapter 79 / 116 kB (cap 600 kB, first chapter only).
- 2 site tests fail before any T102 change, on a clean copy too: `framing.test` "beside Fig. 1 nothing overlaps", `place.test` "every
  value box… found a clear slot". Not the scaffold's: they were T99's hidden balloons, fixed by T105 (T111). A red test you did not
  cause still goes in your report's first line.
- Under `?mute` there is no Begin card: wait for `window.__d.beats.name`, not the card.
- Lint: U01 0 faults; the template fails by design (template text). Durations are notes, not faults: U01 c8a runs 49 s (> 42).
- Dogfood (fresh agent, Sheet II): 12 gaps → 12 fixed; the biggest: the scaffold builds the template, not the linted script (script lands in ticket b).

## Checkpoint postmortem, U01 T76–T110 (T111, measured)
- 35 tickets: 2,356 agent-min, 890 M context tokens, 128 owner messages. Build 18 %, tests + stills 38 %, orientation 27 %, waiting 11 %.
  Rework ~300 agent-min (13 %) and 36 owner messages (28 %). Report: `~/agents/research/2026-09-26/T111/POSTMORTEM.md`.
- A fresh agent builds a narrated chapter in 6.7 min (T103). Tiny fixes after T98: 29 → 17 min (target 6); medium 102 → 58 min.
- Top rework causes: tests blind to his hand (synthetic clicks; T99 shipped with no node test and hid 4 balloons): 190 min; relays that
  lost the object or the letter (pick B→A, "the needle"): 74 min; budgets and designs nobody signed off (3 MB audio cap, −1.5 guess
  range, Race, Parts modal). The rules are now in `process.md` (Tests, Don't, the pick) and `ux-checklist.md`.
- Pitfalls that recurred after a postmortem named them: the `pgrep -f` wait (T105, T110). A pitfall goes into a skill, not only a report.

## Links
- Code: `~/.claude/skills/make-lesson/` (SKILL.md, reference/, scaffold/, scripts/, templates/)
- Tests: the scaffold's `tests/unit/<slug>.test.mjs`; smoke tools `~/agents/research/2026-09-26/T102/smoke*.mjs`
- Design / results: `~/agents/research/2026-09-26/T102/`; postmortem T98; shape T101 `moves.md`
